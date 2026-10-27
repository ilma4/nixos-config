{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.backup.monitoring;
  serverRepo = config.i4.backup.localRepo;
  collectorConfig = pkgs.writeText "i4-backup-monitoring.json" (builtins.toJSON {
    repositories = lib.mapAttrsToList (name: repo: repo // {inherit name;}) (cfg.repositories
      // {
        nas-server = {
          source = "nas-server";
          hostname = config.networking.hostName;
          paths = config.i4.backup.paths;
          inherit (serverRepo) location passwordFile;
          extraArgs = serverRepo.extraResticArgs;
        };
      });
    compare = ["nas-hdd" "hetzner"];
    stateFile = "/var/lib/i4-backup-monitoring/state.json";
    pushgatewayUrl = "http://127.0.0.1:9091/metrics/job/i4-backup-monitoring/host/${config.networking.hostName}";
    relayService = "i4-quicksilver-backup-relay.service";
  });
  collector = pkgs.writeShellScript "i4-backup-monitoring" ''
    set -euo pipefail

    exec ${lib.getExe pkgs.bun} ${../../modules/backup/monitor.ts} ${collectorConfig}
  '';
  repositoryType = lib.types.submodule {
    options = {
      source = lib.mkOption {type = lib.types.str;};
      hostname = lib.mkOption {type = lib.types.str;};
      paths = lib.mkOption {type = lib.types.listOf lib.types.str;};
      location = lib.mkOption {type = lib.types.str;};
      passwordFile = lib.mkOption {type = lib.types.str;};
      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
    };
  };
in {
  options.i4.backup.monitoring.repositories = lib.mkOption {
    type = lib.types.attrsOf repositoryType;
    description = "Repositories inspected for Quicksilver snapshot freshness and replication.";
  };

  config = {
    systemd.services.i4-backup-monitoring = {
      description = "Inspect backup snapshots and NAS/Hetzner replication";
      # Run through the timer and relay hooks, not on every system activation:
      # inspecting the HDD-backed repositories wakes sleeping disks.
      after = ["network-online.target" "sops-nix.service" "pushgateway.service"];
      wants = ["network-online.target" "pushgateway.service"];
      path = [pkgs.restic pkgs.systemd];
      environment.RESTIC_CACHE_DIR = "/var/lib/i4-backup-monitoring/cache";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = collector;
        StateDirectory = "i4-backup-monitoring";
        StateDirectoryMode = "0700";
        TimeoutStartSec = "25min";
        UMask = "0077";
      };
    };
    # Restart ensures relay completion refreshes a collection already in flight.
    systemd.services.i4-backup-monitoring-refresh = {
      description = "Refresh backup monitoring after a relay result";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl --no-block restart i4-backup-monitoring.service";
      };
    };
    systemd.timers.i4-backup-monitoring = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 07:00:00";
        Persistent = true;
      };
    };

    # Hook every stage: a dependency failure can prevent the relay from starting.
    systemd.services.i4-quicksilver-backup-init.onFailure = ["i4-backup-monitoring-refresh.service"];
    systemd.services.i4-quicksilver-backup-rotate-keys.onFailure = ["i4-backup-monitoring-refresh.service"];
    systemd.services.i4-quicksilver-backup-relay = {
      onFailure = ["i4-backup-monitoring-refresh.service"];
      onSuccess = ["i4-backup-monitoring-refresh.service"];
    };
  };
}
