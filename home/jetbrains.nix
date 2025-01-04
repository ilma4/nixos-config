{
  config,
  pkgs,
  inputs,
  pkgs-unstable,
  ...
}: {
  home.packages = with pkgs-unstable.jetbrains;
    [
      idea-ultimate
      clion
      pycharm-professional
      rust-rover

      pycharm-community-bin
      idea-community-bin
    ]
    ++ [pkgs-unstable.android-studio];
}
