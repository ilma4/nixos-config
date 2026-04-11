{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    escapeShellArg
    escapeShellArgs
    getExe
    hasPrefix
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    optionalAttrs
    removeSuffix
    types
    ;

  cfg = config.i4.backup;
in {
  options.i4.backup.metrics = {
    enable = mkEnableOption "oneshot restic metrics pushed through Prometheus Pushgateway";

    pushgatewayBaseUrl = mkOption {
      type = types.singleLineStr;
      default = "http://127.0.0.1:9091";
      description = "Base URL of the Prometheus Pushgateway that receives restic metrics.";
    };
  };

  config = mkIf (cfg.enable && cfg.metrics.enable) (let
    commonAfter = ["network-online.target"];
    allRepos =
      mapAttrsToList
      (name: repo: {
        repoName = name;
        unitId = name;
        inherit repo;
      })
      ({local = cfg.localRepo;} // cfg.remoteRepos);

    mkMetricsResticWrapper = repo: let
      resticArgs = [(getExe pkgs.restic)] ++ repo.extraResticArgs;
    in
      pkgs.writeShellScriptBin "restic" ''
        set -euo pipefail

        exec ${escapeShellArgs resticArgs} "$@"
      '';

    mkPushgatewayUrl = repoName: "${removeSuffix "/" cfg.metrics.pushgatewayBaseUrl}/metrics/job/restic-backup/host/${config.networking.hostName}/repo/${repoName}";

    mkMetricsScript = {
      repoName,
      repo,
      ...
    }:
      pkgs.writeShellScript "i4-backup-metrics-${repoName}-daily" ''
        set -euo pipefail

        export PATH=${lib.makeBinPath [(mkMetricsResticWrapper repo) pkgs.coreutils]}:''${PATH:-}
        export RESTIC_REPOSITORY=${escapeShellArg repo.location}
        export RESTIC_PASSWORD_FILE=${escapeShellArg repo.passwordFile}

        metrics_file="$(mktemp --suffix=.prom)"
        trap 'rm -f "$metrics_file"' EXIT

        ${getExe pkgs.restic-exporter} -output "$metrics_file"

        check_status=0
        if [ "$(date +%d)" = "01" ]; then
          check_value=1
          if ! restic check --read-data; then
            check_value=0
            check_status=1
          fi

          printf '# HELP restic_check_all_data_success Result of restic check all data operation in the repository\n# TYPE restic_check_all_data_success gauge\nrestic_check_all_data_success %s\n' "$check_value" >> "$metrics_file"
        fi

        ${getExe pkgs.curl} --fail --show-error --silent -X PUT --data-binary "@$metrics_file" ${escapeShellArg (mkPushgatewayUrl repoName)}

        exit "$check_status"
      '';

    mkMetricsService = {
      repoName,
      repo,
      ...
    }: {
      description = "Run daily restic metrics export with first-of-month data-reading repository check for ${repoName}";
      after = commonAfter;
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.backupUser;
        Group = cfg.backupGroup;
        ExecStart = mkMetricsScript {
          inherit repoName repo;
        };
      };
    };

    mkMetricsTimer = {
      calendar,
      serviceName,
      ...
    }: {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = calendar;
        Persistent = true;
        Unit = "${serviceName}.service";
      };
    };

    metricServices = builtins.listToAttrs (
      builtins.map (repoInfo: let
        dailyName = "i4-backup-metrics-${repoInfo.unitId}-daily";
      in
        nameValuePair dailyName (mkMetricsService repoInfo))
      allRepos
    );

    metricTimers = builtins.listToAttrs (
      builtins.map (repoInfo: let
        dailyName = "i4-backup-metrics-${repoInfo.unitId}-daily";
      in
        nameValuePair dailyName (mkMetricsTimer {
          unitId = repoInfo.unitId;
          calendar = "*-*-* 04:20:00";
          serviceName = dailyName;
        }))
      allRepos
    );
  in {
    assertions = [
      {
        assertion = hasPrefix "http://" cfg.metrics.pushgatewayBaseUrl || hasPrefix "https://" cfg.metrics.pushgatewayBaseUrl;
        message = "i4.backup.metrics.pushgatewayBaseUrl must start with http:// or https:// when metrics are enabled";
      }
    ];

    systemd.services = optionalAttrs cfg.metrics.enable metricServices;
    systemd.timers = optionalAttrs cfg.metrics.enable metricTimers;
  });
}
