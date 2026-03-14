{
  constants,
  lib,
  notify,
  pkgs,
  ...
}: let
  const = constants.nas.restic-chunker-params-donor;
  repoLocation = const.location;
  passwordFile = "/run/secrets/${const.password-secret}";
  restic = lib.getExe pkgs.restic;

  checkRepoScript = pkgs.writeShellScript "restic-chunker-params-donor-check.sh" ''
    set -euo pipefail

    if ${restic} --no-cache --repo ${lib.escapeShellArg repoLocation} --password-file ${lib.escapeShellArg passwordFile} snapshots >/dev/null 2>&1; then
      exit 0
    fi

    # TODO: enable notifications
    # ${notify "Restic chunker params donor repository is missing or inaccessible at ${repoLocation}."}
  '';
in {
  sops.secrets.${const.password-secret} = {
    owner = "root";
    group = "root";
  };

  systemd.services.restic-chunker-params-donor-check = {
    description = "Check restic chunker params donor repository exists";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = checkRepoScript;
    };
  };
}
