{
  config,
  pkgs,
  ...
}: let
  HOME = config.home.homeDirectory;
in {
  home.packages = with pkgs; [
    screen

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
      identityFile = "~/.ssh/github";
    };
    "nvc00731.amt.labs.intellij.net" = {
      identityFile = "~/.ssh/apal-server";
    };
    "192.168.1.155" = {
      identityFile = "~/.ssh/jb-macbook-to-oneplus10R";
      user = "nix-on-droid";
      port = 8022;
    };
  };

  programs.ssh.extraConfig =
    if pkgs.stdenv.isDarwin
    then "UseKeychain yes"
    else "";
}
