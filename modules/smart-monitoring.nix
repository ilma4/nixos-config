{
  config,
  lib,
  ...
}: {
  services.prometheus.exporters.smartctl = {
    enable = lib.mkDefault (!config.boot.isContainer);
    listenAddress = lib.mkDefault "127.0.0.1";
    port = 9633;
    maxInterval = "5m";
    # Collect from active disks without spinning up sleeping NAS HDDs.
    extraFlags = ["--smartctl.powermode-check=standby"];
  };
}
