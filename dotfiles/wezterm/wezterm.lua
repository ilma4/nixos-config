local wezterm = require("wezterm")

local config = wezterm.config_builder()

local function color_scheme_for_appearance(appearance)
  if appearance:find("Dark") then
    return "Vs Code Dark+ (Gogh)"
    -- return "Builtin Solarized Dark"
  end

  return "VSCodeLight+ (Gogh)"
end

config.font = wezterm.font("JetBrains Mono")
config.harfbuzz_features = { "calt=0", "clig=0", "liga=0" }
config.font_size = 13.0
config.color_scheme = color_scheme_for_appearance(wezterm.gui.get_appearance())

local colors = wezterm.color.get_builtin_schemes()[config.color_scheme]
config.window_frame = {
  active_titlebar_bg = colors.background,
  inactive_titlebar_bg = colors.background,
  active_titlebar_fg = colors.foreground,
  inactive_titlebar_fg = colors.foreground,
  button_bg = colors.background,
  button_fg = colors.foreground,
}

config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE' -- use header, as tabbar
config.window_close_confirmation = 'NeverPrompt'

if wezterm.target_triple:find('apple%-darwin') then
  config.integrated_title_button_alignment = 'Left'
else
  config.integrated_title_button_alignment = 'Right'
end

config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false

return config
