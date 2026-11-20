{
  constants,
  pkgs,
  lib,
  ...
}: let
  # The migrated Mac profile requires at least this Brave version.
  # Resume the regular Nixpkgs package once it catches up.
  profileBraveVersion = "1.99.57";
  braveForProfile =
    if lib.versionAtLeast pkgs.brave.version profileBraveVersion
    then pkgs.brave
    else
      pkgs.brave.overrideAttrs {
        version = profileBraveVersion;
        src = pkgs.fetchurl {
          url = "https://github.com/brave/brave-browser/releases/download/v${profileBraveVersion}/brave-browser_${profileBraveVersion}_amd64.deb";
          hash = "sha256-jNFMV/f9bXnf2aJUUBdbVDihsRtWX/XQitmRtwLen9U=";
        };
      };
in {
  imports = [
    ../../home/base.nix
    ../../home/personal.nix

    ./sway.nix
    ./ssh-tpm.nix
    ./homelab-trust.nix
    ./top-commands.nix
  ];

  home.username = "ilma4";
  i4.personal.enable = true;
  i4.dev.enable = true;
  i4.dev.jjSigningKey = constants.msi-modern-github-pub-key;

  programs.bash.initExtra = ''
    if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then
      tmux attach-session -t default || tmux new-session -s default
    fi
  '';

  top-commands.commands = lib.mkOptionDefault {
    suspend = "systemctl suspend";
    sleep = "systemctl suspend";
    reboot = "systemctl reboot";
  };

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    braveForProfile

    (writers.writePython3Bin "set-power" {
      doCheck = false; # disable PEP style checks
    } (builtins.readFile ../../scripts/set-power.py))
  ];
}
