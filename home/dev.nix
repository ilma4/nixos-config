{
  config,
  constants,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}: let
  gitUser =
    lib.attrByPath ["programs" "git" "settings" "user"] {
      name = "Ilia Malakhov";
      email = "ilya.malakhov4@gmail.com";
    }
    config;
  jjUserName = lib.attrByPath ["name"] "Ilia Malakhov" gitUser;
  jjUserEmail = lib.attrByPath ["email"] "ilya.malakhov4@gmail.com" gitUser;
  jjSigningKey = builtins.head constants.github-pub-keys;
  jjAllowedSignersFile = pkgs.writeText "jj-allowed-signers" (
    lib.concatMapStrings (key: "${jjUserEmail} ${key}\n") constants.github-pub-keys
  );
  jjProfileConfig = ''
    [user]
    name = ${builtins.toJSON jjUserName}
    email = ${builtins.toJSON jjUserEmail}
  '';
  # Keep the SSH signing block in work profiles as comments until the
  # work-specific signing key is supplied. Personal profiles keep it active.
  jjSigningConfigPrefix = lib.optionalString (!config.i4.personal.enable) "# ";
  jjSigningConfig = ''
    ${jjSigningConfigPrefix}[signing]
    ${jjSigningConfigPrefix}backend = "ssh"
    ${jjSigningConfigPrefix}behavior = "drop"
    ${jjSigningConfigPrefix}key = ${builtins.toJSON jjSigningKey}
    ${jjSigningConfigPrefix}backends.ssh.program = "${lib.getExe' pkgs.openssh "ssh-keygen"}"
    ${jjSigningConfigPrefix}backends.ssh.allowed-signers = "${jjAllowedSignersFile}"
  '';
  i4UpdateHostScript = pkgs.writeShellScriptBin "i4-update-host" (builtins.readFile ../scripts/i4-update-host.sh);
  i4UpdateHostZshCompletion = pkgs.writeTextFile {
    name = "i4-update-host-zsh-completion";
    destination = "/share/zsh/site-functions/_i4-update-host";
    text = builtins.readFile ../scripts/completions/_i4-update-host;
  };
  i4UpdateHost = pkgs.symlinkJoin {
    name = "i4-update-host";
    paths = [i4UpdateHostScript i4UpdateHostZshCompletion];
  };
  gitBreakLockPackage = pkgs.writeShellScriptBin "git-break-lock" (
    builtins.replaceStrings ["@lsof@"] ["${lib.getExe pkgs.lsof}"] (builtins.readFile ../scripts/git-break-lock.sh)
  );
  # Keep autoenv's varstash helper next to the copied source: autoenv loads it
  # relative to its own source path. The adjacent .zwc is picked up by zsh when
  # this file is sourced.
  zshAutoenvInitSnippet = pkgs.runCommandLocal "i4-zsh-autoenv-init" {} ''
    set -euo pipefail
    mkdir -p "$out/lib"
    cp ${pkgs.zsh-autoenv}/share/zsh-autoenv/autoenv.zsh "$out/autoenv.zsh"
    cp ${pkgs.zsh-autoenv}/share/zsh-autoenv/lib/varstash "$out/lib/varstash"
    ${lib.getExe pkgs.zsh} -fc "zcompile -R -- '$out/autoenv.zsh.zwc' '$out/autoenv.zsh'"
  '';
in {
  imports = [./coding-agents.nix];

  options.i4.dev.enable = lib.mkEnableOption "development tools";

  config = lib.mkIf (config.i4.dev.enable && (config ? home)) {
    i4.coding-agents.enable = lib.mkDefault true;

    # Home Assistant MCP, scoped to ~/.config/ha-mcp / the ha-pi command. See home/ha-mcp.nix.
    i4.ha-mcp.enable = lib.mkDefault false;

    home.packages = with pkgs; [
      docker # docker cli
      podman # podman cli
      podman-compose # podman-compose is not bundled with podman

      nixd
      nil
      alejandra
      sops
      gh
      nodejs
      bun

      uv
      pkgs-unstable.jujutsu

      # mcp-nixos # build failure, don't use like this anyway
      # pkgs-unstable.ha-mcp

      android-tools # adb

      # tex-fmt # latex formatting

      (pkgs.rust-bin.stable.latest.default.override {
        extensions = ["rust-src"];
      })

      (lib.mkIf pkgs.stdenv.isDarwin pkgs.darwin.libiconv) # TODO: this is a workaround I don't remember for which

      i4UpdateHost
      # (lib.mkIf isNotNixOS pkgs-unstable.bazelisk)
      # (lib.mkIf isNotNixOS (pkgs.writeShellScriptBin "bazel" "exec ${pkgs.bazelisk}/bin/bazelisk \"$@\""))
    ];

    home.shellAliases = lib.mkIf pkgs.stdenv.isDarwin {
      codex = "$HOME/.local/bin/codex --yolo";
      claude = "$HOME/.local/bin/claude --dangerously-skip-permissions";
    };

    programs.zsh.shellAliases = {
      # bazel = lib.mkIf isNotNixOS "${pkgs.bazelisk}/bin/bazelisk";
      gw = "./gradlew";
    };

    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
      # zsh hook is precomputed into direnvHookSnippet (home/base.nix) and
      # sourced from initContent there, so Home Manager must not also emit its
      # own `eval "$(direnv hook zsh)"` (that forks direnv on every zsh startup).
      # Bash integration is left enabled and untouched.
      enableZshIntegration = false;
      nix-direnv.enable = true;
    };

    programs.zsh.initContent = lib.mkOrder 600 ''
      source ${zshAutoenvInitSnippet}/autoenv.zsh
    '';

    programs.bash.enable = true;

    home.file = {
      ".bazelrc".text = ''
        common --disk_cache=${config.home.homeDirectory}/.cache/bazel-disk
      '';
      ".ideavimrc".source = ../dotfiles/ideavimrc;
    };

    xdg.configFile."jj/config.toml".source = ../dotfiles/jj/config.toml;
    xdg.configFile."jj/conf.d/10-profile.toml".text = jjProfileConfig;
    xdg.configFile."jj/conf.d/20-signing.toml".text = jjSigningConfig;

    home.sessionPath =
      ["$HOME/.local/bin"]
      ++ (
        if pkgs.stdenv.isDarwin
        then ["$HOME/Library/Application Support/JetBrains/Toolbox/scripts"]
        else []
      );

    # also check `work.nix` for work-specific options
    programs.git = {
      settings = {
        alias = {
          break-lock = "!${lib.getExe gitBreakLockPackage}";
          fetch-once = "!f() { git fetch origin +refs/heads/$1:refs/remotes/origin/$1; }; f";
          push-force-safe = "push --force-with-lease --force-if-includes";
          flush-status-cache = "!git -c core.untrackedCache=false status; git status";
          nuke = "!git reset --hard && git clean -fdx"; # clean everything
        };
      };

      ignores = [
        ".idea/inspectionProfiles/"
        ".idea/runConfigurations/"
        ".idea/workspace.xml"
        ".claude/settings.local.json"
      ];

      lfs.enable = true;
    };

    # xdg.configFile."git/ignore".force = true;

    home.sessionVariables = {
      LIBRARY_PATH = "$LIBRARY_PATH:${config.home.profileDirectory}/lib";
    };
  };
}
