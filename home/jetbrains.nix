{
  config,
  pkgs,
  inputs,
  pkgs-unstable,
  ...
}: {
  imports = [];

  home.packages = with pkgs-unstable.jetbrains;
    [
      idea-ultimate
      clion
      pycharm-professional
      rust-rover

      pycharm-community-bin
      idea-community-bin
    ]
    ++ (with pkgs-unstable; [
      android-studio
    ]);
}
