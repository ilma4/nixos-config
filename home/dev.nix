{
  config,
  lib,
  pkgs,
  ...
}: {
  options.i4.dev.enable = lib.mkEnableOption "development tools";

  config = lib.mkIf (config.i4.dev.enable && (config ? home)) {
    home.packages = with pkgs; [
      docker # docker cli
      podman # podman cli
      podman-compose # podman-compose is not bundled with podman

      nixd
      nil
      alejandra
      sops

      ghc
      stack

      uv
      mcp-nixos

      android-tools # adb

      # tex-fmt # latex formatting
      haskell-language-server

      (pkgs.rust-bin.stable.latest.default.override {
        extensions = ["rust-src"];
      })

      (lib.mkIf pkgs.stdenv.isDarwin pkgs.darwin.libiconv) # TODO: this is a workaround I don't remember for which

      (
        pkgs.writeShellScriptBin "i4-update-host"
        (builtins.readFile ../dotfiles/i4-update-host.sh)
      )
      (
        pkgs.writeShellScriptBin "simple-service-update"
        (builtins.readFile ../scripts/simple-service-update)
      )
      # (lib.mkIf isNotNixOS pkgs-unstable.bazelisk)
      # (lib.mkIf isNotNixOS (pkgs.writeShellScriptBin "bazel" "exec ${pkgs.bazelisk}/bin/bazelisk \"$@\""))
    ];

    programs.zsh.shellAliases = {
      # bazel = lib.mkIf isNotNixOS "${pkgs.bazelisk}/bin/bazelisk";
      gw = "./gradlew";
    };

    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
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

      lfs.enable = true;
    };

    home.sessionVariables = {
      LIBRARY_PATH = "$LIBRARY_PATH:${config.home.profileDirectory}/lib";
    };
  };
}
