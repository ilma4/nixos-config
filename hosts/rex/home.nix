{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../home/base.nix
    ../../home/personal.nix
    ../../home/dev.nix
  ];

  home.username = "ilma4";
  rebuild-script = "sudo nixos-rebuild switch --flake ${config.home.homeDirectory}/.config/nixos-config#rex";

  i4.personal.enable = true;
  i4.dev.enable = true;

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    gnomeExtensions.caffeine
    gnome-tweaks

    (writers.writePython3Bin "set-power" {
      doCheck = false; # disable PEP style checks
    } (builtins.readFile ../../scripts/set-power.py))
  ];

  programs.gnome-shell = {
    enable = true;
    extensions = with pkgs.gnomeExtensions; [
      {package = blur-my-shell;}
      {package = gsconnect;}
      {package = dash-to-dock;}
    ];
  };

  dconf = {
    enable = true;
    settings."org/gnome/shell" = {
      disable-user-extensions = false;
    };
  };
}
