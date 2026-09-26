# Disconnect wifi while any wired interface is connected and re-enable
# autoconnect once all of them are disconnected. Implemented as a
# NetworkManager dispatcher hook, so it also handles hotplugged
# usb-ethernet adapters. Deliberately avoids `nmcli radio wifi off`:
# the rfkill soft-block it performs sends the MSI EC into an ACPI GPE
# notify storm (~7 events/s), which among other things keeps resetting
# the console blanking timer.
{pkgs, ...}: {
  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = pkgs.writeShellScript "disable-wifi-when-ethernet-connected" ''
        set -euo pipefail

        nmcli=${pkgs.networkmanager}/bin/nmcli
        awk=${pkgs.gawk}/bin/awk
        state_dir=/run/disable-wifi-when-ethernet-connected

        # $2 is the event type; only interface state changes are relevant
        case "''${2:-}" in
          up | down) ;;
          *) exit 0 ;;
        esac

        if "$nmcli" -t -f TYPE,STATE device status | ${pkgs.gnugrep}/bin/grep -qx 'ethernet:connected'; then
          # Disconnecting also blocks autoconnect until it is re-armed below
          ${pkgs.coreutils}/bin/mkdir -p "$state_dir"
          "$nmcli" -t -f DEVICE,TYPE,STATE device status \
            | "$awk" -F: '$2 == "wifi" && $3 ~ /^connect/ {print $1}' \
            | while IFS= read -r dev; do
              "$nmcli" device disconnect "$dev"
              # Only restore autoconnect for devices disconnected by this hook.
              : > "$state_dir/$dev"
            done
        else
          "$nmcli" -t -f DEVICE,TYPE device status \
            | "$awk" -F: '$2 == "wifi" {print $1}' \
            | while IFS= read -r dev; do
              [[ -f "$state_dir/$dev" ]] || continue
              "$nmcli" device set "$dev" autoconnect yes
              ${pkgs.coreutils}/bin/rm "$state_dir/$dev"
            done
        fi
      '';
    }
  ];
}
