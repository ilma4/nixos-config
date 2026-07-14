{
  config,
  constants,
  lib,
  ...
}: let
  cfg = config.i4.notifications;
  ntfyTopicUrl = "${constants.ntfy.local-base-url}/${constants.ntfy.topic}";
in {
  options.i4.notifications = {
    enable = lib.mkEnableOption "notifications via ntfy";

    notify = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      readOnly = true;
      description = "Generate a shell command that publishes a notification to the local ntfy server.";
      example = lib.literalExpression ''config.i4.notifications.notify "Can't create backup"'';
    };
  };

  config = lib.mkMerge [
    {
      _module.args.notify = cfg.notify;
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.services.ntfy-sh.enable;
          message = "i4.notifications requires services.ntfy-sh.enable.";
        }
      ];

      i4.notifications.notify = message:
        "${lib.getExe config.services.ntfy-sh.package} publish --quiet --message ${lib.escapeShellArg message} ${lib.escapeShellArg ntfyTopicUrl}";
    })
  ];
}
