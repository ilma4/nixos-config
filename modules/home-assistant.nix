{flake-location, ...}: {
  users.users.homeassistant = {
    isSystemUser = true;
    uid = 990;
    group = "homeassistant";
  };
  users.groups.homeassistant.gid = 986;

  dockerCompose.home-assistant.composeFile = "${flake-location}/compose/home-assistant.yml";
  dockerCompose.home-assistant.environment = {
    CONFIG_DIR = "/srv/homeassistant";
  };

  systemd.tmpfiles.rules = [
    "/srv/homeassistant 0755 root root -"
  ];
  networking.firewall.allowedTCPPorts = [
    8123 # home-assistant
  ];
}
