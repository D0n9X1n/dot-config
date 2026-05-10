#!/usr/bin/env pwsh
# Custom status line for Claude Code on Windows (PowerShell 7+).
# Functional parity with claude/statusline.sh — same segments, same Gruvbox
# accents, same vim-airline mode badge, same per-cwd git cache.
#
# Claude Code feeds this script a JSON payload on stdin. We read fields
# via ConvertFrom-Json (PowerShell builtin — no jq dependency), do all
# rendering in process (no per-segment subshell forks), and emit one
# ANSI-colored line on stdout.
#
# Wired up via claude/settings.json:
#   "statusLine": { "type": "command",
#                   "command": "pwsh -NoProfile -File ~/.claude/statusline.ps1" }

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false  # don't blow up on git nonzero

# --- Config ---------------------------------------------------------------
$Segments = @('vim','time','timer','cost','git','branch','model','effort',
              'mcp','skills','ctx','agent','worktree','style','stash','venv')
$Sep = ' | '

$IconsOn = -not $env:CLAUDE_STATUSLINE_NO_ICONS
$ColorOn = -not $env:CLAUDE_STATUSLINE_NO_COLOR

# Nerd Font icons (UTF-8). Same FontAwesome subset as the .sh version.
$Icon = @{
    Time     = "`u{F252}"
    Model    = "`u{F2DB}"
    Effort   = "`u{F0E4}"
    Run      = "`u{F135}"
    Wall     = "`u{F254}"
    Api      = "`u{F233}"
    Cost     = "`u{F155}"
    Diff     = "`u{F12A}"
    Ctx      = "`u{F1C0}"
    Vim      = "`u{F121}"
    Agent    = "`u{F135}"
    Worktree = "`u{F1BB}"
    Style    = "`u{F0AD}"
    Repo     = "`u{F0E8}"
    Branch   = "`u{F126}"
    Stash    = "`u{F187}"
    Venv     = "`u{F1AE}"
    Gh       = "`u{F09B}"
    Skills   = "`u{F0AE}"
    Mcp      = "`u{F1E6}"
}

# Gruvbox Dark Hard 24-bit accents — match .sh version.
if ($ColorOn) {
    $Reset    = "`e[0m"
    $Dim      = "`e[2m"
    $Red      = "`e[38;2;251;73;52m"      # #fb4934
    $Green    = "`e[38;2;184;187;38m"     # #b8bb26
    $Yellow   = "`e[38;2;250;189;47m"     # #fabd2f
    $Blue     = "`e[38;2;131;165;152m"    # #83a598
    $Purple   = "`e[38;2;211;134;155m"    # #d3869b
    $Aqua     = "`e[38;2;142;192;124m"    # #8ec07c
    $Orange   = "`e[38;2;254;128;25m"     # #fe8019
    $Fg       = "`e[38;2;235;219;178m"    # #ebdbb2
    # Background variants for the vim-airline mode badge.
    $BgRed    = "`e[48;2;204;36;29m"      # #cc241d
    $BgBlue   = "`e[48;2;69;133;136m"     # #458588
    $BgYellow = "`e[48;2;215;153;33m"     # #d79921
    $BgOrange = "`e[48;2;214;93;14m"      # #d65d0e
    $BgGreen  = "`e[48;2;152;151;26m"     # #98971a
    $BgFg     = "`e[38;2;29;32;33m"       # #1d2021 — dark fg on bright bg
} else {
    $Reset = ''; $Dim = ''; $Red = ''; $Green = ''; $Yellow = ''; $Blue = ''
    $Purple = ''; $Aqua = ''; $Orange = ''; $Fg = ''
    $BgRed = ''; $BgBlue = ''; $BgYellow = ''; $BgOrange = ''; $BgGreen = ''; $BgFg = ''
}

$CacheDir = Join-Path ([System.IO.Path]::GetTempPath()) "claude-statusline-cache-$env:USERNAME"
[void](New-Item -ItemType Directory -Force -Path $CacheDir -ErrorAction SilentlyContinue)

