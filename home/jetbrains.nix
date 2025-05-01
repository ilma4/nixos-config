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
    ]
    ++ [pkgs-unstable.android-studio];
}
