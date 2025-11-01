{
  config,
  inputs,
  pkgs-unstable,
  lib,
  ...
}: {
  options.i4.home-manager.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "enable home-manager options";
  };

  config = lib.mkIf config.i4.home-manager.enable {
    home-manager.useGlobalPkgs = true;
    home-manager.extraSpecialArgs = {
      inherit inputs;
      inherit pkgs-unstable;
    };
  };
}
