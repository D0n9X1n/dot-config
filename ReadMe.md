# dot-configs

[![CI](https://github.com/D0n9X1n/dot-config/actions/workflows/ci.yml/badge.svg)](https://github.com/D0n9X1n/dot-config/actions/workflows/ci.yml)
[![Release](https://github.com/D0n9X1n/dot-config/actions/workflows/release.yml/badge.svg)](https://github.com/D0n9X1n/dot-config/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/D0n9X1n/dot-config?sort=semver&color=fe8019)](https://github.com/D0n9X1n/dot-config/releases/latest)
[![License](https://img.shields.io/github/license/D0n9X1n/dot-config?color=b8bb26)](./LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/D0n9X1n/dot-config?color=83a598)](https://github.com/D0n9X1n/dot-config/commits/main)
[![Repo size](https://img.shields.io/github/repo-size/D0n9X1n/dot-config?color=d3869b)](https://github.com/D0n9X1n/dot-config)
[![Platform](https://img.shields.io/badge/platform-macOS-1d2021?logo=apple&logoColor=ebdbb2)](#)
[![Made with Bash](https://img.shields.io/badge/made%20with-bash-fabd2f?logo=gnubash&logoColor=1d2021)](#)
[![ShellCheck](https://img.shields.io/badge/lint-shellcheck-8ec07c?logo=gnubash&logoColor=1d2021)](https://www.shellcheck.net/)
[![Gruvbox](https://img.shields.io/badge/theme-gruvbox%20dark%20hard-fb4934)](#)

Personal dotfiles repository. Single source of truth for shell, terminal, and
editor configuration; synced across machines via git + an idempotent installer
that creates symlinks into the home directory.

## Repository layout

```
dot-configs/
├── install.sh                   # idempotent linker (macOS only)
├── .tmux.conf                   # -> ~/.tmux.conf  (tab/split/session manager)
├── oh-my-zsh-custom/            # contents -> ~/.oh-my-zsh/custom/
│   ├── custom.zsh               # aliases, proxy helpers, brew completions, env
│   ├── copilot.zsh              # copilot update wrapper -> cleanup hook
│   └── gg.zsh                   # gg() function (terminal title + copilot)
├── copilot/                     # contents -> ~/.copilot/
│   ├── settings.json            # Copilot CLI settings
│   ├── statusline.sh            # statusline (bash 3.2+)
│   ├── cleanup-legacy.sh        # prune stale Copilot CLI upgrade payloads
│   └── copilot-instructions.md  # global agent instructions
├── claude/                      # contents -> ~/.claude/
│   ├── settings.json            # Claude Code settings
│   └── statusline.sh            # statusline
├── wezterm/                     # terminal config (NOT auto-linked — opt-in)
│   └── wezterm.lua              # WezTerm config — link manually if used
├── themes/apollo/               # Apollo theme (wezterm/vim/nvim/vscode/wt) — reference, not auto-linked
├── launchd/                     # macOS launchd agent templates
│   └── com.d0n9x1n.copilot-relay.plist  # copilot-relay proxy on login (rendered by install.sh)
├── mcp-shared.json              # secret-free MCP entries synced via git
├── .claude/CLAUDE.md            # agent instructions for Claude Code working in this repo
├── .github/copilot-instructions.md  # agent instructions for Copilot CLI
├── LICENSE
├── ReadMe.md                    # this file
└── QUICKREF.md                  # condensed reference (agent-friendly)
```

`install.sh` is the only entry point (macOS-only). It uses symlinks so
the live config tracks repo edits, and is idempotent.

`install.sh` is the only entry point. It:

`install.sh` writes timestamped output to
`~/Library/Logs/dot-configs-install.log` (override with
`DOT_CONFIGS_INSTALL_LOG=/path/to/log`).

1. Installs required macOS apps and fonts via Homebrew (best-effort; failures
   are logged but never abort the install). Set `SKIP_BREW=1` to skip this
   step entirely (useful for CI / fake-`HOME` testing). Casks: `wezterm`,
   the Recursive font family, Symbols Only Nerd Font, Noto Color Emoji.
   Formulae: `tmux`.
2. Symlinks every **top-level** dotfile in this repo (files starting with `.`)
   into `$HOME` (currently `.tmux.conf`, plus the existing `.gitignore` /
   `.DS_Store` pass-through which has been there since v0.1).
3. Symlinks every file in `oh-my-zsh-custom/` into `~/.oh-my-zsh/custom/`.
   Skipped (with a warning) if `~/.oh-my-zsh/custom/` does not exist.
4. Symlinks every file in `copilot/` into `~/.copilot/`. Skipped (with a
   warning) if `~/.copilot/` does not exist. Preserves the executable bit on
   `*.sh` files (so `statusline.sh` runs without re-chmod), then runs
   `cleanup-legacy.sh` to prune stale Copilot CLI package versions/logs.
5. Symlinks every file in `claude/` into `~/.claude/`. **Creates the
   destination directory if missing** (Claude Code only creates `~/.claude/`
   on first launch; mkdir-p so install.sh wires things up on a fresh box).
   `settings.json` is the one exception — instead of a plain symlink it is
   **generated** by jq-merging the committed `claude/settings.json` with
   the local `~/.config/github-copilot/mcp.json` so Claude Code sees the
   exact same MCP servers Copilot CLI does, without committing
   secret-bearing MCP env (e.g. `WAKATIME_API_KEY`) to this public repo.
   Falls back to a plain symlink if `jq` or `mcp.json` is missing.
6. Bootstraps **TPM** (Tmux Plugin Manager): clones it under `~/.tmux/plugins/tpm`
   if missing, then runs `tpm/bin/install_plugins` to clone every plugin
   listed in `.tmux.conf`. Skipped if `tmux` isn't on PATH.
7. Backs up any existing destination file or symlink that doesn't already point
   at the repo as `<name>.bak.YYYYMMDDHHMMSS` before linking.
8. Leaves correctly-pointing symlinks alone (no-op).

> **`wezterm/` is intentionally not auto-linked.** The `wezterm` cask is
> still auto-installed so the terminal is one symlink away. Manually opt in
> with:
>
> ```bash
> ln -sfn "$(pwd)/wezterm/wezterm.lua" ~/.wezterm.lua
> ```

Safe to re-run at any time. Pulling new commits automatically takes effect on
all machines because every config file is a symlink into this repo.

## Usage

```bash
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
bash ~/Public/dot-configs/install.sh
```

macOS only.

Subsequent updates on a machine:

```bash
cd ~/Public/dot-configs && git pull
# Re-run install.sh only if new files were added; existing symlinks need no action.
```

## Fresh-devbox runbook (agent-friendly)

Step-by-step setup on a brand-new macOS box. An agent (or human) can follow
this top-to-bottom with no prior context. **Each step is verifiable** — run
the check command before moving on. Stop at the first failure and report.

### 0. Prerequisites

```bash
# macOS only.
xcode-select --install            # Apple CLI tools (provides git, make, etc.)
xcode-select -p                   # check: should print a path
```

If Homebrew isn't installed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew --version                    # check: prints "Homebrew x.y.z"
```

If `git` isn't authenticated for github.com:

```bash
gh auth login                     # or: configure ssh keys per your standard
ssh -T git@github.com 2>&1 | grep -q "successfully authenticated" \
  && echo "ok" || echo "FAIL: github auth needed"
```

### 1. Clone the repo

```bash
mkdir -p ~/Public
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
test -f ~/Public/dot-configs/install.sh && echo "ok" || echo "FAIL: clone failed"
```

### 2. Install oh-my-zsh (required before step 3 if you want zsh customizations)

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
test -d ~/.oh-my-zsh/custom && echo "ok" || echo "FAIL: oh-my-zsh missing"
```

### 3. Run the installer

```bash
bash ~/Public/dot-configs/install.sh
```

Verify symlinks landed:

```bash
ls -l ~/.tmux.conf ~/.oh-my-zsh/custom/custom.zsh 2>&1 | grep -q "dot-configs" \
  && echo "ok" || echo "FAIL: symlinks missing"
```

### 4. Install the CLIs and proxy (Claude Code + GitHub Copilot)

```bash
# Node + npm via Homebrew (skip if already present).
command -v node >/dev/null || brew install node
node --version                    # check: v22+ required by copilot-relay

# CLIs themselves. install.sh manages copilot-relay separately below.
npm install -g @anthropic-ai/claude-code @github/copilot
claude --version                  # check: prints version
copilot --version                 # check: prints version

# Re-run after Node is present: installs or updates copilot-relay, writes
# ~/.copilot-relay/config.yaml, removes legacy proxy launchd jobs, and loads
# the relay launchd agent.
bash ~/Public/dot-configs/install.sh
npm list -g copilot-relay --depth=0 # check: prints installed relay version
```

### 5. Authenticate the proxy (one-time, browser device-code flow)

```bash
copilot-relay auth                   # opens browser; enter the device code
# Verify token landed:
test -f ~/.copilot-relay/github_token && echo "ok" || echo "FAIL: auth incomplete"
```

### 6. Start the proxy daemon (must stay running for Claude Code)

If you ran `install.sh` after step 4, **the launchd agent is already
loaded** and the proxy is running — skip ahead. The agent
(`com.d0n9x1n.copilot-relay`) starts on every login, restarts on crash,
and logs to `~/Library/Logs/copilot-relay.{out,err}.log` plus
`~/.copilot-relay/logs/copilot-relay.log`. Verify:

```bash
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay" | grep state
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4142/healthz  # expect 200
```

If you want to manage the agent manually:

```bash
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.d0n9x1n.copilot-relay.plist
launchctl bootout   "gui/$(id -u)" ~/Library/LaunchAgents/com.d0n9x1n.copilot-relay.plist
launchctl kickstart -k "gui/$(id -u)/com.d0n9x1n.copilot-relay"   # restart in place
tail -f ~/Library/Logs/copilot-relay.{out,err}.log ~/.copilot-relay/logs/copilot-relay.log
```

For a one-off foreground run (debugging, no auto-restart):

```bash
copilot-relay start &
sleep 2
curl -s http://127.0.0.1:4142/healthz | head -c 100 \
  && echo "" || echo "FAIL: proxy not responding on :4142"
```

### 7. Wire up MCP servers (optional but recommended)

This repo handles MCP servers in two layers:

- **Synced, secret-free entries** live in `mcp-shared.json` at the repo
  root. install.sh merges them into your local Copilot MCP config on
  every install, then the existing pipeline imports the result into
  Claude Code's `~/.claude.json`. Add anything that's safe to commit
  (URL-only HTTP MCPs, public NPM stdio commands) here.
- **Per-machine entries with secrets** (PATs, API keys) live ONLY in
  the gitignored `~/.config/github-copilot/mcp.json`. install.sh's merge
  preserves them.

Confirm everything got wired:

```bash
test -f ~/.config/github-copilot/mcp.json && echo "Copilot MCP file present"
jq '.mcpServers | keys' ~/.claude.json   # should list servers
```

**GitHub MCP setup (special case):** GitHub's hosted MCP at
`https://api.githubcopilot.com/mcp/` does NOT support OAuth Dynamic
Client Registration with Anthropic's SDK. Use Bearer-PAT auth instead.
The template entry is documented in `mcp-shared.json` under
`_github_template`. To enable it on a device:

```bash
PAT='github_pat_XXXXX'   # create at https://github.com/settings/personal-access-tokens/new
jq --arg pat "$PAT" '.mcpServers.github = {
  type: "http",
  url: "https://api.githubcopilot.com/mcp/",
  headers: { Authorization: ("Bearer " + $pat) }
}' ~/.config/github-copilot/mcp.json > /tmp/mcp.json \
  && mv /tmp/mcp.json ~/.config/github-copilot/mcp.json
bash ~/Public/dot-configs/install.sh    # re-import into ~/.claude.json
```

Then restart Claude Code; `/mcp` should show `github ✓ ready`.

### 8. Optional: WezTerm (terminal)

`install.sh` installs the wezterm cask but does **not** symlink the config
(opt-in). To enable:

```bash
ln -sfn ~/Public/dot-configs/wezterm/wezterm.lua ~/.wezterm.lua
# Open WezTerm; verify Gruvbox dark hard scheme is active.
```

### 8.5. Optional: Apollo theme (wezterm / vim / neovim / vscode / windows terminal)

Apollo lives at `themes/apollo/`. `PALETTE.md` is the single source of
truth — every editor file mirrors it. `install.sh` does **not** wire
these up; install per-editor manually (one-time per machine).

```bash
THEMES=~/Public/dot-configs/themes/apollo

# Vim
mkdir -p ~/.vim/colors
ln -sfn "$THEMES/apollo.vim" ~/.vim/colors/apollo.vim
# then in .vimrc:  colorscheme apollo

# Neovim (any nvim config — drop into a `colors/` on rtp)
mkdir -p ~/.config/nvim/colors
ln -sfn "$THEMES/apollo.nvim.lua" ~/.config/nvim/colors/apollo.lua
# then in init.lua:  vim.cmd('colorscheme apollo')

# WezTerm — already wired via wezterm/wezterm.lua (#141617 bg). To use
# the standalone scheme instead, in wezterm.lua:
#   local apollo = dofile(os.getenv("HOME") .. "/Public/dot-configs/themes/apollo/apollo.lua")
#   config.color_schemes = { Apollo = apollo }
#   config.color_scheme  = "Apollo"

# VS Code — local extension (NOT synced via Settings Sync; copy per machine)
EXT=~/.vscode/extensions/apollo-theme-0.0.1
mkdir -p "$EXT/themes"
cp "$THEMES/apollo-color-theme.json" "$EXT/themes/"
cat > "$EXT/package.json" <<'JSON'
{
  "name": "apollo-theme", "displayName": "Apollo", "version": "0.0.1",
  "publisher": "local", "engines": {"vscode": "^1.60.0"},
  "categories": ["Themes"],
  "contributes": {"themes": [{"label": "Apollo", "uiTheme": "vs-dark",
    "path": "./themes/apollo-color-theme.json"}]}
}
JSON
# then in VS Code settings.json:  "workbench.colorTheme": "Apollo"
# Reload window (⌘⇧P → Developer: Reload Window).

# Windows Terminal — paste themes/apollo/apollo.terminal.json into the
# "schemes" array in settings.json, then set "colorScheme": "Apollo"
# on the profile(s) you want.
```

### 9. Optional: tmux plugins

`install.sh` runs TPM bootstrap automatically. Verify:

```bash
ls ~/.tmux/plugins/ | head        # should list tpm + a handful of plugins
tmux source-file ~/.tmux.conf 2>&1 || echo "FAIL: tmux config error"
```

### 10. Smoke test — end to end

```bash
# Fresh shell so .zshrc/oh-my-zsh-custom are loaded.
zsh -l -c 'echo $SHELL; alias ls; type enable_proxy' \
  | grep -q "enable_proxy is a shell function" \
  && echo "shell ok" || echo "FAIL: oh-my-zsh-custom not loaded"

# Claude Code → proxy round-trip
claude --print "say 'hello from devbox'" 2>&1 | head -5
# Should print a model response. If it errors with connection refused,
# the proxy (step 6) isn't running.
```

If all 10 steps print `ok` (or the equivalent positive signal), the box is
fully set up. The `gg <title>` function, the statusline (5-line layout
with git/branch/cost/ctx/agents/skills segments), the dark-ansi Claude Code
theme, and the Gruvbox-aligned tmux/wezterm chrome are all live.

### Platform notes

- **macOS-only.** `install.sh` is the single supported installer.
- **The proxy must keep running** for Claude Code to function. Quitting
  the `copilot-relay start` process breaks every Claude Code session
  immediately; the launchd agent keeps it running and restarts it after
  crashes or updates.

## How to add a new config

| Goal | Where to add the file |
|---|---|
| New `~/.something` dotfile | Drop it at repo root as `.something`, then re-run `install.sh`. |
| New oh-my-zsh customization (alias, function, env) | Create a new `*.zsh` file in `oh-my-zsh-custom/`, then re-run `install.sh`. Files there are auto-loaded by oh-my-zsh in alphabetical order. |
| New Copilot CLI config | Drop the file under `copilot/`, then re-run `install.sh`. (`mcp-config.json` is gitignored because it contains secrets — manage that file manually.) |
| New Claude Code config | Drop the file under `claude/`, then re-run `install.sh`. The destination directory is created automatically. |
| Editing an existing config | Edit it in this repo. Symlinks make changes live immediately on every machine. Reload mechanisms: tmux `prefix + r`; wezterm auto-reloads. |

After adding/editing, commit and push. Other machines pick up the change with
`git pull` (and `install.sh` again only if new files were introduced).

## Included configs

### Shell (`oh-my-zsh-custom/`)

#### `custom.zsh`

- Aliases: `ls=eza`, `ll=eza -l`, `c=cd ..`, `vim=nvim`, `proxy/unproxy`.
- `enable_proxy` / `disable_proxy` functions: toggle SOCKS5 proxy at
  `127.0.0.1:46971` for shell env vars, git, and npm in one call.
- Sources `zsh-fast-syntax-highlighting` and `zsh-completions` from Homebrew if
  available.
- Loads optional autojump if installed.
- Adds `.NET` and Android SDK tooling to `PATH`.

#### `copilot.zsh`

Wraps `copilot update`: after a successful update it runs
`~/.copilot/cleanup-legacy.sh`, so old `~/.copilot/pkg/<platform>/<version>`
payloads left by upgrades are pruned automatically.

#### `gg.zsh` — `gg <title>`

Sets the current terminal tab and window title to `<title>` via OSC 1 / 2
escape sequences (works in WezTerm, iTerm2, anything OSC-compliant).
**Inside tmux** the OSC escape doesn't propagate to the outer terminal because
`.tmux.conf` keeps `allow-rename off` and `automatic-rename off`, so `gg` also
calls `tmux rename-window` directly — that updates tmux's status-bar window
name, and `set-titles on` then bubbles `#S · #W` up to the outer terminal's
titlebar. After updating titles, `gg` launches
`copilot --allow-all-tools --allow-all-paths --effort xhigh` in the current
shell. Useful for labeling Copilot CLI sessions so they're identifiable in
the tab bar.

Implementation notes:

- Sends OSC 1 (icon name / tab title) and OSC 2 (window title) — terminals
  that pull the window title from the active surface's OSC 2 (WezTerm) pick
  this up automatically when not nested in tmux.
- Prepends a Nerd Font glyph (`fa-github`, U+F09B) to the title so Copilot
  tabs are visually distinct from plain shells / `cc` tabs at a glance.
  Requires a Nerd-patched font in the terminal — Rec Mono St.Helens (the
  default in this repo's `wezterm.lua`) is itself a Nerd Font 3.4.0 build
  so the glyph renders natively, no fallback needed.
- When `$TMUX` is set, also runs `tmux rename-window -- "$title"` so tmux's
  own window-name machinery is in sync (it doesn't read OSC sequences once
  `automatic-rename` is off).
- For WezTerm specifically (gated by `$WEZTERM_PANE`), also calls
  `wezterm cli set-tab-title` and `set-window-title` to update WezTerm's
  internal state — no-op when wezterm is on PATH but not the active terminal.
- Sets `DISABLE_AUTO_TITLE=true` while Copilot is running so oh-my-zsh's
  `precmd` / `preexec` hooks don't keep overwriting the title.
- Calls `command copilot ...` to bypass any shell alias of the same name.

### Terminal — WezTerm (`wezterm/`, opt-in)

The terminal config kept in-repo. **Not auto-linked** by `install.sh`; the
`wezterm` cask is installed so the terminal is one symlink away:

```bash
ln -sfn "$(pwd)/wezterm/wezterm.lua" ~/.wezterm.lua
```

Highlights of the in-repo config: `color_scheme = "Gruvbox dark, hard
(base16)"`, Rec Mono St.Helens, custom 5-row "floating tabs" with Nerd
Font process icons and a Knight-Rider loading bar for vibe-coding
sessions, DPI-adaptive font weight, FreeType fine-tuning, smart `Cmd+C`
(copy if selection else SIGINT), `inactive_pane_hsb = {1,1,1}` (no
dimming of inactive panes), and a tab-bar `BAR_BG` derived from the
active color scheme so swapping schemes auto-aligns the tab strip.

### Terminal — tmux (`.tmux.conf`)

Primary tab/split/session manager. Linked to `~/.tmux.conf` by `install.sh`.

| Setting | Value |
|---|---|
| Theme | hand-rolled Gruvbox Dark Hard palette (matches WezTerm) |
| Prefix | `C-q` (chosen over default C-b for ergonomics — far from C-c/d/z, doesn't clash with readline, modern macOS disables the legacy C-q XON flow control so nothing reclaims the keystroke; press `prefix + C-q` to send a literal `C-q` to the active pane) |
| `default-terminal` | `tmux-256color` + `RGB` overrides for `wezterm`, `xterm-256color`, `*-direct`; `terminal-features … :RGB` so tmux 3.2+ actually advertises truecolor (without it tmux silently downsamples to the 256-color cube) |
| Env scrubbing | `set-environment -gu TERMINFO TERMINFO_DIRS TERMCAP TERM_PROGRAM TERM_PROGRAM_VERSION` + `set -g COLORTERM truecolor` — defends against long-lived tmux servers inheriting dead `$TERMINFO` from previously installed terminals (which otherwise silently degrades panes from `tmux-256color` to `xterm-color` and breaks Copilot CLI's truecolor input panel). **Recovery for an already-poisoned server**: save state with `prefix + Ctrl-s`, then `tmux kill-server` from a non-tmux shell. |
| Mouse | `on` (scroll, click-to-select, drag-to-resize) |
| `escape-time` | `0` (vim-friendly) |
| `history-limit` | `100000` |
| Window/pane base index | `1` (1-indexed; `renumber-windows on`) |
| Status position | top |
| Set-clipboard | `on` (OSC 52 — works through SSH because WezTerm honours OSC 52) |
| Mode keys | `vi` |
| Allow rename / Auto rename | `off` (so `gg` / Vim-buffer titles stick; `gg` calls `tmux rename-window` explicitly) |

Keybinds (additive — tmux defaults like `prefix + n / p / 1..9 / Tab` for
window nav, `prefix + z` for zoom, `prefix + Space` for layout cycle, `prefix
+ d` for detach, `prefix + s` for session list are all kept):

| Action | Shortcut |
|---|---|
| Reload tmux.conf | `prefix + r` |
| Split right (vertical separator) | `prefix + |` (cwd inherited) |
| Split down (horizontal separator) | `prefix + -` (cwd inherited) |
| New window (cwd inherited) | `prefix + c` (default rebound to inherit cwd) |
| Pane focus (vim-style) | `prefix + h / j / k / l` |
| Pane resize (repeatable, no re-prefix) | `prefix + H / J / K / L` |
| Copy mode (vi keys) | `prefix + v`, then `v` start-selection, `y` copy |
| Mouse drag selection | auto-copies on drag end (OSC 52) |

Status bar segments:

- **Left**: yellow pill with the current session name (`#S`).
- **Window list**: inactive in dim grey on bg0; active in dark text on a
  Gruvbox bright-blue pill, plus a magnifier when zoomed
  (`#{?window_zoomed_flag, ,}`).
- **Right**: prefix indicator (only while the prefix is held, in red),
  `HH:MM`, vertical bar, and `YYYY-MM-DD`.

Plugins (managed by **TPM** — bootstrap is automatic on first run, both via
`.tmux.conf`'s `if "test ! -d ..."` guard and via `install.sh`):

| Plugin | Why |
|---|---|
| `tmux-plugins/tpm` | Plugin manager |
| `tmux-plugins/tmux-sensible` | Opinionated defaults that don't fight ours |
| `tmux-plugins/tmux-yank` | Cross-platform clipboard helpers |
| `tmux-plugins/tmux-resurrect` | Save/restore sessions (`prefix + Ctrl-s` / `Ctrl-r`); pane contents and Vim/NeoVim sessions captured |
| `tmux-plugins/tmux-continuum` | Auto-save every 5 min, auto-restore on tmux start |

> **Validate locally** with
> `tmux -f .tmux.conf -L _v new-session -d -s _v ; tmux -L _v kill-server`
> — silent exit means the config parsed cleanly. To force re-install of
> plugins: `~/.tmux/plugins/tpm/bin/install_plugins`.

### Copilot CLI (`copilot/`)

Files in `copilot/` are linked into `~/.copilot/`. `install.sh` skips this
step (with a warning) if `~/.copilot/` does not exist (Copilot CLI not
installed).

#### `settings.json`

Copilot CLI configuration. Pinned model `gpt-5.5`,
`contextTier: long_context` (1M context), `effortLevel: xhigh`, theme `dark`,
`keepAlive: busy`,
`continueOnAutoMode: true`, custom footer, and a custom status line provided
by `statusline.sh`.

> **Caveat:** Copilot CLI rewrites `settings.json` at runtime to inject /
> strip a `staff` field and to toggle UI defaults — edit it via atomic
> read–mutate–write–commit. Inside the `statusLine` block only the single
> `padding` field is honored (`paddingTop` / `paddingLeft` / etc. are
> silently ignored); per-side spacing is emitted from inside `statusline.sh`
> instead.

#### `statusline.sh`

Executable script — a "full mirror" of `~/.claude/statusline.sh` adapted to
Copilot's `statusLine` JSON. Per-segment Gruvbox color accents and
color-graded Context %. Default layout is five lines: L1 time/run/req/wakatime,
L2 model/effort/context, L3 mcp/skills/agents/tasks/style, L4 cwd path, L5
repo/branch/diff/stash/worktree. Copilot-only segments such as `api`,
`cache_pct`, `last_call`, `gh_account`, `ext_count`, and `venv` remain
available via `COPILOT_STATUSLINE_SEGMENTS`.

Environment overrides:

- `COPILOT_STATUSLINE_NO_ICONS=1` — drop icons, keep text labels.
- `COPILOT_STATUSLINE_NO_COLOR=1` — drop color (legacy
  `COPILOT_STATUSLINE_NO_DIM=1` is honored as an alias for backwards-compat).
- `COPILOT_STATUSLINE_PAD_TOP=N` / `..._PAD_LEFT=N` / `..._PAD_RIGHT=N` —
  override per-side padding (defaults: top = 0, left = 0, right = 0).
- `COPILOT_STATUSLINE_SEGMENTS="…"` — override the segment list and order
  (e.g. add `diff`, drop `cache_pct`, reorder freely).

Run `~/.copilot/statusline.sh --test` to verify each codepoint renders in
your terminal (uses `fc-list` if installed). Parses Copilot's session JSON
from stdin via a single `jq` call, caches git state for 5s
(`COPILOT_STATUSLINE_GIT_TTL=N` overrides), and caches `gh auth status` for
5 minutes. Bash 3.2-compatible. `install.sh` keeps the executable bit set.

> **Perf (v0.6.0):** the sibling `claude/statusline.sh` was rewritten for
> warm-cache latency 125ms → 18ms — pure-bash JSON parsing (no `jq`
> dependency), per-cwd git state cached for 5s under
> `$TMPDIR/claude-statusline-cache-$USER/git-<hash>`, awk forks dropped
> in favour of bash printf / arithmetic for `cost`/`ctx`/`fmt_tokens`,
> and `printf -v __SEG` replaces the per-segment `$(seg_$s)` subshell
> capture. `copilot/statusline.sh` tracks the same shape.

> **Layout (v0.13.x):** five-line layout by default. Literal `\n` tokens
> in the `SEGMENTS` list introduce line breaks:
> L1 `time | run | req | wakatime`, L2 `model | effort | context`,
> L3 `mcp | skills | agents | tasks | style`, L4 cwd path, L5
> `repo | branch | diff | stash | worktree`. `seg_path` (icon U+F07C
> folder-open) renders the full cwd with `$HOME` collapsed to `~`.
> `seg_agent` counts local custom agent profiles (`*.md` in
> `~/.copilot/agents/` + `<cwd>/.github/agents/`), and `seg_skills` counts
> skill bundles (`SKILL.md` under `~/.copilot/skills/`, `~/.agents/skills/`,
> `<cwd>/.github/skills/`, `<cwd>/.claude/skills/`, and
> `<cwd>/.agents/skills/`) — i.e. **available definitions**, not live
> sub-agents. `seg_subagents` shows the live running-subagent count.
> `seg_timer` shows `Nh Mm` once the session crosses one hour (v0.13.2).
> Override per-shell via
> `COPILOT_STATUSLINE_SEGMENTS`.

#### `cleanup-legacy.sh`

Executable upgrade-cleanup hook. It detects the current Copilot CLI version via
`copilot --version`, keeps only that package under
`~/.copilot/pkg/<platform>/<version>`, removes older package payloads, empty
package dirs, `.DS_Store`, root `*.bak.*` files, and all but the newest
`logs/process-*.log`. `install.sh` runs it after linking Copilot files; the
`oh-my-zsh-custom/copilot.zsh` wrapper runs it after every successful
`copilot update`.

#### `copilot-instructions.md`

Global agent instructions — autonomous mode (no per-action confirmation):
operate in plan / exec cycles and verify before claiming completion.

### Claude Code (`claude/`)

Files in `claude/` are linked into `~/.claude/`. Bridges Anthropic's
[Claude Code CLI](https://github.com/anthropics/claude-code) to GitHub
Copilot models via a local [`copilot-relay`](https://www.npmjs.com/package/copilot-relay)
proxy that translates Anthropic-format requests into Copilot ones.

#### `settings.json`

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4142",
    "ANTHROPIC_AUTH_TOKEN": "dummy",
    "ANTHROPIC_MODEL": "claude-opus-4-8",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.5",
    "ANTHROPIC_SMALL_FAST_MODEL": "gpt-5.5",
    "MODEL_REASONING_EFFORT": "xhigh"
  },
  "permissions": { "allow": ["*"], "defaultMode": "auto" },
  "model": "claude-opus-4-8",
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0,
    "refreshInterval": 100
  },
  "effortLevel": "xhigh",
  "theme": "dark-ansi",
  "skipAutoPermissionPrompt": true,
  "skipDangerousModePermissionPrompt": true
}
```

Defaults pinned globally (synced across machines via this repo):

- **Model: `claude-opus-4-8`** (Opus 4.8). This is Claude Code's recognized
  Opus 4.8 name, so the UI uses the 1M context window. `copilot-relay` routes
  Opus-family requests to Copilot upstream `opusModel: claude-opus-4.8`, so
  **no `[1m]` / `-1m` alias is needed**. `env.ANTHROPIC_MODEL`, top-level
  `model`, and the zsh wrappers are all pinned to `claude-opus-4-8`. Do not
  use top-level `model: "default"` here: relay routes model names that do not
  contain `opus` to `gptModel` (`gpt-5.5`), which appears as 200k context.
- **Family-aware routing via env vars + relay**:
  - **`ANTHROPIC_DEFAULT_SONNET_MODEL: gpt-5.5`** — every Sonnet alias from
    Claude Code's built-in picker routes to `gpt-5.5`.
  - **`ANTHROPIC_DEFAULT_HAIKU_MODEL: gpt-5.5`** — Haiku tier for current
    Claude Code versions, including sub-agents and small-fast side tasks.
  - **`ANTHROPIC_SMALL_FAST_MODEL: gpt-5.5`** — legacy alias for older Claude
    Code versions.
  - `copilot-relay` also has `gptModel: gpt-5.5` and
    `opusModel: claude-opus-4.8`, so Claude-side aliases and relay routing
    agree.
- **Effort: `xhigh`** — applied two ways:
  `effortLevel: "xhigh"` (Claude Code's client-side reasoning budget,
  applied to every session) and `thinkEffort: xhigh` in
  `~/.copilot-relay/config.yaml` (written by `install.sh`, hot-reloaded by
  the relay, and forwarded to Copilot upstream). `MODEL_REASONING_EFFORT`
  remains in `settings.json` so the statusline can display the pinned effort.
- `ANTHROPIC_BASE_URL` — the local `copilot-relay` proxy on port 4142.
  All model names above are Copilot-side identifiers the proxy knows how
  to route. Claude Code itself doesn't know about `gpt-5.5`; the proxy
  translates every request and replies with Anthropic-shaped JSON.
- `ANTHROPIC_AUTH_TOKEN` — required by Claude Code's startup check.
  `dummy` is fine; real auth happens in `copilot-relay auth`.
- `skipAutoPermissionPrompt: true` + `permissions.defaultMode: "auto"` —
  autonomous mode by default (no per-action confirmation). Note: the
  binary explicitly **rejects** `defaultMode: "bypassPermissions"`
  ("bypassPermissions mode is disabled by settings"), so for full
  bypass we wrap the launchers — see "Wrappers" below.
- `editorMode`: not pinned. `statusLine.refreshInterval: 100` drops the
  redraw cadence so the statusline updates feel snappy.
- `theme: "dark-ansi"` lets the chrome inherit the terminal's ANSI palette
  (so it tracks the WezTerm Gruvbox scheme rather than hard-coding its
  own colors).

#### Wrappers (`oh-my-zsh-custom/claude.zsh`, `cc.zsh`)

Bare `claude` is wrapped as a shell function that always passes
`--permission-mode bypassPermissions`. The CLI flag is the only path
the binary honors for non-interactive bypass — the equivalent
settings.json key is gated off by feature flag.

Same applies to `cc <title>`: it renames the active terminal tab via
OSC 1/2 (+ tmux + WezTerm CLI fallbacks) then launches Claude Code with
the bypass flag plus `--model claude-opus-4-8 --effort xhigh`. The title is prefixed with a Nerd Font glyph
(`mdi-creation`, U+F0674 — sparkles) so Claude tabs are visually distinct
from Copilot's `gg` tabs (which use `fa-github`) and from plain shells.

To switch models mid-session, use Claude Code's `/model <name>` —
free-form names pass through the proxy unchanged.

One-time setup (after running `install.sh` on a fresh box):

```bash
npm install -g @anthropic-ai/claude-code
bash ~/Public/dot-configs/install.sh  # installs/updates copilot-relay and starts launchd
copilot-relay auth                    # browser device-code login (GitHub)
claude                            # in another shell — uses Opus 4.8 1M @ xhigh effort
```

> **Caveat:** Claude Code rewrites `settings.json` at runtime to add fields
> like `firstStartTime`, telemetry IDs, etc. Same atomic
> read–mutate–write–commit pattern as Copilot CLI's `settings.json`. If a
> spurious diff appears in the working tree, restore the committed shape
> rather than committing the runtime addition.

## Requirements

### Apps (auto-installed via Homebrew on macOS)

- [WezTerm](https://wezfurlong.org/wezterm/) — terminal (cask installed
  automatically; config is opt-in via the symlink command above)
- [oh-my-zsh](https://ohmyz.sh/) — required only if you want the
  `oh-my-zsh-custom/` files linked
- [GitHub Copilot CLI](https://github.com/github/copilot) — required only if
  you want the `copilot/` files linked
- [Claude Code CLI](https://github.com/anthropics/claude-code) +
  [`copilot-relay`](https://www.npmjs.com/package/copilot-relay) — required only
  if you want the `claude/` files linked (Anthropic CLI bridged onto GitHub
  Copilot models via a local proxy on port 4142)
- [`gh`](https://cli.github.com/) — optional; `statusline.sh` calls
  `gh auth status` (cached 5 minutes) to render the GH segment

### Tools (auto-installed via Homebrew on macOS)

- [tmux](https://github.com/tmux/tmux) ≥ 3.3 (3.6a tested) — primary tab,
  split, and session manager. TPM and listed plugins bootstrap automatically
  on first launch.
- `git` — required by TPM to clone the plugin manager and plugin repos.

### Fonts (installed automatically via Homebrew)

- Recursive (Rec Mono St.Helens — part of the Rec Mono variable family) —
  `font-recursive`
- Recursive Mono Nerd Font — `font-recursive-mono-nerd-font`
- Symbols Only Nerd Font — `font-symbols-only-nerd-font`
- Noto Color Emoji — `font-noto-color-emoji`

### Optional Homebrew formulae used by `custom.zsh`

- `autojump`, `zsh-fast-syntax-highlighting`, `zsh-completions` — sourced if
  present; absence is silently ignored.

## License

See [LICENSE](LICENSE).
