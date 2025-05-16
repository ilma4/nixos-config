{
  config,
  lib,
  secrets,
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
    sops.defaultSopsFile = "${secrets}/example.yaml";
    sops.defaultSopsFormat = "yaml";

    # map i4-encrypted-files
    sops.secrets = lib.pipe config.i4-encrypted-files [
      (map (name: {
        name = name;
        value = {
          format = lib.mkDefault "binary";
          sopsFile = "${secrets}/${name}";
        };
      }))
      lib.listToAttrs
    ];
  };
}
