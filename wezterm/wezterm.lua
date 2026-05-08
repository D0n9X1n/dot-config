-- ~/.wezterm.lua
-- =========================================================
-- Keymap quick reference
-- Splits:
--   Cmd+d            -> split down (vertical)
--   Cmd+Shift+d      -> split right (horizontal)
-- Tabs:
--   Cmd+Left/Right  -> previous/next tab
-- Panes:
--   Ctrl+Shift+Arrows -> focus pane in direction
-- Resize panes:
--   Cmd+Ctrl+Alt+Shift+Arrows -> resize by small steps
-- Zoom:
--   Cmd+Ctrl+Alt+Enter -> toggle pane zoom
-- =========================================================
local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Use Metal via WebGpu instead of deprecated OpenGL (fixes sleep/wake crashes)
config.front_end = "WebGpu"

-- =========================================================
-- Theme
-- =========================================================
config.color_scheme = "GruvboxDarkHard"

-- =========================================================
-- Fonts
-- =========================================================
config.custom_block_glyphs = true

local EN_FONT = "Rec Mono St.Helens"

local function make_font(weight)
  return wezterm.font_with_fallback({
    { family = EN_FONT, weight = weight },
    "Symbols Nerd Font Mono",
    "Noto Color Emoji",
  })
end

config.font = make_font(500)
config.font_size = 14.0
config.line_height = 1.1
config.use_cap_height_to_scale_fallback_fonts = false

-- No hinting + grayscale anti-aliasing = thinnest possible strokes.
-- Display-specific overrides via apply_display_overrides().
config.freetype_load_target = "Light"
config.freetype_render_target = "Normal"
config.freetype_load_flags = "NO_HINTING"

config.bold_brightens_ansi_colors = "No"

-- Map bold to same weight (font only has Regular and Bold)
config.font_rules = {
  {
    intensity = "Bold",
    italic = false,
    font = make_font(500),
  },
}

-- =========================================================
-- Colors (declared first — referenced by Tab bar block + format-tab-title)
-- =========================================================
-- Gruvbox layered backgrounds — clear active vs inactive separation.
-- Bar matches terminal bg so the chrome is seamless; tabs are progressively
-- brighter (inactive bg0 → hover bg1 → active bg2). Active also gets a
-- Gruvbox bright-yellow accent fg so it pops without being garish.
local BAR_BG      = "#1d2021"  -- gruvbox dark hard bg (matches terminal)
local INACTIVE_BG = "#282828"  -- gruvbox bg0
local HOVER_BG    = "#3c3836"  -- gruvbox bg1
local ACTIVE_BG   = "#504945"  -- gruvbox bg2

local FG_DIM      = "#928374"  -- gruvbox gray (dim for inactive)
local FG          = "#ebdbb2"  -- gruvbox fg
local FG_ACCENT   = "#fabd2f"  -- gruvbox bright yellow (active accent)

config.colors = {
  tab_bar = {
    background = BAR_BG,
    inactive_tab_edge = BAR_BG,
    active_tab = { bg_color = ACTIVE_BG, fg_color = FG_ACCENT, intensity = "Bold" },
    inactive_tab = { bg_color = INACTIVE_BG, fg_color = FG_DIM },
    inactive_tab_hover = { bg_color = HOVER_BG, fg_color = FG },
    new_tab = { bg_color = BAR_BG, fg_color = FG_DIM },
    new_tab_hover = { bg_color = HOVER_BG, fg_color = FG },
  },
}

-- =========================================================
-- Tab bar — retro mode, multi-line for height
-- =========================================================
-- Why retro (not fancy):
--   * Fancy mode shows a close × on hover that can't be hidden (controlled
--     by WezTerm's chrome), and forces a single-line layout.
--   * Retro lets format-tab-title return MULTI-LINE text — the bar grows
--     to the tallest tab. That's how we get height + a loading bar row.
config.use_fancy_tab_bar = false
config.enable_tab_bar = true
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 40
config.show_new_tab_button_in_tab_bar = false
config.show_tab_index_in_tab_bar = false

-- Drive the loading-bar animation. WezTerm fires update-status on this
-- interval; we bump a global frame counter and nudge the bar to redraw.
config.status_update_interval = 200  -- 5Hz

-- =========================================================
-- Custom tab renderer
--   * 3 lines tall (top accent / title / bottom row)
--   * Vibe-coding tabs (manually titled via gg) get an animated
--     Knight-Rider loading bar on the bottom row
--   * No rounded pills, no close icon
-- =========================================================
local MIN_TAB_WIDTH = 22 -- minimum clickable width (columns)

local nf = wezterm.nerdfonts or {}

-- Animated loading-bar driver: bump the frame counter on every status tick.
-- update-status also nudges the tab bar to redraw, so format-tab-title
-- below re-runs with the latest frame.
wezterm.GLOBAL.tab_frame = wezterm.GLOBAL.tab_frame or 0
wezterm.on("update-status", function(window, _pane)
  wezterm.GLOBAL.tab_frame = (wezterm.GLOBAL.tab_frame + 1) % 1000
  -- An empty right-status keeps the bar repainting without showing extra UI.
  window:set_right_status("")
end)

