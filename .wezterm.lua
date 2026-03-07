-- ~/.wezterm.lua
-- =========================================================
-- Keymap quick reference
-- Splits:
--   Cmd+Ctrl+Alt+v  -> split right (horizontal)
--   Cmd+Ctrl+Alt+h  -> split down (vertical)
-- Tabs:
--   Cmd+Left/Right  -> previous/next tab
-- Panes:
--   Cmd+Ctrl+Alt+Arrows -> focus pane in direction
-- Resize panes:
--   Cmd+Ctrl+Alt+Shift+Arrows -> resize by small steps
-- Zoom:
--   Cmd+Ctrl+Alt+Enter -> toggle pane zoom
-- =========================================================
local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder and wezterm.config_builder() or {}

-- =========================================================
-- Theme
-- =========================================================
config.color_scheme = "Solarized Dark - Patched"

-- =========================================================
-- Make Powerline/NERD glyphs render correctly
-- =========================================================
config.custom_block_glyphs = false

-- =========================================================
-- Fonts
-- EN=14, CN=16 (scaled)
-- Use Nerd Font as much as possible (icons/powerline glyphs)
-- =========================================================
local USE_NERD_PRIMARY = false -- set true if you want ALL text to use Nerd Font

local EN_FONT_NORMAL = "RecMonoBaker Nerd Font"
local EN_FONT_NERD = "RecMonoBaker Nerd Font"

config.font_size = 14.0
local CN_SCALE = 17.0 / 14.0

local function main_font_family()
  return USE_NERD_PRIMARY and EN_FONT_NERD or EN_FONT_NORMAL
end

local function make_font(weight)
  return wezterm.font_with_fallback({
    { family = main_font_family(), weight = weight },

    -- CJK monospace fallback
    { family = "LXGW WenKai Mono", scale = CN_SCALE },

    -- Prefer Nerd Font for powerline glyphs
    EN_FONT_NERD,
    "Symbols Nerd Font Mono",
    "Noto Color Emoji",
  })
end

-- Default to DemiBold (overridden to Regular on Retina via event below)
config.font = make_font("DemiBold")

config.use_cap_height_to_scale_fallback_fonts = false
config.line_height = 1.1

-- =========================================================
-- Bold settings (allow bold on non-Retina, keep brightening off)
-- =========================================================
config.bold_brightens_ansi_colors = "No"

-- Remove font_rules to allow native bold rendering
-- (Bold text will use Bold weight instead of Regular)

-- =========================================================
-- Auto-detect Retina: use DemiBold on non-Retina, Regular on Retina
-- =========================================================
wezterm.on("window-config-reloaded", function(window, _pane)
  local dpi = window:get_dimensions().dpi
  local is_retina = dpi > 100
  local overrides = window:get_config_overrides() or {}

  local desired_weight = is_retina and "Regular" or "DemiBold"
  local new_font = make_font(desired_weight)

  -- Only apply override if it changed, to avoid infinite reload loop
  if overrides._font_weight ~= desired_weight then
    overrides.font = new_font
    overrides._font_weight = desired_weight
    window:set_config_overrides(overrides)
  end
end)

-- =========================================================
-- Retro tab bar (NO fancy)
-- =========================================================
config.use_fancy_tab_bar = false
config.enable_tab_bar = true
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = false

config.tab_max_width = 40
config.show_new_tab_button_in_tab_bar = false
config.show_tab_index_in_tab_bar = false -- no index
config.window_frame = {
  font_size = 18.0,
}

-- =========================================================
-- Colors
-- =========================================================
local BAR_BG      = "#002b36"
local INACTIVE_BG = "#073642"
local HOVER_BG    = "#586e75"
local ACTIVE_BG   = "#073642"

local FG_DIM      = "#839496"
local FG          = "#eee8d5"

config.colors = config.colors or {}
config.colors.tab_bar = {
  background = BAR_BG,

  -- Hide the default '|' divider by painting edge as background
  inactive_tab_edge = BAR_BG,

  active_tab = { bg_color = ACTIVE_BG, fg_color = FG },
  inactive_tab = { bg_color = INACTIVE_BG, fg_color = FG_DIM },
  inactive_tab_hover = { bg_color = HOVER_BG, fg_color = FG },

  new_tab = { bg_color = BAR_BG, fg_color = FG_DIM },
  new_tab_hover = { bg_color = HOVER_BG, fg_color = FG },
}

-- =========================================================
-- Custom tab renderer (pill style, title only)
-- =========================================================
local MIN_TAB_WIDTH = 22 -- minimum clickable width (columns)

local nf = wezterm.nerdfonts or {}
local TAB_GAP = " "

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
    fg = FG
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

  -- Width math: keep pill edges symmetric and never cut off the right edge
  local mw = max_width or 999
  -- left pill(1) + space before title(1) + space after title(1) + right pill(1) + gap(1)
  local FIXED = 1 + 1 + 1 + 1 + 1
  local title_max = mw - FIXED
  if title_max < 1 then title_max = 1 end

  title = wezterm.truncate_right(title, title_max)

  -- Enforce minimum width for the title area
  local min_title = MIN_TAB_WIDTH - 2 -- exclude the two spaces around title
  if min_title < 1 then min_title = 1 end
  if min_title > title_max then min_title = title_max end
  title = wezterm.pad_right(title, min_title)

  return {
    -- Soft block with padding
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = "  " .. title .. "  " },

    -- Breathing room between tabs
    { Background = { Color = BAR_BG } },
    { Foreground = { Color = BAR_BG } },
    { Text = TAB_GAP },
  }
end)

-- =========================================================
-- Window padding
-- =========================================================
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }

-- =========================================================
-- Keybindings
-- =========================================================
config.keys = {
  -- Splits
  { key = "v", mods = "CMD|CTRL|ALT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "h", mods = "CMD|CTRL|ALT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

  -- Cmd + Left/Right: switch tabs
  { key = "LeftArrow",  mods = "CMD", action = act.ActivateTabRelative(-1) },
  { key = "RightArrow", mods = "CMD", action = act.ActivateTabRelative(1) },

  -- Pane navigation
  { key = "LeftArrow",  mods = "CMD|CTRL|ALT", action = act.ActivatePaneDirection("Left") },
  { key = "RightArrow", mods = "CMD|CTRL|ALT", action = act.ActivatePaneDirection("Right") },
  { key = "UpArrow",    mods = "CMD|CTRL|ALT", action = act.ActivatePaneDirection("Up") },
  { key = "DownArrow",  mods = "CMD|CTRL|ALT", action = act.ActivatePaneDirection("Down") },

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
-- QoL / stability
-- =========================================================
config.term = "xterm-256color"
config.scrollback_lines = 20000
config.audible_bell = "Disabled"

config.window_background_opacity = 1.0
config.text_background_opacity = 1.0

-- =========================================================
-- Dim inactive panes for clear active/inactive distinction
-- =========================================================
config.inactive_pane_hsb = {
  saturation = 0.7,
  brightness = 0.4,
}

return config
