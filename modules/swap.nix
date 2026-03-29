{
  config,
  lib,
  myLib,
  ...
}: let
  cfg = config.i4.swap;
in {
  options.i4.swap = {
    zramEnable = lib.mkEnableOption "zram swap";
    zswapEnable = lib.mkEnableOption "zswap";
    swapEnable = lib.mkEnableOption "swap";
    swapSize = lib.mkOption {
      type = lib.types.int;
      default = 16 * 1024; # 16 GiB
    };
  };

  config = myLib.unifiedModules.enableForConfigurations ["isNixos"] (lib.mkMerge [
    {
      assertions = [
        {
          assertion = !(cfg.zramEnable && (cfg.swapEnable || cfg.zswapEnable));
          message = "zram cannot be enabled with swap or zswap";
        }
        {
          assertion = !cfg.zswapEnable || cfg.swapEnable;
          message = "if zswap is enabled, swap must also be enabled";
        }
      ];
    }

    (lib.mkIf cfg.zramEnable {
      zramSwap = {
        enable = true;
        memoryPercent = 100;
        algorithm = "zstd";
      };
    })

    (lib.mkIf cfg.zswapEnable {
      boot.kernelParams = [
        "zswap.enabled=1"
        "zswap.compressor=zstd"
        "zswap.max_pool_percent=30"
        "zswap.shrinker_enabled=1"
      ];
    })
    (lib.mkIf cfg.swapEnable {
      swapDevices = [
        {
          device = "/var/lib/swapfile";
          size = cfg.swapSize;
        }
      ];
    })
  ]);
}
