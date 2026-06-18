{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  constants,
  osConfig ? null,
  ...
}: let
  HOME = config.home.homeDirectory;
  inherit (pkgs) stdenv;
  isDarwin = stdenv.isDarwin;
  isNixos = stdenv.isLinux && !config.targets.genericLinux.enable;
  homebrewPrefix =
    if osConfig != null && osConfig ? homebrew
    then osConfig.homebrew.prefix or (lib.removeSuffix "/bin" osConfig.homebrew.brewPrefix)
    else "/opt/homebrew";
  i4-revision-package = pkgs.writeShellScriptBin "i4-revision" ''
    set -euo pipefail
    echo '${inputs.self.rev or inputs.self.dirtyRev or "null"}'
  '';
  gitSpushPackage = pkgs.writeShellScriptBin "git-spush" (builtins.readFile ../scripts/git-spush.sh);
  dircolorsConfigText = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "${name} ${toString value}") config.programs.dircolors.settings
    ++ [""]
    ++ lib.optional (config.programs.dircolors.extraConfig != "") config.programs.dircolors.extraConfig
  );
  lsColorsShellSnippet = pkgs.runCommandLocal "i4-ls-colors.sh" {} ''
    set -euo pipefail
    ${lib.getExe' config.programs.dircolors.package "dircolors"} -b ${pkgs.writeText "dir_colors" dircolorsConfigText} > "$out"
  '';
in {
  imports = [
    ./dev.nix
    ./fonts.nix
    ./ha-mcp.nix
    ./neovim.nix
    ./personal.nix
    ./raycast.nix
    ./zed.nix
    ../modules/nix-settings.nix
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

      patool # archive universal extract utility

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

      (pkgs.writeShellScriptBin "nix-rebuild" ''
        set -euo pipefail
        ${config.rebuild-script}
      '')
      i4-revision-package
      gitSpushPackage
    ];

    programs.git = {
      enable = true;
      signing = {
        format = "ssh";
        key = constants.github-pub-key;
        signByDefault = false;
      };
      settings = {
        core = {
          autocrlf = "input"; # do not change line separators
        };
        gpg.ssh.allowedSignersFile = toString (pkgs.writeText "allowed_signers" ("ilya.malakhov4@gmail.com " + constants.github-pub-key));
      };
      # config to commit located in `dev.nix`
    };

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      # Skip compinit's per-startup security audit (compaudit) and staleness
      # check; fpath only changes on nix-rebuild. Run `rm ~/.zcompdump*` after a
      # rebuild that adds new completions.
      completionInit = ''autoload -U compinit && compinit -C -d "$HOME/.zcompdump"'';

      # oh-my-zsh was loaded only for the vi-mode plugin but cost ~190ms at
      # startup (framework sourcing + the compinit/compaudit it drives). Native
      # `bindkey -v` in initContent below replaces it.
      oh-my-zsh.enable = false;

      # Add Powerlevel10k theme and your custom config as plugins
      shellAliases = {
        ls = lib.mkIf isDarwin "${pkgs.coreutils}/bin/ls --color=auto"; # use GNU ls on macOS, it has better colors
        # dirsize = "${pkgs.ncdu}/bin/ncdu";
        # l = "ls -lah";
        # ll = "ls -lh";
      };

      initContent = let
        early = lib.mkOrder 500 ''
          # Powerlevel10k instant prompt — must stay near the top and before any
          # console output/input so the prompt renders immediately at startup.
          if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
            source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
          fi

          fpath+=(${pkgs.zsh-completions}/share/zsh/site-functions)
          ${lib.optionalString isDarwin "fpath+=(${homebrewPrefix}/share/zsh/site-functions)"}

          # Powerlevel10k theme
          source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
          source ${../dotfiles/p10k.zsh} # Powerlevel10k config
        '';

        beforeCompinit = lib.mkOrder 550 ''
          ${lib.optionalString isDarwin ''
            # nix-darwin includes completions from /nix/var/nix/profiles/default,
            # which may resolve to a mixed-ownership store path on quicksilver.
            for default_profile_fpath in \
              /nix/var/nix/profiles/default/share/zsh/site-functions \
              /nix/var/nix/profiles/default/share/zsh/$ZSH_VERSION/functions \
              /nix/var/nix/profiles/default/share/zsh/vendor-completions
            do
              fpath=(''${fpath:#$default_profile_fpath})
            done
            unset default_profile_fpath
          ''}

          # Collapse fpath entries that resolve to the same directory. Nix can
          # expose zsh's builtin functions through several profile symlinks
          # ($HOME/.nix-profile, /run/current-system/sw, and the store path);
          # `typeset -U fpath` only removes exact string duplicates, so compinit
          # would otherwise scan and dump the same ~1k files multiple times.
          typeset -A i4_seen_fpath
          typeset -a i4_deduped_fpath
          for i4_fpath_dir in "''${fpath[@]}"; do
            if [[ -d $i4_fpath_dir ]]; then
              i4_fpath_key="''${i4_fpath_dir:A}"
            else
              i4_fpath_key="$i4_fpath_dir"
            fi

            [[ -n ''${i4_seen_fpath[$i4_fpath_key]-} ]] && continue
            i4_seen_fpath[$i4_fpath_key]=1
            i4_deduped_fpath+=("$i4_fpath_dir")
          done
          fpath=("''${i4_deduped_fpath[@]}")
          unset i4_seen_fpath i4_deduped_fpath i4_fpath_dir i4_fpath_key

          # LS_COLORS is computed by dircolors at Nix build time, so zsh only
          # sources a static assignment instead of spawning dircolors on every
          # interactive shell startup.
          source ${lsColorsShellSnippet}
        '';

        normal = lib.mkOrder 1000 ''
          # Native vi mode (replaces the oh-my-zsh vi-mode plugin).
          bindkey -v

          # disable ZLE execute-named-cmd prompt (like ":" in normal mode in (neo)vim)
          bindkey -M vicmd ':' undefined-key

          # 10milliseconds delay after seeing Esc character
          export KEYTIMEOUT=1


          # Integrate vi-mode yank/put with the system clipboard. Pick the
          # first available clipboard tool; if none exists (e.g. headless
          # server) the widgets are left unbound and vi falls back to its
          # internal register.
          if (( $+commands[pbcopy] )); then
            function _clip_copy { pbcopy }
            function _clip_paste { pbpaste }
          elif (( $+commands[wl-copy] )); then
            function _clip_copy { wl-copy }
            function _clip_paste { wl-paste --no-newline }
          elif (( $+commands[xclip] )); then
            function _clip_copy { xclip -selection clipboard }
            function _clip_paste { xclip -selection clipboard -o }
          elif (( $+commands[xsel] )); then
            function _clip_copy { xsel --clipboard --input }
            function _clip_paste { xsel --clipboard --output }
          fi

          if (( $+functions[_clip_copy] )); then
            function vi-yank-clip { zle vi-yank; printf '%s' "$CUTBUFFER" | _clip_copy }
            function vi-yank-eol-clip { zle vi-yank-eol; printf '%s' "$CUTBUFFER" | _clip_copy }
            function vi-delete-clip { zle vi-delete; printf '%s' "$CUTBUFFER" | _clip_copy }
            function vi-put-after-clip { CUTBUFFER="$(_clip_paste)"; zle vi-put-after }
            function vi-put-before-clip { CUTBUFFER="$(_clip_paste)"; zle vi-put-before }
            zle -N vi-yank-clip
            zle -N vi-yank-eol-clip
            zle -N vi-delete-clip
            zle -N vi-put-after-clip
            zle -N vi-put-before-clip
            bindkey -M vicmd 'y' vi-yank-clip
            bindkey -M vicmd 'Y' vi-yank-eol-clip
            bindkey -M vicmd 'd' vi-delete-clip
            bindkey -M vicmd 'p' vi-put-after-clip
            bindkey -M vicmd 'P' vi-put-before-clip
            bindkey -M visual 'y' vi-yank-clip
          fi

          # Completion: colorize file listings using precomputed LS_COLORS, and
          # show an interactive menu that highlights the currently selected item.
          zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
          zstyle ':completion:*' menu select
        '';
      in
        lib.mkMerge [early normal beforeCompinit];

      # Fix ssh agent forwarding when reattaching to screen from new ssh connection
      profileExtra =
        lib.mkIf (stdenv.isLinux && config.configure-ssh) # macOS works fine with ssh agent
        
        ''
          if [ -n "''${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ] && [ ! -h "$SSH_AUTH_SOCK" ]; then
              mkdir -p ${HOME}/.ssh
              ln -sf "$SSH_AUTH_SOCK" ${HOME}/.ssh/ssh_auth_sock
          fi

          if [ -S ${HOME}/.ssh/ssh_auth_sock ]; then
              export SSH_AUTH_SOCK=${HOME}/.ssh/ssh_auth_sock
          fi
        '';
    };

    programs.ssh = lib.mkIf config.configure-ssh {
      enable = true;
      enableDefaultConfig = false;

      # Home Manager's implicit Host * defaults are being removed.
      # Keep the current effective defaults explicit in this repo.
      settings."*" = {
        ForwardAgent = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        Compression = false;
        AddKeysToAgent = "no";
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      };
      # AddKeysToAgent = "yes";
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

    home.file = {
      ".config/htop/htoprc".source = ../dotfiles/htoprc;
    };

    programs.dircolors = {
      enable = true;
      enableBashIntegration = false;
      enableZshIntegration = false;
    };

    programs.bash.initExtra = ''
      # Same precomputed LS_COLORS snippet used by zsh; avoids running
      # dircolors for every interactive bash startup.
      source ${lsColorsShellSnippet}
    '';

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
