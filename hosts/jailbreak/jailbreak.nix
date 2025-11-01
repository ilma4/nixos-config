{inputs, ...}: {
  imports = [
    inputs.nixos-wsl.nixosModules.default
    inputs.home-manager.nixosModules.home-manager
  ];
  system.stateVersion = "24.11";
  wsl.defaultUser = "nixos";
  wsl.enable = true;
}
