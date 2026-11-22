#!/opt/bin/python3
"""KN-3012 4.9-ndm-5 dual-slot updater. Default is read-only preflight.
Hardware flashing has NOT been validated. See README.md before use.
"""
import argparse
import dataclasses
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import stat
import struct
import sys
import time
import urllib.error
import urllib.request
import zlib

CHUNK = 128 * 1024
MAX_IMAGE = 0x1ce0000
GEOMETRY = {'Firmware_1': (0x60000, 0x1ee0000),
            'Config_1': (0x1f40000, 0x80000),
            'U-State': (0x3ae0000, 0x20000),
            'Firmware_2': (0x3b40000, 0x1ee0000),
            'Config_2': (0x5a20000, 0x80000),
            'Storage_A': (0x2000000, 0x1ae0000),
            'Storage_B': (0x5aa0000, 0x1b40000)}

class Refused(RuntimeError):
    pass

def require(condition, message):
    if not condition:
        raise Refused(message)

@dataclasses.dataclass(frozen=True)
class Partition:
    name: str
    index: int
    offset: int
    size: int
    erase: int
    flags: int
    kind: str

@dataclasses.dataclass(frozen=True)
class Plan:
    current: int
    target: int
    state: dict
    parts: dict
    image_size: int
    image_hash: str

def digest(f, length):
    f.seek(0)
    h = hashlib.sha256()
    left = length
    while left:
        chunk = f.read(min(CHUNK, left))
        require(bool(chunk), 'Unexpected end of input during verification')
        h.update(chunk)
        left -= len(chunk)
    return h.hexdigest()

def verify_image(f, expected_hash):
    require(re.fullmatch(r'[0-9a-fA-F]{64}', expected_hash), 'Supply an explicit 64-digit SHA-256')
    size = os.fstat(f.fileno()).st_size
    require(4096 < size <= MAX_IMAGE, 'Image size outside the supported KN-3012 limit')
    require(digest(f, size) == expected_hash.lower(), 'Image SHA-256 mismatch')
    f.seek(0)
    header = f.read(64)
    fields = struct.unpack('>7I4B32s', header)
    magic, hcrc, _, kernel_size, _, _, dcrc, osid, arch, itype, comp, name = fields
    require(magic == 0x27051956 and name.split(b'\0', 1)[0] == b'KN-3012', 'Not a KN-3012 uImage')
    require((osid, arch, itype, comp) == (5, 5, 2, 3), 'Unexpected kernel image format')
    masked = header[:4] + b'\0' * 4 + header[8:]
    require(zlib.crc32(masked) == hcrc, 'Kernel header checksum mismatch')
    require(0 < kernel_size < size - 124, 'Invalid kernel length')
    crc = 0
    left = kernel_size
    while left:
        chunk = f.read(min(left, CHUNK))
        require(bool(chunk), 'Truncated kernel')
        crc = zlib.crc32(chunk, crc)
        left -= len(chunk)
    require(crc == dcrc, 'Kernel payload checksum mismatch')
    f.seek(-60, os.SEEK_END)
    tail_magic, device, version, tail_crc = struct.unpack('>4sI48s4s', f.read(60))
    require(tail_magic == b'ZNBG' and device == 0x12308000, 'Wrong SDK trailer/device ID')
    require(version.split(b'\0', 1)[0].startswith(b'KN-3012 '), 'Wrong trailer board')
    f.seek(0)
    crc = 0
    left = size - 60
    while left:
        chunk = f.read(min(left, CHUNK))
        require(bool(chunk), 'Truncated image')
        crc = zlib.crc32(chunk, crc)
        left -= len(chunk)
    require((crc ^ 0xffffffff) == int.from_bytes(tail_crc, 'little'), 'Firmware trailer checksum mismatch')
    return size, expected_hash.lower()

def rci_get(path):
    # Do not consult proxy settings for the local NDM endpoint.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open('http://127.0.0.1:79/rci/' + path, timeout=10) as response:
        value = json.load(response)
    require(isinstance(value, dict), 'Unexpected RCI response')
    return value

