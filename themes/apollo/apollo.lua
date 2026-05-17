-- Apollo — wezterm color_scheme
-- Gruvbox dark hard base + Material warm beige ANSI 7 + darker canvas.
-- Drop into wezterm config:
--   local apollo = require("apollo")
--   config.color_schemes = { Apollo = apollo }
--   config.color_scheme  = "Apollo"
return {
  foreground    = "#ebdbb2",
  background    = "#141617",
  cursor_bg     = "#ebdbb2",
  cursor_fg     = "#141617",
  cursor_border = "#ebdbb2",
  selection_fg  = "#ebdbb2",
  selection_bg  = "#3c3836",
  ansi = {
    "#1d2021", "#cc241d", "#98971a", "#d79921",
    "#458588", "#b16286", "#689d6a", "#d4be98",
  },
  brights = {
    "#928374", "#fb4934", "#b8bb26", "#fabd2f",
    "#83a598", "#d3869b", "#8ec07c", "#ebdbb2",
  },
}
