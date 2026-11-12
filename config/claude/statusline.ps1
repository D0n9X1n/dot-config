#!/usr/bin/env pwsh
# Custom status line for Claude Code on Windows (PowerShell 7+).
# Functional parity with config/claude/statusline.sh — same segments, same Gruvbox
# accents, same vim-airline mode badge, same per-cwd git cache.
#
# Claude Code feeds this script a JSON payload on stdin. We read fields
# via ConvertFrom-Json (PowerShell builtin — no jq dependency), do all
# rendering in process (no per-segment subshell forks), and emit one
# ANSI-colored line on stdout.
#
# Windows only. config/claude/settings.json keeps the macOS statusline.sh
# command; on Windows, set this in ~/.claude/settings.json:
#   "statusLine": { "type": "command",
#                   "command": "pwsh -NoProfile -File ~/.claude/statusline.ps1",
#                   "padding": 1, "refreshInterval": 100 }

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false  # don't blow up on git nonzero

# Force UTF-8 on BOTH stdin and stdout so Claude Code payload text and Nerd Font
# glyphs reach the terminal as real bytes instead of using the default ANSI codepage.
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# --- Config ---------------------------------------------------------------
# Two lines under a padding row. Line 1: model, effort, WakaTime, venv, and
# the context bar last. Line 2: the branch first (with its clean/dirty,
# ahead/behind and stash indicators), then the session Diff (lines added
# and removed), and the folder path at the right end. Every item has its
# Nerd Font icon and its label.
$Segments = @('model','effort','wakatime','venv','ctx')
$Line2    = @('branch','diff')
$Sep = " `u{2502} "   # thin rule, three columns wide

$IconsOn = -not $env:CLAUDE_STATUSLINE_NO_ICONS
$ColorOn = -not $env:CLAUDE_STATUSLINE_NO_COLOR

# Nerd Font icons (UTF-8). Same FontAwesome subset as the .sh version.
$Icon = @{
    Time     = "`u{F2F2}"
    Model    = "`u{F2DB}"
    Effort   = "`u{F0E4}"
    Run      = "`u{F135}"
    Wall     = "`u{F254}"
    Api      = "`u{F233}"
    Cost     = "`u{F155}"
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
    Wakatime = "`u{F017}"
    Diff     = "`u{F440}"
    Path     = "`u{F07C}"
}