-- Knight-Rider bar across a fixed-width track. A 3-block highlight bounces
-- left↔right; the rest of the row uses ▁ for a faint base line.
local function loading_bar(width, frame)
  if width < 4 then width = 4 end
  local span = width - 2  -- positions the 3-block highlight can occupy
  local cycle = span * 2
  local pos = frame % cycle
  if pos >= span then pos = cycle - pos - 1 end
  local out = {}
  for i = 1, width do
    if i >= pos + 1 and i <= pos + 3 then
      out[i] = "█"
    else
      out[i] = "▁"
    end
  end
  return table.concat(out)
end

local function tab_title(tab_info)
  local has_folder = false
  local process_name = ""
  local title = tab_info.tab_title
  if not title or title == "" then
    local cwd_uri = tab_info.active_pane.current_working_dir
    local proc = tab_info.active_pane.foreground_process_name
    if proc then
      process_name = proc:gsub("^.*/", "")
    end
    if cwd_uri then
      local cwd = cwd_uri
      if type(cwd_uri) == "userdata" and cwd_uri.path then
        cwd = cwd_uri.path
      else
        cwd = cwd_uri:gsub("^file://", "")
      end
      cwd = cwd:gsub("/+$", "")
      local parent = cwd:match("([^/]+)/[^/]+$") or ""
      local leaf = cwd:match("([^/]+)$") or ""
      if parent ~= "" and leaf ~= "" then
        title = parent .. "/" .. leaf
      else
        title = leaf ~= "" and leaf or cwd
      end
      has_folder = true
    else
      title = tab_info.active_pane.title
    end
  end
  return title:gsub("^%s+", ""):gsub("%s+$", ""), has_folder, process_name
end

wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
  local is_active = tab.is_active

  local bg = INACTIVE_BG
  local fg = FG_DIM
  if is_active then
    bg = ACTIVE_BG
    fg = FG_ACCENT  -- gruvbox bright yellow on active tab body
  elseif hover then
    bg = HOVER_BG
    fg = FG
  end

  local title, has_folder, process_name = tab_title(tab)
  local folder_icon = nf.fa_folder or ""
  local process_icons = {
    ["zsh"] = nf.md_console or "",
    ["bash"] = nf.md_console or "",
    ["fish"] = nf.md_console or "",
    ["nvim"] = nf.custom_vim or "",
    ["vim"] = nf.custom_vim or "",
    ["ssh"] = nf.md_ssh or "󰣀",
    ["git"] = nf.fa_git or "",
    ["node"] = nf.md_nodejs or "",
    ["python"] = nf.fa_python or "",
    ["ruby"] = nf.md_language_ruby or "",
    ["go"] = nf.md_language_go or "",
    ["cargo"] = nf.md_language_rust or "",
    ["rustc"] = nf.md_language_rust or "",
    ["java"] = nf.fa_java or "",
    ["docker"] = nf.md_docker or "",
    ["kubectl"] = nf.md_kubernetes or "󱃾",
    ["kube"] = nf.md_kubernetes or "󱃾",
    ["terraform"] = nf.md_terraform or "󱁢",
    ["aws"] = nf.md_aws or "",
    ["gcloud"] = nf.md_google_cloud or "󰊭",
    ["psql"] = nf.md_database or "",
    ["postgres"] = nf.md_database or "",
    ["mysql"] = nf.md_database or "",
    ["redis"] = nf.md_database or "",
    ["nginx"] = nf.md_server or "󰒋",
    ["tmux"] = nf.md_window_restore or "󰖲",
    ["make"] = nf.md_hammer_wrench or "󰈏",
  }
  local icon = process_icons[process_name]
  if icon then
    title = icon .. " " .. title
  elseif has_folder then
    title = folder_icon .. " " .. title
  end
  local index = tostring(tab.tab_index + 1)
  title = index .. " " .. title

  -- Width math: 3 chars left pad + title + 3 chars right pad = title + 6
  local mw = max_width or 999
  local FIXED = 6
  local title_max = mw - FIXED
  if title_max < 1 then title_max = 1 end

  title = wezterm.truncate_right(title, title_max)

  -- Enforce minimum width for the title area
  local min_title = MIN_TAB_WIDTH - FIXED
  if min_title < 1 then min_title = 1 end
  if min_title > title_max then min_title = title_max end
  title = wezterm.pad_right(title, min_title)

  -- Vibe-coding detection: tab.tab_title is set manually by the gg() shell
  -- function (via 'wezterm cli set-tab-title'). Any tab with a non-empty
  -- manual title is treated as a vibe-coding session and gets the animated
  -- loading bar on its bottom row.
  local manual_title = tab.tab_title
  local is_vibe = manual_title ~= nil and manual_title ~= ""

  -- 5-row layout for visible vertical padding ("floating tab" effect).
  --   Row 1: BAR_BG  -- gap above the tab body, looks like extended bar
  --   Row 2: tab bg, blank  -- inner top padding
  --   Row 3: tab bg, title  -- the actual title text
  --   Row 4: tab bg, loading bar (vibe) or blank (regular)  -- inner bottom
  --   Row 5: BAR_BG  -- gap below the tab body
  -- 3-space horizontal padding on each side keeps the title from kissing
  -- the tab edge.
  local PAD_X = "   "
  local body_row = PAD_X .. title .. PAD_X
  local bar_width = #body_row
  local pad_row = string.rep(" ", bar_width)

  local row4
  if is_vibe then
    local frame = wezterm.GLOBAL.tab_frame or 0
    row4 = PAD_X .. loading_bar(bar_width - #PAD_X * 2, frame) .. PAD_X
  else
    row4 = pad_row
  end

  return {
    -- Row 1: bar bg above tab (outer top padding)
    { Background = { Color = BAR_BG } },
    { Foreground = { Color = BAR_BG } },
    { Text = pad_row .. "\n" },

    -- Row 2: inner top padding (tab bg, no text)
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = pad_row .. "\n" },

    -- Row 3: title — bold + accent fg on active tab
    { Attribute = { Intensity = is_active and "Bold" or "Normal" } },
    { Text = body_row .. "\n" },
    { Attribute = { Intensity = "Normal" } },

    -- Row 4: loading bar (vibe-coding only) or inner bottom padding
    { Text = row4 .. "\n" },

    -- Row 5: bar bg below tab (outer bottom padding)
    { Background = { Color = BAR_BG } },
    { Foreground = { Color = BAR_BG } },
    { Text = pad_row },

    -- One-cell horizontal gap of bar bg between adjacent tabs.
    { Text = " " },
  }
