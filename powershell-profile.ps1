# PowerShell profile snippet — Windows counterpart of oh-my-zsh-custom/.
#
# install.ps1 dot-sources this from $PROFILE.CurrentUserAllHosts so it loads
# in every PowerShell session (pwsh and Windows PowerShell, console and ISE).
# Hand-edits to your own $PROFILE are preserved — install.ps1 only appends a
# single `. "<repo path>\powershell-profile.ps1"` line, never overwrites.

# --- Aliases (mirror oh-my-zsh-custom/custom.zsh) -------------------------
Set-Alias ll Get-ChildItem -Force -ErrorAction SilentlyContinue
function global:c { Set-Location .. }

# --- gg <title>: rename tab + launch GitHub Copilot CLI -------------------
# Mirrors oh-my-zsh-custom/gg.zsh. Sets the active terminal tab/window
# title to <title> via OSC 1/2 escapes, also tells WezTerm + tmux directly
# so the title sticks even when nested, then runs `copilot` with the same
# always-on flags the macOS version uses.
function global:gg {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Title
    )
    # OSC 2 = window title, OSC 1 = icon/tab title. \a (BEL) terminator
    # is the broadly-supported variant; ST is also valid but BEL travels
    # through more wrappers.
    $bel = [char]7
    [Console]::Write("`e]2;$Title$bel")
    [Console]::Write("`e]1;$Title$bel")

    if ($env:TMUX) {
        & tmux rename-window -- $Title 2>$null
    }
    if ($env:WEZTERM_PANE -and (Get-Command wezterm -ErrorAction SilentlyContinue)) {
        & wezterm cli set-tab-title -- $Title 2>$null
        & wezterm cli set-window-title -- $Title 2>$null
    }
    # Windows Terminal: title is also settable via the OSC above; no extra
    # call needed. Same for ConEmu / Alacritty / WezTerm direct.

    & copilot --allow-all-tools --allow-all-paths --effort xhigh
}

# --- cc <title>: rename tab + launch Claude Code CLI ----------------------
# Mirrors oh-my-zsh-custom/cc.zsh. Same recipe as gg, but launches
# `claude` instead. Model + effort are pinned globally in
# ~/.claude/settings.json; --permission-mode bypassPermissions is the
# only path the binary honors for non-interactive permission bypass.
function global:cc {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Title
    )
    $bel = [char]7
    [Console]::Write("`e]2;$Title$bel")
    [Console]::Write("`e]1;$Title$bel")

    if ($env:TMUX) {
        & tmux rename-window -- $Title 2>$null
    }
    if ($env:WEZTERM_PANE -and (Get-Command wezterm -ErrorAction SilentlyContinue)) {
        & wezterm cli set-tab-title -- $Title 2>$null
        & wezterm cli set-window-title -- $Title 2>$null
    }

    & claude --permission-mode bypassPermissions
}

# --- claude convenience aliases (mirror oh-my-zsh-custom/claude.zsh) -----
# Bare `claude` is also a wrapper that auto-applies bypass mode.
function global:claude { & (Get-Command claude -CommandType Application) --permission-mode bypassPermissions @args }
function global:claude-opus { claude --model claude-opus-4.7-xhigh @args }
function global:claude-gpt  { claude --model gpt-5.5 @args }
