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

  /*
  containers.immich = let port = 2283; in {
    forwardPorts = {
      containerPort = port;
      hostPort = port;
      protocol = "tcp";
    };
    
    bindMounts = {
      "/srv/immich" = { 
        #hostPath = "/srv/nixos-immich";
        hostPath = "/mnt/hdd/immich"; # mediaLocation
        isReadOnly = false;
      };
      # "/etc/localtime" = { hostPath = "/etc/localtime"; };
    };

    autoStart = true;
    config = let
      hostConfig = config;
    in
      {
        config,
        pkgs,
        ...
      }: {
        services.immich = {
          enable = true;
          host = "0.0.0.0";
          port = port;
          mediaLocation = "/srv/immich"; # databases are stored inside container
        };

        networking = {
          firewall.allowedTCPPorts = [port];
          useHostResolvConf = lib.mkForce false; # FIXME
        };

        system.stateVersion = "24.11";
      };
  };
  */

  networking.firewall.allowedTCPPorts = [
    8123 # home-assistant
    8080 # homer
    2283 # immich
  ];
}
