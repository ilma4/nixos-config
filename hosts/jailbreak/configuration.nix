{inputs, ...}: {
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];
  system.stateVersion = "24.11";
  wsl.defaultUser = "nixos";
  wsl.enable = true;
}
