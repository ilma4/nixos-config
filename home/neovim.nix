{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.i4.neovim;
in {
  options.i4.neovim.enable = lib.mkEnableOption "advanced neovim config (LSP and formatters)";

  config = lib.mkIf (cfg.enable && (config ? home)) {
    programs.neovim = {
      plugins = with pkgs.vimPlugins; [
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

      extraPackages = with pkgs; [
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

      extraLuaConfig = ''
        vim.o.clipboard = "unnamedplus"

        vim.opt.expandtab   = true
        vim.opt.shiftwidth  = 4
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
    };
  };
}