# --- 1. Read JSON payload from stdin --------------------------------------
$payload = $null
if (-not [Console]::IsInputRedirected) {
    # No stdin (e.g. running by hand) — emit nothing useful.
} else {
    $raw = [Console]::In.ReadToEnd()
    if ($raw) {
        try { $payload = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $payload = $null }
    }
}

# Helper: safe nested property access with default.
function Get-Field($obj, [string]$path, $default = '') {
    if ($null -eq $obj) { return $default }
    $cur = $obj
    foreach ($seg in $path -split '\.') {
        if ($null -eq $cur) { return $default }
        $cur = $cur.PSObject.Properties[$seg]?.Value
    }
    if ($null -eq $cur -or $cur -eq '') { return $default }
    return $cur
}

$sessionId    = Get-Field $payload 'session_id'
$modelName    = Get-Field $payload 'model.display_name'
if (-not $modelName) { $modelName = Get-Field $payload 'model.id' }
$cwd          = Get-Field $payload 'workspace.current_dir'
if (-not $cwd) { $cwd = Get-Field $payload 'cwd' }
$effortLevel  = Get-Field $payload 'effort.level'
$vimMode      = Get-Field $payload 'vim.mode'
$agentName    = Get-Field $payload 'agent.name'
$worktreeName = Get-Field $payload 'workspace.git_worktree'
if (-not $worktreeName) { $worktreeName = Get-Field $payload 'worktree.name' }
$costUsd      = [double](Get-Field $payload 'cost.total_cost_usd' 0)
$totalMs      = [int64](Get-Field $payload 'cost.total_duration_ms' 0)
$apiMs        = [int64](Get-Field $payload 'cost.total_api_duration_ms' 0)
$ctxPct       = Get-Field $payload 'context_window.used_percentage'
$ctxSize      = Get-Field $payload 'context_window.context_window_size'
$outputStyle  = Get-Field $payload 'output_style.name'

# Cd into the workspace so git segments report the right repo.
if ($cwd -and (Test-Path $cwd)) {
    Set-Location -Path $cwd -ErrorAction SilentlyContinue
}

# --- Helpers --------------------------------------------------------------
function Format-Label([string]$color, [string]$icon, [string]$text) {
    if ($IconsOn) { return "$color$icon $text$Reset " }
    return "$color$text$Reset "
}

function Format-Ms([int64]$ms) {
    $s = [int]($ms / 1000)
    if ($s -ge 3600) { return ('{0}h{1}m' -f [int]($s/3600), [int](($s % 3600)/60)) }
    if ($s -ge 60)   { return ('{0}m' -f [int]($s/60)) }
    return ('{0}s' -f $s)
}

function Format-Tokens([int64]$n) {
    if ($n -ge 1000000) { return ('{0:N1}M' -f ($n/1000000.0)) }
    if ($n -ge 1000)    { return ('{0}k' -f [int]($n/1000)) }
    return [string]$n
}

# --- Pre-compute git state (per-cwd cache, 5s TTL) ------------------------
$GitInside = $false
$GitDirty = $false
$GitBranch = ''
$GitSync = ''
$GitStashCount = 0

$cwdHash = [System.BitConverter]::ToString(
    [System.Security.Cryptography.MD5]::HashData(
        [System.Text.Encoding]::UTF8.GetBytes((Get-Location).Path)
    )
).Replace('-','').Substring(0,16)
$gitCacheFile = Join-Path $CacheDir "git-$cwdHash.psd1"

$useCache = $false
if (Test-Path $gitCacheFile) {
    $age = (Get-Date) - (Get-Item $gitCacheFile).LastWriteTime
    if ($age.TotalSeconds -lt 5) {
        try {
            $cached = Import-PowerShellDataFile $gitCacheFile
            $GitInside     = [bool]$cached.GitInside
            $GitDirty      = [bool]$cached.GitDirty
            $GitBranch     = [string]$cached.GitBranch
            $GitSync       = [string]$cached.GitSync
            $GitStashCount = [int]$cached.GitStashCount
            $useCache = $true
        } catch { $useCache = $false }
    }
}

