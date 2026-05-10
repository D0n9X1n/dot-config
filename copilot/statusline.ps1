#!/usr/bin/env pwsh
# Custom status line for GitHub Copilot CLI on Windows (PowerShell 7+).
# Functional parity with copilot/statusline.sh — same segments, same Gruvbox
# accents, same per-cwd git cache, same model-name trimming.
#
# Wired via copilot/settings.json:
#   "statusLine": { "type": "command",
#                   "command": "pwsh -NoProfile -File ~/.copilot/statusline.ps1" }

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# --- Config ---------------------------------------------------------------
$Segments = if ($env:COPILOT_STATUSLINE_SEGMENTS) {
    $env:COPILOT_STATUSLINE_SEGMENTS -split '\s+'
} else {
    # Two-line layout: status segments line 1, repo/integrations line 2.
    # The literal '\n' token in the array introduces a line break.
    @('time','model','effort','timer','wall','api','premium','cache_pct',
      'last_call','ctx','vim','agent','style',
      '\n',
      'repo','branch','worktree','stash','venv','gh_account','ext_count','mcp_count')
}
$Sep = ' | '

$IconsOn = -not $env:COPILOT_STATUSLINE_NO_ICONS
$ColorOn = -not $env:COPILOT_STATUSLINE_NO_COLOR -and -not $env:COPILOT_STATUSLINE_NO_DIM

$Icon = @{
    Time     = "`u{F252}"
    Model    = "`u{F2DB}"
    Effort   = "`u{F0E4}"
    Run      = "`u{F135}"
    Wall     = "`u{F254}"
    Api      = "`u{F233}"
    Req      = "`u{F155}"
    Cache    = "`u{F021}"
    Last     = "`u{F1D8}"
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
    Ext      = "`u{F0AE}"
    Mcp      = "`u{F1E6}"
}

if ($ColorOn) {
    $Reset    = "`e[0m"
    $Dim      = "`e[2m"
    $Red      = "`e[38;2;251;73;52m"
    $Green    = "`e[38;2;184;187;38m"
    $Yellow   = "`e[38;2;250;189;47m"
    $Blue     = "`e[38;2;131;165;152m"
    $Purple   = "`e[38;2;211;134;155m"
    $Aqua     = "`e[38;2;142;192;124m"
    $Orange   = "`e[38;2;254;128;25m"
    $Fg       = "`e[38;2;235;219;178m"
} else {
    $Reset = ''; $Dim = ''; $Red = ''; $Green = ''; $Yellow = ''; $Blue = ''
    $Purple = ''; $Aqua = ''; $Orange = ''; $Fg = ''
}

$CacheDir = Join-Path ([System.IO.Path]::GetTempPath()) "copilot-statusline-cache-$env:USERNAME"
[void](New-Item -ItemType Directory -Force -Path $CacheDir -ErrorAction SilentlyContinue)

# --- 1. Read JSON payload from stdin --------------------------------------
$payload = $null
if ([Console]::IsInputRedirected) {
    $raw = [Console]::In.ReadToEnd()
    if ($raw) { try { $payload = $raw | ConvertFrom-Json -ErrorAction Stop } catch { } }
}

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

$sessionId   = Get-Field $payload 'session_id'
$sessionName = Get-Field $payload 'session_name'
$modelName   = Get-Field $payload 'model.display_name'
if (-not $modelName) { $modelName = Get-Field $payload 'model.id' }
$cwd         = Get-Field $payload 'workspace.current_dir'
if (-not $cwd) { $cwd = Get-Field $payload 'cwd' }
$premium     = [int64](Get-Field $payload 'cost.total_premium_requests' 0)
$apiMs       = [int64](Get-Field $payload 'cost.total_api_duration_ms' 0)
$totalMs     = [int64](Get-Field $payload 'cost.total_duration_ms' 0)
$linesAdded  = [int64](Get-Field $payload 'cost.total_lines_added' 0)
$linesRemoved= [int64](Get-Field $payload 'cost.total_lines_removed' 0)
$totalInput  = [int64](Get-Field $payload 'context_window.total_input_tokens' 0)
$cacheRead   = [int64](Get-Field $payload 'context_window.total_cache_read_tokens' 0)
$lastIn      = [int64](Get-Field $payload 'context_window.last_call_input_tokens' 0)
$lastOut     = [int64](Get-Field $payload 'context_window.last_call_output_tokens' 0)
$ctxPct      = Get-Field $payload 'context_window.used_percentage'
$ctxSize     = Get-Field $payload 'context_window.context_window_size'

if ($cwd -and (Test-Path $cwd)) {
    Set-Location -Path $cwd -ErrorAction SilentlyContinue
}

