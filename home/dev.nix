{
  config,
  lib,
  pkgs,
  ...
}: let
  isNotNixOS = pkgs.stdenv.isDarwin || config.targets.genericLinux.enable;
in {
  home.packages = with pkgs;
    [
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
          if [ -z "$1" ]; then
            echo "Error: No 'targetHost' provided."
            echo "Usage: i4-update-host <targetHost>"
            exit 1
          fi

          targetHost="$1"

          nix shell nixpkgs#nixos-rebuild --command nixos-rebuild switch \
            --flake "${config.flake-location}#$targetHost" \
            --target-host "root@$targetHost" \
            --build-host "root@$targetHost" \
            --fast
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
      then [pkgs.bazelisk]
      else []
    );

  programs.zsh.shellAliases = lib.mkIf isNotNixOS {
    bazel = "bazelisk";
    gw = "./gradlew";
  };

  home.file.".bazelrc".text = ''
    common --disk_cache=${config.home.homeDirectory}/.cache/bazel-disk
  '';

  home.sessionPath = ["$HOME/.local/bin"];

  programs.git = {
    userName = "Ilia Malakhov";
    # userEmail = "ilya.malakhov4@gmail.com";
    /*
    signing = {
      signByDefault = false;
      key = "64ECA0776D0E99AC";
    };
    */
    lfs.enable = true;
    extraConfig = {
      "includeIf \"gitdir:~/Projects/JetBrains/\"" = {
        path = "~/Projects/JetBrains/.gitconfig";
      };
    };
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
