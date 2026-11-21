{
  services.pipewire.extraConfig.pipewire."90-sony-wh-1000xm5-eq"."context.modules" = [
    {
      name = "libpipewire-module-filter-chain";
      args = {
        "node.description" = "Sony WH-1000XM5 EQ";
        "audio.channels" = 2;
        "audio.position" = ["FL" "FR"];
        "filter.graph" = {
          nodes = [
            {
              type = "builtin";
              name = "eq";
              label = "param_eq";
              config.filename = "${./sony-wh-1000xm5-parametric-eq.txt}";
            }
          ];
          inputs = ["eq:In 1" "eq:In 2"];
          outputs = ["eq:Out 1" "eq:Out 2"];
        };
        "capture.props" = {
          "node.name" = "sony-wh-1000xm5-eq-input";
          "media.class" = "Audio/Sink";
          # Insert the EQ only when WirePlumber routes audio to these headphones in stereo mode.
          "filter.smart" = true;
          "filter.smart.target" = {
            "api.bluez5.address" = "AC:80:0A:93:B1:08";
            "api.bluez5.profile" = "a2dp-sink";
            "media.class" = "Audio/Sink";
          };
        };
        "playback.props" = {
          "node.name" = "sony-wh-1000xm5-eq-output";
          "node.passive" = true;
          # Keep the filter ready for reconnects, but never send it to another sink.
          "node.dont-fallback" = true;
          "node.linger" = true;
        };
      };
    }
  ];
}
