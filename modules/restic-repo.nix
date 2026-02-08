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

  repoCalls =
    lib.concatStringsSep "\n"
    (lib.mapAttrsToList (
        name: repo: ''
          manage_repo \
            ${lib.escapeShellArg name} \
            ${lib.escapeShellArg repo.location} \
            ${lib.escapeShellArg repo."password-file"} \
            ${lib.escapeShellArg (
            if repo."old-password-file" == null
            then ""
            else repo."old-password-file"
          )} \
            ${lib.escapeShellArg repo.permissions} \
            ${lib.escapeShellArg (
            if isHomeManager
            then ""
            else repo.user
          )} \
            ${lib.escapeShellArg (
            if isHomeManager
            then ""
            else repo.group
          )}
        ''
      )
      cfg.repos);

  activationScript = pkgs.writeShellScript "i4-restic-repo-activation.sh" ''
    set -euo pipefail

    RESTIC_BIN="${pkgs.restic}/bin/restic"
    JQ_BIN="${pkgs.jq}/bin/jq"
    SUPPORTS_OWNER="${
      if isHomeManager
      then "0"
      else "1"
    }"

    manage_repo() {
      local repo_name="$1"
      local repo_location="$2"
      local password_file="$3"
      local old_password_file="$4"
      local repo_permissions="$5"
      local repo_user="$6"
      local repo_group="$7"
      local key_json
      local key_count
      local current_key_id
      local key_id
      local key_count_after

      if [ ! -f "$password_file" ]; then
        echo "restic-repo[$repo_name]: password file does not exist: $password_file" >&2
        exit 1
      fi

      if [ -n "$old_password_file" ] && [ ! -f "$old_password_file" ]; then
        echo "restic-repo[$repo_name]: old password file does not exist: $old_password_file" >&2
        exit 1
      fi

      mkdir -p "$repo_location"
      chmod "$repo_permissions" "$repo_location"

      if [ "$SUPPORTS_OWNER" = "1" ] && [ -n "$repo_user" ] && [ -n "$repo_group" ]; then
        chown "$repo_user:$repo_group" "$repo_location"
      fi

      if [ ! -f "$repo_location/config" ]; then
        "$RESTIC_BIN" --repo "$repo_location" --password-file "$password_file" init
      fi

      if [ -n "$old_password_file" ]; then
        if "$RESTIC_BIN" --repo "$repo_location" --password-file "$password_file" key list >/dev/null 2>&1; then
          return 0
        fi

        "$RESTIC_BIN" --repo "$repo_location" --password-file "$old_password_file" key add --new-password-file "$password_file"
        "$RESTIC_BIN" --repo "$repo_location" --password-file "$password_file" key list >/dev/null
        return 0
      fi

      key_json="$("$RESTIC_BIN" --repo "$repo_location" --password-file "$password_file" key list --json)"
      key_count="$(printf '%s' "$key_json" | "$JQ_BIN" 'length')"

      if [ "$key_count" -le 1 ]; then
        return 0
      fi

      current_key_id="$(printf '%s' "$key_json" | "$JQ_BIN" -r '.[] | select(.current == true) | .id' | head -n 1)"
      if [ -z "$current_key_id" ] || [ "$current_key_id" = "null" ]; then
        echo "restic-repo[$repo_name]: unable to determine current key id" >&2
        exit 1
      fi

      printf '%s' "$key_json" | "$JQ_BIN" -r '.[].id' | while IFS= read -r key_id; do
        if [ "$key_id" != "$current_key_id" ]; then
          "$RESTIC_BIN" --repo "$repo_location" --password-file "$password_file" key remove "$key_id"
        fi
      done

      key_count_after="$("$RESTIC_BIN" --repo "$repo_location" --password-file "$password_file" key list --json | "$JQ_BIN" 'length')"
      if [ "$key_count_after" -ne 1 ]; then
        echo "restic-repo[$repo_name]: expected one key after cleanup, found $key_count_after" >&2
        exit 1
      fi
    }

    ${repoCalls}
  '';
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
            "password-file" = mkOption {
              type = types.singleLineStr;
              description = "Path to current repository password file.";
            };
            "old-password-file" = mkOption {
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
              type = types.nullOr types.singleLineStr;
              default = null;
              description = "Owner user for the repository directory.";
            };
            group = mkOption {
              type = types.nullOr types.singleLineStr;
              default = null;
              description = "Owner group for the repository directory.";
            };
          };
        }));
        default = {};
        description = "Local restic repositories to create and maintain during activation.";
      };
    };
  };

  config = mkIf cfg.enable (
    let
      hasSopsSecrets = (config ? sops) && (config.sops ? secrets) && config.sops.secrets != {};
      invalidOwnershipRepos = lib.attrNames (
        lib.filterAttrs (
          _: repo:
            if isHomeManager
            then repo.user != null || repo.group != null
            else repo.user == null || repo.group == null
        )
        cfg.repos
      );
    in
      mkMerge [
        {
          assertions = [
            {
              assertion = invalidOwnershipRepos == [];
              message =
                if isHomeManager
                then "On Home Manager, `i4.restic.repos.<name>.user` and `i4.restic.repos.<name>.group` must be null. Invalid repos: ${lib.concatStringsSep ", " invalidOwnershipRepos}"
                else "On NixOS and nix-darwin, `i4.restic.repos.<name>.user` and `i4.restic.repos.<name>.group` must be set. Invalid repos: ${lib.concatStringsSep ", " invalidOwnershipRepos}";
            }
          ];
        }
        (optionalAttrs isHomeManager {
          home.activation.i4-restic-repo =
            lib.hm.dag.entryAfter (
              ["writeBoundary"]
              ++ lib.optional hasSopsSecrets "sops-nix"
            ) ''
              ${activationScript}
            '';
        })
        (optionalAttrs (!isHomeManager && !isDarwin) {
          system.activationScripts.i4-restic-repo =
            lib.stringAfter
            (lib.optional hasSopsSecrets "setupSecrets")
            ''
              ${activationScript}
            '';
        })
        (optionalAttrs (!isHomeManager && isDarwin) {
          system.activationScripts.postActivation.text = lib.mkOrder 2000 ''
            ${activationScript}
          '';
        })
      ]
  );
}
