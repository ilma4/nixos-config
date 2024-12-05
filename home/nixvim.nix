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

      plugins.cmp = {
        enable = true;
        autoEnableSources = true;
      };

      plugins.none-ls = {
        enable = true;
        sources.formatting = {
          alejandra.enable = true;
          hclfmt.enable = true;
          just.enable = true;
          #opentofu_fmt.enable = true;
          prettier.enable = true;
          # rubyfmt is broken on darwin-based systems
          rubyfmt.enable = (
            pkgs.stdenv.hostPlatform.system
            != "x86_64-darwin"
            && pkgs.stdenv.hostPlatform.system != "aarch64-darwin"
          );
          sqlformat.enable = true;
          stylua.enable = true;
          yamlfmt.enable = true;
        };
        sources.diagnostics = {
          trivy.enable = true;
          yamllint.enable = true;
        };
      };

      plugins.auto-save.enable = true;
      plugins.telescope.enable = true;

      extraPlugins = [
        pkgs.vimPlugins."vim-suda"
      ];
    };
  };
}
