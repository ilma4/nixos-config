{
  config,
  lib,
  pkgs,
  ...
}: let
  basePlugins = with pkgs.vimPlugins; [
    vim-suda
  ];
  baseExtraConfigLua = ''
    vim.g.suda_smart_edit = 1
    vim.opt.number = true
    vim.opt.clipboard = "unnamedplus"
  '';
in {
  config = lib.mkIf (config ? home) {
    programs.neovim = {
      enable = true;
      withPython3 = true;
      withRuby = true;
      initLua = baseExtraConfigLua;
      plugins = basePlugins;
    };
  };
}
