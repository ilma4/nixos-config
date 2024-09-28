{ config, pkgs, ... }:
{
  programs.nixvim = {
    enable = true;

    clipboard = {
      providers.wl-copy.enable = true;
      register = "unnamedplus";
    };

    plugins.treesitter.enable = true;
    plugins.cmp.enable = true;
    plugins.cmp.autoEnableSources = true;
    plugins.lsp.enable = true;
    plugins.auto-save.enable = true;

    extraPlugins = [
      pkgs.vimPlugins."vim-suda"
    ];
  };
}