class Device:
    def __init__(self):
        require(os.geteuid() == 0, 'Run from the router root shell')
        require(platform.system() == 'Linux' and platform.machine().startswith('mips'), 'Only a MIPS Linux router is supported')
        require(platform.release() == '4.9-ndm-5', 'Kernel release not audited by this updater')
        require(rci_get('show/version').get('hw_id') == 'KN-3012', 'Router is not KN-3012')
        require(rci_get('components/auto-update').get('disable') is True,
                'Disable automatic firmware updates in the router UI first')
        require(Path('/lib/libndmOpkg.so').is_file(), 'Custom OPKG integration is not present')
        self.lock = open('/var/lock/kn3012-update.lock', 'a')
        fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def state(self):
        return {key: int((Path('/proc/dual_image') / key).read_text().strip())
                for key in ('boot_current', 'boot_active', 'boot_backup', 'boot_fails')}

    def partitions(self):
        result = {}
        for line in Path('/proc/mtd').read_text().splitlines():
            m = re.fullmatch(r'mtd(\d+): ([0-9a-fA-F]+) ([0-9a-fA-F]+) "([^"]+)"', line)
            if not m:
                continue
            index, size, erase, name = m.groups()
            require(name not in result, 'Duplicate partition name')
            base = Path('/sys/class/mtd') / ('mtd' + index)
            result[name] = Partition(name, int(index), int((base/'offset').read_text()),
                                     int(size, 16), int(erase, 16),
                                     int((base/'flags').read_text().strip(), 0),
                                     (base/'type').read_text().strip())
        return result

    def open_partition(self, p, write=False):
        node = Path('/dev') / (('mtdblock' if write else 'mtd') + str(p.index))
        fd = os.open(node, (os.O_RDWR | os.O_EXCL if write else os.O_RDONLY) | os.O_NOFOLLOW)
        info = os.fstat(fd)
        valid = (stat.S_ISBLK(info.st_mode) and os.major(info.st_rdev) == 31
                 and os.minor(info.st_rdev) == p.index) if write else (
                 stat.S_ISCHR(info.st_mode) and os.major(info.st_rdev) == 90
                 and os.minor(info.st_rdev) == 2 * p.index)
        if not valid:
            os.close(fd)
            raise Refused('Unexpected MTD device')
        return os.fdopen(fd, 'r+b' if write else 'rb', buffering=0)

    def write_partition(self, p, source, length):
        source.seek(0)
        with self.open_partition(p, True) as target:
            left = length
            while left:
                chunk = source.read(min(left, CHUNK))
                require(bool(chunk), 'Short source read')
                view = memoryview(chunk)
                while view:
                    written = target.write(view)
                    require(written and written > 0, 'Short flash write')
                    view = view[written:]
                left -= len(chunk)
            os.fsync(target.fileno())

    def verify_partition(self, p, length, expected):
        with self.open_partition(p) as f:
            require(digest(f, length) == expected, 'Flash readback verification failed: ' + p.name)

    def verify_persistent_state(self, parts, expected):
        with self.open_partition(parts['U-State']) as f:
            data = f.read(8)
        require(len(data) == 8, 'Short U-State read')
        magic, version, active, backup, fails = struct.unpack('>4s4B', data)
        require(magic == b'USTA' and version == 1, 'Unknown persistent boot-state format')
        require((active, backup, fails) == (expected['boot_active'], expected['boot_backup'], expected['boot_fails']),
                'Persistent boot-state readback mismatch')

    def set_state(self, key, value):
        require(key in ('boot_active', 'boot_backup', 'boot_fails'), 'Invalid boot-state field')
        with open(Path('/proc/dual_image') / key, 'w') as f:
            f.write(str(value) + '\n')
        require(self.state()[key] == value, 'Boot-state readback mismatch: ' + key)

    def commit(self):
        with open('/proc/dual_image/commit', 'w') as f:
            f.write('1\n')


def plan_update(device, size, sha):
    state = device.state()
    current = state['boot_current']
    require(current in (1, 2), 'Invalid current slot')
    target = 3 - current
    require(state == dict(boot_current=current, boot_active=current,
                          boot_backup=target, boot_fails=0),
            'Boot state is not a settled, healthy dual-slot state')
    parts = device.partitions()
    for name, geometry in GEOMETRY.items():
        require(name in parts, 'Required partition missing: ' + name)
        p = parts[name]
        require((p.offset, p.size) == geometry and p.erase == 0x20000 and p.kind == 'nand',
                'Unaudited geometry: ' + name)
        require(p.flags & 0x400, 'Partition not writable: ' + name)
    require('Storage' in parts, 'Merged internal storage partition missing')
    require(parts['Storage'].size == parts['Storage_A'].size + parts['Storage_B'].size,
            'Unexpected merged storage size')
    device.verify_persistent_state(parts, state)
    require(size <= parts['Firmware_' + str(target)].size, 'Image does not fit inactive slot')
    return Plan(current, target, state, parts, size, sha)


