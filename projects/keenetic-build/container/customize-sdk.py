#!/usr/bin/env python3
import os, pathlib, shutil, subprocess, sys
sdk = pathlib.Path(sys.argv[1])
inputs = pathlib.Path(sys.argv[2])
donors = inputs.parent / 'donors'
os.chdir(sdk)
# Add the same storage capabilities used by the EN7528 Viva/Hopper targets;
# retain every KN-3012 identity and board setting.
target=sdk/'target/linux/en7528/KN-3012/target.mk'
s=target.read_text()
if 'FEATURES +=' not in s:
    target.write_text(s+'\nFEATURES += usb usbstorage extended_storage\n')
for model in ('KN-3810','KN-1912'):
    image=inputs/f'{model}-5.01.C.8.0-2-donor.bin'
    data=image.read_bytes()
    offset=data.index(b'hsqs')
    dest=donors/model
    dest.parent.mkdir(exist_ok=True)
    subprocess.run(['unsquashfs','-f','-o',str(offset),'-d',str(dest),'-regex',str(image),'^([^d].*$)|(d([^e].*$|$))|(de([^v].*$|$))|(dev.+$)'],check=True)
    # Extract missing proprietary payloads by their original package xattr.
    copied=set()
    for root, dirs, names in os.walk(dest):
        for name in names:
            src=pathlib.Path(root)/name
            if src.is_symlink():
                continue
            try: package=os.getxattr(src,'user.package').decode().rstrip('\0')
            except OSError: continue
            if package.startswith('ndm-mod-'):
                out=sdk/'package/private/ndm'/('files-'+package)/src.relative_to(dest)
            elif package in ('nsh','nsh-static','npkg','dropbear','opkg_led_ctl'):
                category={'nsh':'private/nsh','nsh-static':'private/nsh','npkg':'private/npkg','dropbear':'net/dropbear','opkg_led_ctl':'system/opkg_led_ctl'}[package]
                out=sdk/'package'/category/('files-'+package)/src.relative_to(dest)
            else:
                continue
            if not out.exists():
                out.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(src,out)
                copied.add(package)
    print(model, 'imported packages:', ', '.join(sorted(copied)))
# The KN-1912 component catalog exposes shell/OPKG/storage entries absent
# from the stock KN-3012 catalog; its board identity remains KN-3012.
components=donors/'KN-1912/etc/components.xml'
shutil.copy2(components,sdk/'package/private/ndm/files-ndm/etc/components.xml')
config=sdk/'.config'
s=config.read_text()
options=['USES_EXTENDED_STORAGE','KERNEL_MTD_NDM_EXTENDED_STORAGE',
'PACKAGE_ndm-mod-shell','PACKAGE_ndm-mod-opkg','PACKAGE_busybox',
'PACKAGE_ndm-mod-storage','PACKAGE_ndm-mod-storage-base','PACKAGE_ndm-mod-storage-mtd',
'PACKAGE_kmod-ndm-storage','PACKAGE_kmod-fs-ubi','PACKAGE_kmod-fs-ubifs',
'PACKAGE_ndm-mod-usb','PACKAGE_ubi-utils','PACKAGE_ip6tables','PACKAGE_ip6tables-mod-nat']
import re
for key in options:
    s=re.sub(r'^(?:# )?CONFIG_'+re.escape(key)+r'(?:=.*| is not set)$','',s,flags=re.M)
    s+='\nCONFIG_'+key+'=y\n'
config.write_text(s)
(sdk/'files/storage').mkdir(parents=True,exist_ok=True)
(sdk/'files/opt').mkdir(parents=True,exist_ok=True)
print('KN-3012 customization prepared')
