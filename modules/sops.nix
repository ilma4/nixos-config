{
  config,
  lib,
  flake-location,
  ...
}: {
  options = {
    i4-encrypted-files = lib.mkOption {
      type = lib.types.listOf lib.types.singleLineStr;
      default = [];
      description = "TODO";
      example = "TODO";
    };
  };
  config = {
    sops.defaultSopsFile = "${flake-location}/secrets/example.yaml";
    sops.defaultSopsFormat = "yaml";
    # sops.age.keyFile = "/home/ilma4/.config/sops/age/keys.txt";
    sops.age.keyFile =
      if (builtins.hasAttr "users" config) # true if NixOS/Nix-darwin
      then "${config.users.users.ilma4.home}/.config/sops/age/keys.txt"
      else "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    # map i4-encrypted-files
    sops.secrets = lib.pipe config.i4-encrypted-files [
      (map (name: {
        name = name;
        value = {
          format = lib.mkDefault "binary";
          sopsFile = "${flake-location}/secrets/${name}";
        };
      }))
      lib.listToAttrs
    ];
  };
}
