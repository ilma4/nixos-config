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
    vim.g.clipboard = "osc52"
    vim.opt.clipboard = "unnamedplus"

    local function is_suda_buffer(bufnr)
      local name = vim.api.nvim_buf_get_name(bufnr)
      return vim.bo[bufnr].buftype == "acwrite" or name:match("^suda://") ~= nil
    end

    local function autosave()
      local bufnr = vim.api.nvim_get_current_buf()
      if not vim.api.nvim_buf_is_valid(bufnr)
          or vim.bo[bufnr].buftype ~= ""
          or vim.bo[bufnr].readonly
          or not vim.bo[bufnr].modified
          or is_suda_buffer(bufnr)
      then
        return
      end

      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("silent! update")
      end)
    end

    vim.api.nvim_create_autocmd({"FocusLost", "InsertLeave", "TextChanged"}, {callback = autosave})
    vim.fn.timer_start(10000, autosave, {["repeat"] = -1})
  '';
in {
  config = lib.mkIf (config ? home) {
    programs.neovim = {
      enable = true;
      withPython3 = false;
      withRuby = false;
      initLua = baseExtraConfigLua;
      plugins = basePlugins;
    };
  };
}
