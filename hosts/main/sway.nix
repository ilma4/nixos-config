{ config, lib, pkgs, inputs, ... }:

{
  home.packages = with pkgs ; [
    wl-clipboard
    grim
    brightnessctl
    pavucontrol
  ];

  programs.waybar = {
    enable = true;
  };

  programs.tofi.enable = true;

  services.swayidle = let 
    swaylock = "/usr/bin/swaylock" ; # swaylock from nixpkgs doesn't work on Ubuntu 
    swaymsg = "${pkgs.sway}/bin/swaymsg" ;
  in {
    enable = true;
    timeouts = [
      { timeout = 300; command = "${swaylock} -f -c 000000"; }
      { 
        timeout = 600; 
        command = "${swaymsg} \"output * power off\";  systemctl suspend-then-hibernate"; 
        resumeCommand = "${swaymsg} \"output * power on\"";
      }
    ];
    events = [
      { event = "before-sleep"; command = "${swaylock} -f -c 000000"; }
    ];
  };

  services.kdeconnect = {
    enable = true;
    indicator = true;
  };

  services.mako = {
    enable = true;
    defaultTimeout = 5000;
  };
  
  services.wob.enable = true;


  wayland.windowManager.sway.enable = true;


  wayland.windowManager.sway.config = {
    modifier = "Mod4";
    focus.wrapping = "yes";
    bars = [ { command = "${pkgs.waybar}/bin/waybar"; } ];
    window.titlebar = false;
    startup = [
      { command = "nm-applet --indicator"; }
    ];

    output = {
      "*" = {
        bg = "${pkgs.sway}/share/backgrounds/sway/Sway_Wallpaper_Blue_2048x1536.png fill";
      };
      eDP-1 = {
        mode = "2880x1800@120.000hz";
        scale = "2.0";
        adaptive_sync = "on";
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
        xkb_options = "grp:win_space_toggle,caps:escape,compose:ralt";
      };
    };

    menu = "${pkgs.tofi}/bin/tofi-drun --drun-launch=true --width 800 --height 700  --font ${pkgs.jetbrains-mono}/share/fonts/TTF/JetBrainsMono-Light.ttf";
  };

  wayland.windowManager.sway.config.window.commands = [
    {
      command = "inhibit_idle fullscreen";
      criteria = {
        class = "^.*";
        app_id = "^.*";
      };
    }
  ];


  wayland.windowManager.sway.config.keybindings = let
      modifier = config.wayland.windowManager.sway.config.modifier;
      pamixer = "${pkgs.pamixer}/bin/pamixer";
      grim = "${pkgs.grim}/bin/grim";
      wl-copy = "${pkgs.wl-clipboard}/bin/wl-copy";
      brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
      playerctl = "${pkgs.playerctl}/bin/playerctl";
      slurp = "${pkgs.slurp}/bin/slurp";
    in lib.mkOptionDefault {
      "print" = "exec ${grim} - | ${wl-copy}";
      "Shift+print" = "exec ${grim} -g \"\$(${slurp})\" - | ${wl-copy}";

      "XF86AudioRaiseVolume" = "exec ${pamixer} -ui 1"; # TODO: wob integration
      "XF86AudioLowerVolume" = "exec ${pamixer} -ud 1"; # TODO: wob integration
      "XF86AudioMute" = "exec ${pamixer} --toggle-mute"; # && ( pamixer --get-mute && echo 0 > $WOBSOCK ) || pamixer --get-volume > $WOBSOCK
      "XF86AudioMicMute" = "exec pactl set-source-mute @DEFAULT_SOURCE@ toggle";


      "XF86MonBrightnessDown" = "exec ${brightnessctl} set 5%-"; # | sed -En 's/.*\(([0-9]+)%\).*/\1/p' > $WOBSOCK
      "XF86MonBrightnessUp" = "exec ${brightnessctl} set +5%"; # | sed -En 's/.*\(([0-9]+)%\).*/\1/p' > $WOBSOCK

      "XF86AudioPause" = "exec ${playerctl} play-pause";
      "XF86AudioPlay" = "exec ${playerctl} play-pause";
      "XF86AudioPrev" = "exec ${playerctl} previous";
      "XF86AudioNext" = "exec ${playerctl} next";
    };

    home.sessionVariables.NIXOS_OZONE_WL = "1"; # forces electron apps use wayland
    home.sessionVariables.QT_QPA_PLATFORMTHEME = "gnome";
}
