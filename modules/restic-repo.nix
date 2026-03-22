{
  config,
  lib,
  pkgs,
  myLib,
  ...
}: let
  inherit
    (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalAttrs
    types
    ;
  inherit (myLib.unifiedModules.checkers) isDarwin isHomeManager;

  cfg = config.i4.restic;

  reposJsonFile = pkgs.writeText "i4-restic-repos.json" (builtins.toJSON (
    lib.mapAttrsToList (
      name: repo: {
        inherit name;
        inherit (repo) location permissions;
        passwordFile = repo."password-file";
        oldPasswordFile = repo."old-password-file";
        user =
          if isHomeManager
          then null
          else repo.user;
        group =
          if isHomeManager
          then null
          else repo.group;
      }
    )
    cfg.repos
  ));

  activationScript = pkgs.writers.writePython3Bin "i4-restic-repo-activation" {doCheck = false;} ''
    import json
    import os
    import subprocess
    import sys

    RESTIC_BIN = "${pkgs.restic}/bin/restic"
    SUPPORTS_OWNER = ${
      if isHomeManager
      then "False"
      else "True"
    }
    with open("${reposJsonFile}", "r", encoding="utf-8") as repos_file:
      REPOS = json.load(repos_file)


    def repo_error(repo_name, message):
      print(f"restic-repo[{repo_name}]: {message}", file=sys.stderr)
      raise SystemExit(1)


    def run(command, check=True, stdout=None, stderr=None, text=False):
      return subprocess.run(command, check=check, stdout=stdout, stderr=stderr, text=text)


    def restic_cmd(repo_location, password_file, *args):
      return [RESTIC_BIN, "--no-cache=true", "--repo", repo_location, "--password-file", password_file, *args]


    def list_keys(repo_location, password_file):
      result = run(
        restic_cmd(repo_location, password_file, "key", "list", "--json"),
        text=True,
        stdout=subprocess.PIPE,
      )
      return json.loads(result.stdout)


    def manage_repo(repo):
      repo_name = repo["name"]
      repo_location = repo["location"]
      password_file = repo["passwordFile"]
      old_password_file = repo["oldPasswordFile"] or ""
      repo_permissions = repo["permissions"]
      repo_user = repo["user"] or ""
      repo_group = repo["group"] or ""

      if not os.path.isfile(password_file):
        repo_error(repo_name, f"password file does not exist: {password_file}")

      if old_password_file and not os.path.isfile(old_password_file):
        repo_error(repo_name, f"old password file does not exist: {old_password_file}")

      os.makedirs(repo_location, exist_ok=True)
      os.chmod(repo_location, int(repo_permissions, 8))

      if SUPPORTS_OWNER and repo_user and repo_group:
        run(["chown", f"{repo_user}:{repo_group}", repo_location])

      if not os.path.isfile(os.path.join(repo_location, "config")):
        run(restic_cmd(repo_location, password_file, "init"))

      if old_password_file:
        auth_check = run(
          restic_cmd(repo_location, password_file, "key", "list"),
          check=False,
          stdout=subprocess.DEVNULL,
          stderr=subprocess.DEVNULL,
        )
        if auth_check.returncode == 0:
          return

        run(restic_cmd(repo_location, old_password_file, "key", "add", "--new-password-file", password_file))
        run(restic_cmd(repo_location, password_file, "key", "list"), stdout=subprocess.DEVNULL)
        return

      keys = list_keys(repo_location, password_file)
      if len(keys) <= 1:
        return

      current_key_id = None
      for key in keys:
        if key.get("current") is True:
          current_key_id = key.get("id")
          if current_key_id:
            break

      if not current_key_id:
        repo_error(repo_name, "unable to determine current key id")

      for key in keys:
        key_id = key.get("id")
        if key_id != current_key_id:
          if not key_id:
            repo_error(repo_name, "encountered key entry without id during cleanup")
          run(restic_cmd(repo_location, password_file, "key", "remove", key_id))

      key_count_after = len(list_keys(repo_location, password_file))
      if key_count_after != 1:
        repo_error(repo_name, f"expected one key after cleanup, found {key_count_after}")


    def main():
      for repo in REPOS:
        manage_repo(repo)


    if __name__ == "__main__":
      try:
        main()
      except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
  '';

  activationScriptExe = "${activationScript}/bin/i4-restic-repo-activation";
in {
  options = {
    i4.restic = {
      enable = mkEnableOption "manage local restic repositories";
      repos = mkOption {
        type = types.attrsOf (types.submodule (_: {
          options = {
            location = mkOption {
              type = types.singleLineStr;
              description = "Local restic repository directory.";
            };
            password-file = mkOption {
              type = types.singleLineStr;
              description = "Path to current repository password file.";
            };
            old-password-file = mkOption {
              type = types.nullOr types.singleLineStr;
              default = null;
              description = "Path to old repository password file used for key rotation.";
            };
            permissions = mkOption {
              type = types.strMatching "[0-7]{3,4}";
              default = "0700";
              description = "Mode for the repository directory.";
            };
            user = mkOption {
              type = types.singleLineStr;
              description = "Owner user for the repository directory";
            };
            group = mkOption {
              type = types.singleLineStr;
              description = "Owner group for the repository directory";
            };
          };
        }));
        default = {};
        description = "Local restic repositories to create and maintain during activation.";
      };
    };
  };

  config = mkIf cfg.enable {
    system.activationScripts.i4-restic-repo =
      lib.stringAfter "setupSecrets"
      ''
        ${activationScriptExe}
      '';
  };
}
