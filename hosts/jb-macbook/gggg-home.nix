{
  config,
  lib,
  pkgs,
  modules,
  ...
}: {
  imports = [
    "${modules}/base.nix"
  ];

  home.username = "gggg";
  home.homeDirectory = "/Users/gggg";
  configure-ssh = false;
  flake-location = "";
}
