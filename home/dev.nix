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
      then [pkgs-unstable.bazelisk]
      else []
    );

  programs.zsh.shellAliases = lib.mkIf isNotNixOS {
    bazel = "bazelisk";
    gw = "./gradlew";
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
    "torrent-vm" = {
      hostname = "127.0.0.1";
      port = 2222;
    };
  };

  home.sessionVariables = {
    LIBRARY_PATH = "$LIBRARY_PATH:${config.home.profileDirectory}/lib";
  };
}