if (-not $useCache) {
    $null = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) {
        $GitInside = $true
        $gs = git status --porcelain=v2 --branch 2>$null
        $dirtyLines = @($gs | Where-Object { $_ -and $_ -notmatch '^#' })
        $GitDirty = $dirtyLines.Count -gt 0
        $branchHeader = $gs | Where-Object { $_ -match '^# branch\.head ' } | Select-Object -First 1
        if ($branchHeader) { $GitBranch = ($branchHeader -split '\s+')[2] }
        $abHeader = $gs | Where-Object { $_ -match '^# branch\.ab ' } | Select-Object -First 1
        if ($abHeader) {
            $parts = ($abHeader -split '\s+')
            $ahead = [int]($parts[2] -replace '^\+','')
            $behind = [int]($parts[3] -replace '^-','')
            if ($ahead -gt 0)  { $GitSync += "↑$ahead" }
            if ($behind -gt 0) { $GitSync += "↓$behind" }
        }
        if (-not $GitBranch -or $GitBranch -eq '(detached)') {
            $GitBranch = (git rev-parse --short HEAD 2>$null)
        }
        $stashList = git stash list 2>$null
        $GitStashCount = if ($stashList) { @($stashList).Count } else { 0 }
        # Persist cache (PowerShell data file format).
        try {
            $cacheData = "@{`n  GitInside = `$$GitInside`n  GitDirty = `$$GitDirty`n  GitBranch = '$($GitBranch -replace ""'"",""''"")'`n  GitSync = '$($GitSync -replace ""'"",""''"")'`n  GitStashCount = $GitStashCount`n}"
            Set-Content -Path $gitCacheFile -Value $cacheData -Encoding UTF8 -NoNewline
        } catch { }
    }
}

# --- Segment functions: each returns its rendered string (or '') ---------
function Seg-Time {
    "$(Format-Label $Yellow $Icon.Time 'Time')$Fg$(Get-Date -Format 'HH:mm:ss')$Reset"
}

function Seg-Model {
    if (-not $modelName) { return '' }
    $short = $modelName -replace '^claude-','' -replace '-internal$',''
    "$(Format-Label $Aqua $Icon.Model 'Model')$Fg$short$Reset"
}

function Seg-Effort {
    if (-not $effortLevel) { return '' }
    "$(Format-Label $Purple $Icon.Effort 'Effort')$Fg$effortLevel$Reset"
}

function Seg-Timer {
    if (-not $sessionId) { return '' }
    $f = Join-Path ([System.IO.Path]::GetTempPath()) "claude-statusline-$env:USERNAME-$sessionId.start"
    if (-not (Test-Path $f)) { Set-Content -Path $f -Value ([DateTimeOffset]::Now.ToUnixTimeSeconds()) -ErrorAction SilentlyContinue }
    if (-not (Test-Path $f)) { return '' }
    try {
        $started = [int64](Get-Content $f -ErrorAction Stop)
        $now = [DateTimeOffset]::Now.ToUnixTimeSeconds()
        $mins = [int](($now - $started) / 60)
        if ($mins -le 0) { return '' }
        "$(Format-Label $Orange $Icon.Run 'Run')$Fg${mins}m$Reset"
    } catch { '' }
}

function Seg-Cost {
    if ($costUsd -le 0) { return '' }
    $pretty = '${0:N2}' -f $costUsd
    "$(Format-Label $Green $Icon.Cost 'Cost')$Fg$pretty$Reset"
}

function Seg-Ctx {
    if (-not $ctxPct -or $ctxPct -eq '') { return '' }
    $pctInt = [int][math]::Floor([double]$ctxPct)
    $color = $Green
    if ($pctInt -ge 80) { $color = $Red }
    elseif ($pctInt -ge 50) { $color = $Yellow }
    $body = "$color$pctInt%$Reset"
    if ($ctxSize -and $ctxSize -ne 0) {
        $body += "$Dim/$(Format-Tokens ([int64]$ctxSize))$Reset"
    }
    "$(Format-Label $Aqua $Icon.Ctx 'Context')$body"
}

