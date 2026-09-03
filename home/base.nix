{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  constants,
  ...
}: let
  inherit (pkgs) stdenv;
  isDarwin = stdenv.isDarwin;
  isNixos = stdenv.isLinux && !config.targets.genericLinux.enable;
  i4-revision-package = pkgs.writeShellScriptBin "i4-revision" ''
    set -euo pipefail
    echo '${inputs.self.rev or inputs.self.dirtyRev or "null"}'
  '';
  # Work around both patool completion packaging bugs: argcomplete is missing
  # at runtime, and the generated scripts register the absolute Nix store path
  # instead of the command name. Remove once the upstream fix is available.
  # https://github.com/NixOS/nixpkgs/issues/448393
  patoolWithCompletions = pkgs.patool.overridePythonAttrs (old: {
    dependencies = (old.dependencies or []) ++ [pkgs.python3Packages.argcomplete];
    postInstall = ''
      installShellCompletion --cmd patool \
        --bash <(${pkgs.python3Packages.argcomplete}/bin/register-python-argcomplete -s bash patool) \
        --fish <(${pkgs.python3Packages.argcomplete}/bin/register-python-argcomplete -s fish patool) \
        --zsh <(${pkgs.python3Packages.argcomplete}/bin/register-python-argcomplete -s zsh patool)
    '';
  });
  tmuxUtf8Wrapper = pkgs.writeShellScriptBin "tmux" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.tmux} -u "$@"
  '';
  tmuxUtf8Package = pkgs.symlinkJoin {
    name = "${pkgs.tmux.pname}-utf8-${pkgs.tmux.version}";
    paths = [pkgs.tmux];
    postBuild = ''
      set -euo pipefail
      rm "$out/bin/tmux"
      ln -s ${lib.getExe tmuxUtf8Wrapper} "$out/bin/tmux"
    '';
  };
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
    ./neovim-ide.nix
    ./personal.nix
    ./raycast.nix
    ./zed.nix
    ./zsh.nix
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
      osc
      restic
      rclone
      rsync

      patoolWithCompletions # archive universal extract utility

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
      btop
      mprocs # parallel process TUI used by utils/deploy-all.sh

      (pkgs.writeShellScriptBin "nix-rebuild" ''
        set -euo pipefail
        ${config.rebuild-script}
      '')
      i4-revision-package
    ];

    programs.git = {
      enable = true;
      signing = {
        format = "ssh";
        # Pass the literal public key as user.signingkey. Git only auto-detects
        # an inline key when it starts with "ssh-" or "key::"; an "ecdsa-…" key
        # (our Secretive key) is otherwise treated as a file path and signing
        # fails with "Couldn't load public key …: No such file or directory".
        # The "key::" prefix marks it as a literal key for every key type.
        key = "key::" + builtins.head constants.github-pub-keys;
        signByDefault = false;
      };
      settings = {
        core = {
          autocrlf = "input"; # do not change line separators
        };
        gpg.ssh.allowedSignersFile = toString (pkgs.writeText "allowed_signers" (lib.concatMapStrings (key: "ilya.malakhov4@gmail.com " + key + "\n") constants.github-pub-keys));
      };
      # config to commit located in `dev.nix`
    };

    programs.ssh = lib.mkIf config.configure-ssh {
      enable = true;
      enableDefaultConfig = false;

      # Home Manager's implicit Host * defaults are being removed.
      # Keep the current effective defaults explicit in this repo.
      settings."*" = {
        ForwardAgent = false;
        # Keepalives make ssh exit ~45s (15s * 3) after the network path dies
        # instead of hanging until TCP gives up. The ssh wrapper in
        # programs.zsh.initContent relies on this: it resets the terminal's
        # extended-keys mode when ssh exits, which never happens while a dead
        # connection hangs.
        ServerAliveInterval = 15;
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
      # Integration is precomputed in home/zsh.nix and sourced from its
      # initContent; disabling this stops Home Manager from emitting its own
      # `eval "$(atuin init zsh)"`, which forks atuin to GENERATE the init
      # script on every startup (~17ms). The precompute is faithful because the
      # config it reads is the store-managed dotfiles/atuin/config.toml deployed
      # below — see home/zsh.nix.
      enableZshIntegration = false;
      enableBashIntegration = false;
      flags = [
        "--disable-up-arrow"
      ];
    };

    # Deploy the atuin config read-only from the Nix store. This is the exact
    # file atuinInitSnippet reads at build time, so the precomputed init can
    # never drift from the runtime config. Kept as a verbatim dotfile (not
    # programs.atuin.settings) so comments/upstream defaults are preserved; an
    # empty settings means Home Manager writes nothing here, so no conflict.
    xdg.configFile."atuin/config.toml".source = ../dotfiles/atuin/config.toml;

    programs.ripgrep.enable = true;
    programs.fd.enable = true;
    programs.bat.enable = true;
    programs.htop.enable = true;

    programs.fzf.enable = true;
    # Integration is precomputed in home/zsh.nix and sourced from its
    # initContent; this stops Home Manager from emitting its own
    # `source <(fzf --zsh)`, which forks fzf on every startup.
    programs.fzf.enableZshIntegration = false;
    programs.tmux = {
      enable = true;
      package = tmuxUtf8Package;
      keyMode = "vi";
      baseIndex = 1; # enumerate windows from 1 instead of 0
      terminal = "tmux-256color";
      extraConfig = ''
        # Enable extended keys in csi-u format
        set -g extended-keys on
        set -s extended-keys-format csi-u

        set -g mouse on # enable mouse
        set -g history-limit 100000 # increase history

        # Force tmux clients to use UTF-8 output (the package wrapper adds -u),
        # enable 24-bit color, and tell tmux that WezTerm's xterm-compatible
        # client supports extended keys. Without extkeys, Shift+Enter reaches
        # tmux as the same carriage return as Enter.
        set -as terminal-features ",*:RGB,xterm*:extkeys"

        # Forward OSC 52 clipboard sequences from applications through tmux.
        set -s set-clipboard on
        set -s allow-passthrough on
        set -as terminal-features ',xterm-256color:clipboard'
      '';
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
      # Precomputed LS_COLORS snippet avoids running dircolors for every
      # interactive bash startup.
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
