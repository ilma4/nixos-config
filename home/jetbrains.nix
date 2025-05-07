{pkgs-unstable, ...}: {
  home.packages = with pkgs-unstable.jetbrains;
    [
      idea-ultimate
    ]
    ++ (with pkgs-unstable; [jetbrains-toolbox]);
}
