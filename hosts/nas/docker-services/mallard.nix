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
  mallardUidGid = "${toString config.users.users.mallard.uid}:${toString config.users.groups.mallard.gid}";

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

    ${pkgs.coreutils}/bin/install -d -m 0750 -o mallard -g mallard "${srvDir}" "${voicesDir}"

    for file in "${src}/voices"/*.ogg; do
      target="${voicesDir}/$(${pkgs.coreutils}/bin/basename "$file")"

      if [[ ! -e "$target" ]]; then
        ${pkgs.coreutils}/bin/install -m 0640 -o mallard -g mallard "$file" "$target"
      fi
    done
  '';

  buildImageScript = pkgs.writeShellScript "mallard-build-image.sh" ''
    set -euo pipefail

    exec ${pkgs.podman}/bin/podman build --pull=newer --tag ${imageTag} ${src}
  '';
in {
  users.users.mallard = {
    isSystemUser = true;
    uid = 805;
    group = "mallard";
    description = "Mallard Telegram bot user";
  };
  users.groups.mallard.gid = config.users.users.mallard.uid;

  sops.secrets.${telegramMyIdSecret} = {
    owner = "mallard";
    group = "mallard";
  };

  sops.secrets.${mallardApiKeySecret} = {
    owner = "mallard";
    group = "mallard";
  };

  sops.templates."mallard.env" = {
    content = ''
      TG_API_KEY=${config.sops.placeholder.${mallardApiKeySecret}}
      TG_ADMIN_ID=${config.sops.placeholder.${telegramMyIdSecret}}
    '';
    mode = "0400";
    owner = "mallard";
    group = "mallard";
    restartUnits = ["mallard.service"];
  };

  systemd.tmpfiles.rules = [
    "d ${srvDir} 0750 mallard mallard -"
    "d ${voicesDir} 0750 mallard mallard -"
  ];

  systemd.services.mallard = {
    description = "Mallard Telegram bot";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = [
      "network-online.target"
      # "sops-nix.service"
    ];
    requires = [
      # "sops-nix.service"
    ];
    unitConfig.RequiresMountsFor = "/var/lib/containers/storage";
    # unitConfig.ConditionUser = "mallard";

    serviceConfig = {
      Type = "notify";
      Environment = "PODMAN_SYSTEMD_UNIT=%n";
      NotifyAccess = "all";
      Delegate = true;
      KillMode = "mixed";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "15min";
      TimeoutStopSec = "30s";
      ExecStartPre = [
        prepareVoicesScript
        buildImageScript
      ];
      ExecStart = "${pkgs.podman}/bin/podman run --detach --replace --rm --name ${containerName} --cgroups=split --sdnotify=conmon --env-file ${config.sops.templates."mallard.env".path} --user ${mallardUidGid} --volume ${voicesDir}:/app/voices ${imageTag}";
      ExecStop = "${pkgs.podman}/bin/podman stop --ignore --time 10 ${containerName}";
      ExecStopPost = "${pkgs.podman}/bin/podman rm --ignore -f ${containerName}";
    };
  };
}
