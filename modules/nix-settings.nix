{
  pkgs,
  lib,
  options,
  ...
}: let
  hasNixOptimiseAutomatic =
    options ? nix
    && options.nix ? optimise
    && options.nix.optimise ? automatic;
in {
  nix =
    {
      package = lib.mkDefault pkgs.nix;
      gc.automatic = lib.mkDefault true;
      settings = {
        # allowed-users = [ "ilma4" ];
        # sandbox = true; # enabled on linux by default. Still broken on nix-darwin 25.11

        experimental-features = "nix-command flakes"; # Necessary for using flakes on this system.
      };
    }
    // lib.optionalAttrs hasNixOptimiseAutomatic {
      optimise.automatic = true;
    };
}
