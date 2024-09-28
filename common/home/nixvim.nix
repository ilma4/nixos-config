{ config, pkgs, ... }:
{
  programs.nixvim = {
    enable = true;

    clipboard = {
      providers.wl-copy.enable = true;
      register = "unnamedplus";
    };

    plugins.treesitter.enable = true;
    extraPlugins = [
      pkgs.vimPlugins."vim-suda"
    ];
  };
}