def backup_configs(device, plan, directory):
    directory.mkdir(mode=0o700, parents=False, exist_ok=False)
    (directory/'plan.json').write_text(json.dumps(dataclasses.asdict(plan), indent=2) + '\n')
    hashes = {}
    for slot in (1, 2):
        p = plan.parts['Config_' + str(slot)]
        path = directory / ('Config_' + str(slot) + '.bin')
        with device.open_partition(p) as source, open(path, 'xb') as dest:
            left = p.size
            while left:
                chunk = source.read(min(left, CHUNK))
                require(bool(chunk), 'Short configuration backup')
                dest.write(chunk)
                left -= len(chunk)
            dest.flush()
            os.fsync(dest.fileno())
        with open(path, 'rb') as f:
            hashes[slot] = digest(f, p.size)
        device.verify_partition(p, p.size, hashes[slot])
    (directory/'config-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    os.sync()
    return hashes


def apply_update(device, plan, image, backup_dir):
    """No slot mutation until firmware AND config readback succeed."""
    require(plan_update(device, plan.image_size, plan.image_hash) == plan, 'Layout/state changed')
    hashes = backup_configs(device, plan, backup_dir)
    fw = plan.parts['Firmware_' + str(plan.target)]
    cfg = plan.parts['Config_' + str(plan.target)]
    device.write_partition(fw, image, plan.image_size)
    device.verify_partition(fw, plan.image_size, plan.image_hash)
    # Detect changes to the input and active settings during the long write.
    require(digest(image, plan.image_size) == plan.image_hash, 'Input image changed')
    active_cfg = plan.parts['Config_' + str(plan.current)]
    device.verify_partition(active_cfg, active_cfg.size, hashes[plan.current])
    with open(backup_dir / ('Config_' + str(plan.current) + '.bin'), 'rb') as snapshot:
        device.write_partition(cfg, snapshot, cfg.size)
    device.verify_partition(cfg, cfg.size, hashes[plan.current])
    require(plan_update(device, plan.image_size, plan.image_hash) == plan, 'Layout/state changed before commit')
    state_changed = False
    commit_started = False
    try:
        state_changed = True
        device.set_state('boot_backup', plan.current)
        device.set_state('boot_active', 0)
        expected = dict(boot_current=plan.current, boot_active=0,
                        boot_backup=plan.current, boot_fails=0)
        require(device.state() == expected, 'Staged boot state mismatch')
        os.sync()
        commit_started = True
        device.commit()
        require(device.state() == expected, 'Committed boot-state readback mismatch')
        device.verify_persistent_state(plan.parts, expected)
    except Exception as e:
        if state_changed and not commit_started:
            try:
                for key in ('boot_active', 'boot_backup', 'boot_fails'):
                    device.set_state(key, plan.state[key])
            except Exception:
                raise Refused('Could not restore in-memory boot state; do not reboot') from e
        if commit_started:
            raise Refused('Boot-state commit failed or is uncertain; do not reboot. Keep the router powered and inspect state.') from e
        raise
    return plan.target


def storage_path(path):
    storage = Path('/storage')
    require(storage.is_dir() and os.path.ismount(storage), '/storage is not mounted')
    path = path.resolve(strict=True)
    require(path.is_relative_to(storage.resolve()), 'Image must be on internal /storage')
    # Reject tmpfs/RAM storage and unexpected mount arrangements.
    mounts = Path('/proc/mounts').read_text().splitlines()
    require(any(len(v := line.split()) > 2 and v[1] == '/storage' and v[2] == 'ubifs'
                for line in mounts), 'Expected UBIFS at /storage')
    require(path.stat().st_dev == storage.stat().st_dev, 'Image is on a different filesystem')
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--sha256', required=True, help='Trusted SHA-256 of the intended firmware image')
    parser.add_argument('--apply', action='store_true', help='WRITE the inactive slot; never reboots automatically')
    args = parser.parse_args()
    os.umask(0o077)
    device = Device()
    image_path = storage_path(args.image)
    fd = os.open(image_path, os.O_RDONLY | os.O_NOFOLLOW)
    require(stat.S_ISREG(os.fstat(fd).st_mode), 'Image must be a regular file')
    with os.fdopen(fd, 'rb', buffering=0) as image:
        fcntl.flock(image, fcntl.LOCK_EX | fcntl.LOCK_NB)
        size, sha = verify_image(image, args.sha256)
        plan = plan_update(device, size, sha)
        print(json.dumps({'mode': 'apply' if args.apply else 'check-only',
                          'current_slot': plan.current, 'target_slot': plan.target,
                          'image_size': size, 'sha256': sha,
                          'firmware_target': plan.parts['Firmware_' + str(plan.target)].name}, indent=2), flush=True)
        if not args.apply:
            print('Preflight passed. No flash writes or boot-state changes were made.')
            return
        # Config backups need 1 MiB plus a reserve; firmware source remains in place.
        vfs = os.statvfs('/storage')
        require(vfs.f_bavail * vfs.f_frsize >= 4 * 1024 * 1024, 'At least 4 MiB free on /storage is required')
        backups = Path('/storage') / ('kn3012-backup-' + str(time.time_ns()))
        target = apply_update(device, plan, image, backups)
        print('Verified firmware and configuration. Slot %d selected for next boot.' % target)
        print('Backups: ' + str(backups))
        print('No reboot performed. Reboot manually when ready.')

if __name__ == '__main__':
    try:
        main()
    except (Refused, OSError, ValueError, urllib.error.URLError) as e:
        print('STOPPED: ' + str(e), file=sys.stderr)
        sys.exit(1)
