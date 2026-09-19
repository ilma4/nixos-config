# QBittorrent with amnezia vpn microvm

- use microvm.nix https://github.com/microvm-nix/microvm.nix
- inside vm enable amnezia vpn (use unstable package)
- inside vm enable qbittorrent nox
- port forward webui port to host
- do not port forward other ports

- amnezia vpn client requires gui to login and configure: therefore, provide vnc over ssh setup and sway

- vm has 2 cpu cores and 2GiB RAM
