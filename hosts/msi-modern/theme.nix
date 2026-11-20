{
  config,
  constants,
  lib,
  pkgs,
  ...
}: let
  gsettings = "${pkgs.glib.bin}/bin/gsettings";
  schemaDir = constants.gsettings-desktop-schema-data-dir pkgs.gsettings-desktop-schemas;
  schema = "org.gnome.desktop.interface";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  modifier = config.wayland.windowManager.sway.config.modifier;
  darkman = lib.getExe config.services.darkman.package;

  initializeMode = pkgs.writeShellScript "darkman-initialize-mode" ''
    set -euo pipefail
    mode="$(${darkman} get)"
    if [[ "$mode" == null ]]; then
      ${darkman} set light
    fi
  '';

  footLauncher = pkgs.writeShellScript "foot-themed" ''
    set -euo pipefail
    # Foot's spawn-terminal action resolves `foot` on PATH.
    export PATH="''${0%/*}:$PATH"
    mode="$(${darkman} get 2>/dev/null)" || mode=
    case "$mode" in
      light|dark) set -- -o "main.initial-color-theme=$mode" "$@" ;;
    esac
    exec ${lib.getExe pkgs.foot} "$@"
  '';
in {
  programs.foot.package = pkgs.symlinkJoin {
    pname = "foot-themed";
    inherit (pkgs.foot) version meta;
    paths = [pkgs.foot];
    postBuild = ''
      set -euo pipefail
      ln -sf ${footLauncher} "$out/bin/foot"

      # The upstream socket-activated service uses an absolute executable path.
      unit=share/systemd/user/foot-server.service
      rm "$out/$unit"
      substitute "${pkgs.foot}/$unit" "$out/$unit" \
        --replace-fail 'ExecStart=${lib.getExe pkgs.foot} --server=3' "ExecStart=$out/bin/foot --server=3"
    '';
  };
  programs.foot.settings.colors-light = {
    background = "faf9f8";
    foreground = "242424";
    regular0 = "242424";
    regular1 = "a31515";
    regular2 = "136b36";
    regular3 = "805900";
    regular4 = "0054a6";
    regular5 = "852482";
    regular6 = "006168";
    # Keep ANSI white light for uses like white-on-red ls setuid entries.
    regular7 = "e6e6e6";
    bright0 = "666666";
    bright1 = "b82030";
    bright2 = "287938";
    bright3 = "906400";
    bright4 = "0969b1";
    bright5 = "9e3799";
    bright6 = "007580";
    bright7 = "ffffff";
    jump-labels = "ffffff 805900";
    search-box-match = "ffffff 805900";
    search-box-no-match = "ffffff a31515";
    scrollback-indicator = "ffffff 0969b1";

    # Powerlevel10k uses these indexed colors on a transparent background.
    "31" = "006483";
    "39" = "0050a0";
    "70" = "386900";
    "74" = "236989";
    "76" = "2e7000";
    "101" = "656541";
    "103" = "58587c";
    "178" = "805900";
    "180" = "765431";
    "196" = "b00020";
    "220" = "986200";
  };

  services.darkman = {
    enable = true;
    settings = {
      # Keep the existing manual toggle; do not request location access.
      usegeoclue = false;
      portal = true;
    };
    scripts = {
      gtk = ''
        set -euo pipefail
        case "$1" in
          light) gtk=Adwaita ;;
          dark) gtk=Adwaita-dark ;;
          *) exit 0 ;;
        esac

        # GTK/Qt applications that do not use Darkman's Settings portal.
        export GSETTINGS_SCHEMA_DIR=${schemaDir}/glib-2.0/schemas
        ${gsettings} set ${schema} gtk-theme "$gtk"
        ${gsettings} set ${schema} color-scheme "prefer-$1"

        # XWayland GTK apps read the theme through XSettings instead.
        tmp="$(${lib.getExe' pkgs.coreutils "mktemp"} "$XDG_RUNTIME_DIR/msi-modern-xsettings.XXXXXXXX")"
        printf 'Net/ThemeName "%s"\n' "$gtk" > "$tmp"
        ${lib.getExe' pkgs.coreutils "mv"} -f -- "$tmp" "$XDG_RUNTIME_DIR/msi-modern-xsettings"
        ${systemctl} --user kill --kill-whom=main --signal=HUP xsettingsd.service 2>/dev/null || true
      '';
      foot = ''
        set -euo pipefail
        case "$1" in
          light) signal=USR2 ;;
          dark) signal=USR1 ;;
          *) exit 0 ;;
        esac
        # Native switches also notify terminal apps that subscribe to theme changes.
        ${lib.getExe' pkgs.procps "pkill"} --signal "$signal" --require-handler --euid "$EUID" --exact foot || [[ "$?" == 1 ]]
      '';
    };
  };
  systemd.user.services.darkman.Service.ExecStartPost = "${initializeMode}";

  # GTK 3 has an internal dark variant but no standalone Adwaita-dark theme.
  xdg.dataFile."themes/Adwaita-dark/gtk-3.0/gtk.css".text = ''
    @import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css");
  '';

  # The GTK3 integration gives Qt the actual GTK palette, not just a hint
  # about whether the desktop prefers dark mode.
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
  };

  # Mark these files without using a dark foreground on a colored background.
  programs.dircolors.settings = {
    BLK = "01;33";
    CAPABILITY = "04;31";
    CHR = "01;33";
    FIFO = "33";
    ORPHAN = "01;91";
    OTHER_WRITABLE = "04;34";
    SETGID = "04;33";
    STICKY_OTHER_WRITABLE = "04;32";
  };

  # The dark variant uses the existing Waybar style; Waybar listens for
  # color-scheme changes from the portal to pick its stylesheet.
  xdg.configFile."waybar/style-light.css".text = ''
    @import url("style.css");

    window#waybar,
    window#waybar.chromium,
    window#waybar.termite {
      background-color: rgba(246, 245, 244, 0.95);
      border-bottom-color: #c0bfbc;
      color: #241f31;
    }

    #workspaces button { color: #241f31; }
    #workspaces button.focused, #workspaces button.active { color: white; }
    #scratchpad { color: #241f31; }
  '';

  systemd.user.services.xsettingsd = {
    Unit = {
      Description = "Publish the desktop theme to XWayland apps";
      PartOf = ["sway-session.target"];
      After = ["darkman.service"];
      ConditionEnvironment = "DISPLAY";
    };
    Service = {
      ExecStartPre = "${lib.getExe' pkgs.coreutils "touch"} %t/msi-modern-xsettings";
      ExecStart = "${lib.getExe pkgs.xsettingsd} -c %t/msi-modern-xsettings";
    };
    Install.WantedBy = ["sway-session.target"];
  };

  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    "--no-repeat ${modifier}+Shift+t" = "exec ${darkman} toggle";
  };

  top-commands.commands = lib.mkOptionDefault {
    "Toggle light/dark theme" = "${darkman} toggle";
  };
}
