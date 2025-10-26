{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./universall-apps.nix
  ];

  i4-apps.apps = {
    firefox = {};
  };
}
