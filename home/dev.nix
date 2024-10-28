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
