{
  config,
  myLib,
  pkgs,
  ...
}: let
  version = "5.1.4";
  download = "/mnt/hdd/torrent";
  puid = "1000";
  pgid = "1000";
  configDir = "/srv/qbittorrent/config";
  checkIntervalSeconds = 30;
  expectedVpnIp = "185.68.21.215";
  qbittorrentContainer = "qbittorrent";
  qbittorrentUnit = "qbittorrent.service";
  restartDelay = "5m";
  stateDir = "/run/qbittorrent-vpn-ip-check";
  failureNotifiedFile = "${stateDir}/failure-notified";
  awaitingRecoveryFile = "${stateDir}/awaiting-recovery";

  vpnIpCheckScript = pkgs.writeShellScript "qbittorrent-vpn-ip-check.sh" ''
    set -euo pipefail

    STATE_DIR="${stateDir}"
    FAILURE_NOTIFIED_FILE="${failureNotifiedFile}"
    AWAITING_RECOVERY_FILE="${awaitingRecoveryFile}"

    ${pkgs.coreutils}/bin/mkdir -p "$STATE_DIR"

    while ${pkgs.systemd}/bin/systemctl --quiet is-active ${qbittorrentUnit}; do
      current_ip="$(${pkgs.podman}/bin/podman exec ${qbittorrentContainer} curl --silent https://ifconfig.me || true)"

      if [ -z "$current_ip" ]; then
        ${pkgs.coreutils}/bin/sleep ${toString checkIntervalSeconds}
        continue
      fi

      if [ "$current_ip" = "${expectedVpnIp}" ]; then
        if [ -e "$AWAITING_RECOVERY_FILE" ]; then
          echo "qBittorrent VPN IP recovered after restart: $current_ip"
        fi

        ${pkgs.coreutils}/bin/rm -f "$FAILURE_NOTIFIED_FILE" "$AWAITING_RECOVERY_FILE"
        ${pkgs.coreutils}/bin/sleep ${toString checkIntervalSeconds}
        continue
      fi

      if [ ! -e "$FAILURE_NOTIFIED_FILE" ]; then
        echo "qBittorrent VPN IP mismatch detected: got $current_ip, expected ${expectedVpnIp}"
        ${pkgs.coreutils}/bin/touch "$FAILURE_NOTIFIED_FILE"
      else
        echo "qBittorrent VPN IP mismatch persists: got $current_ip, expected ${expectedVpnIp}"
      fi

      ${pkgs.coreutils}/bin/touch "$AWAITING_RECOVERY_FILE"

      ${pkgs.systemd}/bin/systemd-run \
        --quiet \
        --unit=qbittorrent-vpn-restart \
        --on-active=${restartDelay} \
        --replace \
        --property=Type=oneshot \
        ${pkgs.systemd}/bin/systemctl start ${qbittorrentUnit}

      ${pkgs.systemd}/bin/systemctl stop ${qbittorrentUnit}
      exit 0
    done
  '';
in {
  dockerCompose.qbittorrent = {
    composeText = ''
      services:
        qbittorrent:
          container_name: qbittorrent
          image: ghcr.io/hotio/qbittorrent:release-${version}
          labels:
            - "traefik.enable=true"
            - "traefik.http.routers.qbittorrent.rule=Host(`torrent.ilma4.home.arpa`)"
            - "traefik.http.routers.qbittorrent.entrypoints=websecure"
            - "traefik.http.routers.qbittorrent.tls=true"
            - "traefik.http.routers.qbittorrent.middlewares=qbittorrent-headers"
            - "traefik.http.middlewares.qbittorrent-headers.headers.customrequestheaders.Origin="
            - "traefik.http.middlewares.qbittorrent-headers.headers.customrequestheaders.Referer="
            - "traefik.http.services.qbittorrent.loadbalancer.server.port=8080"
            - "traefik.http.services.qbittorrent.loadbalancer.passhostheader=false"
          expose:
            - "8080"
          networks:
            - reverse_proxy
          environment:
            - VPN_ENABLED=true
            - VPN_PROVIDER=generic
            - PUID=${puid}
            - PGID=${pgid}
            - UMASK=002
            - WEBUI_PORTS=8080/tcp
          volumes:
            - "/etc/localtime:/etc/localtime:ro"
            - "${configDir}:/config"
            - "${download}:/downloads"
            - "/home/ilma4/torrents:/ssd-downloads"
            - "${config.sops.secrets.wg-conf.path}:/config/wireguard/wg0.conf:ro"
          cap_add:
            - NET_ADMIN
          sysctls:
            - net.ipv4.conf.all.src_valid_mark=1
          restart: unless-stopped

      networks:
        reverse_proxy:
          external: true
    '';
  };

  sops.secrets.wg-conf = {
    sopsFile = "${myLib.secrets}/ru-torrent-wg.conf";
    format = "binary";
  };

  systemd.tmpfiles.rules = [
    "d /srv/qbittorrent 0775 ${puid} ${pgid} -"
    "d ${configDir} 0775 ${puid} ${pgid} -"
  ];

  systemd.services.qbittorrent-vpn-ip-check = {
    description = "Check qBittorrent public IP stays on the VPN endpoint";
    after = [qbittorrentUnit];
    bindsTo = [qbittorrentUnit];
    partOf = [qbittorrentUnit];
    requires = [qbittorrentUnit];
    wantedBy = [qbittorrentUnit];
    serviceConfig = {
      ExecStart = vpnIpCheckScript;
      Restart = "on-failure";
      RestartSec = "10s";
      Type = "simple";
    };
  };
}
