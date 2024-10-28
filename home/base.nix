{
  config,
  pkgs,
  lib,
  dotfiles,
  ...
}: let
  HOME = config.home.homeDirectory;
  inherit (pkgs) stdenv;
in {
  imports = [
    ./nixvim.nix
  ];
  nixpkgs.config.allowUnfree = true;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05"; # Please read the comment before changing.

  home.packages = with pkgs; [
    restic
    rclone
    rsync

    curl
    wget

    unrar
    unzip
    zip
    zstd
    xz
    gzip

    (pkgs.writeShellScriptBin "dirsize" ''
      du -shc -- "$@" | sort --human-numeric-sort --reverse
    '')
  ];

  programs.git = {
    enable = true;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    oh-my-zsh = {
      enable = true;
      plugins = ["git" "vi-mode" "extract"];
      theme = "apple";
    };

    # Fix ssh agent forwarding when reattaching to screen from new ssh connection
    profileExtra =
      lib.mkIf stdenv.isLinux # macOS works fine with ssh agent
      
      ''
        if [ -S "$SSH_AUTH_SOCK" ] && [ ! -h "$SSH_AUTH_SOCK" ]; then
            ln -sf "$SSH_AUTH_SOCK" ${HOME}/.ssh/ssh_auth_sock
        fi
        export SSH_AUTH_SOCK=${HOME}/.ssh/ssh_auth_sock
      '';
  };

  programs.ssh = {
    enable = true;
    addKeysToAgent = "yes";
    matchBlocks = {
      "ilma4-bkp" = {forwardAgent = true;};
      "nvc00731.amt.labs.intellij.net" = {forwardAgent = true;};
    };
  };


  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    flags = [
      "--disable-up-arrow"
    ];
  };

  programs.ripgrep.enable = true;
  programs.fd.enable = true;
  programs.bat.enable = true;
  programs.htop.enable = true;
  programs.fzf.enable = true;

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".screenrc".source = "${dotfiles}/screenrc";

    ".bazelrc".text = ''
      common --disk_cache=${HOME}/.cache/bazel-disk
    '';

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/ilma4/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    EDITOR = "nvim";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
