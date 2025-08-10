args @ {
  inputs,
  pkgs-unstable,
  ...
}: {
  home-manager.useGlobalPkgs = true;
  home-manager.extraSpecialArgs = {
    inherit inputs;
    inherit pkgs-unstable;
    flake-location = args.flake-location or "/etc/nixos";
  };
}
