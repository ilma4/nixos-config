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
    mkOption
    types
    ;

  cfg = config.i4.restic;

  mkRepoCreateService = name: repo: {
    description = "Create and initialize restic repository ${name}";
    wantedBy = ["multi-user.target"];
    after = ["sops-nix.service"];
    path = [pkgs.restic pkgs.sudo];
    serviceConfig = {
      Type = "oneshot";
      # User = repo.user;
      # Group = repo.group;
    };
    script = toString (pkgs.writers.writePython3Bin "create-repo.py" {} ''
      import os, sys, subprocess, shutil

      password_file = "${repo.password-file}"
      location = "${repo.location}"

      if os.path.exists(os.path.join(location, "config")):
        print(f"restic-repo[${name}] at ''${location} already exists")
        sys.exit(0)

      os.makedirs(location, exist_ok=True)
      os.chmod(location, int("${repo.permissions}", 8))
      shutil.chown(location, user="${repo.user}", group="${repo.group}")
      subprocess.run(["sudo", "-u", "${repo.user}", "restic", "--no-cache=true", "--repo", location, "--password-file", password_file, "init"], check=True)
    '');
  };

  mkRepoRotateService = name: repo: {
    description = "Rotate and clean keys for restic repository ${name}";
    wantedBy = ["multi-user.target"];
    after = ["restic-repo-${name}-create.service"];
    requires = ["restic-repo-${name}-create.service"];
    enable = repo.old-password-file != null;
    path = [pkgs.restic];
    serviceConfig = {
      Type = "oneshot";
      User = repo.user;
      Group = repo.group;
    };
    script = toString (pkgs.writers.writePython3Bin "rorate-keys.py" {} ''
      import os, sys, subprocess, json

      password_file = "${repo.password-file}"
      old_password_file = "${repo.old-password-file}"
      location = "${repo.location}"

      base_cmd = ["restic", "--no-cache=true", "--repo", location]

      if subprocess.run(base_cmd + ["--password-file", password_file, "key", "list"]).returncode == 0:
        sys.exit(0)

      subprocess.run(base_cmd + ["--password-file", old_password_file, "key", "add", "--new-password-file", password_file], check=True)

      keys = json.load(subprocess.run(base_cmd + ["--password-file", password_file, "key", "list", "--json"], capture_output=True, text=True, check=True).stdout)

      for k in [k for k in keys if k.get("current") == False]:
        subprocess.run(base_cmd + ["--password-file", password_file, "key", "remove", k["id"]], check=True)
    '');
  };
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
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (name: repo: {
        "restic-repo-${name}-create" = mkRepoCreateService name repo;
        "restic-repo-${name}-rotate" = mkRepoRotateService name repo;
      })
      cfg.repos
    );
  };
}
