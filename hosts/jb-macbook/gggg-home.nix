{
  config,
  lib,
  pkgs,
  modules,
  ...
}: {
  imports = [
    "${modules}/base.nix"
    "${modules}/macos.nix"
  ];

  home.username = "gggg";
  home.homeDirectory = "/Users/gggg";
  configure-ssh = false;
  flake-location = "";
}
