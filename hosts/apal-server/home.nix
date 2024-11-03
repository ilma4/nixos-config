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
  targets.genericLinux.enable = true;
  isRootless = true;

  programs.zsh.profileExtra = ''
    if [ -e /home/malakhov/.nix-profile/etc/profile.d/nix.sh ]; then . /home/malakhov/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer
  '';
}
