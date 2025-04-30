{
  config,
  lib,
  pkgs,
  dotfiles,
  ...
}: let
  home-assistant-version = "2025.4.1";
  homer-version = "v25.04.1";
  stirling-pdf-version = "0.45.4";
in {
  users.users = {
    homer = {
      isSystemUser = true;
      uid = 989;
      group = "homer";
    };
    homeassistant = {
      isSystemUser = true;
      uid = 990;
      group = "homeassistant";
    };
    actual-budget = {
      isSystemUser = true;
      uid = 800;
      group = "actual-budget";
    };
  };
  users.groups = {
    homeassistant.gid = 986;
    homer.gid = 985;
    actual-budget.gid = config.users.users.actual-budget.uid;
  };

  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    defaultNetwork.settings = {
      # Required for container networking to be able to use names.
      dns_enabled = true;
    };
  };

  # Enable container name DNS for non-default Podman networks.
  # https://github.com/NixOS/nixpkgs/issues/226365
  networking.firewall.interfaces."podman+".allowedUDPPorts = [53];

  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers = {
    homeassistant = {
      image = "ghcr.io/home-assistant/home-assistant:${home-assistant-version}";
      volumes = [
        "/srv/homeassistant:/config"
        "/etc/localtime:/etc/localtime:ro"
        "/run/dbus:/run/dbus:ro"
      ];
      autoStart = true;
      extraOptions = ["--privileged" "--network=host"];
    };

    homer = {
      image = "b4bz/homer:${homer-version}";
      ports = ["80:8080"];
      volumes = ["${dotfiles}/homer:/www/assets:ro"];
      autoStart = true;
      user = "${toString config.users.users.homer.uid}:${toString config.users.groups.homer.gid}";
      # hostname = "homer";
      # extraOptions = ["--network=nginx"];
    };

    syncthing = {
      image = "syncthing/syncthing:latest";
      ports = [
        "8384:8384"
        "22000:22000"
        "21027:21027/udp"
      ];
      volumes = [
        "/srv/syncthing:/var/syncthing"
        "/srv/Pictures/Oneplus10R:/var/syncthing/Pictures/Oneplus10R"
        "/srv/Pictures/GalaxyS24:/var/syncthing/Pictures/GalaxyS24"
        "/etc/localtime:/etc/localtime:ro"
      ];
      hostname = "ilma4-bkp-syncthing";
      extraOptions = ["--network=host"]; # so UPnP mapping will work
      # TODO: healthcheck
    };

    stirling-pdf = {
      # pdf tools
      image = "docker.io/stirlingtools/stirling-pdf:${stirling-pdf-version}";
      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "/srv/stirling-pdf/trainingData:/usr/share/tessdata"
        "/srv/stirling-pdf/extraConfigs:/configs"
        "/srv/stirling-pdf/logs:/logs"
        "/srv/stirling-pdf/pipeline:/pipeline"
      ];
      ports = ["8085:8080"];
      autoStart = true;
    };

    actual-budget = {
      image = "docker.io/actualbudget/actual-server:latest-alpine";
      volumes = [
        "/srv/actual-budget:/data:rw"
      ];
      ports = [
        "5006:5006/tcp"
      ];
      user = "${toString config.users.users.actual-budget.uid}:${toString config.users.groups.actual-budget.gid}";
      extraOptions = [
        "--health-cmd=node src/scripts/health-check.js"
        "--health-interval=1m0s"
        "--health-retries=3"
        "--health-start-period=20s"
        "--health-timeout=10s"
      ];
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
    80 # homer
    2283 # immich
    8085 # stirling-pdf (pdf tools)
    5006 # actual-budget

    # syncthing
    8334
    22000

    443 # https for tailscale serve
  ];

  networking.firewall.allowedUDPPorts = [
    #syncthing
    22000
    21027
  ];
}
