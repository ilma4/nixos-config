{
  config,
  constants,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkMerge mkOption types;

  cfg = config.traefikReverseProxy or {};

  baseCertDir = "/var/lib/nginx-reverse-proxy";
  certsDir = "/var/lib/nginx-reverse-proxy/certs";
  privateDir = "/var/lib/nginx-reverse-proxy/private";
  reverseProxySubnet = "10.20.0.0/24";
  reverseProxyGateway = constants.nas.reverse-proxy-gateway;
  obsidian = constants.nas.obsidian-webdav;

  genScript = pkgs.writeShellScript "traefik-rp-gen-certs.sh" ''
    set -euo pipefail
    umask 077
    FORCE="''${FORCE:-0}"
    CERTS_DIR=${certsDir}
    PRIVATE_DIR=${privateDir}
    mkdir -p "$CERTS_DIR" "$PRIVATE_DIR"
    chmod 700 "$PRIVATE_DIR"
    chmod 755 "$CERTS_DIR"

    KEY="$PRIVATE_DIR/wildcard-ec.key"
    CERT="$CERTS_DIR/wildcard-ec.crt"

    if [ "$FORCE" = "1" ]; then
      rm -f "$KEY" "$CERT"
    fi

    # Rotate certificates left over from the previous reverse-proxy domain.
    if [ -f "$CERT" ] && ! ${pkgs.openssl}/bin/openssl x509 \
      -in "$CERT" -noout -checkhost home-assistant.ilma4.home.arpa >/dev/null 2>&1; then
      rm -f "$KEY" "$CERT"
    fi

    if [ ! -f "$KEY" ] || [ ! -f "$CERT" ]; then
      ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 365 \
        -newkey ec \
        -sha384 \
        -pkeyopt ec_paramgen_curve:P-384 \
        -keyout "$KEY" \
        -out "$CERT" \
        -subj "/CN=*.ilma4.home.arpa/O=ilma4/C=US" \
        -addext "subjectAltName=DNS:*.ilma4.home.arpa,DNS:ilma4.home.arpa"
      chmod 600 "$KEY"
      chmod 644 "$CERT"
    fi
  '';

  dynamicYaml = pkgs.writeText "traefik-dynamic.yaml" ''
    http:
      routers:
        cypht:
          rule: "Host(`${constants.mail-archive.cypht.host}`)"
          entryPoints:
            - websecure
          service: cypht
          tls: {}
        ntfy:
          rule: "Host(`${constants.ntfy.host}`)"
          entryPoints:
            - websecure
          service: ntfy
          tls: {}
        qbittorrent:
          rule: "Host(`qbittorrent.ilma4.home.arpa`)"
          entryPoints:
            - websecure
          service: qbittorrent
          tls: {}
        obsidian-webdav:
          rule: "Host(`${obsidian.host}`)"
          entryPoints:
            - websecure
          middlewares:
            - obsidian-webdav-clients
          service: obsidian-webdav
          tls:
            certResolver: tailscale
      middlewares:
        obsidian-webdav-clients:
          ipAllowList:
            sourceRange:
              - "192.168.1.0/24"
              - "100.64.0.0/10"
              - "fd7a:115c:a1e0::/48"
      services:
        cypht:
          loadBalancer:
            servers:
              - url: "http://${constants.mail-archive.cypht.proxyGateway}:${toString constants.mail-archive.cypht.port}"
        ntfy:
          loadBalancer:
            servers:
              - url: "http://${reverseProxyGateway}:${toString constants.ntfy.port}"
        qbittorrent:
          loadBalancer:
            servers:
              - url: "http://${reverseProxyGateway}:8080"
        obsidian-webdav:
          loadBalancer:
            servers:
              - url: "http://${reverseProxyGateway}:${toString obsidian.port}"

    tls:
      certificates:
        - certFile: /certs/wildcard-ec.crt
          keyFile: /private/wildcard-ec.key
  '';

  composeYaml = ''
    services:
      traefik:
        image: docker.io/library/traefik:v3
        container_name: traefik
        restart: always
        command:
          - "--api.insecure=true"
          - "--providers.docker=true"
          - "--providers.docker.exposedbydefault=false"
          - "--providers.file.filename=/etc/traefik/dynamic.yaml"
          - "--certificatesresolvers.tailscale.tailscale=true"
          - "--entrypoints.web.address=:80"
          - "--entrypoints.websecure.address=:443"
          - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
          - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
        volumes:
          - /run/podman/podman.sock:/var/run/docker.sock:ro
          - /run/tailscale:/var/run/tailscale:ro
          - ${dynamicYaml}:/etc/traefik/dynamic.yaml:ro
          - ${certsDir}:/certs:ro
          - ${privateDir}:/private:ro
        networks:
          reverse_proxy:
            ipv4_address: ${constants.nas.traefik-ip}
        ports:
          - "80:80"
          - "443:443"
          # - "8080:8080"

    networks:
      reverse_proxy:
        external: true
  '';
in {
  options.traefikReverseProxy = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Traefik reverse proxy.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Ensure the reverse_proxy podman network exists
      systemd.services.podman-network-reverse_proxy = {
        description = "Ensure podman network reverse_proxy exists";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.bash}/bin/bash -euo pipefail -c '${pkgs.podman}/bin/podman network exists reverse_proxy || ${pkgs.podman}/bin/podman network create --subnet=${reverseProxySubnet} --gateway=${reverseProxyGateway} --ip-range=10.20.0.32/27 reverse_proxy'";
        };
      };

      systemd.services.traefik-reverse-proxy-pki = {
        description = "Generate the Traefik reverse proxy certificate";
        before = ["docker-compose-reverse_proxy.service"];
        requiredBy = ["docker-compose-reverse_proxy.service"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${genScript}";
        };
      };

      systemd.services.docker-compose-reverse_proxy.restartTriggers = [genScript];
      # Keep Traefik's directory bind mount valid when tailscaled recreates its socket.
      systemd.services.tailscaled.serviceConfig.RuntimeDirectoryPreserve = "yes";
      systemd.services.reverse_proxy = {
        after = ["tailscaled.service"];
        wants = ["tailscaled.service"];
        preStart = ''
          set -euo pipefail
          # Wait for the tailnet to advertise certificate domains after the daemon starts.
          for attempt in {1..30}; do
            if ${config.services.tailscale.package}/bin/tailscale status --json --peers=false \
              | ${pkgs.jq}/bin/jq --exit-status --arg domain '${obsidian.host}' \
                '.BackendState == "Running" and ((.CertDomains // []) | index($domain) != null)' >/dev/null; then
              exit 0
            fi
            sleep 1
          done
          echo "Tailscale did not advertise the Obsidian certificate domain before Traefik startup." >&2
        '';
      };

      dockerCompose."reverse_proxy" = {
        composeText = composeYaml;
      };

      networking.firewall.allowedTCPPorts = [80 443 8080];

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "traefik-rp-gen-certs.sh" ''
          set -euo pipefail
          exec ${genScript} "$@"
        '')
      ];

      systemd.tmpfiles.rules = [
        "d ${baseCertDir} 0755 root root -"
        "d ${certsDir} 0755 root root -"
        "d ${privateDir} 0700 root root -"
      ];
    }
  ]);
}
