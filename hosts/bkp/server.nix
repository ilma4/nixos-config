{
  config,
  lib,
  pkgs,
  ...
}: {
  users.users = {
    vaultwarden.isSystemUser = true;
    homer.isSystemUser = true;
    homeassistant.isSystemUser = true;
    mosquitto.isSystemUser = true;
  };

  virtualisation.oci-containers.containers = {
    vaultwarden = {
      image = "vaultwarden/server:latest";
      ports = [
        "8222:80"
      ];
      volumes = ["/srv/vaultwarden:/data"];
      autoStart = true;
      user = "vaultwarden";
    };

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

    mosquitto = {
      image = "eclipse-mosquitto:latest";
      ports = ["1883:1883"];
      volumes = ["/srv/mosquitto:/mosquitto"];
      autoStart = true;
      user = "mosquitto";
    };

    homer = {
      image = "b4bz/homer:latest";
      ports = ["8080:8080"];
      volumes = ["/srv/homer:/www/assets"];
      autoStart = true;
      user = "homer";
    };
  };

  networking.firewall.allowedTCPPorts = [
    8123 # homeassistant
    8222 # vaultwarden
    1883 # mosquitto (aka eclipse-mqtt)
    8080 # homer
  ];
}
