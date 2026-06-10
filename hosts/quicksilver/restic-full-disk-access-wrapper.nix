{
  config,
  lib,
  pkgs,
  ...
}: let
  backupUser = "ilma4";
  backupGroup = "staff";
  backupHome = "/Users/${backupUser}";
  backupCache = "${backupHome}/Library/Caches/restic";
  appName = "ResticBackup";
  bundleIdentifier = "local.restic.backup";
  appPath = "${backupHome}/Applications/${appName}.app";
  binDir = "${appPath}/Contents/MacOS";
  backupExecutableName = "i4-backup";
  resticExecutableName = "restic";
  # Use ad-hoc signing.  This avoids depending on a local codesigning identity,
  # but macOS TCC grants may be tied to the cdhash and can be lost when the
  # wrapper is rebuilt.
  codeSigningIdentity = "-";
  wrapperVersion = "7";
  wrapperPath = "${binDir}:${backupHome}/.nix-profile/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  checkFullDiskAccess = "${../../scripts/check-full-disk-access.sh}";
  checkLocalNetworkAccess = "${../../scripts/check-local-network-access.sh}";

  backupCfg = config.i4.backup;

  # Build with Nix, then copy into the stable app bundle path during activation
  # so macOS TCC attributes access to ResticBackup.app.
  backupWrapper =
    pkgs.writers.writeRustBin backupExecutableName {
      rustcArgs = ["--edition=2021" "-C" "opt-level=2"];
    }
    ''
      use std::env;
      use std::ffi::{OsStr, OsString};
      use std::os::unix::process::{CommandExt, ExitStatusExt};
      use std::path::Path;
      use std::process::{Command, ExitStatus, Stdio};

      const ENV_BACKUP_HOME: &str = "I4_BACKUP_HOME";
      const ENV_BACKUP_CACHE: &str = "I4_BACKUP_CACHE";
      const ENV_WRAPPER_PATH: &str = "I4_BACKUP_WRAPPER_PATH";
      const ENV_RESTIC_EXECUTABLE_NAME: &str = "I4_BACKUP_RESTIC_EXECUTABLE_NAME";
      const ENV_RESTIC: &str = "I4_BACKUP_RESTIC";

      struct RuntimeConfig {
          backup_home: OsString,
          backup_cache: OsString,
          wrapper_path: OsString,
          restic_executable_name: OsString,
          restic: OsString,
      }

      impl RuntimeConfig {
          fn from_env() -> Self {
              Self {
                  backup_home: required_env(ENV_BACKUP_HOME),
                  backup_cache: required_env(ENV_BACKUP_CACHE),
                  wrapper_path: required_env(ENV_WRAPPER_PATH),
                  restic_executable_name: required_env(ENV_RESTIC_EXECUTABLE_NAME),
                  restic: required_env(ENV_RESTIC),
              }
          }
      }

      fn required_env(name: &str) -> OsString {
          match env::var_os(name) {
              Some(value) => value,
              None => {
                  eprintln!("missing required environment variable: {name}");
                  std::process::exit(64);
              }
          }
      }

      fn exit_code(status: ExitStatus) -> i32 {
          status
              .code()
              .or_else(|| status.signal().map(|signal| 128 + signal))
              .unwrap_or(127)
      }

      fn run_process<P, I, S>(config: &RuntimeConfig, program: P, argv0: &str, args: I) -> i32
      where
          P: AsRef<OsStr>,
          I: IntoIterator<Item = S>,
          S: AsRef<OsStr>,
      {
          let program = program.as_ref();
          let mut command = Command::new(program);
          command
              .arg0(argv0)
              .args(args)
              .env("HOME", config.backup_home.as_os_str())
              .env("RESTIC_CACHE_DIR", config.backup_cache.as_os_str())
              .env("PATH", config.wrapper_path.as_os_str())
              .stdout(Stdio::inherit())
              .stderr(Stdio::inherit());

          match command.status() {
              Ok(status) => exit_code(status),
              Err(err) => {
                  eprintln!("posix_spawn failed: {}: {err}", program.to_string_lossy());
                  127
              }
          }
      }

      fn run_restic(config: &RuntimeConfig, args: &[OsString]) -> i32 {
          run_process(config, config.restic.as_os_str(), "restic", args.iter().skip(1))
      }

      fn run_i4_backup_command(
          config: &RuntimeConfig,
          backup_program: &OsStr,
          command: &str,
          config_file: &OsStr,
      ) -> i32 {
          run_process(config, backup_program, "i4-backup", [OsStr::new(command), config_file])
      }

      fn main() {
          let config = RuntimeConfig::from_env();
          let args: Vec<OsString> = env::args_os().collect();
          let is_restic = args
              .first()
              .and_then(|argv0| Path::new(argv0.as_os_str()).file_name())
              .is_some_and(|name| name == config.restic_executable_name.as_os_str());

          if is_restic {
              std::process::exit(run_restic(&config, &args));
          }

          if args.len() != 5 {
              eprintln!(
                  "usage: {} <i4-backup-program> <init-repos-config> <rotate-keys-config> <run-backup-config>",
                  args.first()
                      .and_then(|arg| arg.to_str())
                      .unwrap_or("i4-backup")
              );
              std::process::exit(64);
          }

          let backup_program = args[1].as_os_str();
          for (command, config_file) in [
              ("init-repos", args[2].as_os_str()),
              ("rotate-keys", args[3].as_os_str()),
              ("run-backup", args[4].as_os_str()),
          ] {
              let status = run_i4_backup_command(&config, backup_program, command, config_file);
              if status != 0 {
                  std::process::exit(status);
              }
          }
      }
    '';
