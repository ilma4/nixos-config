{...}: {
  targets.darwin.defaults = {
    NSGlobalDomain = {
      "com.apple.trackpad.scaling" = 2.0;
      "com.apple.keyboard.fnState" = true;
    };

    "com.apple.AppleMultitouchTrackpad" = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
    };

    "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
    };

    "com.apple.spaces" = {
      spans-displays = false;
    };

    "com.apple.menuextra.clock" = {
      Show24Hour = true;
    };

    "com.apple.finder" = {
      ShowPathbar = true;
    };

    "com.apple.dock" = {
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;

      mru-spaces = false;
      orientation = "bottom";

      autohide = true;
      autohide-time-modifier = 0.1;
    };

    "com.apple.WindowManager" = {
      GloballyEnabled = false;
    };
  };
}
