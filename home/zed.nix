{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.zed;
  isDarwin = pkgs.stdenv.isDarwin;
in {
  options.i4.zed = {
    enable = lib.mkEnableOption "Zed editor configuration";
  };

  config = lib.mkIf cfg.enable {
    programs.zed-editor = {
      enable = !isDarwin;
    };
  };
}
