{
  lib,
  pkgs,
}: name: repo: let
  wrapperName = "i4-restic-${name}";
  resticArgs = ["${lib.getExe pkgs.restic}" "--repo" repo.location "--password-file" repo.passwordFile] ++ repo.extraResticArgs;
  wrapper = pkgs.writeShellScriptBin wrapperName ''
    set -euo pipefail

    exec ${lib.escapeShellArgs resticArgs} "''$@"
  '';
  zshCompletion = pkgs.writeTextFile {
    name = "${wrapperName}-zsh-completion";
    destination = "/share/zsh/site-functions/_${wrapperName}";
    text = ''
      #compdef ${wrapperName}

      source ${pkgs.restic}/share/zsh/site-functions/_restic
      _restic "$@"
    '';
  };
in
  pkgs.symlinkJoin {
    name = wrapperName;
    paths = [wrapper zshCompletion];
  }
