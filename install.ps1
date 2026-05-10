#!/usr/bin/env pwsh
# Windows installer for the dot-configs repo. Mirrors install.sh:
#   - top-level dotfiles (.tmux.conf, etc.) -> $HOME (skip on Windows since
#     these are POSIX-shell oriented; tmux/oh-my-zsh aren't native Win)
#   - copilot/* -> $HOME/.copilot/  (powershell statusline lands here)
#   - claude/*  -> $HOME/.claude/   (powershell statusline lands here)
#
# On Windows the .sh statusline is useless (no bash by default), and on
# POSIX the .ps1 is useless (no pwsh by default). So install.ps1 LINKS THE
# .ps1 VERSIONS and SKIPS the .sh siblings; install.sh does the inverse.
#
# Symlink requirements on Windows:
#   - PowerShell 7+ (pwsh, the new cross-platform PowerShell)
#   - Either Developer Mode enabled (Settings > Privacy & security >
#     For developers > Developer Mode), or run this script from an
#     elevated (Administrator) shell. Without one of those, New-Item
#     -ItemType SymbolicLink throws UnauthorizedAccessException.
#
# Usage:
#     pwsh -ExecutionPolicy Bypass -File install.ps1
#
# Idempotent: re-running is safe. Existing correctly-pointing symlinks are
# left alone; mismatched destinations are renamed to <name>.bak.<timestamp>
# before the new symlink is created.

$ErrorActionPreference = 'Stop'

$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$timestamp = Get-Date -Format 'yyyyMMddHHmmss'

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-DevMode {
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
        return ((Get-ItemProperty -Path $key -ErrorAction Stop).AllowDevelopmentWithoutDevLicense -eq 1)
    } catch { return $false }
}

if (-not (Test-IsAdmin) -and -not (Test-DevMode)) {
    Write-Warning @"
Neither Administrator privileges nor Developer Mode detected.
New-Item -ItemType SymbolicLink will likely fail.

Either:
  1. Re-run this script from an elevated PowerShell (right-click > Run as Administrator), or
  2. Enable Developer Mode: Settings > Privacy & security > For developers > Developer Mode = On.

Continuing anyway — failures will be reported per-file.
"@
}

# --- Helpers ---------------------------------------------------------------
function Backup-Path([string]$path) {
    if (Test-Path $path) {
        $bak = "$path.bak.$timestamp"
        Move-Item -Path $path -Destination $bak -Force
        Write-Host "  Backed up: $path -> $bak"
    }
}

function Link-File([string]$src, [string]$dst) {
    # If dst is already a symlink pointing at src, leave it alone.
    if (Test-Path $dst) {
        $item = Get-Item -Path $dst -Force
        if ($item.LinkType -eq 'SymbolicLink' -and $item.Target -eq $src) {
            Write-Host "  Already linked: $dst"
            return
        }
        Backup-Path $dst
    }
    try {
        New-Item -ItemType SymbolicLink -Path $dst -Target $src -Force | Out-Null
        Write-Host "  Linked: $dst -> $src"
    } catch {
        Write-Warning "  FAILED to link $dst -> $src : $_"
    }
}

