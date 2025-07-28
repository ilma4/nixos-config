{
  pkgs,
  lib,
  inputs,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
in {
  programs.zed-editor = {
    enable = true;
    package = lib.mkIf isDarwin pkgs.bash; # hack to avoid installing, on darwin zed is installed via homebrew
  };
}
