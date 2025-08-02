{
  pkgs,
  lib,
  inputs,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
in {
  programs.zed-editor = {
    enable = !isDarwin;
  };
}
