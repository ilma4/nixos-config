{
  config,
  lib,
  pkgs,
  ...
}: let
  backupUser = "ilma4";
  backupGroup = "staff";
  backupHome = "/Users/${backupUser}";
  backupCache = "${backupHome}/NoBackup/restic-cache";
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
  wrapperVersion = "5";
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

      const BACKUP_HOME: &str = r#"${backupHome}"#;
      const BACKUP_CACHE: &str = r#"${backupCache}"#;
      const WRAPPER_PATH: &str = r#"${wrapperPath}"#;
      const RESTIC_EXECUTABLE_NAME: &str = r#"${resticExecutableName}"#;
      const RESTIC: &str = "/run/current-system/sw/bin/restic";
      const BACKUP_PROGRAM: &str = r#"${backupCfg.internal.backupProgram}"#;
      const INIT_REPOS_CONFIG: &str = r#"${backupCfg.internal.initReposConfigFile}"#;
      const ROTATE_KEYS_CONFIG: &str = r#"${backupCfg.internal.rotateKeysConfigFile}"#;
      const RUN_BACKUP_CONFIG: &str = r#"${backupCfg.internal.runBackupConfigFile}"#;

      fn exit_code(status: ExitStatus) -> i32 {
          status
              .code()
              .or_else(|| status.signal().map(|signal| 128 + signal))
              .unwrap_or(127)
      }

      fn run_process<I, S>(program: &str, argv0: &str, args: I) -> i32
      where
          I: IntoIterator<Item = S>,
          S: AsRef<OsStr>,
      {
          let mut command = Command::new(program);
          command
              .arg0(argv0)
              .args(args)
              .env("HOME", BACKUP_HOME)
              .env("RESTIC_CACHE_DIR", BACKUP_CACHE)
              .env("PATH", WRAPPER_PATH)
              .stdout(Stdio::inherit())
              .stderr(Stdio::inherit());

          match command.status() {
              Ok(status) => exit_code(status),
              Err(err) => {
                  eprintln!("posix_spawn failed: {program}: {err}");
                  127
              }
          }
      }

      fn run_restic(args: &[OsString]) -> i32 {
          run_process(RESTIC, "restic", args.iter().skip(1))
      }

      fn run_i4_backup_command(command: &str, config_file: &str) -> i32 {
          run_process(BACKUP_PROGRAM, "i4-backup", [command, config_file])
      }

      fn main() {
          let args: Vec<OsString> = env::args_os().collect();
          let is_restic = args
              .first()
              .and_then(|argv0| Path::new(argv0.as_os_str()).file_name())
              .is_some_and(|name| name == OsStr::new(RESTIC_EXECUTABLE_NAME));

          if is_restic {
              std::process::exit(run_restic(&args));
          }

          for (command, config_file) in [
              ("init-repos", INIT_REPOS_CONFIG),
              ("rotate-keys", ROTATE_KEYS_CONFIG),
              ("run-backup", RUN_BACKUP_CONFIG),
          ] {
              let status = run_i4_backup_command(command, config_file);
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
      ProgramArguments = lib.mkForce ["${binDir}/${backupExecutableName}"];
      EnvironmentVariables.PATH = lib.mkForce wrapperPath;
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
        created_wrapper=0

        run_as_backup_user() {
          if [ "$(/usr/bin/id -un)" = ${lib.escapeShellArg backupUser} ]; then
            "$@"
          else
            /usr/bin/sudo -u ${lib.escapeShellArg backupUser} "$@"
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

        has_full_disk_access=0
        full_disk_access_report=""
        if full_disk_access_report="$(HOME=${lib.escapeShellArg backupHome} /bin/bash ${lib.escapeShellArg checkFullDiskAccess} "$app" 2>&1)"; then
          has_full_disk_access=1
        fi

        has_local_network=0
        local_network_access_report=""
        if local_network_access_report="$(HOME=${lib.escapeShellArg backupHome} /bin/bash ${lib.escapeShellArg checkLocalNetworkAccess} "$app" 2>&1)"; then
          has_local_network=1
        fi

        if [ "$created_wrapper" -eq 1 ] || [ "$has_full_disk_access" -ne 1 ] || [ "$has_local_network" -ne 1 ]; then
          echo "warning: ${appName}.app backup wrapper may need macOS privacy permissions:" >&2
          if [ "$created_wrapper" -eq 1 ]; then
            echo "  - wrapper was created or recreated at $app" >&2
          fi
          if [ "$has_full_disk_access" -ne 1 ]; then
            echo "  - Full Disk Access is not granted or no longer valid for ${appName}.app (${bundleIdentifier})" >&2
            if [ -n "$full_disk_access_report" ]; then
              printf '%s\n' "$full_disk_access_report" | /usr/bin/sed 's/^/      /' >&2
            fi
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