# Effort is appended to model name as " (xhigh)" / " (high)" / etc.
$effortLevel = ''
if ($modelName) {
    switch -Regex ($modelName) {
        '\(xhigh\)'  { $effortLevel = 'xhigh';  break }
        '\(high\)'   { $effortLevel = 'high';   break }
        '\(medium\)' { $effortLevel = 'medium'; break }
        '\(low\)'    { $effortLevel = 'low';    break }
    }
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
$GitWorktreeName = ''

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
            $GitInside       = [bool]$cached.GitInside
            $GitDirty        = [bool]$cached.GitDirty
            $GitBranch       = [string]$cached.GitBranch
            $GitSync         = [string]$cached.GitSync
            $GitStashCount   = [int]$cached.GitStashCount
            $GitWorktreeName = [string]$cached.GitWorktreeName
            $useCache = $true
        } catch { }
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
            $ahead  = [int]($parts[2] -replace '^\+','')
            $behind = [int]($parts[3] -replace '^-','')
            if ($ahead -gt 0)  { $GitSync += "↑$ahead" }
            if ($behind -gt 0) { $GitSync += "↓$behind" }
        }
        if (-not $GitBranch -or $GitBranch -eq '(detached)') {
            $GitBranch = (git rev-parse --short HEAD 2>$null)
        }
        $stashList = git stash list 2>$null
        $GitStashCount = if ($stashList) { @($stashList).Count } else { 0 }
        # Detect linked worktree
        $gd = git rev-parse --git-dir 2>$null
        if ($gd -match '/\.git/worktrees/([^/]+)') { $GitWorktreeName = $Matches[1] }
        try {
            $cacheData = "@{`n  GitInside = `$$GitInside`n  GitDirty = `$$GitDirty`n  GitBranch = '$($GitBranch -replace ""'"",""''"")'`n  GitSync = '$($GitSync -replace ""'"",""''"")'`n  GitStashCount = $GitStashCount`n  GitWorktreeName = '$($GitWorktreeName -replace ""'"",""''"")'`n}"
            Set-Content -Path $gitCacheFile -Value $cacheData -Encoding UTF8 -NoNewline
        } catch { }
    }
}

# --- Segment functions ----------------------------------------------------
function Seg-Time {
    "$(Format-Label $Yellow $Icon.Time 'Time')$Fg$(Get-Date -Format 'HH:mm:ss')$Reset"
}

function Seg-Model {
    if (-not $modelName) { return '' }
    # Trim Copilot's verbose names: "Claude Opus 4.7 (1M context)(Internal only) (10x) (xhigh)"
    # -> "Opus 4.7 (1M)"
    $short = $modelName -replace '^Claude ',''
    $short = $short -replace ' ?\(Internal only\)',''
    $short = $short -replace ' ?\([0-9]+x\)',''
    $short = $short -replace ' ?\((xhigh|high|medium|low)\)',''
    $short = $short -replace '\(([0-9.]+[KMG]?) context\)','($1)'
    $short = ($short -replace '  +',' ').TrimEnd()
    "$(Format-Label $Aqua $Icon.Model 'Model')$Fg$short$Reset"
}

function Seg-Effort {
    if (-not $effortLevel) { return '' }
    "$(Format-Label $Purple $Icon.Effort 'Effort')$Fg$effortLevel$Reset"
}

function Seg-Timer {
    if (-not $sessionId) { return '' }
    $f = Join-Path ([System.IO.Path]::GetTempPath()) "copilot-statusline-$env:USERNAME-$sessionId.start"
    if (-not (Test-Path $f)) {
        Set-Content -Path $f -Value ([DateTimeOffset]::Now.ToUnixTimeSeconds()) -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $f)) { return '' }
    try {
        $started = [int64](Get-Content $f -ErrorAction Stop)
        $now = [DateTimeOffset]::Now.ToUnixTimeSeconds()
        $mins = [int](($now - $started) / 60)
        if ($mins -le 0) { return '' }
        "$(Format-Label $Orange $Icon.Run 'Run')$Fg${mins}m$Reset"
    } catch { '' }
}

function Seg-Wall {
    if ($totalMs -le 0) { return '' }
    "$(Format-Label $Purple $Icon.Wall 'Wall')$Fg$(Format-Ms $totalMs)$Reset"
}

function Seg-Api {
    if ($apiMs -le 0) { return '' }
    "$(Format-Label $Blue $Icon.Api 'API')$Fg$(Format-Ms $apiMs)$Reset"
}

function Seg-Premium {
    if ($premium -le 0) { return '' }
    "$(Format-Label $Green $Icon.Req 'Req')$Fg$premium$Reset"
}

