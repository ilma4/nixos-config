{
  config,
  constants,
  pkgs,
  ...
}: let
  containerName = "mallard-bot";
  imageTag = "localhost/mallard-bot:2562a38f15ad";

  srvDir = "/srv/mallard";
  voicesDir = "${srvDir}/voices";

  telegramMyIdSecret = constants.telegram.my-id-secret;
  mallardApiKeySecret = constants.telegram.mallard.api-key-secret;

  src = pkgs.fetchFromGitHub {
    owner = "ArtemKar123";
    repo = "Mallard-bot";
    rev = "2562a38f15adabbc2e29387590314c648bd390a1";
    hash = "sha256-Iga6Ot38QkNdQSI/Gj/hBSax3XGA6vP41ugr/1wpYZg=";
  };

  prepareVoicesScript = pkgs.writeShellScript "mallard-prepare-voices.sh" ''
    set -euo pipefail

    ${pkgs.coreutils}/bin/mkdir -p "${voicesDir}"

    for file in "${src}/voices"/*.ogg; do
      ${pkgs.coreutils}/bin/cp -n "$file" "${voicesDir}/"
    done
  '';

  buildImageScript = pkgs.writeShellScript "mallard-build-image.sh" ''
    set -euo pipefail

    exec ${pkgs.podman}/bin/podman build --pull=newer --tag ${imageTag} ${src}
  '';
in {
  sops.secrets.${telegramMyIdSecret} = {
    owner = "root";
    group = "root";
  };

  sops.secrets.${mallardApiKeySecret} = {
    owner = "root";
    group = "root";
  };

  sops.templates."mallard.env" = {
    content = ''
      TG_API_KEY=${config.sops.placeholder.${mallardApiKeySecret}}
      TG_ADMIN_ID=${config.sops.placeholder.${telegramMyIdSecret}}
    '';
    mode = "0400";
    owner = "root";
    group = "root";
    restartUnits = ["mallard.service"];
  };

  systemd.tmpfiles.rules = [
    "d ${srvDir} 0755 root root -"
    "d ${voicesDir} 0755 root root -"
  ];

  systemd.services.mallard = {
    description = "Mallard Telegram bot";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = [
      "network-online.target"
      "sops-nix.service"
    ];
    requires = ["sops-nix.service"];
    unitConfig.RequiresMountsFor = "/var/lib/containers/storage";

    serviceConfig = {
      Type = "forking";
      Environment = "PODMAN_SYSTEMD_UNIT=%n";
      PIDFile = "%t/%n-pid";
      KillMode = "none";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "15min";
      TimeoutStopSec = "30s";
      ExecStartPre = [
        "${pkgs.coreutils}/bin/rm -f %t/%n-pid"
        prepareVoicesScript
        buildImageScript
      ];
      ExecStart = "${pkgs.podman}/bin/podman run --detach --replace --rm --name ${containerName} --conmon-pidfile %t/%n-pid --cgroups=no-conmon --sdnotify=conmon --env-file ${config.sops.templates."mallard.env".path} --log-driver=journald --volume ${voicesDir}:/app/voices ${imageTag}";
      ExecStop = "${pkgs.podman}/bin/podman stop --ignore --time 10 ${containerName}";
      ExecStopPost = "${pkgs.podman}/bin/podman rm --ignore -f ${containerName}";
    };
  };
}
