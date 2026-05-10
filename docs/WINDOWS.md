# Windows setup

> **Status: experimental / community-maintained.**
> The maintainer develops on macOS. The PowerShell ports of `statusline.sh`
> (`claude/statusline.ps1`, `copilot/statusline.ps1`) and the `install.ps1`
> installer are 1:1 functional translations of the bash versions, but
> they are **not part of the regular test loop**. Expect rough edges on
> first run and please file an issue with the exact error if you hit one
> — most fixes will be small.

The supported install path is `install.sh` on macOS / Linux. This file is
for users who want the same statusline + Claude Code → Copilot proxy
bridge on a native Windows box.

## What you get on Windows

| Component        | Status                     | Notes |
|------------------|----------------------------|-------|
| Statusline       | ✅ PowerShell port shipped | Visual + functional parity with the .sh version: Gruvbox palette, vim-airline mode badge, per-cwd 5s git cache. ~30–80 ms render (Windows fork is slower than macOS). |
| install.ps1      | ✅ Shipped                 | Symlinks `.ps1` siblings + the Windows variant of `settings.json`. Skips `.sh` files. Idempotent. |
| Claude Code      | ✅ Works natively          | `npm install -g @anthropic-ai/claude-code` |
| copilot-api proxy| ✅ Works natively          | `npm install -g copilot-api` |
| GitHub Copilot CLI| ✅ Works natively         | `npm install -g @github/copilot` |
| `cc` / `gg` shortcuts | ✅ PowerShell functions | `cc <title>` / `gg <title>` rename the tab + launch Claude Code / Copilot. Auto-installed into `$PROFILE.CurrentUserAllHosts` via dot-source. |
| `c`, `ll` aliases | ✅ PowerShell             | `c` → `Set-Location ..`, `ll` → `Get-ChildItem`. From the same profile snippet. |
| oh-my-zsh-custom/| ❌ Not linked              | Zsh-only. The cc/gg/aliases above replace the most-used pieces. |
| `.tmux.conf`     | ❌ Not linked              | tmux is POSIX-only. Use Windows Terminal tabs / WezTerm panes. |
| WezTerm          | ✅ Optional                | Install via `winget install WezFurlong.WezTerm`; install.ps1 will symlink the config. |

## Prerequisites

1. **PowerShell 7+** (the cross-platform pwsh, not Windows PowerShell 5.1).
   Several script features (`?.` operator, `Get-Member -ErrorAction`,
   `BitConverter.ToString` patterns) require pwsh 7.

   ```powershell
   winget install Microsoft.PowerShell
   pwsh --version   # check: 7.x or higher
   ```

2. **Symlink permission.** `New-Item -ItemType SymbolicLink` requires
   either:

   - **Developer Mode** enabled — Settings → Privacy & security → For
     developers → Developer Mode = On. (Recommended; one-time, doesn't
     need every PowerShell session to be elevated.)
   - **OR** an elevated (Administrator) PowerShell session.

   Without one of these, `install.ps1` will report per-file
   `UnauthorizedAccessException` and produce no symlinks.

3. **Git for Windows** — `winget install Git.Git`. Provides `git.exe`,
   which the statusline and `install.ps1` both call.

4. **Node.js** — `winget install OpenJS.NodeJS`. Required to install the
   three CLIs below.

5. **A Nerd Font** in your terminal — the statusline icons are
   FontAwesome glyphs. Recursive Mono Nerd Font is the closest match to
   the macOS setup; download from
   <https://www.nerdfonts.com/font-downloads> and configure your terminal
   (Windows Terminal: Settings → Profiles → Defaults → Appearance →
   Font face).

## Step-by-step runbook

```powershell
# 0. Sanity
pwsh --version
git --version
node --version

# 1. Clone
mkdir $env:USERPROFILE\Public -ErrorAction SilentlyContinue
cd $env:USERPROFILE\Public
git clone git@github.com:D0n9X1n/dot-config.git dot-configs
cd dot-configs

# 2. Run the installer
pwsh -ExecutionPolicy Bypass -File .\install.ps1
# Expected output: a list of "Linked: ..." lines. If any line says
# "FAILED to link", check that you enabled Developer Mode (step 2 of
# Prerequisites above) and re-run.

# 3. Install the three CLIs
npm install -g @anthropic-ai/claude-code copilot-api @github/copilot
claude --version
copilot --version
copilot-api --version

# 4. Authenticate the proxy (one-time, browser device-code flow)
copilot-api auth

# 5. Start the proxy in a dedicated terminal — must stay running
#    Open a new Windows Terminal tab for this:
copilot-api start --claude-code

# 6. In another terminal, launch Claude Code
claude
# You should see the Gruvbox-colored statusline with a vim-airline
# mode badge in the bottom row of Claude Code's UI.
```

## How install.ps1 chooses files

The repo has both `.sh` and `.ps1` siblings, plus `settings.json` and
`settings-windows.json`. `install.ps1`:

