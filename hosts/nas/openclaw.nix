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
    # Reuse the host's evaluated guest instead of re-evaluating a stored flake.
    evaluatedConfig = inputs.self.nixosConfigurations.openclaw;
    restartIfChanged = true;
  };

  # Also restart for runner-only changes, such as vCPU or memory settings.
  systemd.services."microvm@openclaw".restartTriggers = [
    inputs.self.nixosConfigurations.openclaw.config.microvm.declaredRunner
  ];
}
