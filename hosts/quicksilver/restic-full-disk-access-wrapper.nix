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
  wrapperVersion = "2";
  wrapperPath = "${binDir}:${backupHome}/.nix-profile/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";

  backupCfg = config.i4.backup;
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
        created_wrapper=0

        current_version=""
        if [ -f "$version_file" ]; then
          current_version="$(/bin/cat "$version_file")"
        fi

        if [ -x "$backup_exe" ] \
          && [ -x "$restic_exe" ] \
          && [ -f "$app/Contents/Info.plist" ] \
          && [ "$current_version" = ${lib.escapeShellArg wrapperVersion} ]; then
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

          cat > "$bin_dir/${backupExecutableName}.c" <<'EOF'
    #include <errno.h>
    #include <libgen.h>
    #include <spawn.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <sys/wait.h>
    #include <unistd.h>

    extern char **environ;

    static int run_process(const char *program, char *const argv[]) {
        pid_t pid;
        int spawn_error = posix_spawn(&pid, program, NULL, NULL, argv, environ);
        if (spawn_error != 0) {
            fprintf(stderr, "posix_spawn failed: %s: %s\n", program, strerror(spawn_error));
            return 127;
        }

        int status;
        while (waitpid(pid, &status, 0) < 0) {
            if (errno != EINTR) {
                fprintf(stderr, "waitpid failed: %s\n", strerror(errno));
                return 127;
            }
        }

        if (WIFEXITED(status)) {
            return WEXITSTATUS(status);
        }
        if (WIFSIGNALED(status)) {
            return 128 + WTERMSIG(status);
        }

        return 127;
    }

    static int run_restic(int argc, char **argv) {
        const char *restic = "/run/current-system/sw/bin/restic";

        char **args = calloc((size_t)argc + 1, sizeof(char *));
        if (!args) {
            perror("calloc");
            return 127;
        }

        args[0] = "restic";
        for (int i = 1; i < argc; i++) {
            args[i] = argv[i];
        }
        args[argc] = NULL;

        int status = run_process(restic, args);
        free(args);
        return status;
    }

    static int run_i4_backup_command(const char *command, const char *config_file) {
        const char *program = "${backupCfg.internal.backupProgram}";
        char *const args[] = {
            "i4-backup",
            (char *)command,
            (char *)config_file,
            NULL,
        };

        return run_process(program, args);
    }

    int main(int argc, char **argv) {
        setenv("HOME", "${backupHome}", 1);
        setenv("RESTIC_CACHE_DIR", "${backupCache}", 1);
        setenv("PATH", "${wrapperPath}", 1);

        char *argv0 = strdup(argv[0]);
        if (!argv0) {
            perror("strdup");
            return 127;
        }

        char *name = basename(argv0);
        int is_restic = strcmp(name, "${resticExecutableName}") == 0;
        free(argv0);

        if (is_restic) {
            return run_restic(argc, argv);
        }

        int status = run_i4_backup_command("init-repos", "${backupCfg.internal.initReposConfigFile}");
        if (status != 0) {
            return status;
        }

        status = run_i4_backup_command("rotate-keys", "${backupCfg.internal.rotateKeysConfigFile}");
        if (status != 0) {
            return status;
        }

        return run_i4_backup_command("run-backup", "${backupCfg.internal.runBackupConfigFile}");
    }
    EOF

          /usr/bin/cc -O2 -o "$backup_exe" "$bin_dir/${backupExecutableName}.c"
          /bin/cp "$backup_exe" "$restic_exe"
          /bin/rm "$bin_dir/${backupExecutableName}.c"
          /bin/chmod 0755 "$backup_exe" "$restic_exe"
          printf '%s\n' ${lib.escapeShellArg wrapperVersion} > "$version_file"

          /usr/bin/codesign --force --deep --sign - "$app"
          /usr/bin/xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
          /usr/sbin/chown -R ${lib.escapeShellArg "${backupUser}:${backupGroup}"} "$app"
          created_wrapper=1
        fi

        has_full_disk_access=0
        if [ -r "/Library/Application Support/com.apple.TCC/TCC.db" ] \
          && [ "$(/usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "select count(*) from access where service = 'kTCCServiceSystemPolicyAllFiles' and client = '${bundleIdentifier}' and client_type = 0 and auth_value = 2;" 2>/dev/null || echo 0)" = 1 ]; then
          has_full_disk_access=1
        fi

        has_local_network=0
        if /usr/bin/python3 - ${lib.escapeShellArg bundleIdentifier} "$backup_exe" <<'PY'
    import plistlib
    import sys
    from pathlib import Path

    bundle_identifier = sys.argv[1]
    executable_path = sys.argv[2]
    plist_path = Path("/Library/Preferences/com.apple.networkextension.plist")

    if not plist_path.exists():
        sys.exit(1)

    try:
        plist = plistlib.loads(plist_path.read_bytes())
    except Exception:
        sys.exit(1)

    objects = plist.get("$objects")
    if not isinstance(objects, list):
        sys.exit(1)


    def resolve(value):
        if isinstance(value, plistlib.UID):
            try:
                return objects[value.data]
            except Exception:
                return None
        return value

    for item in objects:
        if not isinstance(item, dict):
            continue
        if resolve(item.get("SigningIdentifier")) != bundle_identifier:
            continue
        if resolve(item.get("Path")) != executable_path:
            continue
        if item.get("MulticastPreferenceSet") is True and item.get("DenyMulticast") is False:
            sys.exit(0)

    sys.exit(1)
    PY
        then
          has_local_network=1
        fi

        if [ "$created_wrapper" -eq 1 ] || [ "$has_full_disk_access" -ne 1 ] || [ "$has_local_network" -ne 1 ]; then
          echo "warning: ${appName}.app backup wrapper may need macOS privacy permissions:" >&2
          if [ "$created_wrapper" -eq 1 ]; then
            echo "  - wrapper was created or recreated at $app" >&2
          fi
          if [ "$has_full_disk_access" -ne 1 ]; then
            echo "  - Full Disk Access is not granted to ${appName}.app (${bundleIdentifier})" >&2
          fi
          if [ "$has_local_network" -ne 1 ]; then
            echo "  - Local Network is not granted to ${appName}.app (${bundleIdentifier})" >&2
          fi
          echo "  Open System Settings -> Privacy & Security, then grant Full Disk Access and Local Network to:" >&2
          echo "    $app" >&2
        fi
  '';
}
