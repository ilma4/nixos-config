"""Socket-activated TCP proxy with failover across a host's mDNS addresses."""

import logging
import selectors
import socket
import sys
import time

from zeroconf import AddressResolverIPv4, InterfaceChoice, IPVersion, Zeroconf


def connect(host, port):
    with Zeroconf(interfaces=InterfaceChoice.Default, ip_version=IPVersion.V4Only) as zc:
        resolver = AddressResolverIPv4(host.rstrip(".") + ".")
        resolver.request(zc, 3000)
        # A second interface's response can arrive after the first answer.
        time.sleep(0.5)
        resolver.load_from_cache(zc)
        addresses = resolver.parsed_addresses(IPVersion.V4Only)
    for address in addresses:
        try:
            upstream = socket.create_connection((address, port), timeout=2)
        except OSError as error:
            logging.warning("Cannot connect to %s: %s", address, error)
            continue
        upstream.settimeout(None)
        logging.info("Connected to %s via %s", host, address)
        return upstream
    raise ConnectionError(f"No reachable address for {host}: {addresses}")


def relay(client, upstream):
    with selectors.DefaultSelector() as selector:
        selector.register(client, selectors.EVENT_READ, upstream)
        selector.register(upstream, selectors.EVENT_READ, client)
        while True:
            for key, _ in selector.select():
                data = key.fileobj.recv(65536)
                if not data:
                    return
                key.data.sendall(data)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    try:
        with socket.socket(fileno=0) as client, connect(sys.argv[1], int(sys.argv[2])) as upstream:
            relay(client, upstream)
    except OSError:
        logging.exception("Proxy connection failed")
        sys.exit(1)
