{
  config,
  lib,
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
    sops.defaultSopsFile = "${lib.flake-location}/secrets/example.yaml";
    sops.defaultSopsFormat = "yaml";
    # sops.age.keyFile = "/home/ilma4/.config/sops/age/keys.txt";
    # This will generate a new key if the key specified above does not exist
    sops.age.generateKey = true;
    sops.age.keyFile =
      if (builtins.hasAttr "users" config) # true if NixOS/Nix-darwin
      then "/var/lib/sops-nix/keys.txt"
      else "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    # map i4-encrypted-files
    sops.secrets = lib.pipe config.i4-encrypted-files [
      (map (name: {
        name = name;
        value = {
          format = lib.mkDefault "binary";
          sopsFile = "${lib.flake-location}/secrets/${name}";
        };
      }))
      lib.listToAttrs
    ];
  };
}
