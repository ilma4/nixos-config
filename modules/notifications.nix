{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.notifications;
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
      sops.secrets."apprise-config" = {};

      i4.notifications.notify = message:
        "${lib.getExe pkgs.apprise} --config ${lib.escapeShellArg config.sops.secrets."apprise-config".path} --body ${lib.escapeShellArg message}";
    })
  ];
}
