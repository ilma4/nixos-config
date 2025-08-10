{
  config,
  pkgs,
  flake-location,
  ...
}: {
  imports = [
    "${flake-location}/home/base.nix"
    "${flake-location}/home/personal.nix"
    "${flake-location}/home/gui-apps.nix"
    "${flake-location}/home/jetbrains.nix"
    "${flake-location}/home/dev.nix"
  ];

  home.username = "ilma4";
  flake-location = "${config.home.homeDirectory}/nixos";

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    gnomeExtensions.gsconnect
    gnomeExtensions.dash-to-dock
    gnomeExtensions.caffeine
    gnome-tweaks

    (writers.writePython3Bin "set-power" {
      doCheck = false; # disable PEP style checks
    } (builtins.readFile "${flake-location}/dotfiles/set-power.py"))
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
