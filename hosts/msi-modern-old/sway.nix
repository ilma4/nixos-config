{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  isNixos = !config.targets.genericLinux.enable;
  swaylock =
    if isNixos
    then "${pkgs.swaylock}/bin/swaylock}"
    else "/usr/bin/swaylock";
  swaymsg = "${pkgs.sway}/bin/swaymsg";
  waybar = "${pkgs.waybar}/bin/waybar";
  nm-applet = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
  modifier = config.wayland.windowManager.sway.config.modifier;
  pamixer = "${pkgs.pamixer}/bin/pamixer";
  grim = "${pkgs.grim}/bin/grim";
  wl-copy = "${pkgs.wl-clipboard}/bin/wl-copy";
  wl-paste = "${pkgs.wl-clipboard}/bin/wl-paste";
  playerctl = "${pkgs.playerctl}/bin/playerctl";
  slurp = "${pkgs.slurp}/bin/slurp";
  swayosd = "${pkgs.swayosd}/bin/swayosd-client";
  termWithName = "${pkgs.foot}/bin/foot --app-id";
  tofi = "${pkgs.tofi}/bin/tofi";
  tofi-flags = "--width 800 --height 700  --font ${pkgs.jetbrains-mono}/share/fonts/TTF/JetBrainsMono-Light.ttf";
  foot = "${pkgs.foot}/bin/foot";
  sway-audio-idle-inhibit = "${pkgs.sway-audio-idle-inhibit}/bin/sway-audio-idle-inhibit";

  toggle-vpn =
    pkgs.writers.writePython3Bin "toggle-vpn" {}
    /*
    python3
    */
    ''
      import subprocess as sp
      import sys

      if len(sys.argv) < 2:
          sys.exit(1)
      vpn = sys.argv[1]
      active = sp.check_output(["nmcli", "-f", "name", "con", "show", "--active"])
      # print(active.decode("utf-8"))
      active = list(map(lambda x: x.strip(), active.decode("utf-8").split("\n")))
      # print(active)
      if vpn not in active:
          sp.run(["nmcli", "connection", "up", "id", vpn])
      else:
          sp.run(["nmcli", "connection", "down", "id", vpn])
      sys.exit(0)
    '';
in {
  home.packages = [
    pkgs.wl-clipboard
    pkgs.grim
    pkgs.swayosd
    pkgs.pavucontrol
    toggle-vpn
  ];

  top-commands = {
    tofi-command = "${tofi} ${tofi-flags}";
    commands = lib.mkOptionDefault {
      lock_screen = "${swaylock} -f -c 000000";
      wg = "${toggle-vpn}/bin/toggle-vpn wg";
      jetbrainsVpn = "${toggle-vpn}/bin/toggle-vpn JetBrainsVPN";
    };
  };

  programs.tofi.enable = isNixos;
  programs.foot.enable = isNixos;

  wayland.windowManager.sway.systemd.xdgAutostart = true;

  services.swayidle = {
    enable = true;
    timeouts = [
      {
        timeout = 300;
        command = "${swaylock} -f -c 000000";
      }
      {
        timeout = 600;
        command = "${swaymsg} \"output * power off\";  systemctl suspend";
        resumeCommand = "${swaymsg} \"output * power on\"";
      }
    ];
    events = [
      {
        event = "before-sleep";
        command = "${swaylock} -f -c 000000";
      }
    ];
  };

  services.kdeconnect = {
    enable = true;
    indicator = true;
  };

  services.mako = {
    enable = true;
    settings.default-timeout = 5000;
  };

  services.swayosd.enable = true;

  wayland.windowManager.sway.enable = true;
  # wayland.windowManager.sway.package = pkgs.sway;

  wayland.windowManager.sway.config = {
    modifier = "Mod4";
    focus.wrapping = "yes";
    bars = [{command = waybar;}];
    window.titlebar = false;
    terminal = foot;
    startup = [
      {command = nm-applet;}
      {command = sway-audio-idle-inhibit;}
    ];

    output = {
      "*" = {
        bg = "${pkgs.sway}/share/backgrounds/sway/Sway_Wallpaper_Blue_2048x1536.png fill";
      };
      eDP-1 = {
        mode = "2880x1800@120.000hz";
        scale = "2.0";
        adaptive_sync = "on";
        position = "0 0";
      };
      "Dell Inc. DELL U2720Q 23TXZ83" = {
        # monitor in JetBrains office
        scale = "2.0";
        adaptive_sync = "on";
        position = "0 -1080";
      };
    };

    input = {
      "type:touchpad" = {
        accel_profile = "adaptive";
        tap = "enabled";
        natural_scroll = "enabled";
      };

      "type:keyboard" = {
        xkb_layout = "us,ru";
        xkb_options = "grp:alt_space_toggle,caps:escape,compose:ralt";
      };
    };

    # TODO: get rid of `env` hack
    menu = "env PATH=\"/home/ilma4/.nix-profile/bin:$PATH\" ${tofi}-drun --drun-launch=true ${tofi-flags}";
  };

  wayland.windowManager.sway.config.window.commands = [
    {
      command = "inhibit_idle fullscreen";
      criteria = {
        class = "^.*";
        app_id = "^.*";
      };
    }
    {
      command = "opacity 0.8, floating enable, sticky enable, resize set 40 ppt 70 ppt, border pixel 10";
      criteria.app_id = "floating-term";
    }
  ];
  wayland.windowManager.sway.extraConfig = ''
    bindsym --inhibited Mod1+c exec ${wl-copy}
    bindsym --inhibited Mod1+v exec ${wl-paste}
  '';

  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    # "Mod1+c --inhibited" = "exec ${wl-copy}";
    # "Mod1+v --inhibited" = "exec ${wl-paste}";
    "Mod1+Return" = "exec ${foot}";

    "${modifier}+T" = "exec ${termWithName} floating-term";
    "${modifier}+Space" = "exec ${tofi}-drun --drun-launch=true ${tofi-flags}";

    "print" = "exec ${grim} - | ${wl-copy}";
    "Shift+print" = "exec ${grim} -g \"\$(${slurp})\" - | ${wl-copy}";

    "XF86AudioRaiseVolume" = "exec ${swayosd} --output-volume +1";
    "XF86AudioLowerVolume" = "exec ${swayosd} --output-volume -1";
    "XF86AudioMute" = "exec ${swayosd} --output-volume mute-toggle";
    "XF86AudioMicMute" = "exec ${swayosd} --input-volume mute-toggle";

    "XF86MonBrightnessDown" = "exec ${swayosd} --brightness -5";
    "XF86MonBrightnessUp" = "exec ${swayosd} --brightness +5";

    "XF86AudioPause" = "exec ${playerctl} play-pause";
    "XF86AudioPlay" = "exec ${playerctl} play-pause";
    "XF86AudioPrev" = "exec ${playerctl} previous";
    "XF86AudioNext" = "exec ${playerctl} next";

    "Ctrl+${modifier}+h" = "move workspace to output left";
    "Ctrl+${modifier}+l" = "move workspace to output right";
    "Ctrl+${modifier}+j" = "move workspace to output down";
    "Ctrl+${modifier}+k" = "move workspace to output up";
  };

  xdg.desktopEntries."sway" = {
    name = "Sway (Home Manager)";
    comment = "Sway tiling Wayland compositor managed by Nix Home-Manager";
    exec = "sway-session-wrapper"; # We will create this wrapper script next
    type = "Application";
  };

  # Create a wrapper script that contains the critical exec command.
  # This is cleaner than putting a long, complex command directly in the.desktop file.
  home.file.".local/bin/sway-session-wrapper" = {
    executable = true;
    text = ''
      #!/bin/sh
      # This is the magic command that makes everything work.
      exec ${pkgs.dbus}/bin/dbus-run-session -- bash -l -c "exec sway"
    '';
  };

  #home.sessionVariables.NIXOS_OZONE_WL = "1"; # forces electron apps use wayland
  #home.sessionVariables.QT_QPA_PLATFORMTHEME = "gnome"; # QT apps follows gtk theme
}
