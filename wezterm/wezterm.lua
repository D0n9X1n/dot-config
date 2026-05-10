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
-- Custom scheme: GruvboxDarkHard base + Material's warm-beige slot 7
-- (#d4be98). Claude Code's `dark-ansi` theme paints the prompt-input
-- background with ANSI 7; Hard's stock #a89984 reads as gray, Material's
-- #d4be98 reads as warm cream. Keep everything else from Hard.
config.color_schemes = {
  ["GruvboxDarkHardWarm"] = {
    foreground       = "#ebdbb2",
    background       = "#1d2021",
    cursor_bg        = "#ebdbb2",
    cursor_fg        = "#1d2021",
    cursor_border    = "#ebdbb2",
    selection_fg     = "#ebdbb2",
    selection_bg     = "#3c3836",
    ansi = {
      "#1d2021", -- 0  black
      "#cc241d", -- 1  red
      "#98971a", -- 2  green
      "#d79921", -- 3  yellow
      "#458588", -- 4  blue
      "#b16286", -- 5  magenta
      "#689d6a", -- 6  cyan
      "#d4be98", -- 7  white  ← Material's warm beige (was #a89984)
    },
    brights = {
      "#928374", -- 8  bright black
      "#fb4934", -- 9  bright red
      "#b8bb26", -- 10 bright green
      "#fabd2f", -- 11 bright yellow
      "#83a598", -- 12 bright blue
      "#d3869b", -- 13 bright magenta
      "#8ec07c", -- 14 bright cyan
      "#ebdbb2", -- 15 bright white (soft fg)
    },
  },
}
config.color_scheme = "Gruvbox dark, hard (base16)"

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

-- Don't dim unfocused panes/windows. Default wezterm desaturates them
-- (hue=1, saturation=0.9, brightness=0.8), which makes side-by-side
-- comparisons look like the colors don't match — they do, one side is
-- just being dimmed because it isn't focused.
config.inactive_pane_hsb = { hue = 1.0, saturation = 1.0, brightness = 1.0 }

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
-- Subtle tab states: tab background MATCHES terminal background, so tabs
-- look like floating text on the terminal canvas — only the heavy ┃
-- separator divides them. Foreground color alone signals state.
--
-- Pull the actual bg/fg from the active color scheme so swapping between
-- Gruvbox variants (dark hard / medium / Material) keeps the chrome
-- aligned automatically — no hex hunt required.
local SCHEME      = wezterm.color.get_builtin_schemes()[config.color_scheme] or {}
local BAR_BG      = (config.colors and config.colors.background) or SCHEME.background or "#1d2021"
local TAB_BG      = BAR_BG

-- Backwards-compat aliases (still referenced by the format-tab-title body):
local INACTIVE_BG = TAB_BG
local HOVER_BG    = TAB_BG
local ACTIVE_BG   = TAB_BG

local FG_DIM      = "#928374"  -- gruvbox neutral gray (inactive — quieter)
local FG          = "#d5c4a1"  -- gruvbox fg2 (hover — slightly brighter)
local FG_ACCENT   = "#fabd2f"  -- gruvbox bright yellow (active title)

config.colors = {
  tab_bar = {
    background = BAR_BG,
    inactive_tab_edge = BAR_BG,
    active_tab = { bg_color = TAB_BG, fg_color = FG_ACCENT },
    inactive_tab = { bg_color = TAB_BG, fg_color = FG_DIM },
    inactive_tab_hover = { bg_color = TAB_BG, fg_color = FG },
    new_tab = { bg_color = BAR_BG, fg_color = FG_DIM },
    new_tab_hover = { bg_color = BAR_BG, fg_color = FG },
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
config.tab_max_width = 999  -- effectively unbounded — tab width follows title length
config.show_new_tab_button_in_tab_bar = false
config.show_tab_index_in_tab_bar = false

-- Fancy tab-bar height comes from window_frame.font_size. 16pt gives a
-- comfortably tall bar without dwarfing terminal text. Chrome harmonised
-- with the bar so the whole title-bar area is one continuous Gruvbox surface.
config.window_frame = {
  font = wezterm.font({ family = "Rec Mono St.Helens", weight = "Medium" }),
  font_size = 15.0,
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

  -- Width math: 2 chars left pad + title + 6 chars right pad (room for the
  -- close × rendered by fancy-mode chrome) = title + 8.
  local mw = max_width or 999
  local FIXED = 8
  local title_max = mw - FIXED
  if title_max < 1 then title_max = 1 end
  title = wezterm.truncate_right(title, title_max)

  return {
    -- Vertical separator before every tab except the first.
    -- │ U+2502 BOX DRAWINGS LIGHT VERTICAL.
    { Background = { Color = BAR_BG } },
    { Foreground = { Color = FG_DIM } },
    { Text = tab.tab_index > 0 and "│" or " " },

    -- Tab body: 2-char left pad + title + 6-char right pad (close × room).
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = "  " .. title .. "      " },
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
-- Two parallel binding sets: macOS uses CMD as the primary modifier
-- (matching iTerm2 / native mac convention); Windows + Linux use
-- CTRL|SHIFT as the equivalent. Both are registered unconditionally —
-- WezTerm just ignores keymaps whose modifier doesn't exist on the
-- current platform, so the same lua file works everywhere.
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

  -- Splits — macOS
  { key = "d", mods = "CMD",       action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "d", mods = "CMD|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  -- Splits — Windows / Linux (CTRL|SHIFT plays the role of CMD)
  -- Note: CTRL|SHIFT+D is the same chord on macOS too; the macOS CMD
  -- bindings above stay for muscle memory, but if you're on a Windows
  -- keyboard plugged into a Mac these still work.
  { key = "d", mods = "CTRL|SHIFT",     action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "D", mods = "CTRL|SHIFT|ALT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },

  -- Tabs — macOS
  { key = "t", mods = "CMD",                action = act.SpawnTab("CurrentPaneDomain") },
  { key = "LeftArrow",  mods = "CMD",       action = act.ActivateTabRelative(-1) },
  { key = "RightArrow", mods = "CMD",       action = act.ActivateTabRelative(1) },
  -- Tabs — Windows / Linux
  { key = "t", mods = "CTRL|SHIFT",         action = act.SpawnTab("CurrentPaneDomain") },
  { key = "LeftArrow",  mods = "CTRL|SHIFT|ALT", action = act.ActivateTabRelative(-1) },
  { key = "RightArrow", mods = "CTRL|SHIFT|ALT", action = act.ActivateTabRelative(1) },

  -- Pane navigation (CTRL|SHIFT — same chord on every OS)
  { key = "LeftArrow",  mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Left") },
  { key = "RightArrow", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Right") },
  { key = "UpArrow",    mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Up") },
  { key = "DownArrow",  mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Down") },

  -- Resize pane: Cmd+Ctrl+Alt+Shift + arrows
  { key = "LeftArrow",  mods = "CMD|CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
  { key = "RightArrow", mods = "CMD|CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
  { key = "UpArrow",    mods = "CMD|CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Up", 3 }) },
  { key = "DownArrow",  mods = "CMD|CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Down", 3 }) },

  -- Zoom current pane: Cmd+Ctrl+Alt+Enter (mac) / Ctrl+Shift+Enter (win/linux)
  { key = "Enter", mods = "CMD|CTRL|ALT",  action = act.TogglePaneZoomState },
  { key = "Enter", mods = "CTRL|SHIFT",    action = act.TogglePaneZoomState },

  -- Close current pane (closes tab only if it's the last pane)
  { key = "w", mods = "CMD",        action = act.CloseCurrentPane({ confirm = true }) },
  { key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentPane({ confirm = true }) },
}

-- =========================================================
-- QoL
-- =========================================================
config.term = "xterm-256color"
config.scrollback_lines = 20000
config.audible_bell = "Disabled"

-- COLORTERM / FORCE_COLOR — exported into every shell WezTerm spawns.
-- COLORTERM short-circuits truecolor detection in Node/Rust/Python TUIs;
-- FORCE_COLOR=3 overrides ALL detection logic in Node-based supports-color
-- (Copilot CLI, ink TUIs) and forces 24-bit regardless of TERM. Mirrors
-- the matching env in .tmux.conf.
config.set_environment_variables = {
  COLORTERM   = "truecolor",
  FORCE_COLOR = "3",
}

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
