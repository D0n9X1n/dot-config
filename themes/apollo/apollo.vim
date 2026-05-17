" Apollo colorscheme for Vim
" Gruvbox dark hard base + Material warm beige + darker canvas (#141617).
" Install: cp apollo.vim ~/.vim/colors/  (or symlink)
" Use:     :colorscheme apollo

hi clear
if exists('syntax_on') | syntax reset | endif
let g:colors_name = 'apollo'
set background=dark

" Palette
let s:bg     = '#141617'
let s:bg1    = '#1d2021'
let s:bg2    = '#3c3836'
let s:fg     = '#ebdbb2'
let s:fg_dim = '#928374'
let s:fg2    = '#d5c4a1'
let s:red    = '#cc241d'
let s:green  = '#98971a'
let s:yellow = '#d79921'
let s:blue   = '#458588'
let s:purple = '#b16286'
let s:aqua   = '#689d6a'
let s:beige  = '#d4be98'
let s:bred   = '#fb4934'
let s:bgreen = '#b8bb26'
let s:byellow= '#fabd2f'
let s:bblue  = '#83a598'
let s:bpurple= '#d3869b'
let s:baqua  = '#8ec07c'

function! s:hi(group, fg, bg, attr) abort
  let l:cmd = 'hi ' . a:group
  if a:fg !=# '' | let l:cmd .= ' guifg=' . a:fg | endif
  if a:bg !=# '' | let l:cmd .= ' guibg=' . a:bg | endif
  if a:attr !=# '' | let l:cmd .= ' gui=' . a:attr . ' cterm=' . a:attr | endif
  execute l:cmd
endfunction

call s:hi('Normal',       s:fg,     s:bg,  '')
call s:hi('NormalNC',     s:fg,     s:bg,  '')
call s:hi('CursorLine',   '',       s:bg1, '')
call s:hi('CursorLineNr', s:byellow,s:bg1, 'bold')
call s:hi('LineNr',       s:fg_dim, s:bg,  '')
call s:hi('SignColumn',   '',       s:bg,  '')
call s:hi('VertSplit',    s:bg2,    s:bg,  '')
call s:hi('WinSeparator', s:bg2,    s:bg,  '')
call s:hi('StatusLine',   s:fg,     s:bg2, 'none')
call s:hi('StatusLineNC', s:fg_dim, s:bg1, 'none')
call s:hi('Pmenu',        s:fg,     s:bg1, '')
call s:hi('PmenuSel',     s:bg,     s:byellow, 'bold')
call s:hi('Visual',       '',       s:bg2, '')
call s:hi('Search',       s:bg,     s:byellow, '')
call s:hi('IncSearch',    s:bg,     s:bred,    '')
call s:hi('MatchParen',   s:byellow,s:bg2, 'bold')
call s:hi('Folded',       s:fg_dim, s:bg1, 'italic')
call s:hi('NonText',      s:bg2,    '',    '')
call s:hi('SpecialKey',   s:bg2,    '',    '')
call s:hi('Directory',    s:bblue,  '',    '')
call s:hi('Title',        s:byellow,'',    'bold')
call s:hi('ColorColumn',  '',       s:bg1, '')

" Syntax
call s:hi('Comment',      s:fg_dim, '',    'italic')
call s:hi('Constant',     s:bpurple,'',    '')
call s:hi('String',       s:bgreen, '',    '')
call s:hi('Character',    s:bpurple,'',    '')
call s:hi('Number',       s:bpurple,'',    '')
call s:hi('Boolean',      s:bpurple,'',    '')
call s:hi('Identifier',   s:bblue,  '',    '')
call s:hi('Function',     s:byellow,'',    '')
call s:hi('Statement',    s:bred,   '',    '')
call s:hi('Keyword',      s:bred,   '',    '')
call s:hi('Conditional',  s:bred,   '',    '')
call s:hi('Repeat',       s:bred,   '',    '')
call s:hi('Operator',     s:fg2,    '',    '')
call s:hi('PreProc',      s:baqua,  '',    '')
call s:hi('Include',      s:baqua,  '',    '')
call s:hi('Define',       s:baqua,  '',    '')
call s:hi('Macro',        s:baqua,  '',    '')
call s:hi('Type',         s:byellow,'',    '')
call s:hi('StorageClass', s:byellow,'',    '')
call s:hi('Structure',    s:byellow,'',    '')
call s:hi('Special',      s:bpurple,'',    '')
call s:hi('Delimiter',    s:fg2,    '',    '')
call s:hi('Todo',         s:bg,     s:byellow, 'bold')
call s:hi('Error',        s:bred,   '',    'bold')
call s:hi('WarningMsg',   s:byellow,'',    '')
call s:hi('ErrorMsg',     s:bred,   '',    'bold')

" Diff
call s:hi('DiffAdd',      s:bgreen, s:bg1, '')
call s:hi('DiffChange',   s:byellow,s:bg1, '')
call s:hi('DiffDelete',   s:bred,   s:bg1, '')
call s:hi('DiffText',     s:bg,     s:byellow, 'bold')

" Diagnostics (Neovim falls back here too)
call s:hi('DiagnosticError', s:bred,    '', '')
call s:hi('DiagnosticWarn',  s:byellow, '', '')
call s:hi('DiagnosticInfo',  s:bblue,   '', '')
call s:hi('DiagnosticHint',  s:baqua,   '', '')
