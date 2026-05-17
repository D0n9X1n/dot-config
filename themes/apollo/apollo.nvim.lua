-- Apollo colorscheme for Neovim
-- Gruvbox dark hard base + Material warm beige + darker canvas (#141617).
-- Install: place in ~/.config/nvim/colors/apollo.lua (or any colors/ on rtp)
-- Use:     vim.cmd('colorscheme apollo')

vim.cmd('hi clear')
if vim.fn.exists('syntax_on') == 1 then vim.cmd('syntax reset') end
vim.o.background = 'dark'
vim.g.colors_name = 'apollo'

local p = {
  bg      = '#141617',
  bg1     = '#1d2021',
  bg2     = '#3c3836',
  fg      = '#ebdbb2',
  fg_dim  = '#928374',
  fg2     = '#d5c4a1',
  red     = '#cc241d',
  green   = '#98971a',
  yellow  = '#d79921',
  blue    = '#458588',
  purple  = '#b16286',
  aqua    = '#689d6a',
  beige   = '#d4be98',
  bred    = '#fb4934',
  bgreen  = '#b8bb26',
  byellow = '#fabd2f',
  bblue   = '#83a598',
  bpurple = '#d3869b',
  baqua   = '#8ec07c',
}

local set = vim.api.nvim_set_hl
local function hl(group, spec) set(0, group, spec) end

-- UI
hl('Normal',       { fg = p.fg,      bg = p.bg })
hl('NormalNC',     { fg = p.fg,      bg = p.bg })
hl('NormalFloat',  { fg = p.fg,      bg = p.bg1 })
hl('FloatBorder',  { fg = p.bg2,     bg = p.bg1 })
hl('CursorLine',   { bg = p.bg1 })
hl('CursorLineNr', { fg = p.byellow, bg = p.bg1, bold = true })
hl('LineNr',       { fg = p.fg_dim,  bg = p.bg })
hl('SignColumn',   { bg = p.bg })
hl('WinSeparator', { fg = p.bg2,     bg = p.bg })
hl('VertSplit',    { fg = p.bg2,     bg = p.bg })
hl('StatusLine',   { fg = p.fg,      bg = p.bg2 })
hl('StatusLineNC', { fg = p.fg_dim,  bg = p.bg1 })
hl('TabLine',      { fg = p.fg_dim,  bg = p.bg1 })
hl('TabLineSel',   { fg = p.byellow, bg = p.bg,  bold = true })
hl('TabLineFill',  { bg = p.bg })
hl('Pmenu',        { fg = p.fg,      bg = p.bg1 })
hl('PmenuSel',     { fg = p.bg,      bg = p.byellow, bold = true })
hl('PmenuSbar',    { bg = p.bg1 })
hl('PmenuThumb',   { bg = p.bg2 })
hl('Visual',       { bg = p.bg2 })
hl('Search',       { fg = p.bg,      bg = p.byellow })
hl('IncSearch',    { fg = p.bg,      bg = p.bred })
hl('CurSearch',    { fg = p.bg,      bg = p.bred })
hl('MatchParen',   { fg = p.byellow, bg = p.bg2, bold = true })
hl('Folded',       { fg = p.fg_dim,  bg = p.bg1, italic = true })
hl('FoldColumn',   { fg = p.fg_dim,  bg = p.bg })
hl('ColorColumn',  { bg = p.bg1 })
hl('NonText',      { fg = p.bg2 })
hl('Whitespace',   { fg = p.bg2 })
hl('SpecialKey',   { fg = p.bg2 })
hl('Directory',    { fg = p.bblue })
hl('Title',        { fg = p.byellow, bold = true })
hl('Conceal',      { fg = p.fg_dim })
hl('QuickFixLine', { bg = p.bg1 })

-- Syntax
hl('Comment',      { fg = p.fg_dim,  italic = true })
hl('Constant',     { fg = p.bpurple })
hl('String',       { fg = p.bgreen })
hl('Character',    { fg = p.bpurple })
hl('Number',       { fg = p.bpurple })
hl('Boolean',      { fg = p.bpurple })
hl('Float',        { fg = p.bpurple })
hl('Identifier',   { fg = p.bblue })
hl('Function',     { fg = p.byellow })
hl('Statement',    { fg = p.bred })
hl('Conditional',  { fg = p.bred })
hl('Repeat',       { fg = p.bred })
hl('Label',        { fg = p.bred })
hl('Operator',     { fg = p.fg2 })
hl('Keyword',      { fg = p.bred })
hl('Exception',    { fg = p.bred })
hl('PreProc',      { fg = p.baqua })
hl('Include',      { fg = p.baqua })
hl('Define',       { fg = p.baqua })
hl('Macro',        { fg = p.baqua })
hl('PreCondit',    { fg = p.baqua })
hl('Type',         { fg = p.byellow })
hl('StorageClass', { fg = p.byellow })
hl('Structure',    { fg = p.byellow })
hl('Typedef',      { fg = p.byellow })
hl('Special',      { fg = p.bpurple })
hl('SpecialChar',  { fg = p.bpurple })
hl('Tag',          { fg = p.baqua })
hl('Delimiter',    { fg = p.fg2 })
hl('SpecialComment', { fg = p.baqua, italic = true })
hl('Debug',        { fg = p.bred })
hl('Todo',         { fg = p.bg,      bg = p.byellow, bold = true })
hl('Error',        { fg = p.bred,    bold = true })

-- Diff
hl('DiffAdd',      { fg = p.bgreen,  bg = p.bg1 })
hl('DiffChange',   { fg = p.byellow, bg = p.bg1 })
hl('DiffDelete',   { fg = p.bred,    bg = p.bg1 })
hl('DiffText',     { fg = p.bg,      bg = p.byellow, bold = true })

-- Diagnostics
hl('DiagnosticError',     { fg = p.bred })
hl('DiagnosticWarn',      { fg = p.byellow })
hl('DiagnosticInfo',      { fg = p.bblue })
hl('DiagnosticHint',      { fg = p.baqua })
hl('DiagnosticUnderlineError', { sp = p.bred,    underline = true })
hl('DiagnosticUnderlineWarn',  { sp = p.byellow, underline = true })
hl('DiagnosticUnderlineInfo',  { sp = p.bblue,   underline = true })
hl('DiagnosticUnderlineHint',  { sp = p.baqua,   underline = true })

-- Treesitter (modern names)
hl('@comment',          { link = 'Comment' })
hl('@string',           { link = 'String' })
hl('@number',           { link = 'Number' })
hl('@boolean',          { link = 'Boolean' })
hl('@function',         { link = 'Function' })
hl('@function.call',    { link = 'Function' })
hl('@method',           { link = 'Function' })
hl('@keyword',          { link = 'Keyword' })
hl('@conditional',      { link = 'Conditional' })
hl('@repeat',           { link = 'Repeat' })
hl('@type',             { link = 'Type' })
hl('@type.builtin',     { link = 'Type' })
hl('@variable',         { fg = p.fg })
hl('@variable.builtin', { fg = p.bpurple })
hl('@parameter',        { fg = p.fg })
hl('@field',            { fg = p.bblue })
hl('@property',         { fg = p.bblue })
hl('@constant',         { link = 'Constant' })
hl('@constant.builtin', { fg = p.bpurple })
hl('@operator',         { link = 'Operator' })
hl('@punctuation',      { link = 'Delimiter' })
hl('@tag',              { fg = p.baqua })

-- Git signs
hl('GitSignsAdd',    { fg = p.bgreen })
hl('GitSignsChange', { fg = p.byellow })
hl('GitSignsDelete', { fg = p.bred })

-- Terminal ANSI palette (for :term)
vim.g.terminal_color_0  = '#1d2021'
vim.g.terminal_color_1  = '#cc241d'
vim.g.terminal_color_2  = '#98971a'
vim.g.terminal_color_3  = '#d79921'
vim.g.terminal_color_4  = '#458588'
vim.g.terminal_color_5  = '#b16286'
vim.g.terminal_color_6  = '#689d6a'
vim.g.terminal_color_7  = '#d4be98'
vim.g.terminal_color_8  = '#928374'
vim.g.terminal_color_9  = '#fb4934'
vim.g.terminal_color_10 = '#b8bb26'
vim.g.terminal_color_11 = '#fabd2f'
vim.g.terminal_color_12 = '#83a598'
vim.g.terminal_color_13 = '#d3869b'
vim.g.terminal_color_14 = '#8ec07c'
vim.g.terminal_color_15 = '#ebdbb2'
