{pkgs, ...}: {
  imports = [
    ../../home/base.nix
    ../../home/personal.nix
  ];

  home.username = "ilma4";
  i4.personal.enable = true;

  programs.bash.initExtra = ''
    if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then
      tmux attach-session -t default || tmux new-session -s default
    fi
  '';

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    (writers.writePython3Bin "set-power" {
      doCheck = false; # disable PEP style checks
    } (builtins.readFile ../../scripts/set-power.py))
  ];
}
