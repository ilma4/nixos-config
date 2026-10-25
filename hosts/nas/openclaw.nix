{inputs, ...}: {
  imports = [inputs.microvm.nixosModules.host];

  networking.interfaces.openclaw-tap.ipv4.addresses = [
    {
      address = "10.77.0.1";
      prefixLength = 30;
    }
  ];
  networking.nat = {
    enable = true;
    internalInterfaces = ["openclaw-tap"];
  };

  microvm.vms.openclaw = {
    flake = inputs.self;
    restartIfChanged = true;
  };
}
