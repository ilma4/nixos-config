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
in {
  options.i4.notifications = {
    enable = lib.mkEnableOption "notifications via apprise";

    notify = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      readOnly = true;
      description = "Generate a shell command that sends a notification using apprise.";
      example = lib.literalExpression ''config.i4.notifications.notify "Can't create backup"'';
      # default = _: throw "i4.notifications.enable must be true to use notify.";
    };
  };

  config = lib.mkMerge [
    {
      _module.args.notify = cfg.notify;
    }
    (lib.mkIf cfg.enable {
      sops.secrets.${telegramMyIdSecret} = {};
      sops.secrets.${notificationsApiKeySecret} = {};

      sops.templates."apprise.conf" = {
        content = ''
          tgram://bot${config.sops.placeholder.${notificationsApiKeySecret}}/${config.sops.placeholder.${telegramMyIdSecret}}/
        '';
        mode = "0400";
        owner = "root";
        group = "root";
      };

      i4.notifications.notify = message: "${lib.getExe pkgs.apprise} --config ${lib.escapeShellArg config.sops.templates."apprise.conf".path} --body ${lib.escapeShellArg message}";
    })
  ];
}
