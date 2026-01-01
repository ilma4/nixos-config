{
  config,
  pkgs,
  lib,
  ...
}: let
  HOME = config.home.homeDirectory;
  inherit (pkgs) stdenv;
  isDarwin = stdenv.isDarwin;
  isNixos = stdenv.isLinux && !config.targets.genericLinux.enable;
in {
  imports = [
    ./dev.nix
    ./fonts.nix
    ./personal.nix
    ./raycast.nix
    ./zed.nix
  ];

  options = {
    i4.base.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable base configuration";
    };

    configure-ssh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Configure ssh";
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
        + " --flake ${config.home.homeDirectory}/.config/nixos-config#\"$(uname -n)\"";

      description = "nix-rebuild script";
    };

    flake-source = lib.mkOption {
      type = lib.types.nullOr lib.types.singleLineStr;
      description = "The source of the flake";
      example = "/home/user/flake-directory";
      default = null;
    };
  };

  config = lib.mkIf config.i4.base.enable {
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
      ncdu

      (pkgs.writeShellScriptBin "nix-rebuild" config.rebuild-script)
    ];

    programs.git = {
      enable = true;
      settings = {
        core = {
          autocrlf = "input"; # do not change line separators
        };
      };
      # config to commit located in `dev.nix`
    };

    programs.zsh = {
      enable = true;
      enableCompletion = true;

      oh-my-zsh = {
        enable = lib.mkDefault true;
        theme = "";
        plugins = [
          "vi-mode"
          "extract"
          # "zsh-autosuggestions"
          # "zsh-syntax-highlighting"
        ];
      };

      # Add Powerlevel10k theme and your custom config as plugins
      shellAliases = {
        ls = lib.mkIf isDarwin "${pkgs.coreutils}/bin/ls --color=auto"; # use GNU ls on macOS, it has better colors
        # dirsize = "${pkgs.ncdu}/bin/ncdu";
        # l = "ls -lah";
        # ll = "ls -lh";
      };

      initContent = let
        early = lib.mkOrder 500 ''
          fpath+=(${pkgs.zsh-completions}/share/zsh/site-functions)

          # Powerlevel10k theme
          source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
          source ${../dotfiles/p10k.zsh} # Powerlevel10k config
        '';

        beforeCompinit =
          lib.mkOrder 550 ''
          '';

        normal =
          lib.mkOrder 1000 ''
          '';
      in
        lib.mkMerge [early normal beforeCompinit];

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
    };

    programs.atuin = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = false;
      flags = [
        "--disable-up-arrow"
      ];
    };

    programs.ripgrep.enable = true;
    programs.fd.enable = true;
    programs.bat.enable = true;
    programs.htop.enable = true;
    programs.fzf.enable = true;
    programs.tmux = {
      enable = true;
      keyMode = "vi";
      baseIndex = 1; # enumerate windows from 1 instead of 0
    };

    programs.neovim = {
      enable = true;
      plugins = with pkgs.vimPlugins; [
        {
          plugin = vim-suda;
          config = "let g:suda_smart_edit = 1";
        }
      ];

      extraLuaConfig = ''
        vim.o.clipboard = "unnamedplus"

        vim.opt.expandtab   = true
        vim.opt.shiftwidth  = 4
        vim.opt.softtabstop = -1
      '';
    };

    home.file = {
      ".config/htop/htoprc".source = ../dotfiles/htoprc;
    };

    programs.dircolors.enable = true;

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
