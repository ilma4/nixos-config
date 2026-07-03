# Disable wifi while any wired interface is connected and re-enable it
# once all of them are disconnected. Implemented as a NetworkManager
# dispatcher hook, so it also handles hotplugged usb-ethernet adapters.
{pkgs, ...}: {
  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = pkgs.writeShellScript "disable-wifi-when-ethernet-connected" ''
        set -euo pipefail

        nmcli=${pkgs.networkmanager}/bin/nmcli

        # $2 is the event type; only interface state changes are relevant
        case "''${2:-}" in
          up | down) ;;
          *) exit 0 ;;
        esac

        if "$nmcli" -t -f TYPE,STATE device status | ${pkgs.gnugrep}/bin/grep -qx 'ethernet:connected'; then
          "$nmcli" radio wifi off
        else
          "$nmcli" radio wifi on
        fi
      '';
    }
  ];
}
