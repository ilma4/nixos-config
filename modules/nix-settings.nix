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
      sandbox = true; # enabled on linux by default FIXME: broken on nix-darwin 24.11, TODO: check on nix-darwin 25.05, should be fixed

      auto-optimise-store = false; # DO NOT enable. Use optimize.automatic instead
      experimental-features = "nix-command flakes"; # Necessary for using flakes on this system.
    };
  };
}
