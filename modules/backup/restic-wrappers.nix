{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) all attrNames escapeShellArgs length mapAttrsToList mkIf unique;

  cfg = config.i4.backup;

  remoteRepoNames = attrNames cfg.remoteRepos;

  isValidRemoteRepoName = name: builtins.match "^[A-Za-z0-9._-]+$" name != null;

  mkWrapperName = name: "i4-restic-${name}";

  generatedWrapperNames = ["i4-restic-local"] ++ builtins.map mkWrapperName remoteRepoNames;

  remoteRepoNamesAreValid = all isValidRemoteRepoName remoteRepoNames;
  hasLocalRemoteRepo = builtins.elem "local" remoteRepoNames;
  wrapperNamesAreUnique = length generatedWrapperNames == length (unique generatedWrapperNames);

  mkWrapper = name: repo: let
    resticArgs = ["${lib.getExe pkgs.restic}" "--repo" repo.location "--password-file" repo.passwordFile] ++ repo.extraResticArgs;
  in
    pkgs.writeShellScriptBin (mkWrapperName name) ''
      set -euo pipefail

      exec ${escapeShellArgs resticArgs} "''$@"
    '';
in {
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = remoteRepoNamesAreValid;
        message = "i4.backup.remoteRepos keys must match ^[A-Za-z0-9._-]+$ to generate i4-restic-<name> wrappers";
      }
      {
        assertion = !hasLocalRemoteRepo;
        message = "i4.backup.remoteRepos cannot define a `local` repo name because it conflicts with i4-restic-local";
      }
      {
        assertion = wrapperNamesAreUnique;
        message = "i4.backup remote repository wrapper names must be unique";
      }
    ];

    environment.systemPackages =
      if remoteRepoNamesAreValid && !hasLocalRemoteRepo && wrapperNamesAreUnique
      then
        [(mkWrapper "local" cfg.localRepo)]
        ++ mapAttrsToList mkWrapper cfg.remoteRepos
      else [];
  };
}
