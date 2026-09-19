{pkgs-unstable, ...}: {
  home.packages = with pkgs-unstable; [
    llama-cpp
  ];
}