end)

-- =========================================================
-- Window
-- =========================================================
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }

config.inactive_pane_hsb = {
  saturation = 0.7,
  brightness = 0.4,
}

-- =========================================================
-- Keybindings
-- =========================================================
config.keys = {
  -- Only copy when there is a selection; otherwise send Ctrl+C (SIGINT)
  { key = "c", mods = "CMD", action = wezterm.action_callback(function(window, pane)
    local sel = window:get_selection_text_for_pane(pane)
    if sel and sel ~= "" then
      window:perform_action(act.CopyTo("Clipboard"), pane)
    else
      window:perform_action(act.SendKey({ key = "c", mods = "CTRL" }), pane)
    end
  end) },

  -- Splits
  { key = "d", mods = "CMD",       action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "d", mods = "CMD|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },

  -- Cmd + Left/Right: switch tabs
  { key = "LeftArrow",  mods = "CMD", action = act.ActivateTabRelative(-1) },
  { key = "RightArrow", mods = "CMD", action = act.ActivateTabRelative(1) },

  -- Pane navigation
  { key = "LeftArrow",  mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Left") },
  { key = "RightArrow", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Right") },
  { key = "UpArrow",    mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Up") },
  { key = "DownArrow",  mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Down") },

  -- Resize pane: Cmd+Ctrl+Alt+Shift + arrows
  { key = "LeftArrow",  mods = "CMD|CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
  { key = "RightArrow", mods = "CMD|CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
  { key = "UpArrow",    mods = "CMD|CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Up", 3 }) },
  { key = "DownArrow",  mods = "CMD|CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Down", 3 }) },

  -- Zoom current pane: Cmd+Ctrl+Alt+Enter
  { key = "Enter", mods = "CMD|CTRL|ALT", action = act.TogglePaneZoomState },

  -- Cmd+w: close current pane (closes tab only if it's the last pane)
  { key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = true }) },
}

-- =========================================================
-- QoL
-- =========================================================
config.term = "xterm-256color"
config.scrollback_lines = 20000
config.audible_bell = "Disabled"

-- =========================================================
-- Adaptive rendering per display DPI
-- =========================================================
local function apply_display_overrides(window)
  local dpi = window:get_dimensions().dpi or 72
  local is_retina = dpi > 140

  local weight = is_retina and "Medium"       or "Regular"
  local render = is_retina and "Normal"       or "Normal"
  local load   = is_retina and "Normal"       or "Normal"
  local flags  = is_retina and "NO_HINTING"   or "FORCE_AUTOHINT"

  window:set_config_overrides({
    font                   = make_font(weight),
    font_rules             = { { intensity = "Bold", italic = false, font = make_font(weight) } },
    freetype_render_target = render,
    freetype_load_target   = load,
    freetype_load_flags    = flags,
  })
end

wezterm.on("window-config-reloaded", function(window, _pane) apply_display_overrides(window) end)
wezterm.on("window-resized", function(window, _pane) apply_display_overrides(window) end)

return config
