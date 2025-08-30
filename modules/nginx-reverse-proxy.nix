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
    escapeShellArg
    getAttrFromPath
    filter
    map
    fromYaml
    mapAttrs
    hasAttr
    hasAttrByPath
    ;
  inherit (builtins) match;

  cfg = config.nginxReverseProxy or {};

  enabledCompose = filterAttrs (_: v: (v.enable or true)) (config.dockerCompose or {});
  composeFiles = map (v: v.composeFile) (attrValues enabledCompose);

  confDir = "/var/lib/nginx-reverse-proxy/conf";

  containers = lib.pipe enabledCompose [
    (mapAttrs (_: s: fromYaml s.composeFile))
    (filter (s: getAttrFromPath ["networks" "reverse_proxy" "external"] s == true))
    (mapAttrs (_: s: filterAttrs (_: v: hasAttr "container_name" v && hasAttrByPath ["networks" "reverse_proxy"] v && hasAttr "expose" v) s))
    (s: lib.attrsets.mergeAttrsList (lib.attrValues s))
    (mapAttrs (_: s: {
      name = assert (match ".*_.*" s.container_name == null); s.container_name;
      port = s.expose [0];
    }))
    attrValues
  ];

  generatorScript = pkgs.writeShellScript "nginx-reverse-proxy-generate" ''
        set -euo pipefail

        mkdir -p ${confDir}

        tmp="$(mktemp)"
        trap 'rm -f "$tmp"' EXIT

        # Common Nginx configuration + server boilerplate
        cat > "$tmp" <<'EOF'
        map $http_upgrade $connection_upgrade {
          default upgrade;
          \'\' close;
        }

        server {
          listen 80 default_server;
          server_name _;

          # Common proxy settings
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;

          # Tuning
          client_max_body_size 100m;
          sendfile on;

          # Health check
          location = /healthz {
            return 200 "ok";
            add_header Content-Type text/plain;
          }
        EOF

        # Discover services from compose files that:
        # - are connected to the reverse_proxy network
        # - have an expose directive
        for file in \
          ${concatStringsSep " \\\n      " (map escapeShellArg composeFiles)}
        ; do
          [ -f "$file" ] || continue

          # TODO: use https://github.com/jim3692/yaml.nix to convert YAML to attrset during build-time
          # Using yq (Go) to convert to JSON and jq to filter for matching services
          yq -o=json '.' "$file" | jq -r '
            .services // {} | to_entries[] |
            select(
              ((.value.networks? // [] | type) as $t |
                if $t == "array" then (.value.networks | index("reverse_proxy") != null)
                elif $t == "object" then (.value.networks | has("reverse_proxy"))
                else false end
              )
              and ((.value.expose? // []) | length > 0)
            ) |
            [.key, (.value.expose[0] | tostring)] | @tsv
          ' | while IFS=$'\t' read -r name port; do
            # Normalize port (drop protocol suffixes like /tcp and ranges like 8080-8090)
            port="${"\$"}{port%%/*}"
            port="${"\$"}{port%%-*}"

            if [ -n "$name" ] && [ -n "$port" ]; then
              cat >> "$tmp" <<EOF2
          location /$name/ {
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_pass http://$name:$port/;
          }
    EOF2
            fi
          done
        done

        # Close the server block
        echo '}' >> "$tmp"

        # Atomically update generated config
        install -D -m 0644 "$tmp" "${confDir}/generated.conf"
  '';

  composeYaml = pkgs.writeText "reverse-proxy.compose.yml" ''
    version: "3.8"
    services:
      reverse-proxy:
        image: docker.io/library/nginx:stable-alpine
        container_name: reverse-proxy
        restart: always
        networks:
          - reverse_proxy
        volumes:
          - ${confDir}:/etc/nginx/conf.d:ro
        ports:
          - "80:80"

    networks:
      reverse_proxy:
        external: true
  '';
in {
  options.nginxReverseProxy = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic Nginx reverse proxy for Compose services attached to reverse_proxy network with expose defined.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Ensure the reverse_proxy podman network exists
      systemd.services.podman-network-reverse-proxy = {
        description = "Ensure podman network reverse_proxy exists";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.bash}/bin/bash -euo pipefail -c '${pkgs.podman}/bin/podman network exists reverse_proxy || ${pkgs.podman}/bin/podman network create reverse_proxy'";
        };
      };

      # Generate Nginx config from dockerCompose YAMLs
      systemd.services.reverse-proxy-config = {
        description = "Generate Nginx config for reverse_proxy-attached Compose services";
        wantedBy = ["multi-user.target"];
        after = ["podman-network-reverse-proxy.service"];
        requires = ["podman-network-reverse-proxy.service"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${generatorScript}/bin/nginx-reverse-proxy-generate";
        };
        path = [pkgs.coreutils pkgs.jq pkgs.yq-go];
        # Re-run generator when compose files change (on switch)
        restartTriggers = map (f: builtins.readFile f) composeFiles;
      };

      # Nginx reverse proxy as a dockerCompose service
      dockerCompose."reverse-proxy" = {
        enable = true;
        composeFile = composeYaml;
      };

      # Make the compose service depend on config and network
      systemd.services."reverse-proxy" = {
        after = ["reverse-proxy-config.service" "podman-network-reverse-proxy.service"];
        requires = ["reverse-proxy-config.service" "podman-network-reverse-proxy.service"];
      };

      networking.firewall.allowedTcpPorts = [80 443];

      # home.packages = [
      #   pkgs.writeShellScriptBin
      #   "debug-nginx-reverse-proxy"
      #   ''
      #     echo ${builtins.toJSON containers}
      #   ''
      # ];
    }
  ]);
}
