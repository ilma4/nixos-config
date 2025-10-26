{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    mkIf
    mkMerge
    mkOption
    types
    filterAttrs
    attrValues
    concatStringsSep
    getAttrFromPath
    filter
    map
    mapAttrs
    hasAttr
    hasAttrByPath
    isList
    isAttrs
    ;
  inherit (builtins) match elemAt toString;

  cfg = config.nginxReverseProxy or {};

  enabledCompose = lib.filterAttrs (name: v: (name != "reverse_proxy" && v.enable or true)) (config.dockerCompose or {});

  # listOf {name: str, upstream: str};
  containers = lib.pipe enabledCompose [
    (mapAttrs (_: s: lib.yaml.fromYaml s.composeFile))
    (mapAttrs (_: s: s.services or {}))
    (s: lib.trace s lib.attrsets.mergeAttrsList (lib.attrValues s))
    (filterAttrs (
      _: v:
        hasAttr "container_name" v
        && (
          let
            hasCustomResolve =
              if hasAttr "labels" v
              then
                if isList v.labels
                then (filter (l: (match "local\\.ilma4\\.customResolve=.*" l) != null) v.labels) != []
                else if isAttrs v.labels
                then hasAttr "local.ilma4.customResolve" v.labels
                else false
              else false;
            attachedReverseProxy =
              hasAttr "networks" v
              && (
                (isList v.networks && lib.elem "reverse_proxy" v.networks)
                || (isAttrs v.networks && hasAttr "reverse_proxy" v.networks)
              );
            hasExpose = hasAttr "expose" v;
          in
            hasCustomResolve || (attachedReverseProxy && hasExpose)
        )
    ))
    (mapAttrs (
      _: v: let
        name = assert (match ".*_.*" v.container_name == null); v.container_name;
        customResolve =
          if hasAttr "labels" v
          then
            if isList v.labels
            then let
              candidates = filter (l: (match "local\\.ilma4\\.customResolve=(.+)" l) != null) v.labels;
            in
              if candidates == []
              then null
              else let
                m = match "local\\.ilma4\\.customResolve=(.+)" (elemAt candidates 0);
              in
                if m == null
                then null
                else elemAt m 0
            else if isAttrs v.labels
            then
              (
                if hasAttr "local.ilma4.customResolve" v.labels
                then v.labels."local.ilma4.customResolve"
                else null
              )
            else null
          else null;
        port = let
          pRaw = toString (elemAt v.expose 0);
          m = match "([0-9]+).*" pRaw;
        in
          if m == null
          then pRaw
          else (elemAt m 0);
        upstream =
          if customResolve != null
          then
            # Allow scheme to be included; default to http if missing
            if match "https?://.*" customResolve != null
            then customResolve
            else "http://${customResolve}"
          else "http://${name}:${toString port}";
      in {
        inherit name upstream;
      }
    ))
    attrValues
  ];
  domainNames = map (c: "${c.name}.ilma4.local") containers;
  baseCertDir = "/var/lib/nginx-reverse-proxy";
  certsDir = "/var/lib/nginx-reverse-proxy/certs";
  privateDir = "/var/lib/nginx-reverse-proxy/private";
  nginxServerConfs = concatStringsSep "\n" (map (c: ''
      server {
        listen 80;
        server_name ${c.name}.ilma4.local;
        client_max_body_size 100M;
        return 301 https://$host$request_uri;
      }
      server {
        listen 443 ssl;
        server_name ${c.name}.ilma4.local;
        client_max_body_size 100M;
        resolver 10.20.0.1 valid=10s ipv6=off;
        set $upstream_target ${c.upstream};

        ssl_certificate /etc/nginx/pki/certs/${c.name}.ilma4.local.cert.pem;
        ssl_certificate_key /etc/nginx/pki/private/${c.name}.ilma4.local.key.pem;

        location / {
          proxy_pass $upstream_target;

          # These configuration options are required for WebSockets to work
          proxy_http_version 1.1;
         	proxy_set_header Upgrade $http_upgrade;
         	proxy_set_header Connection "upgrade";

          proxy_redirect off;
          proxy_set_header Host $host:$server_port;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          add_header Referrer-Policy "strict-origin-when-cross-origin";
        }
      }
    '')
    containers);
  genScript = pkgs.writeShellScript "nginx-rp-gen-certs.sh" ''
        set -euo pipefail
        umask 077
        FORCE="${"\$"}{FORCE:-0}"
        CERTS_DIR=${certsDir}
        PRIVATE_DIR=${privateDir}
        CA_KEY=$PRIVATE_DIR/ca.key.pem
        CA_CERT=$CERTS_DIR/ca.cert.pem
        CA_CONF=$PRIVATE_DIR/ca.openssl.cnf
        CA_SERIAL=$PRIVATE_DIR/ca.srl
        mkdir -p "$CERTS_DIR" "$PRIVATE_DIR"
        chmod 700 "$PRIVATE_DIR"
        chmod 755 "$CERTS_DIR"

        if [ "$FORCE" = "1" ]; then
          rm -f "$CA_KEY" "$CA_CERT" "$CA_SERIAL"
        fi
        if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_CERT" ]; then
          ${pkgs.openssl}/bin/openssl genrsa -out "$CA_KEY" 4096
          chmod 600 "$CA_KEY"
          cat > "$CA_CONF" <<EOF
    [ req ]
    default_bits = 4096
    prompt = no
    default_md = sha256
    x509_extensions = v3_ca
    distinguished_name = dn

    [ dn ]
    C = US
    O = ilma4
    CN = ilma4 local CA

    [ v3_ca ]
    subjectKeyIdentifier = hash
    authorityKeyIdentifier = keyid:always,issuer
    basicConstraints = critical, CA:true, pathlen:0
    keyUsage = critical, keyCertSign, cRLSign
    EOF
          ${pkgs.openssl}/bin/openssl req -x509 -new -key "$CA_KEY" -days 3650 -sha256 -out "$CA_CERT" -config "$CA_CONF" -extensions v3_ca
          chmod 644 "$CA_CERT"
          if [ ! -f "$CA_SERIAL" ]; then
            echo 1000 > "$CA_SERIAL"
            chmod 644 "$CA_SERIAL"
          fi
        fi

        for DOMAIN in ${lib.concatStringsSep " " domainNames}; do
          KEY="$PRIVATE_DIR/$DOMAIN.key.pem"
          CSR="$PRIVATE_DIR/$DOMAIN.csr.pem"
          CERT="$CERTS_DIR/$DOMAIN.cert.pem"
          CONF="$PRIVATE_DIR/$DOMAIN.openssl.cnf"
          if [ ! -f "$KEY" ] || [ ! -f "$CERT" ] || [ "$FORCE" = "1" ]; then
            ${pkgs.openssl}/bin/openssl genrsa -out "$KEY" 2048
            chmod 600 "$KEY"
            cat > "$CONF" <<EOF
    [ req ]
    default_bits = 2048
    prompt = no
    default_md = sha256
    req_extensions = req_ext
    distinguished_name = dn

    [ dn ]
    C = US
    O = ilma4
    CN = $DOMAIN

    [ req_ext ]
    subjectAltName = @alt_names

    [ alt_names ]
    DNS.1 = $DOMAIN
    EOF
            ${pkgs.openssl}/bin/openssl req -new -key "$KEY" -out "$CSR" -config "$CONF"
            V3CONF="$PRIVATE_DIR/$DOMAIN.v3.ext"
            cat > "$V3CONF" <<EOF
    authorityKeyIdentifier=keyid,issuer
    basicConstraints=CA:FALSE
    keyUsage = digitalSignature, keyEncipherment
    extendedKeyUsage = serverAuth
    subjectAltName = @alt_names
    [alt_names]
    DNS.1 = $DOMAIN
    EOF
            ${pkgs.openssl}/bin/openssl x509 -req -in "$CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAserial "$CA_SERIAL" -out "$CERT" -days 825 -sha256 -extfile "$V3CONF"
            chmod 644 "$CERT"
            rm -f "$CSR" "$CONF" "$V3CONF"
          fi
        done
  '';

  nginxConf = pkgs.writeText "reverse_proxy.conf" nginxServerConfs;
  composeYaml = ''
    services:
      nginx-reverse-proxy:
        image: docker.io/library/nginx:stable-alpine
        container_name: nginx-reverse-proxy
        restart: always
        volumes:
          - ${nginxConf}:/etc/nginx/conf.d/reverse_proxy.conf:ro
          - ${certsDir}:/etc/nginx/pki/certs:ro
          - ${privateDir}:/etc/nginx/pki/private:ro
        networks:
          reverse_proxy:
            ipv4_address: 10.20.0.10
        ports:
          - "80:80"
          - "443:443"

    networks:
      reverse_proxy:
        external: true
  '';
in {
  options.nginxReverseProxy = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic Nginx reverse proxy for Compose services attached to reverse_proxy network with expose defined, or services that specify the 'local.ilma4.customResolve' label.";
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

      # Nginx reverse proxy as a dockerCompose service
      dockerCompose."reverse_proxy" = {
        composeFile = "${pkgs.writeText "reverse_proxy-compose.yaml" composeYaml}";
      };

      systemd.services."reverse_proxy".reloadTriggers = [nginxConf];

      networking.firewall.allowedTCPPorts = [80 443];

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "nginx-rp-gen-certs.sh" ''
          set -euo pipefail
          exec ${genScript} "$@"
        '')
      ];

      systemd.tmpfiles.rules = [
        "d ${baseCertDir} 0755 root root -"
        "d ${certsDir} 0755 root root -"
        "d ${privateDir} 0700 root root -"
      ];

      system.activationScripts.nginxReverseProxyPki.text = "${genScript}";
    }
  ]);
}
