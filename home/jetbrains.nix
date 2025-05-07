{
  config,
  pkgs,
  inputs,
  pkgs-unstable,
  ...
}: {
  home.packages = with pkgs-unstable.jetbrains; [
    idea-ultimate
  ];
}
