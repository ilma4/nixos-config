{
  config,
  lib,
  pkgs,
  ...
}: {
  users.users.homer = {
    isSystemUser = true;
    uid = 989;
    group = "homer";
  };
  users.groups.homer.gid = 985;

  dockerCompose.homer = let
    uidGid = "${toString config.users.users.homer.uid}:${toString config.users.groups.homer.gid}";
  in {
    enable = true;
    composeFile = pkgs.writeText "homer.yml" ''
      version: "3.8"
      services:
        dashboard:
          image: b4bz/homer:latest
          container_name: dashboard
          expose:
            - "8080"

          networks:
            reverse_proxy:

          volumes:
            - /etc/localtime:/etc/localtime:ro
            - ${lib.flake-location}/dotfiles/homer:/www/assets:ro

          user: "${uidGid}"
          restart: unless-stopped

      networks:
        reverse_proxy:
          external: true
    '';
  };
}