function Seg-Cache_pct {
    if ($totalInput -le 0) { return '' }
    $pct = [int](($cacheRead * 100) / $totalInput)
    $color = $Green
    if ($pct -lt 30)    { $color = $Red }
    elseif ($pct -lt 60) { $color = $Yellow }
    "$(Format-Label $Aqua $Icon.Cache 'Cache')$color$pct%$Reset"
}

function Seg-Last_call {
    if ($lastIn -le 0) { return '' }
    "$(Format-Label $Purple $Icon.Last 'Last')$Fg$(Format-Tokens $lastIn)→$(Format-Tokens $lastOut)$Reset"
}

function Seg-Diff {
    $a = $linesAdded; $r = $linesRemoved
    if ($a -le 0 -and $r -le 0) { return '' }
    "$(Format-Label $Green $Icon.Diff 'Diff')$Green+$a$Reset$Red/-$r$Reset"
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

# Copilot CLI doesn't surface vim/agent/style; kept as no-op for parity.
function Seg-Vim { return '' }
function Seg-Agent { return '' }
function Seg-Style { return '' }

function Seg-Worktree {
    if (-not $GitInside -or -not $GitWorktreeName) { return '' }
    "$(Format-Label $Aqua $Icon.Worktree 'Worktree')$Fg$GitWorktreeName$Reset"
}

function Seg-Repo {
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

function Seg-Gh_account {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return '' }
    $cf = Join-Path $CacheDir 'gh_account'
    $account = ''
    if (Test-Path $cf) {
        $age = (Get-Date) - (Get-Item $cf).LastWriteTime
        if ($age.TotalSeconds -lt 300) {
            $account = (Get-Content $cf -Raw -ErrorAction SilentlyContinue).Trim()
        }
    }
    if (-not $account) {
        $authOut = gh auth status 2>&1
        $line = $authOut | Select-String -Pattern 'Logged in to github\.com account ' | Select-Object -First 1
        if ($line) {
            $tokens = ($line.Line -split '\s+')
            for ($i = 0; $i -lt $tokens.Count; $i++) {
                if ($tokens[$i] -eq 'account' -and $i+1 -lt $tokens.Count) {
                    $account = $tokens[$i+1]; break
                }
            }
        }
        if ($account) { Set-Content -Path $cf -Value $account -ErrorAction SilentlyContinue }
    }
    if (-not $account) { return '' }
    "$(Format-Label $Purple $Icon.Gh 'GH')$Fg$account$Reset"
}

function Seg-Ext_count {
    $total = 0
    $seen = @{}
    $candidates = @(
        "$env:USERPROFILE\.copilot\extensions",
        "$env:USERPROFILE\.config\copilot\extensions",
        "$env:USERPROFILE\.config\github-copilot\extensions",
        "$((Get-Location).Path)\.github\extensions"
    )
    foreach ($d in $candidates) {
        if ($seen.ContainsKey($d)) { continue }
        $seen[$d] = $true
        if (Test-Path $d) {
            $total += @(Get-ChildItem -Path $d -Recurse -Depth 1 -Filter 'extension.mjs' -File -ErrorAction SilentlyContinue).Count
        }
    }
    if ($total -le 0) { return '' }
    "$(Format-Label $Aqua $Icon.Ext 'Ext')$Fg$total$Reset"
}

function Seg-Mcp_count {
    $f = "$env:USERPROFILE\.copilot\mcp-config.json"
    if (-not (Test-Path $f)) { return '' }
    try {
        $j = Get-Content $f -Raw | ConvertFrom-Json
        $count = ($j.mcpServers | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Count
        if (-not $count) { return '' }
        "$(Format-Label $Blue $Icon.Mcp 'MCP')$Fg$count$Reset"
    } catch { '' }
}

# --- Render ---------------------------------------------------------------
# A literal '\n' token in $Segments introduces a line break: segments before
# it form line 1, segments after it form line 2.
$out = New-Object System.Text.StringBuilder
$lineStarted = $false
foreach ($s in $Segments) {
    if ($s -eq '\n') {
        [void]$out.Append("`n")
        $lineStarted = $false
        continue
    }
    # Build the function name: snake_case -> "Seg-Snake_case" (PowerShell verb-noun convention)
    $fn = "Seg-$($s.Substring(0,1).ToUpper() + $s.Substring(1))"
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { continue }
    $part = & $fn 2>$null
    if (-not $part) { continue }
    if ($lineStarted) { [void]$out.Append("$Dim$Sep$Reset") }
    [void]$out.Append($part)
    $lineStarted = $true
}

[Console]::Out.Write("`r$($out.ToString())")
