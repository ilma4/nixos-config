{
  config,
  lib,
  pkgs,
  ...
}: let
  user = "malakhov";
  userHome = config.users.users.${user}.home;
  jetbrainsMaintenance = pkgs.writeShellScriptBin "i4-jetbrains-maintenance" ''
    set -euo pipefail

    export HOME=${lib.escapeShellArg userHome}
    export PATH=${lib.escapeShellArg "${userHome}/.nix-profile/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"}

    jetbrains_dir="$HOME/JetBrains"

    if [[ ! -d "$jetbrains_dir" ]]; then
      echo "Skipping JetBrains maintenance: $jetbrains_dir does not exist"
      exit 0
    fi

    printf '\n[%s] Cleaning JetBrains caches\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')"
    "$jetbrains_dir/clean-caches.sh"

    printf '\n[%s] Deduplicating %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$jetbrains_dir"
    ${lib.getExe pkgs.jdupes} \
      --dedupe \
      --one-file-system \
      --permissions \
      --recurse \
      "$jetbrains_dir"

    printf '\n[%s] Done deduplicating %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$jetbrains_dir"

    git_status_failed=0
    for directory in "$jetbrains_dir"/*; do
      [[ -d "$directory" ]] || continue

      printf '\n[%s] git status: %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$directory"
      if ! ${lib.getExe pkgs.git} -C "$directory" status; then
        git_status_failed=1
      fi
    done

    printf '\n[%s] Git caches warmed %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$jetbrains_dir"

    exit "$git_status_failed"
  '';
in {
  home-manager.users.${user}.home.packages = [jetbrainsMaintenance];

  # A system daemon remains loaded when malakhov has no GUI login session.
  launchd.daemons.jetbrains-maintenance = {
    command = lib.getExe jetbrainsMaintenance;
    serviceConfig = {
      UserName = user;
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 0;
        }
      ];
      StandardOutPath = "/tmp/jetbrains-maintenance-malakhov.log";
      StandardErrorPath = "/tmp/jetbrains-maintenance-malakhov.err.log";
    };
  };
}
