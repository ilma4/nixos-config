{ config, pkgs, inputs, pkgs-unstable, ... }:

{
  imports = [ ];

  home.packages = with pkgs-unstable.jetbrains; [
    idea-ultimate
  ];
}
