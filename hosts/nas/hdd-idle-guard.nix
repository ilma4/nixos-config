{pkgs, ...}: let
  script = pkgs.writeShellScript "hdd-idle-guard.sh" ''
    set -euo pipefail

    DISK_A="/dev/disk/by-id/ata-ST4000DM004-2U9104_ZW62WG3D" # Seagate
    DISK_B="/dev/disk/by-id/ata-WDC_WD40EFPX-68C6CN0_WD-WX42D44C18S3" # WD
    STATE_DIR="/run/hdd-idle-guard"
    STATE_A="$STATE_DIR/seagate.count"
    STATE_B="$STATE_DIR/wd.count"

    mkdir -p "$STATE_DIR"

    get_state() {
      local disk="$1"
      local output

      if ! output="$(${pkgs.hdparm}/bin/hdparm -C "$disk" 2>&1)"; then
        log_warn "Unable to read power state for $disk: $output"
        return 1
      fi

      case "$output" in
        *"active/idle"*)
          echo active
          ;;
        *"standby"*|*"sleeping"*)
          echo standby
          ;;
        *)
          log_warn "Unknown power state for $disk: $output"
          return 1
          ;;
      esac
    }

    log_warn() {
      echo "$1" | ${pkgs.systemd}/bin/systemd-cat -t hdd-idle-guard -p warning
    }

    if ! state_a=$(get_state "$DISK_A"); then
      exit 0
    fi
    if ! state_b=$(get_state "$DISK_B"); then
      exit 0
    fi

    count_a=$(cat "$STATE_A" 2>/dev/null || echo 0)
    count_b=$(cat "$STATE_B" 2>/dev/null || echo 0)

    # Reset counters by default
    new_a=0
    new_b=0

    if [ "$state_a" = "active" ] && [ "$state_b" = "standby" ]; then
      new_a=$((count_a + 1))
    elif [ "$state_b" = "active" ] && [ "$state_a" = "standby" ]; then
      new_b=$((count_b + 1))
    fi

    echo "$new_a" > "$STATE_A"
    echo "$new_b" > "$STATE_B"

    if [ "$new_a" -ge 5 ]; then
      log_warn "Disk $DISK_A active alone for 5 minutes, forcing standby"
      ${pkgs.hdparm}/bin/hdparm -y "$DISK_A" >/dev/null
      echo 0 > "$STATE_A"
    fi

    if [ "$new_b" -ge 5 ]; then
      log_warn "Disk $DISK_B active alone for 5 minutes, forcing standby"
      ${pkgs.hdparm}/bin/hdparm -y "$DISK_B" >/dev/null
      echo 0 > "$STATE_B"
    fi
  '';
in {
  environment.systemPackages = [pkgs.hdparm];

  systemd.services.hdd-idle-guard = {
    description = "Spin down lone active HDD after prolonged idle imbalance";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = script;
    };
  };

  systemd.timers.hdd-idle-guard = {
    description = "Run HDD idle guard every minute";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      AccuracySec = "10s";
    };
  };
}