in {
  environment.systemPackages = [pkgs.restic];

  launchd.user.agents.i4-backup = {
    # Launch the stable app executable directly so macOS TCC attributes backup
    # file access to ResticBackup.app rather than /bin/bash or /nix/store tools.
    path = lib.mkForce [];
    serviceConfig = {
      ProgramArguments = lib.mkForce [
        "${binDir}/${backupExecutableName}"
        backupCfg.internal.backupProgram
        backupCfg.internal.initReposConfigFile
        backupCfg.internal.rotateKeysConfigFile
        backupCfg.internal.runBackupConfigFile
      ];
      EnvironmentVariables = {
        PATH = lib.mkForce wrapperPath;
        I4_BACKUP_HOME = backupHome;
        I4_BACKUP_CACHE = backupCache;
        I4_BACKUP_WRAPPER_PATH = wrapperPath;
        I4_BACKUP_RESTIC_EXECUTABLE_NAME = resticExecutableName;
        I4_BACKUP_RESTIC = "/run/current-system/sw/bin/restic";
      };
    };
  };

  system.activationScripts.extraActivation.text = lib.mkAfter ''
        set -euo pipefail

        app=${lib.escapeShellArg appPath}
        bin_dir=${lib.escapeShellArg binDir}
        backup_exe="$bin_dir/${backupExecutableName}"
        restic_exe="$bin_dir/${resticExecutableName}"
        version_file="$app/Contents/i4-wrapper-version"
        signing_identity_file="$app/Contents/i4-code-signing-identity"
        signing_identity=${lib.escapeShellArg codeSigningIdentity}
        bundle_identifier=${lib.escapeShellArg bundleIdentifier}
        created_wrapper=0

        run_as_backup_user() {
          if [ "$(/usr/bin/id -un)" = ${lib.escapeShellArg backupUser} ]; then
            "$@"
          else
            /usr/bin/sudo -u ${lib.escapeShellArg backupUser} "$@"
          fi
        }

        reset_privacy_permission_for_identifier() {
          local service="$1"
          local permission_name="$2"
          local identifier="$3"
          local reset_done=0

          if [ -z "$identifier" ]; then
            return 1
          fi

          if /usr/bin/tccutil reset "$service" "$identifier" >/dev/null 2>&1; then
            reset_done=1
          fi

          if [ "$(/usr/bin/id -un)" != ${lib.escapeShellArg backupUser} ]; then
            if run_as_backup_user /usr/bin/tccutil reset "$service" "$identifier" >/dev/null 2>&1; then
              reset_done=1
            fi
          fi

          if [ "$reset_done" -eq 1 ]; then
            echo "Removed outdated $permission_name permission entries for $identifier" >&2
            return 0
          fi

          echo "warning: failed to remove outdated $permission_name permission entries for $identifier" >&2
          return 1
        }

        check_full_disk_access_permission() {
          has_full_disk_access=0
          full_disk_access_report=""
          if full_disk_access_report="$(HOME=${lib.escapeShellArg backupHome} /bin/bash ${lib.escapeShellArg checkFullDiskAccess} "$app" 2>&1)"; then
            has_full_disk_access=1
          fi
        }

        check_local_network_permission() {
          has_local_network=0
          local_network_access_report=""
          if local_network_access_report="$(HOME=${lib.escapeShellArg backupHome} /bin/bash ${lib.escapeShellArg checkLocalNetworkAccess} "$app" 2>&1)"; then
            has_local_network=1
          fi
        }

        current_version=""
        if [ -f "$version_file" ]; then
          current_version="$(/bin/cat "$version_file")"
        fi

        current_signing_identity=""
        if [ -f "$signing_identity_file" ]; then
          current_signing_identity="$(/bin/cat "$signing_identity_file")"
        fi

        if [ -x "$backup_exe" ] \
          && [ -x "$restic_exe" ] \
          && [ -f "$app/Contents/Info.plist" ] \
          && [ "$current_version" = ${lib.escapeShellArg wrapperVersion} ] \
          && [ "$current_signing_identity" = "$signing_identity" ]; then
          echo "${appName}.app wrapper already exists at $app; leaving it unchanged"
        else
          if [ -e "$app" ] && [ ! -d "$app" ]; then
            echo "Existing $app is not a directory; recreating it"
            /bin/rm -rf "$app"
          fi

          /usr/bin/install -d -o ${lib.escapeShellArg backupUser} -g ${lib.escapeShellArg backupGroup} "$bin_dir"

          cat > "$app/Contents/Info.plist" <<'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>${bundleIdentifier}</string>

      <key>CFBundleName</key>
      <string>ResticBackup</string>

      <key>CFBundleExecutable</key>
      <string>i4-backup</string>

      <key>CFBundlePackageType</key>
      <string>APPL</string>
    </dict>
    </plist>
    EOF

          /bin/cp ${lib.escapeShellArg "${backupWrapper}/bin/${backupExecutableName}"} "$backup_exe"
          /bin/cp "$backup_exe" "$restic_exe"
          /bin/chmod 0755 "$backup_exe" "$restic_exe"
          printf '%s\n' ${lib.escapeShellArg wrapperVersion} > "$version_file"
          printf '%s\n' "$signing_identity" > "$signing_identity_file"

          /usr/sbin/chown -R ${lib.escapeShellArg "${backupUser}:${backupGroup}"} "$app"
          run_as_backup_user /usr/bin/codesign --force --deep --sign "$signing_identity" "$app"
          /usr/bin/xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
          /usr/sbin/chown -R ${lib.escapeShellArg "${backupUser}:${backupGroup}"} "$app"
          created_wrapper=1
        fi

        check_full_disk_access_permission
        check_local_network_permission

        full_disk_access_entries_removed=0
        if [ "$has_full_disk_access" -ne 1 ]; then
          case "$full_disk_access_report" in
            *"code signature no longer matches"*)
              if reset_privacy_permission_for_identifier SystemPolicyAllFiles "Full Disk Access" "$bundle_identifier"; then
                full_disk_access_entries_removed=1
                check_full_disk_access_permission
              fi
              ;;
          esac
        fi

        local_network_entries_removed=0
        if [ "$has_local_network" -ne 1 ]; then
          case "$local_network_access_report" in
            *"grant exists for this path, but its signing identifier does not match"*|*"grant exists for this signing identifier, but for a different path"*)
              stale_local_network_identifier="$(printf '%s\n' "$local_network_access_report" | /usr/bin/sed -n "s/.*signing identifier '\([^']*\)'.*/\1/p" | /usr/bin/head -n 1)"

              if reset_privacy_permission_for_identifier LocalNetwork "Local Network" "$bundle_identifier"; then
                local_network_entries_removed=1
              fi
              if [ -n "$stale_local_network_identifier" ] && [ "$stale_local_network_identifier" != "$bundle_identifier" ]; then
                if reset_privacy_permission_for_identifier LocalNetwork "Local Network" "$stale_local_network_identifier"; then
                  local_network_entries_removed=1
                fi
              fi
              if [ "$local_network_entries_removed" -eq 1 ]; then
                check_local_network_permission
              fi
              ;;
          esac
        fi

        if [ "$created_wrapper" -eq 1 ] || [ "$has_full_disk_access" -ne 1 ] || [ "$has_local_network" -ne 1 ]; then
          echo "warning: ${appName}.app backup wrapper may need macOS privacy permissions:" >&2
          if [ "$created_wrapper" -eq 1 ]; then
            echo "  - wrapper was created or recreated at $app" >&2
          fi
          if [ "$full_disk_access_entries_removed" -eq 1 ]; then
            echo "  - outdated Full Disk Access permission entries were removed" >&2
          fi
          if [ "$has_full_disk_access" -ne 1 ]; then
            echo "  - Full Disk Access is not granted or no longer valid for ${appName}.app (${bundleIdentifier})" >&2
            if [ -n "$full_disk_access_report" ]; then
              printf '%s\n' "$full_disk_access_report" | /usr/bin/sed 's/^/      /' >&2
            fi
          fi
          if [ "$local_network_entries_removed" -eq 1 ]; then
            echo "  - outdated Local Network permission entries were removed" >&2
          fi
          if [ "$has_local_network" -ne 1 ]; then
            echo "  - Local Network is not granted or no longer valid for ${appName}.app (${bundleIdentifier})" >&2
            if [ -n "$local_network_access_report" ]; then
              printf '%s\n' "$local_network_access_report" | /usr/bin/sed 's/^/      /' >&2
            fi
          fi
          echo "  Open System Settings -> Privacy & Security, then grant Full Disk Access and Local Network to:" >&2
          echo "    $app" >&2
        fi
  '';
}
