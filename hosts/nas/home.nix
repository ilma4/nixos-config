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
  ];

  home.username = "ilma4";
  flake-location = "${config.home.homeDirectory}/nixos";

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    (writers.writePython3Bin "set-power" {
      doCheck = false; # disable PEP style checks
    } (builtins.readFile "${dotfiles}/set-power.py"))
  ];
}
