{
  pkgs,
  lib,
  ...
}: {
  imports = [
    "${lib.flake-location}/home/base.nix"
    "${lib.flake-location}/home/personal.nix"
    "${lib.flake-location}/home/dev.nix"
  ];

  home.username = "ilma4";
  i4.personal.enable = true;
  i4.dev.enable = true;

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    gnomeExtensions.gsconnect
    gnomeExtensions.dash-to-dock
    gnomeExtensions.caffeine
    gnome-tweaks

    (writers.writePython3Bin "set-power" {
      doCheck = false; # disable PEP style checks
    } (builtins.readFile "${lib.flake-location}/dotfiles/set-power.py"))
  ];

  programs.gnome-shell.enable = true;

  dconf = {
    enable = true;
    settings."org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = with pkgs.gnomeExtensions; [
        blur-my-shell.extensionUuid
        gsconnect.extensionUuid
        "dash-to-dock"
        "gsconnect"
      ];
    };
  };
}
