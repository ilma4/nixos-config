{
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        port = 1883;
        omitPasswordAuth = true;
        acl = ["pattern readwrite #"];
        settings.allow_anonymous = true;
      }
    ];
  };

  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant.enabled = true;
      permit_join = false;
      mqtt.server = "mqtt://127.0.0.1:1883";
      serial = {
        adapter = "ember";
        port = "/dev/serial/by-id/usb-SONOFF_SONOFF_Dongle_Plus_MG24_002c26fceef8ef11ac7f62135c2a50c9-if00-port0";
        rtscts = false;
      };
    };
  };

  systemd.services.zigbee2mqtt = {
    wants = ["mosquitto.service"];
    after = ["mosquitto.service"];
  };
}
