{
  config,
  lib,
  pkgs,
  ...
}: let
  swaylock = "${pkgs.swaylock}/bin/swaylock";
  swaymsg = "${pkgs.sway}/bin/swaymsg";
  waybar = "${pkgs.waybar}/bin/waybar";
  nm-applet = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
  modifier = config.wayland.windowManager.sway.config.modifier;
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

  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    set -euo pipefail
    region="$(${slurp})" || exit 0
    [[ -n "$region" ]] || exit 0
    ${grim} -g "$region" - | ${wl-copy} --type image/png
  '';
  screenshotCommand = "${screenshot}/bin/screenshot";
  hdmi = pkgs.writeShellScriptBin "hdmi" ''
    set -euo pipefail
    exec ${pkgs.monitor-input}/bin/monitor-input U2725QE=DP1
  '';
  hdmiCommand = "${hdmi}/bin/hdmi";
in {
  home.packages = [
    pkgs.wl-clipboard
    pkgs.grim
    pkgs.swayosd
    pkgs.pavucontrol
    pkgs.adwaita-icon-theme # Provides Pavucontrol's audio-device icons.
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.font-awesome_5
    screenshot
    (pkgs.makeDesktopItem {
      name = "screenshot";
      desktopName = "Screenshot";
      exec = screenshotCommand;
      icon = "applets-screenshooter";
    })
    hdmi
    (pkgs.makeDesktopItem {
      name = "hdmi";
      desktopName = "hdmi";
      comment = "Switch the Dell monitor from USB-C to DisplayPort";
      exec = hdmiCommand;
      icon = "video-display";
    })
  ];

  # Pavucontrol still asks for emblem-default; use Adwaita's monochrome checkmark.
  xdg.dataFile."icons/hicolor/scalable/actions/emblem-default-symbolic.svg".source =
    "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/object-select-symbolic.svg";

  xdg.configFile."waybar/style.css".text = ''
    @import url("${pkgs.waybar}/etc/xdg/waybar/style.css");

    * {
      /* The stock config uses both Nerd Fonts and Font Awesome 5 glyphs. */
      font-family: Roboto, Helvetica, Arial, "JetBrainsMono Nerd Font", "Font Awesome 5 Free Solid", sans-serif;
    }
  '';

  top-commands = {
    tofi-command = "${tofi} ${tofi-flags}";
    commands = lib.mkOptionDefault {
      Screenshot = screenshotCommand;
      hdmi = hdmiCommand;
      lock_screen = "${swaylock} -f -c 000000";
    };
  };

  programs.tofi.enable = true;
  fonts.fontconfig.enable = true;
  programs.foot = {
    enable = true;
    settings.main.font = "JetBrainsMono Nerd Font Mono:size=11";
  };

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
    events = {
      before-sleep = "${swaylock} -f -c 000000";
    };
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

  # The Dell can report both HDMI and DisplayPort at once. Kanshi needs a
  # profile that accounts for every connected output, even disabled ones.
  services.kanshi = let
    dell = "Dell Inc. DELL U2725QE 7WH9B34";
  in {
    enable = true;
    settings =
      map (dock: {
        profile = {
          name = dock.name;
          outputs = [
            {
              criteria = dock.criteria;
              status = "enable";
              mode = "3840x2160@120Hz";
              scale = 2.0;
              adaptiveSync = true;
              position = "0,0";
            }
            {
              criteria = "eDP-1";
              status = "disable";
            }
          ] ++ dock.extraOutputs;
        };
      }) [
        {
          name = "dell-u2725qe-dual-input";
          criteria = "DP-1";
          extraOutputs = [
            {
              criteria = dell;
              status = "disable";
            }
          ];
        }
        {
          name = "dell-u2725qe";
          criteria = "DP-1";
          extraOutputs = [];
        }
      ]
      ++ [
        {
          profile = {
            name = "internal-with-dell-hdmi";
            outputs = [
              {
                criteria = "eDP-1";
                status = "enable";
                scale = 1.0;
                position = "0,0";
              }
              {
                criteria = dell;
                status = "disable";
              }
            ];
          };
        }
        {
          profile = {
            name = "internal";
            outputs = [
              {
                criteria = "eDP-1";
                status = "enable";
                mode = "1920x1080@60Hz";
                scale = 1.0;
                position = "0,0";
              }
            ];
          };
        }
      ];
  };

  wayland.windowManager.sway.enable = true;

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
        scale = "1.0";
        adaptive_sync = "on";
        position = "0 0";
      };
      "Dell Inc. DELL U2725QE 7WH9B34" = {
        render_bit_depth = "10";
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

      "13364:2616:Keychron_Keychron_K3_Max".xkb_options =
        "grp:alt_space_toggle,caps:escape,altwin:swap_alt_win";
      "13364:2616:Keychron_Keychron_K3_Max_Keyboard".xkb_options =
        "grp:alt_space_toggle,caps:escape,altwin:swap_alt_win";
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
    # Reloading Sway resets the outputs even when the Kanshi profile hasn't changed.
    exec_always ${pkgs.systemd}/bin/systemctl --user try-restart kanshi.service
    bindsym --inhibited Mod1+c exec ${wl-copy}
    bindsym --inhibited Mod1+v exec ${wl-paste}
  '';

  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
    "Mod1+Return" = "exec ${foot}";

    "${modifier}+T" = "exec ${termWithName} floating-term";
    "${modifier}+space" = "exec ${tofi}-drun --drun-launch=true ${tofi-flags}";

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
}
