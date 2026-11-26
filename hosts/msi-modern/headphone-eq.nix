{
  services.pipewire.wireplumber.extraConfig."90-sony-wh-1000xm5-eq"."node.filter-graph.rules" = [
    {
      matches = [
        {
          "api.bluez5.address" = "AC:80:0A:93:B1:08";
          "api.bluez5.profile" = "a2dp-sink";
          "media.class" = "Audio/Sink";
        }
      ];
      # Process stereo audio on the Bluetooth sink itself, keeping its volume control.
      actions.create-filter-graph = [
        (builtins.toJSON {
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
        })
      ];
    }
  ];
}
