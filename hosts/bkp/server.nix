{
  config,
  lib,
  pkgs,
  ...
}: {
  users.users = {
    homer = {
      isSystemUser = true;
      group = "homer";
    };
    homeassistant = {
      isSystemUser = true;
      group = "homeassistant";
    };
  };
  users.groups.homeassistant = {};
  users.groups.homer = {};

  virtualisation.oci-containers.containers = {
    homeassistant = {
      image = "ghcr.io/home-assistant/home-assistant:stable";
      volumes = [
        "/srv/homeassistant:/config"
        "/etc/localtime:/etc/localtime:ro"
        "/run/dbus:/run/dbus:ro"
      ];
      autoStart = true;
      extraOptions = ["--privileged" "--network=host"];
    };

    homer = {
      image = "b4bz/homer:latest";
      ports = ["8080:8080"];
      volumes = ["/srv/homer:/www/assets"];
      autoStart = true;
      # user = "homer";
    };
  };

  networking.firewall.allowedTCPPorts = [
    8123 # homeassistant
    8080 # homer
  ];
}
