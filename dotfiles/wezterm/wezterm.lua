local wezterm = require("wezterm")

local config = wezterm.config_builder()
config.enable_kitty_keyboard = true

local function color_scheme_for_appearance(appearance)
  if appearance:find("Dark") then
    return "Vs Code Dark+ (Gogh)"
    -- return "Builtin Solarized Dark"
  end

  return "VSCodeLight+ (Gogh)"
end

local function header_theme_for_appearance(appearance)
  if appearance:find("Dark") then
    return {
      window_frame = {
        active_titlebar_bg = "#111111",
        inactive_titlebar_bg = "#111111",
      },
      tab_bar = {
        active_tab = {
          bg_color = "#2e3440",
          fg_color = "#ffffff",
        },
        inactive_tab = {
          bg_color = "#111222",
          fg_color = "#ffffff",
        },
        new_tab = {
          bg_color = "#2e3440",
          fg_color = "#ffffff",
        },
        new_tab_hover = {
          bg_color = "#434c5e",
          fg_color = "#ffffff",
        },
      },
    }
  end

  return {
    window_frame = {
      active_titlebar_bg = "#333333",
      inactive_titlebar_bg = "#333333",
    },
    tab_bar = {
      active_tab = {
        bg_color = "#ffffff",
        fg_color = "#000000",
      },
      inactive_tab = {
        bg_color = "#cecece",
        fg_color = "#000000",
      },
      new_tab = {
        bg_color = "#cecece",
        fg_color = "#000000",
      },
      new_tab_hover = {
        bg_color = "#ffffff",
        fg_color = "#000000",
      },
    },
  }
end

local function rounded_new_tab(background, foreground, titlebar_background)
  return wezterm.format({
    "ResetAttributes",
    { Background = { Color = titlebar_background } },
    { Foreground = { Color = background } },
    { Text = wezterm.nerdfonts.ple_left_half_circle_thick },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = "+" },
    { Background = { Color = titlebar_background } },
    { Foreground = { Color = background } },
    { Text = wezterm.nerdfonts.ple_right_half_circle_thick },
  })
end

local appearance = wezterm.gui.get_appearance()
local header_theme = header_theme_for_appearance(appearance)

config.font = wezterm.font("JetBrains Mono")
config.harfbuzz_features = { "calt=0", "clig=0", "liga=0" }
config.font_size = 13.0
config.color_scheme = color_scheme_for_appearance(appearance)
config.colors = { tab_bar = header_theme.tab_bar }
config.window_frame = header_theme.window_frame
config.tab_bar_style = {
  new_tab = rounded_new_tab(
    header_theme.tab_bar.new_tab.bg_color,
    header_theme.tab_bar.new_tab.fg_color,
    header_theme.window_frame.active_titlebar_bg
  ),
  new_tab_hover = rounded_new_tab(
    header_theme.tab_bar.new_tab_hover.bg_color,
    header_theme.tab_bar.new_tab_hover.fg_color,
    header_theme.window_frame.active_titlebar_bg
  ),
}

config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE' -- use header, as tabbar
config.window_close_confirmation = 'NeverPrompt'
config.keys = {
  { key = 'w', mods = 'CMD', action = wezterm.action.CloseCurrentTab({ confirm = false }) },
  { key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentTab({ confirm = false }) },
}
config.enable_scroll_bar = true

if wezterm.target_triple:find('apple%-darwin') then
  config.integrated_title_button_alignment = 'Left'
else
  config.integrated_title_button_alignment = 'Right'
end

config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false

return config
