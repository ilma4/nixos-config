{pkgs, pkgs-unstable, ...}: let
  configureZigbeeSockets = pkgs.writeShellApplication {
    name = "i4-configure-zigbee-sockets";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      mosquitto
    ];
    text = builtins.readFile ../../scripts/i4-configure-zigbee-sockets.sh;
  };
in {
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
    package = pkgs-unstable.zigbee2mqtt;
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

  services.openthread-border-router = {
    enable = true;
    openFirewall = true;
    backboneInterfaces = ["enp2s0"];
    # Container churn can push interface indices past the 16-bit MRT6_ADD_MIF
    # limit. Allocate a free low index for the Thread TUN interface instead.
    package = pkgs.openthread-border-router.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        (
        set -euo pipefail
        substituteInPlace third_party/openthread/repo/src/posix/platform/netif.cpp \
          --replace-fail \
          '    VerifyOrDie(ioctl(sTunFd, TUNSETIFF, static_cast<void *>(&ifr)) == 0, OT_EXIT_ERROR_ERRNO);' \
          '    {
                  char name[IF_NAMESIZE];
                  unsigned int index = 1000;
                  while (index <= 65535 && if_indextoname(index, name) != nullptr)
                  {
                      ++index;
                  }
                  VerifyOrDie(index <= 65535, OT_EXIT_FAILURE);
                  VerifyOrDie(ioctl(sTunFd, TUNSETIFINDEX, &index) == 0, OT_EXIT_ERROR_ERRNO);
              }
              VerifyOrDie(ioctl(sTunFd, TUNSETIFF, static_cast<void *>(&ifr)) == 0, OT_EXIT_ERROR_ERRNO);'
        )
      '';
    });

    radio = {
      # Dedicated Thread dongle; the other MG24 is used by Zigbee2MQTT.
      device = "/dev/serial/by-id/usb-SONOFF_SONOFF_Dongle_Plus_MG24_9cf7b5852672f011b27afb9e1045c30f-if00-port0";
      baudRate = 460800;
      flowControl = false;
    };

    rest = {
      listenAddress = "::";
      listenPort = 8081;
    };
  };

  services.matter-server.enable = true;

  systemd.services.zigbee2mqtt = {
    wants = ["mosquitto.service"];
    after = ["mosquitto.service"];
  };

  environment.systemPackages = [
    configureZigbeeSockets
  ];
}