1. Skips every `.sh` file.
2. Skips `settings.json` if `settings-windows.json` exists in the same
   folder, **and** symlinks `settings-windows.json` to the destination
   under the canonical name `settings.json`. (Claude Code / Copilot CLI
   only look at `settings.json` — they don't know about the variant.)
3. Skips `README*` files (those belong in the repo, not in `~/.claude/`).

The result on disk:

```
%USERPROFILE%\.claude\
├── settings.json     -> ...\dot-configs\claude\settings-windows.json
├── statusline.ps1    -> ...\dot-configs\claude\statusline.ps1
└── (no statusline.sh — skipped on Windows)

%USERPROFILE%\.copilot\
├── settings.json     -> ...\dot-configs\copilot\settings-windows.json
├── statusline.ps1    -> ...\dot-configs\copilot\statusline.ps1
└── copilot-instructions.md -> ...\dot-configs\copilot\copilot-instructions.md
```

## What `settings-windows.json` differs in

Only one field differs from the macOS `settings.json`:

```jsonc
"statusLine": {
  "type": "command",
  "command": "pwsh -NoProfile -File ~/.claude/statusline.ps1",  // was: "~/.claude/statusline.sh"
  ...
}
```

Everything else (env vars, model overrides, theme, vim mode, refresh
interval) is byte-identical to the macOS version. When you add a new
top-level key on macOS, **you must also add it to
`settings-windows.json`** — they're not auto-synced. (A future
improvement: have `install.ps1` derive the Windows variant on the fly
by editing the macOS `settings.json` in memory.)

## Shell setup

Windows users typically use PowerShell instead of zsh. `install.ps1`
auto-installs a profile snippet (`powershell-profile.ps1`) into
`$PROFILE.CurrentUserAllHosts` via dot-source, so it loads in every
PowerShell session. It defines:

- **`cc <title>`** — rename the active tab to `<title>` (via OSC 1/2
  + WezTerm + tmux), then launch Claude Code. Mirrors `oh-my-zsh-custom/cc.zsh`.
- **`gg <title>`** — same recipe, launches GitHub Copilot CLI with the
  always-on flags. Mirrors `oh-my-zsh-custom/gg.zsh`.
- **`c`** — `Set-Location ..` (zsh `c=cd ..` equivalent).
- **`ll`** — `Get-ChildItem` (zsh `ll=eza -l` equivalent — `eza` isn't
  on Windows, falls back to PowerShell's native listing).
- **`claude-opus`**, **`claude-gpt`** — model-pinned `claude` shortcuts.

The installer never overwrites your existing `$PROFILE`. It only appends
a single `. "<repo path>\powershell-profile.ps1"` line, marked with a
`# dot-configs (auto-injected by install.ps1)` comment for clarity.

If you want additional aliases or functions, add them to your own
`$PROFILE` — they'll coexist with the dot-sourced snippet.

## Troubleshooting

### `install.ps1` says "FAILED to link" for every file

You don't have Developer Mode on and aren't running as Administrator.
Either enable Developer Mode (Settings → Privacy & security → For
developers) or relaunch PowerShell as Administrator. Then re-run
`install.ps1` — it's idempotent and will pick up where it left off.

### Claude Code shows no statusline

Run the script directly to check it works:

```powershell
'{}' | pwsh -NoProfile -File $env:USERPROFILE\.claude\statusline.ps1
```

If you see a colored line of segments, the script is fine; if Claude Code
still doesn't show it, verify `~/.claude/settings.json`'s
`statusLine.command` field points at the .ps1 file (it should, since
install.ps1 linked the Windows variant).

### Statusline icons render as `?` or `□`

Your terminal isn't using a Nerd Font. Install one (see Prerequisites
step 5) and configure Windows Terminal / WezTerm to use it.

### Statusline runs slowly

The PowerShell version is inherently slower than bash on macOS (~30–80 ms
vs ~24 ms) because PowerShell startup is heavier. The 5-second git cache
helps; if it's still sluggish, increase `refreshInterval` in
`~/.claude/settings.json` (the linked `settings-windows.json` defaults
to 100 ms; try 200 or 300).

### `claude` command fails to start

Verify the proxy is running:

```powershell
curl.exe http://localhost:4141/v1/models
```

If that errors, you need to start `copilot-api start --claude-code` in
another terminal and leave it running.

### "command not found: pwsh" inside Claude Code

If Claude Code's process can't find `pwsh.exe`, the statusline command
will silently fail. Verify with:

```powershell
where.exe pwsh
```

If empty, the install path of PowerShell 7 isn't in your `PATH`. Either
add it (typically `C:\Program Files\PowerShell\7\`) or edit
`~/.claude/settings.json` to use the absolute path:

```jsonc
"command": "C:\\Program Files\\PowerShell\\7\\pwsh.exe -NoProfile -File ~/.claude/statusline.ps1"
```

## Reporting issues

If something doesn't work, please file an issue at
<https://github.com/D0n9X1n/dot-config/issues> with:

1. The output of `pwsh --version`, `git --version`, `claude --version`.
2. The exact command you ran and the exact error message.
3. Whether Developer Mode is on (`(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock').AllowDevelopmentWithoutDevLicense`).

The maintainer can't reproduce on Windows directly, so detailed reports
make fixes much faster.
