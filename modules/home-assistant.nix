{...}: let
  home-assistant-version = "2025.4.1";
in {
  users.users.homeassistant = {
    isSystemUser = true;
    uid = 990;
    group = "homeassistant";
  };
  users.groups.homeassistant.gid = 986;

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
  };
  networking.firewall.allowedTCPPorts = [
    8123 # home-assistant
  ];
}
