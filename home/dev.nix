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
      if isNotNixOS
      then [pkgs.bazelisk]
      else []
    );

  programs.zsh.shellAliases = lib.mkIf isNotNixOS {
    bazel = "bazelisk";
  };
}
