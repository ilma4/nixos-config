{
  config,
  lib,
  myLib,
  ...
}: {
  options = {
    i4.sops.enable = lib.mkEnableOption "enable sops options";

    i4-encrypted-files = lib.mkOption {
      type = lib.types.listOf lib.types.singleLineStr;
      default = [];
      description = "TODO";
      example = "TODO";
    };
  };

  config = lib.mkIf config.i4.sops.enable {
    sops.defaultSopsFile = "${myLib.secrets}/example.yaml";
    sops.defaultSopsFormat = "yaml";

    sops.age.keyFile =
      if (builtins.hasAttr "users" config) # true if NixOS/Nix-darwin
      then "/var/lib/sops-nix/age/keys.txt"
      else "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    # This will generate a new key if the key specified above does not exist
    sops.age.generateKey = true;

    # Do not import ssh keys, only my own
    sops.age.sshKeyPaths = [];
    sops.gnupg.sshKeyPaths = [];

    # map i4-encrypted-files
    sops.secrets = lib.pipe config.i4-encrypted-files [
      (map (file: {
        name = file;
        value = {
          format = lib.mkDefault "binary";
          sopsFile = file;
        };
      }))
      lib.listToAttrs
    ];
  };
}
