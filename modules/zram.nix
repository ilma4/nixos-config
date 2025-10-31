{
  config,
  lib,
  myLib,
  ...
}: let
  cfg = config.i4.zram;
in {
  options.i4.zram = {
    enable = lib.mkEnableOption "zram swap";
  };
  config = lib.mkIf cfg.enable (myLib.unifiedModules.enableForConfigurations ["isNixos"] {
    zramSwap = {
      enable = true;
      memoryPercent = 100;
      algorithm = "zstd";
    };
  });
}
