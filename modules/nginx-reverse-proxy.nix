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

  # listOf {name: str, port: int};
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
  composeYaml = ''
    version: "3.8"
    services:
      reverse-proxy:
        image: docker.io/library/nginx:stable-alpine
        container_name: reverse-proxy
        restart: always
        networks:
          - reverse_proxy
        # volumes:
          # - ${confDir}:/etc/nginx/conf.d:ro
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
        composeStr = composeYaml;
      };

      networking.firewall.allowedTCPPorts = [80 443];
    }
  ]);
}
