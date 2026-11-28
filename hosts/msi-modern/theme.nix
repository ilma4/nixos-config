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
  swaymsg = lib.getExe' pkgs.sway "swaymsg";
  # Darkman 2.2 can leave control.sock stale when a second instance replaces
  # it before failing to acquire the D-Bus name. Talk to the name owner instead.
  darkmanControl = pkgs.writeShellScript "darkman-control" ''
    set -euo pipefail
    name=nl.whynothugo.darkman
    bus=(${lib.getExe' pkgs.systemd "busctl"} --user --auto-start=no --timeout=2s call
         "$name" /nl/whynothugo/darkman org.freedesktop.DBus.Properties)

    get_mode() {
      local reply
      reply="$("''${bus[@]}" Get ss "$name" Mode)" || return
      case "$reply" in
        'v s "light"') echo light ;;
        'v s "dark"') echo dark ;;
        'v s "null"') echo null ;;
        *) printf 'Unexpected Darkman mode reply: %s\n' "$reply" >&2; return 1 ;;
      esac
    }

    set_mode() {
      "''${bus[@]}" Set ssv "$name" Mode s "$1"
    }

    case "$1" in
      get) get_mode ;;
      set) set_mode "$2" ;;
      toggle)
        mode="$(get_mode)"
        if [[ "$mode" == light ]]; then mode=dark; else mode=light; fi
        set_mode "$mode"
        echo "$mode"
        ;;
    esac
  '';
  # GNOME's Adwaita pair is natively 4096x4096. Decode JPEG XL for swaybg.
  wallpapers = pkgs.runCommand "gnome-adwaita-wallpapers" {} ''
    set -euo pipefail
    mkdir -p "$out"
    src=${pkgs.gnome-backgrounds}/share/backgrounds/gnome
    for variant in l d; do
      ${lib.getExe' (lib.getBin pkgs.libjxl) "djxl"} \
        --color_space=RGB_D65_SRG_Rel_SRG --bits_per_sample=8 \
        "$src/adwaita-$variant.jxl" "$out/adwaita-$variant.png"
    done
  '';

  setWallpaper = pkgs.writeShellScript "sway-set-theme-wallpaper" ''
    set -euo pipefail
    [[ -S "''${SWAYSOCK:-}" ]] || exit 0
    mode="''${1:-}"
    if [[ -z "$mode" ]]; then
      # Don't activate Darkman before Sway imports the session environment.
      ${systemctl} --user is-active --quiet darkman.service || exit 0
      mode="$(${darkmanControl} get)"
    fi
    case "$mode" in
      light) image=${wallpapers}/adwaita-l.png ;;
      dark) image=${wallpapers}/adwaita-d.png ;;
      *) exit 0 ;;
    esac
    exec ${swaymsg} -q "output * bg \"$image\" fill"
  '';

  toggleTheme = pkgs.writeShellScriptBin "toggle-theme" ''
    set -euo pipefail
    exec ${lib.getExe pkgs.python3} ${./theme-refresh-workspaces.py} \
      ${swaymsg} ${darkmanControl}
  '';

  initializeMode = pkgs.writeShellScript "darkman-initialize-mode" ''
    set -euo pipefail
    mode="$(${darkmanControl} get)"
    if [[ "$mode" == null ]]; then
      ${darkmanControl} set light
    else
      # Sway may have started before Darkman was ready to report its mode.
      ${setWallpaper} "$mode" || true
    fi
  '';

  footLauncher = pkgs.writeShellScript "foot-themed" ''
    set -euo pipefail
    # Foot's spawn-terminal action resolves `foot` on PATH.
    export PATH="''${0%/*}:$PATH"
    mode="$(${darkmanControl} get 2>/dev/null)" || mode=
    case "$mode" in
      light|dark) set -- -o "main.initial-color-theme=$mode" "$@" ;;
    esac
    exec ${lib.getExe pkgs.foot} "$@"
  '';
in {
  home.packages = [toggleTheme];

  # Replace the upstream launcher, which still calls the socket-based CLI.
  xdg.desktopEntries.darkman = {
    name = "Toggle darkman";
    genericName = "Toggle dark mode";
    exec = "${lib.getExe toggleTheme}";
    categories = ["Settings"];
    settings.Keywords = "dark;light;colour-preference;theme;";
  };

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
    # Base16 Google Light (Seth Wright), using the tinted-foot mapping.
    background = "ffffff";
    foreground = "373b41";
    regular0 = "ffffff";
    regular1 = "cc342b";
    regular2 = "198844";
    regular3 = "fba922";
    regular4 = "3971ed";
    regular5 = "a36ac7";
    regular6 = "4f87cf"; # Lighter ANSI cyan for symlinks in light mode.
    regular7 = "373b41";
    bright0 = "c5c8c6";
    bright1 = "cc342b";
    bright2 = "198844";
    bright3 = "fba922";
    bright4 = "3971ed";
    bright5 = "a36ac7";
    bright6 = "3971ed";
    bright7 = "1d1f21";
    "16" = "f96a38";
    "17" = "3971ed";
    "18" = "e0e0e0";
    "19" = "c5c8c6";
    "20" = "969896";
    "21" = "282a2e";

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
      wallpaper = setWallpaper;
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

  wayland.windowManager.sway = {
    config.output."*".bg = "${wallpapers}/adwaita-l.png fill";
    config.keybindings = lib.mkOptionDefault {
      "--no-repeat ${modifier}+Shift+t" = "exec ${lib.getExe toggleTheme}";
    };
    # Sway reloads its configured light fallback; restore the current mode.
    extraConfig = ''
      exec_always ${setWallpaper}
    '';
  };

  top-commands.commands = lib.mkOptionDefault {
    "Toggle light/dark theme" = lib.getExe toggleTheme;
  };
}