function Link-Dir-Contents {
    param(
        [string]$srcDir,
        [string]$dstDir,
        [string[]]$skipNames = @(),
        [string[]]$skipExtensions = @()
    )
    if (-not (Test-Path $srcDir)) { return }
    if (-not (Test-Path $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    # If the source dir contains a settings-windows.json, that file gets
    # linked in place of settings.json — it carries Windows-specific paths
    # for statusLine.command (pwsh + .ps1) but is otherwise identical.
    $hasWinSettings = Test-Path (Join-Path $srcDir 'settings-windows.json')

    Get-ChildItem -Path $srcDir -File | ForEach-Object {
        $name = $_.Name
        $ext = $_.Extension
        if ($skipNames -contains $name) {
            Write-Host "  Skipped (excluded): $name"
            return
        }
        # Skip ".sh" siblings — POSIX-only counterpart of .ps1
        if ($skipExtensions -contains $ext) {
            return
        }
        # Skip README docs — they live in the repo, not in ~/.claude/
        if ($name -match '^README') { return }
        # On Windows, prefer settings-windows.json over settings.json.
        if ($hasWinSettings -and $name -eq 'settings.json') {
            Write-Host "  Skipped: settings.json (using settings-windows.json instead)"
            return
        }
        # The Windows variant lands at the canonical settings.json path so
        # Claude Code / Copilot CLI find it under the standard name.
        $dstName = if ($name -eq 'settings-windows.json') { 'settings.json' } else { $name }
        Link-File -src $_.FullName -dst (Join-Path $dstDir $dstName)
    }
}

# --- 1. Copilot ($HOME/.copilot/) -----------------------------------------
$copilotSrc  = Join-Path $srcDir 'copilot'
$copilotDest = Join-Path $env:USERPROFILE '.copilot'
if (Test-Path $copilotSrc) {
    Write-Host "Linking Copilot CLI config files -> $copilotDest"
    Link-Dir-Contents -srcDir $copilotSrc -dstDir $copilotDest -skipExtensions @('.sh')
} else {
    Write-Host "Skipping Copilot: source dir missing"
}

# --- 2. Claude Code ($HOME/.claude/) --------------------------------------
$claudeSrc  = Join-Path $srcDir 'claude'
$claudeDest = Join-Path $env:USERPROFILE '.claude'
if (Test-Path $claudeSrc) {
    Write-Host "Linking Claude Code config files -> $claudeDest"
    Link-Dir-Contents -srcDir $claudeSrc -dstDir $claudeDest -skipExtensions @('.sh')
} else {
    Write-Host "Skipping Claude Code: source dir missing"
}

# --- 3. WezTerm (opt-in) --------------------------------------------------
$weztermSrc = Join-Path $srcDir 'wezterm/wezterm.lua'
$weztermDst = Join-Path $env:USERPROFILE '.wezterm.lua'
if (Test-Path $weztermSrc) {
    Write-Host "Linking WezTerm config -> $weztermDst"
    Link-File -src $weztermSrc -dst $weztermDst
}

# --- 4. PowerShell profile (cc, gg, c, ll) --------------------------------
# We don't symlink $PROFILE itself — the user may have personal additions
# we shouldn't clobber. Instead we append a single dot-source line that
# pulls in our shared snippet. Idempotent: existing line is detected and
# skipped.
$profileSrc = Join-Path $srcDir 'powershell-profile.ps1'
$profileDst = $PROFILE.CurrentUserAllHosts
if (Test-Path $profileSrc) {
    Write-Host "Wiring PowerShell profile snippet (cc, gg, c, ll, claude-*)"
    $profileDir = Split-Path -Parent $profileDst
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    if (-not (Test-Path $profileDst)) {
        Set-Content -Path $profileDst -Value '' -Encoding UTF8
    }
    $sourceLine = ". `"$profileSrc`""
    $existing = Get-Content $profileDst -Raw -ErrorAction SilentlyContinue
    if ($existing -notmatch [regex]::Escape($profileSrc)) {
        Add-Content -Path $profileDst -Value "`n# dot-configs (auto-injected by install.ps1)`n$sourceLine`n"
        Write-Host "  Appended dot-source to $profileDst"
    } else {
        Write-Host "  Already wired: $profileDst"
    }
}

# --- 5. Inform user about the proxy ---------------------------------------
Write-Host ""
Write-Host "===================================================================="
Write-Host "Install complete."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Install the CLIs:"
Write-Host "       winget install OpenJS.NodeJS"
Write-Host "       npm install -g @anthropic-ai/claude-code copilot-api @github/copilot"
Write-Host ""
Write-Host "  2. Authenticate the proxy (one-time, browser device-code):"
Write-Host "       copilot-api auth"
Write-Host ""
Write-Host "  3. Start the proxy in a dedicated terminal (must stay running):"
Write-Host "       copilot-api start --claude-code"
Write-Host ""
Write-Host "  4. In another terminal, launch Claude Code:"
Write-Host "       claude"
Write-Host ""
Write-Host "Statusline files linked:"
Write-Host "  ~/.claude/statusline.ps1   (used by Claude Code)"
Write-Host "  ~/.copilot/statusline.ps1  (used by Copilot CLI)"
Write-Host ""
Write-Host "Both settings.json files reference the .ps1 versions on Windows."
Write-Host "===================================================================="
