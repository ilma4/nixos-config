{
  inputs,
  pkgs-unstable,
  ...
}: {
  home-manager.useGlobalPkgs = true;
  home-manager.extraSpecialArgs = {
    inherit inputs;
    inherit pkgs-unstable;
  };
}
