#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory
import zlib


def require(condition, message):
    if not condition:
        raise ValueError(message)


def extract(image, data, root):
    offset = data.index(b"hsqs")
    subprocess.run(
        ["unsquashfs", "-o", str(offset), "-d", str(root), "-regex", str(image),
         "^([^d].*$)|(d([^e].*$|$))|(de([^v].*$|$))|(dev.+$)"],
        check=True, stdout=sys.stderr,
    )


def emulate(root, executable, *args):
    return subprocess.run(
        ["qemu-mipsel", "-L", str(root), str(executable), *args],
        check=True, text=True, stdout=subprocess.PIPE,
    ).stdout.strip()


def verify(image, stock):
    data = image.read_bytes()
    require(124 < len(data) <= 0x1CE0000, "Invalid KN-3012 image size")
    magic, hcrc, _, size, _, _, dcrc, osid, arch, kind, comp, name = struct.unpack(
        ">7I4B32s", data[:64]
    )
    require(magic == 0x27051956 and name.split(b"\0", 1)[0] == b"KN-3012", "Wrong uImage board")
    require((osid, arch, kind, comp) == (5, 5, 2, 3), "Unexpected uImage format")
    require(0 < size < len(data) - 124, "Invalid kernel length")
    require(zlib.crc32(data[:4] + b"\0" * 4 + data[8:64]) == hcrc, "Invalid uImage header CRC")
    require(zlib.crc32(data[64:64 + size]) == dcrc, "Invalid kernel data CRC")
    tail, device, version, trailer_crc = struct.unpack(">4sI48s4s", data[-60:])
    require(tail == b"ZNBG" and device == 0x12308000, "Wrong SDK trailer or device ID")
    require(version.rstrip(b"\0") == b"KN-3012 5.01.C.8.0-2", "Wrong SDK trailer version")
    require(zlib.crc32(data[:-60]) ^ 0xFFFFFFFF == int.from_bytes(trailer_crc, "little"),
            "Invalid SDK trailer CRC")

    required = [
        "lib/libndmExec.so", "lib/libndmOpkg.so", "lib/libndmStorageBase.so",
        "lib/libndmStorageMtd.so", "usr/sbin/npkg", "bin/sh", "opt", "storage",
    ]
    modules = ["ubi.ko", "ubifs.ko", "ndm_storage.ko"]
    with TemporaryDirectory() as temp:
        root = Path(temp) / "firmware"
        stock_root = Path(temp) / "stock"
        extract(image, data, root)
        for name in required:
            path = root / name
            require(path.exists() or path.is_symlink(), f"Missing {name}")
        for name in modules:
            require(any(p.is_file() for p in (root / "lib/modules").rglob(name)), f"Missing {name}")
        extract(stock, stock.read_bytes(), stock_root)
        library = "lib/libndmCorePack.so"
        require((root / library).read_bytes() == (stock_root / library).read_bytes(),
                "Proprietary core library differs from stock")
        busybox = root / "bin/busybox"
        if not busybox.is_file():
            busybox = root / "usr/bin/busybox"
        shell = emulate(root, busybox, "ash", "-c", "printf 'BusyBox ash executes successfully\\n'")
        ip6tables = emulate(root, root / "usr/sbin/ip6tables", "--version")

    return {
        "file": image.name,
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
        "board": "KN-3012",
        "device_id": hex(device),
        "uimage_header_crc": "passed",
        "kernel_crc": "passed",
        "partition_size": "passed",
        "firmware_trailer_crc": "passed",
        "squashfs": "extracted successfully",
        "required_payloads": required,
        "storage_modules": modules,
        "core_library": "matches stock",
        "emulated_shell": shell,
        "emulated_ip6tables": ip6tables,
        "physical_boot": "not tested",
        "router_flashed": False,
    }


def main():
    parser = argparse.ArgumentParser(description="Verify a KN-3012 firmware image offline")
    parser.add_argument("image", type=Path)
    parser.add_argument("stock", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = verify(args.image, args.stock)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Firmware verification failed: {error}\n")
    text = json.dumps(report, indent=2) + "\n"
    if args.output:
        (args.output / "validation.json").write_text(text)
        (args.output / "SHA256SUMS").write_text(f'{report["sha256"]}  {args.image.name}\n')
    print(text, end="")


if __name__ == "__main__":
    main()
