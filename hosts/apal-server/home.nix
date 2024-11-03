{
  config,
  pkgs,
  modules,
  ...
}: {
  imports = [
    "${modules}/base.nix"
    "${modules}/work.nix"
  ];

  home.username = "malakhov";
  home.homeDirectory = "/home/malakhov";
  flake-location = "github:ilma4/nixos-config";
}
