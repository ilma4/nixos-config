{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}: let
  isNotNixOS = pkgs.stdenv.isDarwin || config.targets.genericLinux.enable;
in {
  home.packages = with pkgs;
    [
      docker # docker cli
      podman # podman cli
      podman-compose # podman-compose is not bundled with podman

      nixd
      nil
      alejandra
      tex-fmt
      sops

      haskell-language-server

      (pkgs.rust-bin.stable.latest.default.override {
        extensions = ["rust-src"];
      })

      (
        pkgs.writeShellScriptBin "i4-update-host" ''
          # Wrapper around external script to set default FLAKE_LOCATION
          export FLAKE_LOCATION="${"\$"}{FLAKE_LOCATION:-${config.flake-location}}"
          exec "${config.flake-location}/dotfiles/i4-update-host.sh" "$@"
        ''
      )
    ]
    ++ (
      if pkgs.stdenv.isDarwin
      then [pkgs.darwin.libiconv]
      else []
    )
    ++ (
      if isNotNixOS
      then [
        pkgs-unstable.bazelisk
        (pkgs.writeShellScriptBin "bazel" ''
          exec ${pkgs.bazelisk}/bin/bazelisk "$@"
        '')
      ]
      else []
    );

  programs.zsh.shellAliases = lib.mkIf isNotNixOS {
    bazel = "${pkgs.bazelisk}/bin/bazelisk";
    gw = "./gradlew";
  };
  programs.bash.shellAliases = lib.mkIf isNotNixOS {
    bazel = "${pkgs.bazelisk}/bin/bazelisk";
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
