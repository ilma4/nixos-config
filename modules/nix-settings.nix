{
  pkgs,
  myLib,
  ...
}:
myLib.unifiedModules.enableForConfigurations [
  "isDarwin"
  "isNixos"
  "isHome"
] {
  nix = {
    package = pkgs.nix;
    gc.automatic = true;
    optimise.automatic = true;
    settings = {
      # allowed-users = [ "ilma4" ];
      # sandbox = true; # enabled on linux by default. Still broken on nix-darwin 25.11

      auto-optimise-store = false; # DO NOT enable. Use optimize.automatic instead
      experimental-features = "nix-command flakes"; # Necessary for using flakes on this system.
    };
  };
}
