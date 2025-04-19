{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  inherit (lib) mkIf;
  inherit (pkgs) stdenv;
in {
  imports = [
    inputs.nixvim.homeManagerModules.nixvim
  ];

  options.nixvim = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable nixvim";
    };
  };

  config = lib.mkIf config.nixvim.enable {
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
        providers.wl-copy.enable = stdenv.isLinux;
        register = "unnamedplus";
      };

      plugins.treesitter.enable = true;

      extraPlugins = [
        pkgs.vimPlugins."vim-suda"
      ];
    };
  };
}
