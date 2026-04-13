{
  config,
  constants,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.notifications;
  telegramMyIdSecret = constants.telegram.my-id-secret;
  notificationsApiKeySecret = constants.telegram.notifications-api-key-secret;
  appriseImage = "docker.io/caronc/apprise:latest";
  appriseUidGid = "${toString config.users.users.apprise.uid}:${toString config.users.groups.apprise.gid}";
  apprisePort = "18000";
  appriseUrl = "http://127.0.0.1:${apprisePort}/notify/";
in {
  options.i4.notifications = {
    enable = lib.mkEnableOption "notifications via apprise";

    notify = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      readOnly = true;
      description = "Generate a shell command that sends a notification using the local apprise API.";
      example = lib.literalExpression ''config.i4.notifications.notify "Can't create backup"'';
      # default = _: throw "i4.notifications.enable must be true to use notify.";
    };
  };

  config = lib.mkMerge [
    {
      _module.args.notify = cfg.notify;
    }
    (lib.mkIf cfg.enable {
      users.users.apprise = {
        isSystemUser = true;
        uid = 807;
        group = "apprise";
      };
      users.groups.apprise.gid = config.users.users.apprise.uid;

      sops.secrets.${telegramMyIdSecret} = {};
      sops.secrets.${notificationsApiKeySecret} = {};

      sops.templates."apprise.env" = {
        content = ''
          APPRISE_STATELESS_URLS=tgram://bot${config.sops.placeholder.${notificationsApiKeySecret}}/${config.sops.placeholder.${telegramMyIdSecret}}/
        '';
        mode = "0400";
        owner = "root";
        group = "root";
        restartUnits = ["apprise.service"];
      };

      dockerCompose.apprise = {
        composeText = ''
          name: apprise

          services:
            apprise:
              image: ${appriseImage}
              container_name: apprise
              restart: unless-stopped
              read_only: true
              user: "${appriseUidGid}"
              ports:
                - "127.0.0.1:${apprisePort}:8000"
              env_file:
                - ${config.sops.templates."apprise.env".path}
              environment:
                APPRISE_STATEFUL_MODE: "disabled"
                ALLOWED_HOSTS: "127.0.0.1 localhost"
                TZ: "${config.time.timeZone}"
              tmpfs:
                - /tmp
              cap_drop:
                - ALL
              security_opt:
                - no-new-privileges:true
        '';
      };

      i4.notifications.notify = message: let
        payload = builtins.toJSON {body = message;};
      in "${lib.getExe pkgs.curl} --fail --silent --show-error --header 'Content-Type: application/json' --data ${lib.escapeShellArg payload} ${lib.escapeShellArg appriseUrl}";
    })
  ];
}
