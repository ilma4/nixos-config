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
      alejandra

      (pkgs.rust-bin.stable.latest.default.override {
        extensions = ["rust-src"];
      })
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
    userEmail = "ilya.malakhov4@gmail.com";
    signing = {
      signByDefault = false;
      key = "64ECA0776D0E99AC";
    };
  };

  home.sessionVariables = {
    LIBRARY_PATH = "$LIBRARY_PATH:${config.home.profileDirectory}/lib";
  };
}
