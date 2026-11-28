{
  constants,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../../home/base.nix
    ../../home/personal.nix

    ./sway.nix
    ./theme.nix
    ./ssh-tpm.nix
    ./homelab-trust.nix
    ./top-commands.nix
  ];

  home.username = "ilma4";
  i4.personal.enable = true;
  i4.zed.enable = true;
  i4.neovim.ide.enable = true;
  i4.dev.enable = true;
  i4.dev.nix.enable = true;
  i4.dev.jjSigningKey = constants.msi-modern-github-pub-key;

  programs.zsh.initContent = lib.mkOrder 350 ''
    # Replace the tty1 login shell before prompt setup starts the Git/JJ worker.
    if [[ -o login && $TTY == /dev/tty1 && -z ''${SSH_CONNECTION:-} &&
          -z ''${WAYLAND_DISPLAY:-} && -z ''${DISPLAY:-} ]]; then
      export WLR_RENDERER=vulkan
      exec sway
    fi
  '';

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
    brave
    libreoffice

    (writers.writePython3Bin "set-power" {
      doCheck = false; # disable PEP style checks
    } (builtins.readFile ../../scripts/set-power.py))
  ];
}
