#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname)" = "Darwin" ]; then
    podman machine start || true
fi

VPN_IP="185.68.21.215"
CHECKER_PID=""
export WG_CONFIG="${WG_CONFIG:-/Users/ilma4/.local/share/qbittorrent-container/wg.conf}"

cleanup() {
    echo "Caught signal, cleaning up..."
    [ -n "$CHECKER_PID" ] && kill $CHECKER_PID 2>/dev/null || true
    podman stop qbittorrent >/dev/null 2>&1 || true
    exit 0
}
trap cleanup SIGINT SIGTERM

podman volume create qbittorrent_config >/dev/null || true

while true; do
    podman run \
        --rm \
        --name qbittorrent \
        -p 127.0.0.1:8080:8080 \
        -e VPN_ENABLED=true \
        -e VPN_CONF=wg0 \
        -e VPN_PROVIDER=generic \
        -e VPN_LAN_NETWORK=192.168.0.0/16 \
        -e WEBUI_PORTS="8080/tcp" \
        -e PUID=1000 \
        -e PGID=1000 \
        -e UMASK=002 \
        -e TZ=Etc/UTC \
        -v /etc/localtime:/etc/localtime:ro \
        -v /Users/ilma4/Downloads/Torrent/torrent-vm:/downloads \
        -v qbittorrent_config:/config \
        -v "${WG_CONFIG}:/config/wireguard/wg0.conf:ro" \
        --cap-add NET_ADMIN \
        ghcr.io/hotio/qbittorrent:release &
    CONTAINER_PID=$!

    (
        while true; do
            sleep 30
            CURRENT_IP=$(podman exec qbittorrent curl --silent https://ifconfig.me || true)
            if [ "$CURRENT_IP" != "${VPN_IP}" ] && [ -n "$CURRENT_IP" ]; then
                echo "IP changed to $CURRENT_IP, expected ${VPN_IP}. Stopping container."
                podman stop qbittorrent || true
                break
            fi
        done
    ) &
    CHECKER_PID=$!

    wait $CONTAINER_PID || true
    kill $CHECKER_PID 2>/dev/null || true

    echo "Container stopped. Restarting in 5 minutes..."
    sleep 300
done
