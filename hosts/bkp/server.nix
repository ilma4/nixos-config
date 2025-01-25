{
  config,
  lib,
  pkgs,
  dotfiles,
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


  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    defaultNetwork.settings = {
      # Required for container networking to be able to use names.
      dns_enabled = true;
    };
  };

  # allows dns resolving for containers on custom networks
  networking.firewall.interfaces."podman+".allowedUDPPorts = [ 53 ];

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
      # ports = ["8080"];
      volumes = ["${dotfiles}/homer:/www/assets:ro" "/etc/passwd:/etc/passwd:ro" "/etc/group:/etc/group:ro"];
      autoStart = true;
      user = "homer:homer";
      hostname = "homer";
      extraOptions = ["--network=nginx"];
    };

    nginx = {
      image = "nginx:stable";
      ports = ["80:80" "443:443"];
      volumes = ["${dotfiles}/nginx:/etc/nginx:ro" /*"/etc/letsencrypt:/etc/letsencrypt:ro"*/ ];
      autoStart = true;
      extraOptions = ["--network=nginx"];
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
    ipv6 = true;
    publish = {
      enable = true;
      domain = true;
      addresses = true;
    };
    reflector = true;
  };

  networking.firewall.allowedTCPPorts = [
    8123 # home-assistant
    8080 # homer
    2283 # immich

    # nginx
    80
    443
  ];
}
