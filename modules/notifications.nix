{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  hasSopsSecretsOption = lib.hasAttrByPath ["sops" "secrets"] options;
in {
  options.i4.notifications.notify = lib.mkOption {
    type = lib.types.functionTo lib.types.str;
    readOnly = true;
    description = "Generate a shell command that sends a notification using apprise.";
    example = lib.literalExpression ''config.i4.notifications.notify "Can't create backup"'';
    default = _: throw "i4.notifications.notify requires the sops-nix module.";
  };

  config = lib.mkMerge [
    {
      i4.notifications.notify =
        if hasSopsSecretsOption
        then message:
          "${lib.getExe pkgs.apprise} --config ${lib.escapeShellArg config.sops.secrets."apprise-config".path} --body ${lib.escapeShellArg message}"
        else _: throw "i4.notifications.notify requires `inputs.sops-nix.nixosModules.sops` to be imported.";
    }
    (lib.mkIf hasSopsSecretsOption {
      sops.secrets."apprise-config" = {};
    })
  ];
}
