{ config, pkgs, ... }:
{
  programs.nixvim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    files = {
      "ftplugin/nix.lua" = {
        opts = {
          expandtab = true;
          shiftwidth = 2;
          tabstop = 2;
        };
      };
    };

    clipboard = {
      providers.wl-copy.enable = true;
      register = "unnamedplus";
    };

    plugins.treesitter.enable = true;
    plugins.cmp.enable = true;
    plugins.cmp.autoEnableSources = true;
    plugins.lsp.enable = true;
    plugins.auto-save.enable = true;
    plugins.telescope.enable = true;

    extraPlugins = [
      pkgs.vimPlugins."vim-suda"
    ];
  };
}
