{ config, lib, pkgs, inputs, ... }:
let 
  isNixos = !config.targets.genericLinux.enable;
  swaylock = if isNixos then "${pkgs.swaylock}/bin/swaylock}" else "/usr/bin/swaylock"; 
  swaymsg = if isNixos then "${pkgs.sway}/bin/swaymsg" else "/usr/bin/swaymsg";
  waybar = if isNixos then "${pkgs.waybar}/bin/waybar" else "/usr/bin/waybar";
  nm-applet = if isNixos then "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator" else "/usr/bin/nm-applet --indicator";
  modifier = config.wayland.windowManager.sway.config.modifier;
  pamixer = "${pkgs.pamixer}/bin/pamixer";
  grim = "${pkgs.grim}/bin/grim";
  wl-copy = "${pkgs.wl-clipboard}/bin/wl-copy";
  playerctl = "${pkgs.playerctl}/bin/playerctl";
  slurp = "${pkgs.slurp}/bin/slurp";
  swayosd = "${pkgs.swayosd}/bin/swayosd-client";
  favCommands = { "a" = "e"; "b" = "test b"; } ;
  termWithName = if isNixos then "${pkgs.foot}/bin/foot --app-id" else "/usr/bin/foot --app-id";
  tofi = if isNixos then "${pkgs.tofi}/bin/tofi" else "/usr/bin/tofi";
  foot = if isNixos then "${pkgs.foot}/bin/foot" else "/usr/bin/foot";
in
{
  home.packages = [
    pkgs.wl-clipboard
    pkgs.grim
    pkgs.swayosd
    pkgs.pavucontrol
  ];

  #programs.waybar = {
  #  enable = true;
  #};

  #programs.tofi.enable = true;
  #programs.foot.enable = true;

  wayland.windowManager.sway.systemd.xdgAutostart = true;

  services.swayidle = {
    enable = true;
    #package = null;
    timeouts = [
      { timeout = 300; command = "${swaylock} -f -c 000000"; }
      { 
        timeout = 600; 
        command = "${swaymsg} \"output * power off\";  systemctl suspend"; 
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
  
  services.swayosd.enable = true;


  wayland.windowManager.sway.enable = true;
  wayland.windowManager.sway.package = null;

  wayland.windowManager.sway.config = {
    modifier = "Mod4";
    focus.wrapping = "yes";
    bars = [ { command = waybar; } ];
    window.titlebar = false;
    terminal = foot;
    startup = [
      { command = nm-applet; }
      # { command = "dbus-update-activation-environment --all"; }
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
      "Dell Inc. DELL U2720Q 23TXZ83" = { # monitor in JetBrains office
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
        xkb_options = "grp:win_space_toggle,caps:escape,compose:ralt";
      };
    };

    menu = "${tofi}-drun --drun-launch=true --width 800 --height 700  --font ${pkgs.jetbrains-mono}/share/fonts/TTF/JetBrainsMono-Light.ttf";
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


  wayland.windowManager.sway.config.keybindings = lib.mkOptionDefault {
      "${modifier}+T" = "exec ${termWithName} floating-term";

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

    #home.sessionVariables.NIXOS_OZONE_WL = "1"; # forces electron apps use wayland
    #home.sessionVariables.QT_QPA_PLATFORMTHEME = "gnome"; # QT apps follows gtk theme
}
