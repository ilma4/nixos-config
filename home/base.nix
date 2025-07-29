{
  config,
  pkgs,
  lib,
  flake-location,
  ...
}: let
  HOME = config.home.homeDirectory;
  inherit (pkgs) stdenv;
  isDarwin = stdenv.isDarwin;
  isNixos = stdenv.isLinux && !config.targets.genericLinux.enable;
in {
  imports = [
  ];

  options = {
    flake-location = lib.mkOption {
      type = lib.types.str;
      example = "/home/ilma4/.config/nixos-config";
      description = "Location of the flake";
      default = "none"; # TODO null
    };

    flake-configuration = lib.mkOption {
      type = lib.types.str;
      example = "ilma4-bkp";
      description = "Configuration of the flake";
      default = "none"; # TODO null
    };

    configure-ssh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Configure ssh";
    };

    isRootless = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether the nix installation is in rootless chroot";
    };

    rebuild-script = lib.mkOption {
      type = lib.types.str;
      example = "nixos-rebuild switch";
      default =
        (
          if isDarwin
          then "sudo darwin-rebuild switch"
          else if isNixos
          then "sudo nixos-rebuild switch"
          else if stdenv.isLinux
          then "home-manager switch"
          else ""
        )
        + " --flake ${config.flake-location}#${config.flake-configuration}";

      description = "nix-rebuild script";
    };
  };

  config = {
    home.homeDirectory = "${
      if isDarwin
      then "/Users/"
      else "/home/"
    }${config.home.username}";

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

      vifm
      unrar
      unzip
      zip
      zstd
      xz
      gzip
      p7zip

      tree

      (pkgs.writeShellScriptBin "dirsize" ''
        du -shc -- "$@" | sort --human-numeric-sort --reverse
      '')

      (pkgs.writeShellScriptBin "check-im-alive" ''
        echo yay
      '')

      (pkgs.writeShellScriptBin "nix-rebuild" config.rebuild-script)
    ];

    programs.git = {
      extraConfig = {
        core = {
          autocrlf = "input"; # do not change line separators
        };
      };
      enable = true;
      # config to commit located in `dev.nix`
    };

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "vi-mode"
          "extract"
        ];
        theme = "apple";
        extraConfig = ''
          # don't do git status after every command for theese repos
          zstyle ':vcs_info:*' disable-patterns "$HOME/Projects/JetBrains/*"
        '';
      };

      # Fix ssh agent forwarding when reattaching to screen from new ssh connection
      profileExtra =
        lib.mkIf (stdenv.isLinux && config.configure-ssh) # macOS works fine with ssh agent
        
        ''
          if [ -S "$SSH_AUTH_SOCK" ] && [ ! -h "$SSH_AUTH_SOCK" ]; then
              ln -sf "$SSH_AUTH_SOCK" ${HOME}/.ssh/ssh_auth_sock
          fi
          export SSH_AUTH_SOCK=${HOME}/.ssh/ssh_auth_sock
        '';
    };

    programs.ssh = lib.mkIf config.configure-ssh {
      enable = true;
      addKeysToAgent = "yes";

      matchBlocks = {
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
    programs.tmux = lib.mkIf (!config.isRootless) {
      enable = true;
      keyMode = "vi";
      baseIndex = 1; # enumerate windows from 1 instead of 0
    };

    programs.neovim = {
      enable = true;
      extraLuaConfig = ''
        vim.o.clipboard = "unnamedplus"

        vim.opt.expandtab   = true
        vim.opt.shiftwidth  = 4
        vim.opt.softtabstop = -1
      '';
    };

    home.file = lib.mkIf (!config.isRootless) {
      ".screenrc".source = "${flake-location}/dotfiles/screenrc";
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
  };
}
