"""Offline tests. FakeDevice maps every MTD operation to temporary regular files."""
import argparse
import dataclasses
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('kn3012_updater', ROOT/'kn3012-update.py')
u = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = u
spec.loader.exec_module(u)
def synthetic_image():
    kernel = b"synthetic kernel"
    name = b"KN-3012"
    header = struct.pack(
        ">7I4B32s", 0x27051956, 0, 0, len(kernel), 0, 0,
        zlib.crc32(kernel), 5, 5, 2, 3, name,
    )
    header = header[:4] + struct.pack(">I", zlib.crc32(header)) + header[8:]
    body = (header + kernel).ljust(8192, b"\0")
    trailer = struct.pack(">4sI48s", b"ZNBG", 0x12308000, b"KN-3012 synthetic")
    return body + trailer + struct.pack("<I", zlib.crc32(body) ^ 0xFFFFFFFF)


class FakeDevice(u.Device):
    def __init__(self, root, slot=1, fault=None):
        self.root, self.fault, self.events = root, fault, []
        self.values = dict(boot_current=slot, boot_active=slot, boot_backup=3-slot, boot_fails=0)
        self.persisted = self.values.copy()
        order = ['U-Boot','U-Config','RF-EEPROM']
        if slot == 1:
            order += ['Kernel_1','RootFS_1']
        order += ['Firmware_1','Config_1','Dump','Storage_A','U-State','D-State','RF-EEPROM_res']
        if slot == 2:
            order += ['Kernel_2','RootFS_2']
        order += ['Firmware_2','Config_2','Storage_B','Full','Storage']
        self.parts = {name:u.Partition(name,order.index(name),offset,size,0x20000,0x400,'nand')
                      for name,(offset,size) in u.GEOMETRY.items()}
        self.parts['Storage'] = u.Partition('Storage',order.index('Storage'),0,0x3620000,0x20000,0x400,'nand')
        for name,p in self.parts.items():
            with open(root/name,'wb') as f:
                f.truncate(p.size)
        for name,value in [('Config_1',b'A'),('Config_2',b'B')]:
            (root/name).write_bytes(value*0x80000)

    def state(self): return self.values.copy()
    def partitions(self): return self.parts.copy()
    def verify_persistent_state(self, parts, expected):
        self.events.append('persistent-read')
        u.require(self.persisted == expected,'Persistent boot-state readback mismatch')
    def open_partition(self,p,write=False):
        self.events.append(('write-open ' if write else 'read-open ')+p.name)
        return open(self.root/p.name,'r+b' if write else 'rb',buffering=0)
    def write_partition(self,p,source,length):
        assert p.name in ['Firmware_'+str(3-self.values['boot_current']),
                          'Config_'+str(3-self.values['boot_current'])]
        self.events.append('write '+p.name)
        if self.fault == 'write-'+p.name.split('_')[0]:
            with open(self.root/p.name,'r+b') as f: f.write(b'partial')
            raise OSError('Injected write error')
        super().write_partition(p,source,length)
        if self.fault == 'corrupt-'+p.name.split('_')[0]:
            with open(self.root/p.name,'r+b') as f: f.write(b'BAD')
        if self.fault == 'active-config-changed' and p.name.startswith('Firmware_'):
            with open(self.root/('Config_'+str(self.values['boot_current'])),'r+b') as f:
                f.write(b'changed')
    def set_state(self,key,value):
        self.events.append('set '+key+'='+str(value))
        if self.fault == 'set-active' and key == 'boot_active' and value == 0:
            raise OSError('Injected state write error')
        self.values[key]=value
    def commit(self):
        self.events.append('commit')
        if self.fault == 'commit-error': raise OSError('Injected commit error')
        self.persisted=self.values.copy()
        if self.fault == 'persistent-corrupt': self.persisted['boot_active']=1

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.root=Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def run_apply(self,slot=1,fault=None):
        d=FakeDevice(self.root,slot,fault)
        p=u.plan_update(d,IMAGE.stat().st_size,SHA)
        with open(IMAGE,'rb') as f:
            target=u.apply_update(d,p,f,self.root/'backup')
        return d,target
    def test_image_checks(self):
        with open(IMAGE,'rb') as f:
            self.assertEqual(u.verify_image(f,SHA),(IMAGE.stat().st_size,SHA))
    def test_wrong_image_hash(self):
        with open(IMAGE,'rb') as f, self.assertRaises(u.Refused):
            u.verify_image(f,'0'*64)
    def test_reject_invalid_header_even_with_matching_sha(self):
        copy=self.root/'bad.bin'; shutil.copyfile(IMAGE,copy)
        with open(copy,'r+b') as f: f.write(b'BAD!')
        sha=hashlib.sha256(copy.read_bytes()).hexdigest()
        with open(copy,'rb') as f, self.assertRaises(u.Refused): u.verify_image(f,sha)
    def test_slot1_success(self):
        d,target=self.run_apply()
        self.assertEqual(target,2)
        self.assertEqual(d.values,dict(boot_current=1,boot_active=0,boot_backup=1,boot_fails=0))
        self.assertEqual((self.root/'Config_1').read_bytes(),(self.root/'Config_2').read_bytes())
        self.assertEqual(d.events.count('commit'),1)
        self.assertTrue((self.root/'backup/Config_2.bin').is_file())
    def test_slot2_success(self):
        d,target=self.run_apply(slot=2)
        self.assertEqual(target,1)
        self.assertEqual(d.parts['Firmware_1'].index,3)
        self.assertEqual(d.parts['Config_1'].index,4)
        self.assertEqual(d.values['boot_backup'],2)
    def assert_stops_before_state(self,fault):
        d=FakeDevice(self.root,1,fault)
        p=u.plan_update(d,IMAGE.stat().st_size,SHA)
        with open(IMAGE,'rb') as f, self.assertRaises((u.Refused,OSError)):
            u.apply_update(d,p,f,self.root/'backup')
        self.assertNotIn('commit',d.events)
        self.assertFalse(any(e.startswith('set ') for e in d.events))
        self.assertEqual(d.values,p.state)
    def test_firmware_write_error(self): self.assert_stops_before_state('write-Firmware')
    def test_firmware_readback_corruption(self): self.assert_stops_before_state('corrupt-Firmware')
    def test_config_write_error(self): self.assert_stops_before_state('write-Config')
    def test_config_readback_corruption(self): self.assert_stops_before_state('corrupt-Config')
    def test_active_settings_changed(self): self.assert_stops_before_state('active-config-changed')
    def test_bad_geometry(self):
        d=FakeDevice(self.root)
        d.parts['Firmware_2']=dataclasses.replace(d.parts['Firmware_2'],offset=0)
        with self.assertRaises(u.Refused): u.plan_update(d,10000,SHA)
        self.assertFalse(any(e.startswith('write') for e in d.events))
    def test_missing_storage(self):
        d=FakeDevice(self.root); del d.parts['Storage_A']
        with self.assertRaises(u.Refused): u.plan_update(d,10000,SHA)
    def test_readonly_firmware(self):
        d=FakeDevice(self.root); d.parts['Firmware_2']=dataclasses.replace(d.parts['Firmware_2'],flags=0)
        with self.assertRaises(u.Refused): u.plan_update(d,10000,SHA)
    def test_unhealthy_boot_state(self):
        d=FakeDevice(self.root); d.values['boot_fails']=1
        with self.assertRaises(u.Refused): u.plan_update(d,10000,SHA)
    def test_persisted_state_mismatch(self):
        d=FakeDevice(self.root); d.persisted['boot_active']=2
        with self.assertRaises(u.Refused): u.plan_update(d,10000,SHA)
    def test_state_error_restores_ram_without_commit(self):
        d=FakeDevice(self.root,1,'set-active'); p=u.plan_update(d,IMAGE.stat().st_size,SHA)
        with open(IMAGE,'rb') as f, self.assertRaises(OSError):
            u.apply_update(d,p,f,self.root/'backup')
        self.assertEqual(d.values,p.state); self.assertNotIn('commit',d.events)
    def test_commit_error_is_explicitly_uncertain(self):
        d=FakeDevice(self.root,1,'commit-error'); p=u.plan_update(d,IMAGE.stat().st_size,SHA)
        with open(IMAGE,'rb') as f, self.assertRaisesRegex(u.Refused,'do not reboot'):
            u.apply_update(d,p,f,self.root/'backup')
    def test_commit_corruption_detected_from_persistent_read(self):
        d=FakeDevice(self.root,1,'persistent-corrupt'); p=u.plan_update(d,IMAGE.stat().st_size,SHA)
        with open(IMAGE,'rb') as f, self.assertRaisesRegex(u.Refused,'do not reboot'):
            u.apply_update(d,p,f,self.root/'backup')
    def test_oversized_image_rejected(self):
        d=FakeDevice(self.root)
        with self.assertRaises(u.Refused): u.plan_update(d,0x2000000,SHA)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run offline updater tests")
    parser.add_argument("image", type=Path, nargs="?")
    parser.add_argument("sha256", nargs="?")
    args = parser.parse_args()
    if (args.image is None) != (args.sha256 is None):
        parser.error("supply both an image and its SHA-256")
    with tempfile.TemporaryDirectory() as temp:
        if args.image:
            IMAGE, SHA = args.image, args.sha256.lower()
        else:
            IMAGE = Path(temp) / "synthetic.bin"
            data = synthetic_image()
            IMAGE.write_bytes(data)
            SHA = hashlib.sha256(data).hexdigest()
        unittest.main(argv=[sys.argv[0]], verbosity=2)
