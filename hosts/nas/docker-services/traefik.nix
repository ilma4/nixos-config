{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkMerge mkOption types;
  version = "v3.7.4";

  cfg = config.traefikReverseProxy or {};

  baseCertDir = "/var/lib/nginx-reverse-proxy";
  certsDir = "/var/lib/nginx-reverse-proxy/certs";
  privateDir = "/var/lib/nginx-reverse-proxy/private";

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

    if [ ! -f "$KEY" ] || [ ! -f "$CERT" ]; then
      ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 365 \
        -newkey ec \
        -sha384 \
        -pkeyopt ec_paramgen_curve:P-384 \
        -keyout "$KEY" \
        -out "$CERT" \
        -subj "/CN=*.ilma4.local/O=ilma4/C=US" \
        -addext "subjectAltName=DNS:*.ilma4.local,DNS:ilma4.local"
      chmod 600 "$KEY"
      chmod 644 "$CERT"
    fi
  '';

  dynamicYaml = pkgs.writeText "traefik-dynamic.yaml" ''
    tls:
      certificates:
        - certFile: /certs/wildcard-ec.crt
          keyFile: /private/wildcard-ec.key
  '';

  composeYaml = ''
    services:
      traefik:
        image: docker.io/library/traefik:${version}
        container_name: traefik
        restart: always
        command:
          - "--api.insecure=true"
          - "--providers.docker=true"
          - "--providers.docker.exposedbydefault=false"
          - "--providers.file.filename=/etc/traefik/dynamic.yaml"
          - "--entrypoints.web.address=:80"
          - "--entrypoints.websecure.address=:443"
          - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
          - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
        volumes:
          - /run/podman/podman.sock:/var/run/docker.sock:ro
          - ${dynamicYaml}:/etc/traefik/dynamic.yaml:ro
          - ${certsDir}:/certs:ro
          - ${privateDir}:/private:ro
        networks:
          reverse_proxy:
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
          ExecStart = "${pkgs.bash}/bin/bash -euo pipefail -c '${pkgs.podman}/bin/podman network exists reverse_proxy || ${pkgs.podman}/bin/podman network create --subnet=10.20.0.0/24 --gateway=10.20.0.1 --ip-range=10.20.0.32/27 reverse_proxy'";
        };
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

      system.activationScripts.traefikReverseProxyPki.text = "${genScript}";
    }
  ]);
}
