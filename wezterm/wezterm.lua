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

local FG_DIM      = "#d5c4a1"  -- gruvbox fg2 (bright cream gray — readable on any tab bg)
local FG          = "#ebdbb2"  -- gruvbox fg (full bright)
local FG_ACCENT   = "#fabd2f"  -- gruvbox bright yellow (active tab title)

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
-- Tab bar — fancy mode at top (chosen for guaranteed legibility)
-- =========================================================
-- Multi-line in retro mode is supported per WezTerm docs but in practice
-- doesn't render reliably with multi-line attribute changes — text becomes
-- invisible. Fancy mode renders correctly and gives us native height via
-- window_frame.font_size. Trade-off: a small × may appear on tab hover
-- (no API to hide it), but tabs are always readable.
config.use_fancy_tab_bar = true
config.enable_tab_bar = true
config.tab_bar_at_bottom = false  -- fancy is top-only
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 40
config.show_new_tab_button_in_tab_bar = false
config.show_tab_index_in_tab_bar = false

-- Fancy tab-bar height comes from window_frame.font_size. 14pt matches
-- terminal body for harmony; chrome harmonised with the Gruvbox bar.
config.window_frame = {
  font = wezterm.font({ family = "Rec Mono St.Helens", weight = "Medium" }),
  font_size = 14.0,
  active_titlebar_bg = BAR_BG,
  inactive_titlebar_bg = BAR_BG,
  active_titlebar_fg = FG,
  inactive_titlebar_fg = FG_DIM,
  active_titlebar_border_bottom = BAR_BG,
  inactive_titlebar_border_bottom = BAR_BG,
  button_fg = FG_DIM,
  button_bg = BAR_BG,
  button_hover_fg = FG,
  button_hover_bg = HOVER_BG,
}

-- =========================================================
-- Custom tab renderer (single-line, fancy-mode compatible)
--   * 2-space horizontal padding on each side
--   * Active tab: bold + Gruvbox bright-yellow accent
--   * Per-process Nerd Font icon prefix when detectable
--   * "#N" tab-index prefix
--   * Tabs auto-fit content (no min width padding); WezTerm caps at tab_max_width
-- =========================================================
local nf = wezterm.nerdfonts or {}

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
  -- Tab number prefix (#1, #2, ...) — easier to scan than a bare digit.
  title = "#" .. tostring(tab.tab_index + 1) .. " " .. title

  -- Width math: 2 chars left pad + title + 6 chars right pad (room before
  -- the close × rendered by fancy-mode chrome) = title + 8.
  local mw = max_width or 999
  local FIXED = 8
  local title_max = mw - FIXED
  if title_max < 1 then title_max = 1 end
  title = wezterm.truncate_right(title, title_max)

  return {
    -- Vertical separator before every tab except the first.
    { Background = { Color = BAR_BG } },
    { Foreground = { Color = FG_DIM } },
    { Text = tab.tab_index > 0 and "│" or " " },

    -- Single-line tab body. Padding around title; bold + accent on active.
    -- Right pad is wider than left so the close × on hover doesn't crowd
    -- the title text.
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Attribute = { Intensity = is_active and "Bold" or "Normal" } },
    { Text = "  " .. title .. "      " },
    { Attribute = { Intensity = "Normal" } },
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