# Gruvbox Dark 24-bit accents — match .sh version.
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
    $Fg       = "`e[38;2;235;219;178m"    # #ebdbb2 — values
    $Muted    = "`e[38;2;146;131;116m"    # #928374 Apollo dim — labels
    $Rule     = "`e[38;2;102;92;84m"      # #665c54 Apollo bright black — separators, empty bar cells
    # Background variants for the vim-airline mode badge.
    $BgRed    = "`e[48;2;204;36;29m"      # #cc241d
    $BgBlue   = "`e[48;2;69;133;136m"     # #458588
    $BgYellow = "`e[48;2;215;153;33m"     # #d79921
    $BgOrange = "`e[48;2;214;93;14m"      # #d65d0e
    $BgGreen  = "`e[48;2;152;151;26m"     # #98971a
    $BgFg     = "`e[38;2;29;32;33m"       # #1d2021 — dark fg on bright bg
} else {
    $Reset = ''; $Dim = ''; $Red = ''; $Green = ''; $Yellow = ''; $Blue = ''
    $Purple = ''; $Aqua = ''; $Orange = ''; $Fg = ''; $Muted = ''; $Rule = ''
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

function Get-SessionEffort($obj) {
    $id = Get-Field $obj 'session_id'
    $path = Get-Field $obj 'transcript_path'
    if ($id -notmatch '^[0-9a-fA-F-]{36}$' -or -not $path -or
        [IO.Path]::GetFileName($path) -cne "$id.jsonl") { return '' }
    $cachePath = Join-Path $CacheDir "effort-$id.json"
    $stream = $null
    try {
        $file = Get-Item -LiteralPath $path -ErrorAction Stop
        $state = @{ Version = 2; Path = $file.FullName; Created = $file.CreationTimeUtc.Ticks.ToString(); Offset = 0L; Level = ''; CommandId = ''; PromptId = '' }
        if (Test-Path -LiteralPath $cachePath) {
            try {
                $cached = Get-Content -LiteralPath $cachePath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                if ($cached.Version -eq $state.Version -and $cached.Path -ceq $state.Path -and $cached.Created -eq $state.Created -and
                    $cached.Offset -ge 0 -and $cached.Offset -le $file.Length) { $state = $cached }
            } catch { }
        }
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        $null = $stream.Seek([long]$state.Offset, [IO.SeekOrigin]::Begin)
        $pending = ''
        $buffer = New-Object byte[] 65536
        $decoder = [Text.UTF8Encoding]::new($false).GetDecoder()
        $characters = New-Object char[] 65540
        $offset = [long]$state.Offset
        $end = $stream.Length
        while ($stream.Position -lt $end) {
            $read = $stream.Read($buffer, 0, [int][Math]::Min($buffer.Length, $end - $stream.Position))
            if ($read -eq 0) { break }
            $decoded = $decoder.GetChars($buffer, 0, $read, $characters, 0)
            $parts = ($pending + [string]::new($characters, 0, $decoded)).Split([char]10)
            $pending = $parts[-1]
            for ($index = 0; $index -lt $parts.Length - 1; $index++) {
                $line = $parts[$index]
                $offset += [Text.Encoding]::UTF8.GetByteCount($line) + 1
                if (-not ($line.Contains('<command-name>/effort</command-name>') -or $line.Contains('<local-command-stdout>'))) { continue }
                try { $entry = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                if ($entry.type -cne 'user' -or $entry.sessionId -cne $id -or $entry.isSidechain -or
                    $entry.message.role -cne 'user' -or $entry.message.content -isnot [string]) { continue }
                $content = $entry.message.content
                if ($content -match '\A<command-name>/effort</command-name>\s*<command-message>effort</command-message>\s*<command-args>[^<]*</command-args>\z') {
                    $state.CommandId = [string]$entry.uuid
                    $state.PromptId = [string]$entry.promptId
                } elseif ($state.CommandId -and $entry.parentUuid -ceq $state.CommandId -and
                    $entry.promptId -ceq $state.PromptId -and $content.StartsWith('<local-command-stdout>')) {
                    $state.Level = ''
                    if ($content -match '\A<local-command-stdout>Set effort level to (low|medium|high|xhigh|max) \((?:this session only|saved as your default for new sessions)\):[^\r\n]*</local-command-stdout>\z') {
                        $state.Level = $Matches[1]
                    }
                    $state.CommandId = ''; $state.PromptId = ''
                }
            }
        }
        $state.Offset = $offset
        try { $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $cachePath -Encoding utf8 -ErrorAction Stop } catch { }
        if ($state.Level -cin @('low', 'medium', 'high', 'xhigh', 'max')) { return $state.Level }
    } catch { }
    finally { if ($stream) { $stream.Dispose() } }
    return ''
}

function Resolve-Effort($obj) {
    $levels = @('low', 'medium', 'high', 'xhigh', 'max')
    $live = Get-Field $obj 'effort.level'
    if ($live -is [string] -and $live -cin $levels) { return $live }
    # Some clients omit effort from statusline JSON even after a session-only change.
    $session = Get-SessionEffort $obj
    if ($session) { return $session }
    return 'unknown'
}

$sessionId    = Get-Field $payload 'session_id'
$modelName    = Get-Field $payload 'model.display_name'
if (-not $modelName) { $modelName = Get-Field $payload 'model.id' }
$cwd          = Get-Field $payload 'workspace.current_dir'
if (-not $cwd) { $cwd = Get-Field $payload 'cwd' }
$effortLevel  = Resolve-Effort $payload
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
    if ($IconsOn) { return "$color$icon $Muted$text$Reset " }
    return "$Muted$text$Reset "
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
function Seg-Model {
    if (-not $modelName) { return '' }
    $short = $modelName -replace '^claude-','' -replace '-internal$',''
    "$(Format-Label $Aqua $Icon.Model 'Model')$Fg$short$Reset"
}
function Seg-Effort {
    if (-not $effortLevel) { return '' }
    "$(Format-Label $Purple $Icon.Effort 'Effort')$Fg$effortLevel$Reset"
}




function Seg-Ctx {
    if (-not $ctxPct -or $ctxPct -eq '') { return '' }
    $pctInt = [int][math]::Floor([double]$ctxPct)
    $color = $Green
    if ($pctInt -ge 80) { $color = $Red }
    elseif ($pctInt -ge 50) { $color = $Yellow }
    $body = "$(Format-Bar $pctInt $color) $color$pctInt%$Reset"
    if ($ctxSize -and $ctxSize -ne 0) {
        $body += "$Muted of $(Format-Tokens ([int64]$ctxSize))$Reset"
    }
    "$(Format-Label $Blue $Icon.Ctx 'Context')$body"
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
    "$(Format-Label $Green $Icon.Worktree 'Worktree')$Fg$worktreeName$Reset"
}

function Seg-Style {
    if (-not $outputStyle -or $outputStyle -eq 'default') { return '' }
    "$(Format-Label $Purple $Icon.Style 'Style')$Fg$outputStyle$Reset"
}


function Seg-Branch {
    # Branch with its indicators: ✓ clean or ● dirty, ahead/behind, and the
    # stash icon with the count only when there are stashes.
    if (-not $GitInside) { return '' }
    $br = if ($GitBranch) { $GitBranch } else { 'detached' }
    if ($br.Length -gt 24) { $br = $br.Substring(0,23) + "`u{2026}" }
    $state = if ($IconsOn) {
        if ($GitDirty) { "$Yellow`u{25CF}$Reset" } else { "$Green`u{2713}$Reset" }
    } else {
        if ($GitDirty) { "${Yellow}dirty$Reset" } else { "${Green}clean$Reset" }
    }
    $body = "$(Format-Label $Orange $Icon.Branch 'Branch')$Fg$br$Reset $state"
    if ($GitSync) { $body += " $Aqua$GitSync$Reset" }
    if ($GitStashCount -gt 0) {
        $body += if ($IconsOn) { " $Purple$($Icon.Stash) $GitStashCount$Reset" } else { " ${Purple}stash $GitStashCount$Reset" }
    }
    $body
}


function Seg-Venv {
    if (-not $env:VIRTUAL_ENV) { return '' }
    "$(Format-Label $Green $Icon.Venv 'Venv')$Fg$(Split-Path -Leaf $env:VIRTUAL_ENV)$Reset"
}

function Get-PathText {
    # $cwd comes from the payload; fall back to $PWD. Home shows as ~.
    $p = if ($cwd) { [string]$cwd } else { [string]$PWD }
    if (-not $p) { return '' }
    $home_ = $env:USERPROFILE
    if ($home_ -and $p.StartsWith($home_, [StringComparison]::OrdinalIgnoreCase)) { $p = '~' + $p.Substring($home_.Length) }
    $p
}

# Plugin skills + agents — enabled plugins also load
# <installPath>\skills\<name>\SKILL.md and <installPath>\agents\<name>.md.
# installed_plugins.json maps each plugin to its installPath; enabledPlugins
# in user, project, and local settings (later wins) turns it on. Counts are
# cached per cwd, keyed by the mtimes of those files, so a render parses JSON
# only when a plugin is installed, updated, or toggled. Seg-Skills and
# Seg-Agents share one result per render.
$script:PluginCounts = $null





function Seg-Wall {
    if ($totalMs -le 0) { return '' }
    "$(Format-Label $Purple $Icon.Wall 'Wall')$Fg$(Format-Ms $totalMs)$Reset"
}

function Seg-Api { return '' }   # disabled, placeholder for parity

# Today's coding time from Wakatime (60s cache).
# Endpoint: GET /api/v1/users/current/summaries?start=today&end=today
# Reads cumulative_total.seconds and formats as "Xh Ym" / "Xm".
# WakaTime API keys are write-only (plugins), so reads use the OAuth access
# token in $env:WAKATIME_OAUTH_TOKEN (scope read_summaries); never api_key.
function Seg-Wakatime {
    $cf = Join-Path $CacheDir 'wakatime.txt'
    $text = ''
    if ((Test-Path $cf) -and (((Get-Date) - (Get-Item $cf).LastWriteTime).TotalSeconds -lt 60)) {
        try { $text = (Get-Content $cf -Raw -ErrorAction SilentlyContinue).Trim() } catch { }
    }
    if (-not $text) {
        $token = "$env:WAKATIME_OAUTH_TOKEN".Trim()
        if (-not $token) { return '' }
        try {
            $resp = Invoke-RestMethod `
                -Uri 'https://api.wakatime.com/api/v1/users/current/summaries?start=today&end=today' `
                -Headers @{ Authorization = "Bearer $token" } `
                -TimeoutSec 3 -ErrorAction Stop
            $secs = [int]$resp.cumulative_total.seconds
            if ($secs -ge 3600) {
                $h = [int]($secs / 3600)
                $m = [int](($secs % 3600) / 60)
                $text = "${h}h${m}m"
            } else {
                $text = ('{0}m' -f [int]($secs / 60))
            }
            Set-Content -Path $cf -Value $text -Encoding UTF8 -NoNewline -ErrorAction SilentlyContinue
        } catch { return '' }
    }
    if (-not $text) { return '' }
    "$(Format-Label $Yellow $Icon.Wakatime 'WakaTime')$Fg$text$Reset"
}
function Seg-Gh_account { return '' }

# --- Layout helpers -------------------------------------------------------
# Ten-cell bar for a percentage: filled cells in the level color, the rest dim.
function Format-Bar([int]$pct, [string]$color) {
    $n = [math]::Max(0, [math]::Min(10, [int][math]::Round($pct / 10.0)))
    "$color$([string]"`u{25B0}" * $n)$Reset$Rule$([string]"`u{25B1}" * (10 - $n))$Reset"
}

# Visible width of a rendered string (ANSI color codes take no columns).
function Get-VisibleWidth([string]$s) { ($s -replace "`e\[[0-9;]*m", '').Length }

# Shorten a path to $max columns from the left, keeping whole folder names.
function Format-PathText([string]$p, [int]$max) {
    if ($max -le 0 -or $p.Length -le $max) { return $p }
    if ($max -le 1) { return "`u{2026}" }
    $tail = $p.Substring($p.Length - ($max - 1))
    $i = $tail.IndexOfAny([char[]]'\/')
    if ($i -gt 0 -and $i -lt $tail.Length - 1) { $tail = $tail.Substring($i) }
    "`u{2026}$tail"
}

# Line 2: the git segments on the left and the folder path at the right end.
# With a known width (COLUMNS) the path is right-aligned and shortened to
# fit; otherwise it follows the git segments after the separator.
function Format-PathLine([string]$left, [string]$pathText) {
    if (-not $pathText) { return $left }
    $prefix = Format-Label $Aqua $Icon.Path 'Path'
    $cols = 0
    [void][int]::TryParse("$env:COLUMNS", [ref]$cols)
    if ($cols -gt 0 -and $left) {
        $usable = $cols - 6   # the CLI pads the statusline on both sides; keep a margin
        $room = $usable - (Get-VisibleWidth $left) - $Sep.Length - (Get-VisibleWidth $prefix)
        if ($room -ge 8) {
            $shown = Format-PathText $pathText $room
            $gap = $usable - (Get-VisibleWidth $left) - (Get-VisibleWidth $prefix) - $shown.Length
            return "$left$(' ' * [math]::Max($Sep.Length, $gap))$prefix$Fg$shown$Reset"
        }
    }
    if (-not $left) { return "$prefix$Fg$pathText$Reset" }
    "$left$Rule$Sep$Reset$prefix$Fg$pathText$Reset"
}
# Code changes in this session: lines added and removed (nonzero parts only).
function Seg-Diff {
    $a = [int64](Get-Field $payload 'cost.total_lines_added' 0)
    $r = [int64](Get-Field $payload 'cost.total_lines_removed' 0)
    if ($a -le 0 -and $r -le 0) { return '' }
    $parts = @()
    if ($a -gt 0) { $parts += "$Green+$a$Reset" }
    if ($r -gt 0) { $parts += "$Red-$r$Reset" }
    "$(Format-Label $Blue $Icon.Diff 'Diff')$($parts -join ' ')"
}
# One rendered line: the named segments that have data, joined by $Sep.
function Format-SegmentLine([string[]]$names) {
    $parts = foreach ($s in $names) {
        $fn = "Seg-$($s.Substring(0,1).ToUpper() + $s.Substring(1))"
        $part = & $fn 2>$null
        if ($part) { $part }
    }
    @($parts) -join "$Rule$Sep$Reset"
}
# --- Render ---------------------------------------------------------------
$lines = @((Format-SegmentLine $Segments), (Format-PathLine (Format-SegmentLine $Line2) (Get-PathText))) | Where-Object { $_ }

# `\r` snaps the cursor to column 1. A padding row, then line 1 (session) and
# line 2 (branch and folder). The padding is a non-breaking space (U+00A0)
# so Claude Code's whitespace trim keeps it (a truly empty line gets
# stripped); NBSP renders invisibly.
$nbsp = [char]0x00A0
[Console]::Out.Write("`r$nbsp`n$($lines -join "`n")")