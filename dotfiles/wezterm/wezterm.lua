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

return config
