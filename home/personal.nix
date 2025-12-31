{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.personal;
  isDarwin = pkgs.stdenv.isDarwin;
in {
  options.i4.personal = {
    enable = lib.mkEnableOption "Personal home configuration (SSH keys, packages, etc.)";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      resticprofile

      /*
      TODO: generate new keys defined in `programs.ssh.matchBlocks` and send them to hosts
      TODO: thing about what to do if can't send key to the server
      (pkgs.writeShellScriptBin "rotate-ssh-keys" ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Rotate the SSH keys
            mv ${HOME}/.ssh/id_rsa ${HOME}/.ssh/id_rsa.old
            mv ${HOME}/.ssh/id_rsa.pub ${HOME}/.ssh/id_rsa.pub.old
            ssh-keygen -t rsa -b 4096 -f ${HOME}/.ssh/id_rsa -N ""
            ''
            )
      */
    ];

    programs.ssh.matchBlocks = {
      "github.com" = {
        extraOptions."IdentityAgent" = "/Users/ilma4/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock";
      };
      "ilma4-bkp.local" = {
        identityFile = "~/.ssh/jb-macbook-to-ilma4-bkp";
      };
      "laat.local" = {
        identityFile = "~/.ssh/jb-mac-to-ilma4-nas";
      };
      "laat" = {
        identityFile = "~/.ssh/jb-mac-to-ilma4-nas";
      };
      "laat-init" = {
        identityFile = "~/.ssh/jb-macbook-to-ilma4-bkp";
        hostname = "192.168.1.33";
        user = "root";
      };
    };

    programs.ssh.extraConfig =
      if isDarwin
      then "UseKeychain yes"
      else "";
  };
}
