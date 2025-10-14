{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
  isNotNixOS = isDarwin || config.targets.genericLinux.enable;
in {
  home.packages = with pkgs; [
    docker # docker cli
    podman # podman cli
    podman-compose # podman-compose is not bundled with podman

    nixd
    nil
    alejandra
    tex-fmt
    sops

    android-tools # adb

    haskell-language-server

    (pkgs.rust-bin.stable.latest.default.override {
      extensions = ["rust-src"];
    })

    (
      lib.mkIf (config.flake-source != null) (
        pkgs.writeShellScriptBin "i4-update-host" ''
          # Wrapper around external script to set default FLAKE_SOURCE
          export FLAKE_SOURCE="${"\$"}{FLAKE_SOURCE:-${config.flake-source}}"
          exec "${lib.flake-location}/dotfiles/i4-update-host.sh" "$@"
        ''
      )
    )

    (lib.mkIf isDarwin pkgs.darwin.libiconv) # TODO: this is a workaround I don't remember for which

    # (lib.mkIf isNotNixOS pkgs-unstable.bazelisk)
    # (lib.mkIf isNotNixOS (pkgs.writeShellScriptBin "bazel" "exec ${pkgs.bazelisk}/bin/bazelisk \"$@\""))
  ];

  programs.zsh.shellAliases = {
    # bazel = lib.mkIf isNotNixOS "${pkgs.bazelisk}/bin/bazelisk";
    gw = "./gradlew";
  };

  programs.bash.shellAliases = lib.mkIf isNotNixOS {
    # bazel = lib.mkIf isNotNixOS "${pkgs.bazelisk}/bin/bazelisk";
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.bash.enable = true;
  programs.zsh.enable = true;

  home.file.".bazelrc".text = ''
    common --disk_cache=${config.home.homeDirectory}/.cache/bazel-disk
  '';

  home.sessionPath = ["$HOME/.local/bin"];

  programs.git = {
    userName = "Ilia Malakhov";
    userEmail = "ilya.malakhov4@gmail.com";

    /*
    signing = {
      signByDefault = false;
      key = "64ECA0776D0E99AC";
    };
    */

    lfs.enable = true;

    aliases = {
      push-force-safe = "push --force-with-lease --force-if-includes";
    };

    includes = [
      {
        contents.user.email = "ilia.malakhov@jetbrains.com";
        condition = "gitdir:~/Projects/JetBrains/";
      }
    ];
  };

  programs.ssh.matchBlocks = {
    "git.jetbrains.team" = {
      extraOptions = {
        "IdentityAgent" = "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\""; # 1password ssh-agent
      };
    };
  };

  home.sessionVariables = {
    LIBRARY_PATH = "$LIBRARY_PATH:${config.home.profileDirectory}/lib";
  };
}
