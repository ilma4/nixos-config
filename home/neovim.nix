{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.neovim;
  basePlugins = with pkgs.vimPlugins; [
    vim-suda
  ];
  baseExtraConfigLua = ''
    vim.g.suda_smart_edit = 1
    vim.opt.number = true
    vim.opt.clipboard = "unnamedplus"
  '';
  idePlugins = with pkgs.vimPlugins; [
    nvim-lspconfig
    conform-nvim

    # tiny helper for builtin commenting
    ts-comments-nvim

    # syntax + AST
    # (nvim-treesitter.withAllGrammars)
    (nvim-treesitter.withPlugins (p: [
      p.nix
      p.lua
      p.bash
      p.yaml
      p.json
      p.toml
      p.markdown
      p.vim
      p.python
      p.haskell
    ]))
  ];
  ideExtraPackages = with pkgs; [
    nixd
    alejandra
    lua-language-server
    stylua
    bash-language-server
    shfmt
    yaml-language-server
    taplo
    vscode-langservers-extracted
    prettier
  ];
  idePackDir = pkgs.vimUtils.packDir {
    neovim-ide = {
      start = idePlugins;
      opt = [];
    };
  };
  ideInitLua = ''
    ${config.programs.neovim.extraLuaConfig}
    ${config.programs.neovim.generatedConfigs.lua or ""}

    vim.opt.expandtab = true
    vim.opt.shiftwidth = 4
    vim.opt.softtabstop = -1

    -- Treesitter
    require("nvim-treesitter.configs").setup({
      highlight = { enable = true },
      indent = { enable = true },
    })

    -- tiny helper for builtin gc comments
    require("ts-comments").setup()

    local conform = require("conform")

    local on_attach = function(_, bufnr)
      local map = function(mode, lhs, rhs)
        vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true })
      end

      map("n", "gd", vim.lsp.buf.definition)
      map("n", "gD", vim.lsp.buf.declaration)
      map("n", "gr", vim.lsp.buf.references)
      map("n", "K", vim.lsp.buf.hover)
      map("n", "<leader>ca", vim.lsp.buf.code_action)
      map("n", "<leader>rn", vim.lsp.buf.rename)
    end

    local servers = {
      {
        name = "nixd",
      },
      {
        name = "lua_ls",
        opts = {
          settings = {
            Lua = {
              diagnostics = {
                globals = { "vim" },
              },
              workspace = {
                checkThirdParty = false,
              },
            },
          },
        },
      },
      {
        name = "bashls",
      },
      {
        name = "yamlls",
      },
      {
        name = "taplo",
      },
      {
        name = "jsonls",
      },
    }

    for _, server in ipairs(servers) do
      local opts = vim.tbl_deep_extend("force", { on_attach = on_attach }, server.opts or {})
      vim.lsp.config(server.name, opts)
      vim.lsp.enable(server.name)
    end

    conform.setup({
      formatters_by_ft = {
        nix = { "alejandra" },
        lua = { "stylua" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        zsh = { "shfmt" },
        yaml = { "prettier" },
        toml = { "taplo" },
        json = { "prettier" },
        jsonc = { "prettier" },
        markdown = { "prettier" },
      },
      format_on_save = {
        timeout_ms = 500,
        lsp_fallback = true,
      },
    })

    vim.keymap.set({ "n", "v" }, "<leader>r", function()
      conform.format({ async = true, lsp_fallback = true })
    end, { desc = "Format current buffer" })

    -- Commenting keybindings
    vim.keymap.set("n", "<C-/>", "gcc", { remap = true, silent = true, desc = "Toggle comment current line" })
    vim.keymap.set("n", "<C-_>", "gcc", { remap = true, silent = true, desc = "Toggle comment current line" })
    vim.keymap.set("v", "<C-/>", "gc", { remap = true, silent = true, desc = "Toggle comment selection" })
    vim.keymap.set("v", "<C-_>", "gc", { remap = true, silent = true, desc = "Toggle comment selection" })
  '';
in {
  options.i4.neovim.enable = lib.mkEnableOption "the neovim-ide command with advanced Neovim config (LSP and formatters)";

  config = lib.mkIf (config ? home) {
    programs.neovim = {
      enable = true;
      extraLuaConfig = baseExtraConfigLua;
      plugins = basePlugins;
    };

    home.packages = lib.mkIf cfg.enable [
      (pkgs.writeShellScriptBin "neovim-ide" ''
        set -euo pipefail

        export NVIM_APPNAME="neovim-ide"
        if [ -n "''${PATH-}" ]; then
          export PATH="${lib.makeBinPath ideExtraPackages}:$PATH"
        else
          export PATH="${lib.makeBinPath ideExtraPackages}"
        fi

        exec ${config.programs.neovim.finalPackage}/bin/nvim \
          --cmd 'set packpath^=${idePackDir}' \
          --cmd 'set runtimepath^=${idePackDir}' \
          "$@"
      '')
    ];

    home.file = lib.mkIf cfg.enable {
      ".config/neovim-ide/init.lua".text = ideInitLua;
    };
  };
}
