"""Allow one numeric IPv4 VPN endpoint without exposing the private profile."""

import ipaddress
from pathlib import Path
import sys


def endpoint(path):
    endpoints = []
    for line in path.read_text().splitlines():
        key, separator, value = line.partition("#")[0].partition("=")
        if separator and key.strip().lower() == "endpoint":
            endpoints.append(value.strip())
    if len(endpoints) != 1:
        raise ValueError
    address, port = endpoints[0].split(":")
    address = ipaddress.IPv4Address(address)
    if not port.isascii() or not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise ValueError
    return f"{address} . {int(port)}"


def main():
    path = Path(sys.argv[1])
    check = "--check" in sys.argv[2:]
    try:
        value = endpoint(path)
    except (OSError, UnicodeError, ValueError):
        # Install an empty set if unprovisioned or malformed, so networking and
        # management still start. The tunnel's --check fails before awg-quick.
        print("VPN endpoint blocked: profile needs one numeric IPv4 Endpoint with a valid UDP port.", file=sys.stderr)
        return 1 if check else 0
    if not check:
        print(f"elements = {{ {value} }}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
