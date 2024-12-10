{
  config,
  pkgs,
  inputs,
  modules,
  dotfiles,
  ...
}: {
  imports = [
    "${modules}/base.nix"
    "${modules}/personal.nix"
    "${modules}/gui-apps.nix"
    "${modules}/jetbrains.nix"
    "${modules}/gaming.nix"
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
