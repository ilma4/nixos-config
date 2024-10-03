{ config, lib, pkgs, inputs, ... }:

{
  home.packages = with pkgs ; [
    wl-clipboard
    grim
    brightnessctl
  ];

  programs.waybar = {
    enable = true;
  };

  programs.tofi.enable = true;

  services.swayidle.enable = true;

  services.kdeconnect = {
    enable = true;
    indicator = true;
  };


  wayland.windowManager.sway.enable = true;
  wayland.windowManager.sway.config = {
    modifier = "Mod4";
    bars = [ { command = "${pkgs.waybar}/bin/waybar"; } ];

    output = {
      eDP-1 = {
        mode = "2880x1800@120.000hz";
        scale_filter = "linear";
        scale = "2.0";
        adaptive_sync = "on";
      };
    };

    input = {
      "type:touchpad" = {
        accel_profile = "adaptive";
        tap = "enabled";
        natural_scroll = "enabled";
        pointer_accel = "0.125";
      };

      "type:keyboard" = {
        xkb_layout = "us,ru";
        xkb_options = "grp:alt_space_toggle,caps:escape,compose:ralt";
      };
    };

    menu = "tofi-drun --drun-launch=true --width 800 --height 700  --font /home/ilma4/.nix-profile/share/fonts/TTF/JetBrainsMono-Light.ttf";
  };


  wayland.windowManager.sway.config.keybindings =  
    let
      modifier = config.wayland.windowManager.sway.config.modifier;
      pamixer = "${pkgs.pamixer}/bin/pamixer";
      grim = "${pkgs.grim}/bin/grim";
      wl-copy = "${pkgs.wl-clipboard}/bin/wl-copy";
      brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
    in lib.mkOptionDefault {
      "print" = "exec ${grim} - | ${wl-copy}";
#      "Shift+print" = "exec ${grim} -g - | ${pkgs.wl-clipboard}/bin/wl-copy"

      "XF86AudioRaiseVolume" = "exec ${pamixer} -ui 1"; # TODO: wob integration
      "XF86AudioLowerVolume" = "exec ${pamixer} -ud 1"; # TODO: wob integration
      "XF86AudioMute" = "exec ${pamixer} --toggle-mute"; # && ( pamixer --get-mute && echo 0 > $WOBSOCK ) || pamixer --get-volume > $WOBSOCK
      "XF86AudioMicMute" = "exec pactl set-source-mute @DEFAULT_SOURCE@ toggle";


      "XF86MonBrightnessDown" = "exec ${brightnessctl} set 5%-"; # | sed -En 's/.*\(([0-9]+)%\).*/\1/p' > $WOBSOCK
      "XF86MonBrightnessUp" = "exec ${brightnessctl} set +5%"; # | sed -En 's/.*\(([0-9]+)%\).*/\1/p' > $WOBSOCK
    };

    home.sessionVariables.NIXOS_OZONE_WL = "1";
}
