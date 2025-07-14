{
  config,
  flake-location,
  ...
}: let
  homer-version = "latest";
in {
  users.users.homer = {
    isSystemUser = true;
    uid = 989;
    group = "homer";
  };
  users.groups.homer.gid = 985;

  virtualisation.oci-containers.containers = {
    homer = {
      image = "b4bz/homer:${homer-version}";
      ports = ["80:8080"];
      volumes = ["${flake-location}/dotfiles/homer:/www/assets:ro"];
      autoStart = true;
      user = "${toString config.users.users.homer.uid}:${toString config.users.groups.homer.gid}";
      # hostname = "homer";
      # extraOptions = ["--network=nginx"];
    };
  };
  networking.firewall.allowedTCPPorts = [
    80 # homer
  ];
}
