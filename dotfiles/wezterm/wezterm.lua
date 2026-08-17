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
config.font_size = 13.0
config.color_scheme = color_scheme_for_appearance(wezterm.gui.get_appearance())

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
