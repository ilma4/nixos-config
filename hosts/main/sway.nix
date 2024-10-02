{ config, pkgs, ... }:

{
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
}
