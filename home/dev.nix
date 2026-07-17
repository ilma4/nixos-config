{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}: let
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
  codexWrapper = pkgs.writeShellScriptBin "codex" ''
    set -euo pipefail

    wrapper_path="''${BASH_SOURCE[0]}"
    if [[ "$wrapper_path" != */* ]]; then
      wrapper_path="$(command -v codex)"
    fi

    codex_path=
    IFS=: read -r -a path_entries <<< "''${PATH-}"
    for path_entry in "''${path_entries[@]}"; do
      [[ -n "$path_entry" ]] || path_entry=.
      candidate="$path_entry/codex"
      if [[ -x "$candidate" ]] && ! [[ "$candidate" -ef "$wrapper_path" ]]; then
        codex_path="$candidate"
        break
      fi
    done

    if [[ -z "$codex_path" ]]; then
      echo "codex: could not find the real executable in PATH" >&2
      exit 127
    fi

    exec "$codex_path" --yolo "$@"
  '';
in {
  options.i4.dev.enable = lib.mkEnableOption "development tools";

  config = lib.mkIf (config.i4.dev.enable && (config ? home)) {
    # Home Assistant MCP, scoped to ~/.config/ha-mcp / the ha-pi command. See home/ha-mcp.nix.
    i4.ha-mcp.enable = lib.mkDefault true;

    home.packages = with pkgs; [
      docker # docker cli
      podman # podman cli
      podman-compose # podman-compose is not bundled with podman

      nixd
      nil
      alejandra
      sops
      gh

      ghc
      stack

      uv
      # mcp-nixos # build failure, don't use like this anyway
      pkgs-unstable.ha-mcp

      android-tools # adb

      # tex-fmt # latex formatting
      haskell-language-server

      (pkgs.rust-bin.stable.latest.default.override {
        extensions = ["rust-src"];
      })

      (lib.mkIf pkgs.stdenv.isDarwin pkgs.darwin.libiconv) # TODO: this is a workaround I don't remember for which

      i4UpdateHost
      (lib.mkIf pkgs.stdenv.isDarwin codexWrapper)
      (lib.mkIf pkgs.stdenv.isDarwin (pkgs.writeShellScriptBin "claude" ''
        set -euo pipefail
        exec /opt/homebrew/bin/claude --dangerously-skip-permissions "$@"
      ''))
      # (lib.mkIf isNotNixOS pkgs-unstable.bazelisk)
      # (lib.mkIf isNotNixOS (pkgs.writeShellScriptBin "bazel" "exec ${pkgs.bazelisk}/bin/bazelisk \"$@\""))
    ];

    home.shellAliases = lib.mkIf pkgs.stdenv.isDarwin {
      # Delegate to the PATH-searching wrapper above.
      codex = "${codexWrapper}/bin/codex";
      claude = "/opt/homebrew/bin/claude --dangerously-skip-permissions";
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

    programs.bash.enable = true;

    home.file = {
      ".bazelrc".text = ''
        common --disk_cache=${config.home.homeDirectory}/.cache/bazel-disk
      '';
      ".ideavimrc".source = ../dotfiles/ideavimrc;
    };

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
          fetch-once = "!f() { git fetch origin +refs/heads/$1:refs/remotes/origin/$1; }; f";
          push-force-safe = "push --force-with-lease --force-if-includes";
          nuke = "!git reset --hard && git clean -fdx"; # clean everything
        };
      };

      ignores = [
        ".idea/inspectionProfiles"
        ".idea/runConfigurations"
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
