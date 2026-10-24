{
  config,
  constants,
  pkgs,
  ...
}: let
  srvDir = "/srv/mallard";
  voicesDir = "${srvDir}/voices";
  mallardUidGid = "${toString config.users.users.mallard.uid}:${toString config.users.groups.mallard.gid}";

  telegramMyIdSecret = constants.telegram.my-id-secret;
  mallardApiKeySecret = constants.telegram.mallard.api-key-secret;

  # Forked from ArtemKar123/Mallard-bot at 2562a38f15adabbc2e29387590314c648bd390a1.
  mallard = import ../../../projects/mallard-bot {inherit pkgs;};
  inherit (mallard) src;
  image = mallard.image;

  loadImageScript = pkgs.writeShellScript "mallard-load-image.sh" ''
    set -euo pipefail
    ${pkgs.podman}/bin/podman load --input ${image}
  '';

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

  dockerCompose.mallard = {
    pullImages = false;
    composeText = ''
      name: mallard

      services:
        mallard:
          image: ${image.imageName}:${image.imageTag}
          pull_policy: never
          container_name: mallard-bot
          env_file:
            - ${config.sops.templates."mallard.env".path}
          user: "${mallardUidGid}"
          volumes:
            - ${voicesDir}:/app/voices
          restart: unless-stopped
    '';
  };

  systemd.services.mallard.serviceConfig = {
    ExecStartPre = [loadImageScript prepareVoicesScript];
    TimeoutStartSec = "15min";
    TimeoutStopSec = "30s";
  };
}
