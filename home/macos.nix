{
  config,
  lib,
  pkgs,
  dotfiles,
  ...
}: {
  home.file.".config/element-vts/sony-mdr7506.els".source = "${dotfiles}/element/sony-mdr7506.els"; # equalizer for headphones
  home.sessionPath = [
    "/opt/homebrew/bin"
  ];
}
