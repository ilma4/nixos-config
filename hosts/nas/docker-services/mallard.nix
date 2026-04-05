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
    composeText = ''
      name: mallard

      services:
        mallard:
          build:
            context: ${src}
          container_name: mallard-bot
          env_file:
            - ${config.sops.templates."mallard.env".path}
          user: "${mallardUidGid}"
          volumes:
            - ${voicesDir}:/app/voices
          restart: unless-stopped
    '';
    upArgs = ["--build"];
  };

  systemd.services.mallard.serviceConfig = {
    ExecStartPre = [prepareVoicesScript];
    TimeoutStartSec = "15min";
    TimeoutStopSec = "30s";
  };
}
