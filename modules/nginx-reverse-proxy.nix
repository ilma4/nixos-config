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

  enabledCompose = lib.filterAttrs (name: v: (name != "reverse-proxy" && v.enable or true)) (config.dockerCompose or {});

  # listOf {name: str, port: int};
  containers = lib.pipe enabledCompose [
    (mapAttrs (_: s: lib.yaml.fromYaml s.composeFile))
    (filterAttrs (_: s: hasAttrByPath ["networks" "reverse_proxy" "external"] s && getAttrFromPath ["networks" "reverse_proxy" "external"] s == true))
    (mapAttrs (
      _: s:
        filterAttrs (
          _: v:
            hasAttr "container_name" v
            && hasAttr "expose" v
            && hasAttr "networks" v
            && (
              (isList v.networks && lib.elem "reverse_proxy" v.networks)
              || (isAttrs v.networks && hasAttr "reverse_proxy" v.networks)
            )
        )
        (s.services or {})
    ))
    (s: lib.trace s lib.attrsets.mergeAttrsList (lib.attrValues s))
    (mapAttrs (_: s: {
      name = assert (match ".*_.*" s.container_name == null); s.container_name;
      port = let
        pRaw = toString (elemAt s.expose 0);
        m = match "([0-9]+).*" pRaw;
      in
        if m == null
        then pRaw
        else (elemAt m 0);
    }))
    attrValues
  ];
  nginxServerConfs = concatStringsSep "\n" (map (c: ''
      server {
        listen 80;
        server_name ${c.name}.ilma4.local;
        location / {
          proxy_pass http://${c.name}:${toString c.port};
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        }
      }
    '')
    containers);
  nginxConf = pkgs.writeText "reverse-proxy.conf" nginxServerConfs;
  composeYaml = ''
    version: "3.8"
    services:
      reverse-proxy:
        image: docker.io/library/nginx:stable-alpine
        container_name: reverse-proxy
        restart: always
        volumes:
          - ${nginxConf}:/etc/nginx/conf.d/reverse-proxy.conf:ro
        networks:
          - reverse_proxy
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

      # Nginx reverse proxy as a dockerCompose service
      dockerCompose."reverse-proxy" = {
        composeFile = "${pkgs.writeText "reverse-proxy-compose.yaml" composeYaml}";
      };

      networking.firewall.allowedTCPPorts = [80 443];
    }
  ]);
}
