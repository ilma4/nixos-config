{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.personal;
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

    programs.git.settings.user = {
      name = "Ilia Malakhov";
      email = "ilya.malakhov4@gmail.com";
    };

    programs.ssh.matchBlocks = {
      "nas-init" = {
        hostname = "192.168.1.33";
        user = "root";
      };
    };
  };
}
