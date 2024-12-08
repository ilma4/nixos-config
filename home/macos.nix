{
  config,
  lib,
  pkgs,
  dotfiles,
  ...
}: {
  home.packages = with pkgs; [
  ];

  home.file.".config/element-vts/sony-mdr7506.els".source = "${dotfiles}/element/sony-mdr7506.els";
}