function Seg-Vim {
    if (-not $vimMode) { return '' }
    # vim-airline gruvbox mode palette: NORMAL=yellow, INSERT=blue, VISUAL=orange, REPLACE=red.
    $modeBg = $BgYellow
    switch -Regex ($vimMode) {
        '^(?i)insert'  { $modeBg = $BgBlue;   break }
        '^(?i)visual'  { $modeBg = $BgOrange; break }
        '^(?i)normal'  { $modeBg = $BgYellow; break }
        '^(?i)replace' { $modeBg = $BgRed;    break }
    }
    "$(Format-Label $Red $Icon.Vim 'Vim')$modeBg$BgFg $vimMode $Reset"
}

function Seg-Agent {
    if (-not $agentName) { return '' }
    "$(Format-Label $Purple $Icon.Agent 'Agent')$Fg$agentName$Reset"
}

function Seg-Worktree {
    if (-not $worktreeName) { return '' }
    "$(Format-Label $Aqua $Icon.Worktree 'Worktree')$Fg$worktreeName$Reset"
}

function Seg-Style {
    if (-not $outputStyle -or $outputStyle -eq 'default') { return '' }
    "$(Format-Label $Purple $Icon.Style 'Style')$Fg$outputStyle$Reset"
}

function Seg-Git {
    if (-not $GitInside) { return '' }
    $state = 'clean'; $stateColor = $Green
    if ($GitDirty) { $state = 'dirty'; $stateColor = $Yellow }
    if ($GitSync) {
        "$(Format-Label $Aqua $Icon.Repo 'Repo')$stateColor$state$Reset $Orange($GitSync)$Reset"
    } else {
        "$(Format-Label $Aqua $Icon.Repo 'Repo')$stateColor$state$Reset"
    }
}

function Seg-Branch {
    if (-not $GitInside -or -not $GitBranch) { return '' }
    $br = $GitBranch
    if ($br.Length -gt 24) { $br = $br.Substring(0,23) + '…' }
    "$(Format-Label $Yellow $Icon.Branch 'Branch')$Fg$br$Reset"
}

function Seg-Stash {
    if (-not $GitInside -or $GitStashCount -le 0) { return '' }
    "$(Format-Label $Orange $Icon.Stash 'Stash')$Fg$GitStashCount$Reset"
}

function Seg-Venv {
    if (-not $env:VIRTUAL_ENV) { return '' }
    "$(Format-Label $Blue $Icon.Venv 'Venv')$Fg$(Split-Path -Leaf $env:VIRTUAL_ENV)$Reset"
}

function Seg-Skills {
    $total = 0
    foreach ($d in @("$env:USERPROFILE\.claude\skills", "$((Get-Location).Path)\.claude\skills")) {
        if (Test-Path $d) {
            $total += @(Get-ChildItem $d -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notmatch '^\.' }).Count
        }
    }
    if ($total -le 0) { return '' }
    "$(Format-Label $Aqua $Icon.Skills 'Skills')$Fg$total$Reset"
}

function Seg-Mcp {
    $f = "$env:USERPROFILE\.claude.json"
    if (-not (Test-Path $f)) { return '' }
    try {
        $j = Get-Content $f -Raw | ConvertFrom-Json
        $count = ($j.mcpServers | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Count
        if (-not $count) { return '' }
        "$(Format-Label $Blue $Icon.Mcp 'MCP')$Fg$count$Reset"
    } catch { '' }
}

function Seg-Wall {
    if ($totalMs -le 0) { return '' }
    "$(Format-Label $Purple $Icon.Wall 'Wall')$Fg$(Format-Ms $totalMs)$Reset"
}

function Seg-Api { return '' }   # disabled, placeholder for parity
function Seg-Diff { return '' }
function Seg-Gh_account { return '' }

# --- Render ---------------------------------------------------------------
$out = New-Object System.Text.StringBuilder
foreach ($s in $Segments) {
    $fn = "Seg-$($s.Substring(0,1).ToUpper() + $s.Substring(1))"
    $part = & $fn 2>$null
    if (-not $part) { continue }
    if ($out.Length -gt 0) { [void]$out.Append("$Dim$Sep$Reset") }
    [void]$out.Append($part)
}

# `\r` snaps cursor to column 1 — same as the .sh version.
[Console]::Out.Write("`r$($out.ToString())")
