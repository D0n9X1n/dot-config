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
├── .rmux.conf                   # -> ~/.rmux.conf (terminal multiplexer)
├── oh-my-zsh-custom/            # contents -> ~/.oh-my-zsh/custom/
│   ├── custom.zsh               # aliases, proxy helpers, brew completions, env
│   ├── copilot.zsh              # copilot update wrapper -> cleanup hook
│   └── gg.zsh                   # gg() function (terminal title + copilot)
├── copilot/                     # contents -> ~/.copilot/
│   ├── AGENTS.md                # global Wiki/release workflow guidance
│   ├── copilot-instructions.md  # native global autonomy instructions
│   ├── settings.json            # Copilot CLI settings
│   ├── statusline.sh            # statusline (bash 3.2+)
│   ├── subagent-state.sh        # hook-maintained live subagent rows
│   └── cleanup-legacy.sh        # prune stale Copilot CLI upgrade payloads
├── claude/                      # contents -> ~/.claude/
│   ├── CLAUDE.md                # global Wiki/release workflow guidance
│   ├── settings.json            # Claude Code settings
│   ├── statusline.sh            # statusline
│   └── skills/                  # skills -> ~/.claude/skills/ (load in every project)
│       └── update-settings/     # edit any config here correctly, then apply it
├── archive/                     # inert retired tmux/WezTerm configs
│   ├── tmux/.tmux.conf
│   └── wezterm/wezterm.lua
├── wiki/                        # bilingual GitHub Wiki source (flat)
├── .sonicterm/                  # tracked TOML config -> ~/.sonicterm/
│   ├── sonicterm.toml           # SonicTerm config
│   ├── keymaps/                 # WezTerm-compatible keymaps
│   └── themes/                  # Gruvbox/WezTerm-aligned themes
├── .copilot-relay/              # secret-free relay config -> ~/.copilot-relay/
│   └── config.yaml              # model routing, effort, logging, claudeSetup=false
├── themes/apollo/               # Apollo theme (wezterm/vim/nvim/vscode/wt) — reference, not auto-linked
├── launchd/                     # macOS launchd agent templates
│   ├── com.d0n9x1n.copilot-relay.plist     # copilot-relay proxy on login (rendered by install.sh)
│   ├── com.d0n9x1n.copilot-relay-healthcheck.plist  # relay watchdog (liveness + deep)
│   ├── copilot-relay-healthcheck.sh        # /healthz every 60s; status --deep every 900s
│   ├── com.d0n9x1n.npm-cache-clean.plist   # weekly npm/npx cache cleaner (rendered by install.sh)
│   └── clean-npm-caches.sh                 # the cleaner script the agent runs
├── mcp-shared.json              # secret-free MCP entries synced via git
├── scripts/check.sh             # local/CI parity checks
├── .github/workflows/publish-wiki.yml  # wiki/ -> GitHub Wiki
├── .claude/CLAUDE.md            # agent instructions for Claude Code working in this repo
├── .github/copilot-instructions.md  # agent instructions for Copilot CLI
├── LICENSE
├── ReadMe.md                    # this file
└── QUICKREF.md                  # condensed reference (agent-friendly)
```

`install.sh` is the only entry point. It:

`install.sh` writes timestamped output to
`~/Library/Logs/dot-configs-install.log` (override with
`DOT_CONFIGS_INSTALL_LOG=/path/to/log`). Real install/update commands are logged
with their full output; existence checks stay quiet so expected "not installed"
probes do not appear as errors.

1. Installs Homebrew if missing, then installs required macOS apps, fonts, and
   command-line tools via Homebrew (best-effort after Homebrew itself exists,
   except Claude Code must satisfy the minimum version below).
   Set `SKIP_BREW=1` to skip this step entirely (useful for CI / fake-`HOME`
   testing). Formulae: `autojump`, `eza`, `git`, `jq`, `neovim`, `node`, `rmux`,
   `zsh-completions`, and `zsh-fast-syntax-highlighting`. Before installing Claude Code, the installer
   removes any old global npm `@anthropic-ai/claude-code` package, then ensures
   the active Claude Code is at least v2.1.217 (required by the native
   concurrent-subagent limit), installing or upgrading the Homebrew cask only
   when needed. It also installs casks for the Recursive base/Nerd Fonts,
   Symbols Only Nerd Font, and Noto Color Emoji, and
   downloads the latest
   `RecMonoBaker-*.ttf` and `RecMonoSt.Helens-*.ttf` assets from
   `MOSconfig/recursive-code-config` releases into `~/Library/Fonts`.
2. Installs/updates npm global CLIs only when they are missing or already
   npm-managed: `@github/copilot` and `copilot-relay`. Existing non-npm
   binaries (for example cask-managed `copilot`) are left in place to avoid npm
   `EEXIST`. Set `SKIP_NPM_GLOBALS=1` to skip.
3. Installs oh-my-zsh unattended if missing (`RUNZSH=no`, `CHSH=no`), then
   fixes insecure zsh completion directory permissions so `compinit` does not
   block new shells. Set `SKIP_OH_MY_ZSH=1` to skip installation.
4. Symlinks every **top-level non-ignored** dotfile in this repo (files starting
   with `.`) into `$HOME` (including `.rmux.conf`; ignored generated files such
   as `.copilot-cli.ts` are skipped). After the RMUX link lands, removes the old
   `~/.tmux.conf` and `~/.wezterm.lua` only when they still point to this
   repository's retired source paths; user-owned replacements are preserved.
5. Symlinks every file in `oh-my-zsh-custom/` into `~/.oh-my-zsh/custom/`.
   `custom.zsh` adds `~/.copilot` to `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`
   without dropping or duplicating existing paths, making the linked global
   `AGENTS.md` discoverable by Copilot CLI.
6. Symlinks every file in `copilot/` into `~/.copilot/`. Creates the
   destination directory if missing. `copilot-instructions.md` is Copilot's
   documented global entry point; `AGENTS.md` carries reusable Wiki/release
   guidance and is activated by the shell environment above. Preserves the
   executable bit on `*.sh`, then runs `cleanup-legacy.sh`.
7. Symlinks every top-level config file in `claude/` into `~/.claude/`,
   including global `CLAUDE.md`. A pre-existing regular global instruction
   file is timestamp-backed up before the tracked symlink replaces it.
   **Creates the destination directory if missing** (Claude Code only creates
   `~/.claude/` on first launch; mkdir-p so install.sh wires things up on a
   fresh box). During migration it removes the obsolete
   `~/.claude/hooks/subagent-counter.sh` only when that path is still a symlink
   to this repository; user-owned hooks are preserved. Skills live one directory
   deeper (`claude/skills/<name>/SKILL.md`), so they get their own pass that
   links each skill's files into `~/.claude/skills/<name>/` — global, meaning
   they load in every project on the machine, not just this repo.
8. Does not install or configure WezTerm; the retired profile lives under
   `archive/wezterm/`. SonicTerm is the actively managed outer terminal.
9. Symlinks tracked SonicTerm TOML files into `~/.sonicterm/`:
   `sonicterm.toml`, `keymaps/*.toml`, and `themes/*.toml`. Logs and runtime
   backup files under `~/.sonicterm/` stay machine-local and are not linked.
10. Merges tracked, secret-free MCP servers into
   `~/.config/github-copilot/mcp.json`, then imports Copilot's MCP servers into
   Claude Code's `~/.claude.json` when `jq` and the MCP file are available.
   Removes the legacy Homebrew `wakatime-cli` formula and vendored WakaTime MCP
   runtime/entries. For Copilot WakaTime upload, if `~/.wakatime.cfg` lacks
   `api_key`, the installer prints a red `ACTION REQUIRED` prompt and asks for
   the key twice with hidden input before writing the local config file. Once
   WakaTime and Copilot CLI are available, it installs or updates the WakaTime-owned
   `wakatime/copilot-cli-wakatime` Copilot plugin. The plugin installs/updates
   its own `~/.wakatime/wakatime-cli` binary on Copilot session start.
11. Leaves archived tmux plugins and resurrect data untouched; RMUX uses no TPM
   bootstrap and no global tmux shim.
12. Links `.copilot-relay/config.yaml` to `~/.copilot-relay/config.yaml`, removes
   legacy proxy launchd jobs, and writes the per-user launchd agent plus its
   watchdog. The watchdog runs at load and every 60 seconds, in two tiers.
   **Liveness (every run, free):** if `GET http://127.0.0.1:4142/healthz` does
   not return 200 the relay process is gone, so it restarts
   `com.d0n9x1n.copilot-relay` with `launchctl kickstart -k`. **Deep (every 900
   seconds):** `copilot-relay status --deep` sends a real request through
   Copilot, catching a relay that is listening but cannot reach Copilot — the
   case `/healthz` cannot see, since it never contacts Copilot. `not running`
   and `listening but unusable` are logged distinctly; the latter is usually
   expired auth, where the fix is `copilot-relay auth` rather than a restart.
   Healthy is a no-op at both tiers. The installer uses the liveness rule: if
   `/healthz` is already 200, it leaves the running relay untouched. If relay is
   not authenticated, the installer prints a red `ACTION REQUIRED` message to run
   `npx copilot-relay auth` first; after auth, re-run `install.sh` to start it.
13. Writes the `npm-cache-clean` launchd agent (macOS): a weekly job (Sun 03:17)
   that runs `npm cache clean --force` and prunes `~/.npm/_npx` copies older than
   14 days, keeping the cache from growing unbounded. Needs no auth; never touches
   the Playwright browser cache (`~/Library/Caches/ms-playwright`).
14. Backs up any existing destination file or symlink that doesn't already point
   at the repo as `<name>.bak.YYYYMMDDHHMMSS` before linking, and keeps only
   the newest backup for each destination.
15. Leaves correctly-pointing symlinks alone (no-op).

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

## Checks

Run `scripts/check.sh all` before pushing shell/statusline/install changes. CI
uses the same script: macOS runs `scripts/check.sh smoke`, while Ubuntu installs
ShellCheck and runs `scripts/check.sh shellcheck`.

## Wiki

`wiki/` is the flat, bilingual source of truth for the GitHub Wiki. English
pages are paired with `-zh-CN` pages, and `_Sidebar.md` provides global
navigation. `.github/workflows/publish-wiki.yml` publishes changes from `main`,
renaming `README.md` to the Wiki-required `Home.md`; browser edits are replaced
on the next publication. The Wiki repository must be initialized once by
creating a temporary page in GitHub before the first workflow run.

## Releases

Pushing a `v*.*.*` tag runs `.github/workflows/release.yml` and publishes a
GitHub Release. The release body is generated from the commit subject list
between the new tag and the previous reachable `v*.*.*` tag, so the release
message stays aligned with the commits that shipped.

## Fresh-devbox runbook (agent-friendly)

Step-by-step setup on a brand-new macOS box. An agent (or human) can follow
this top-to-bottom with no prior context. **Each step is verifiable** — run
the check command before moving on. Stop at the first failure and report.

### 0. Prerequisites

```bash
# macOS only. The installer can bootstrap Homebrew, Node/npm, oh-my-zsh,
# Claude Code, Copilot CLI, and copilot-relay. You still need git or an
# archive download path to get this repo onto the machine first.
xcode-select -p 2>/dev/null || xcode-select --install
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

### 2. Run the installer

```bash
bash ~/Public/dot-configs/install.sh
```

Verify bootstrap and symlinks landed:

```bash
brew --version
node --version
brew list --cask claude-code
copilot --version
npm list -g copilot-relay --depth=0
copilot plugin list | grep -q copilot-cli-wakatime && echo "WakaTime plugin ok"
ls -l ~/.rmux.conf ~/.copilot/settings.json ~/.claude/settings.json ~/.oh-my-zsh/custom/custom.zsh
rmux -V
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay" | grep state
```

### 3. Authenticate the proxy (one-time, browser device-code flow)

```bash
npx copilot-relay auth               # opens browser; enter the device code
# Verify token landed:
test -f ~/.copilot-relay/github_token && echo "ok" || echo "FAIL: auth incomplete"
```

### 4. Start the proxy daemon (must stay running for Claude Code)

After `npx copilot-relay auth`, re-run `install.sh`; the launchd agent should
start serving the proxy. The agent (`com.d0n9x1n.copilot-relay`) starts on every
login and restarts on crash. A sibling watchdog
(`com.d0n9x1n.copilot-relay-healthcheck`) runs at load and every 60 seconds, in
two tiers: it calls `GET /healthz` on every run (200 is a no-op; anything else
means the process is gone, so it `launchctl kickstart -k`s the relay), and every
900 seconds it also runs `copilot-relay status --deep`, which sends a real
request through Copilot. The deep tier is what catches a relay that is listening
but whose Copilot token expired — `/healthz` returns 200 in that state because it
never contacts Copilot.
Relay logs go to `~/Library/Logs/copilot-relay.{out,err}.log` plus
`~/.copilot-relay/logs/copilot-relay.log`; watchdog restart logs (both tiers) go
to `~/Library/Logs/copilot-relay-healthcheck.log`, and the deep-check timestamp
lives at `~/Library/Caches/copilot-relay-healthcheck.deep`. Verify:

```bash
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay" | grep state
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay-healthcheck" | grep state
curl -sS -o /dev/null --connect-timeout 1 http://127.0.0.1:4142/healthz && echo "healthy"

# Run the deep tier on demand (spends a few tokens).
# Exit 0 = reachable, 1 = not running, 2 = listening but cannot reach Copilot.
copilot-relay status --deep; echo "exit=$?"
```

If the agent is loaded but port 4142 is not listening after auth, restart it:

```bash
launchctl kickstart -k "gui/$(id -u)/com.d0n9x1n.copilot-relay"
```

If you want to manage the agent manually:

```bash
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.d0n9x1n.copilot-relay.plist
launchctl bootout   "gui/$(id -u)" ~/Library/LaunchAgents/com.d0n9x1n.copilot-relay.plist
launchctl kickstart -k "gui/$(id -u)/com.d0n9x1n.copilot-relay"   # restart in place
tail -f ~/Library/Logs/copilot-relay.{out,err}.log ~/.copilot-relay/logs/copilot-relay.log ~/Library/Logs/copilot-relay-healthcheck.log
```

For a one-off foreground run (debugging, no auto-restart):

```bash
npx copilot-relay start &
sleep 2
curl -sS -o /dev/null --connect-timeout 1 http://127.0.0.1:4142/ \
  && echo "listening" || echo "FAIL: proxy not responding on :4142"
```

### 5. Wire up MCP servers (optional but recommended)

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
copilot plugin list | grep -q copilot-cli-wakatime && echo "Copilot WakaTime plugin present"
```

**WakaTime is plugin-only.** This repo no longer vendors a WakaTime MCP server
or installs Homebrew `wakatime-cli`. Copilot CLI activity upload is handled by
the official
[`wakatime/copilot-cli-wakatime`](https://github.com/wakatime/copilot-cli-wakatime)
plugin, which sends AI heartbeats after user prompts and file-edit tool events.
`install.sh` installs or updates the plugin after the WakaTime API key and
Copilot CLI are available, removes the legacy WakaTime MCP runtime/entries,
removes the legacy Homebrew `wakatime-cli` formula, and removes the legacy
`@geeknees/copilot-cli-wakatime` npm package if present. The plugin installs and
updates its own `~/.wakatime/wakatime-cli` binary on Copilot session start.

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

### 8. RMUX and the outer terminal

`install.sh` installs RMUX and links `.rmux.conf`. SonicTerm supplies the
actively managed outer terminal; the installer adds neither tmux nor WezTerm:

```bash
ls -l ~/.rmux.conf
rmux -V
rmux diagnose --human
```

Open RMUX in SonicTerm. Verify `C-q` is the prefix, `C-q |` and
`C-q -` split in the current directory, `C-q T` toggles native mouse selection,
and `C-q r` reloads the profile. For Claude teammate panes, use `rmux claude`;
ordinary `claude` and `cc` sessions remain unchanged.

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

# WezTerm — its old managed profile is archived. To use the standalone
# scheme in a user-owned ~/.wezterm.lua:
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

### 9. Validate RMUX and Wiki configuration

```bash
bash scripts/check.sh rmux
bash scripts/check.sh wiki
```

The RMUX check uses a unique named socket, parses and sources `.rmux.conf`,
asserts representative options and bindings, and kills the isolated daemon on
exit. The Wiki check validates English/Chinese pairing and both the source and
published link graphs.

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
fully set up. The `gg [title]` function, the statusline (5-line layout
with git/branch/cost/ctx/agents/skills segments), the dark-ansi Claude Code
theme, and the Gruvbox-aligned RMUX chrome are all live.

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
| New SonicTerm config | Drop TOML under `.sonicterm/`, `.sonicterm/keymaps/`, or `.sonicterm/themes/`, then re-run `install.sh`. Do not commit `logs/` or runtime backups. |
| RMUX config | Edit `.rmux.conf`, then reload with `prefix + r`. Do not add TPM/plugin bootstrap or a global tmux shim. |
| Wiki page | Add a flat English page plus its `-zh-CN` pair under `wiki/`, update `_Sidebar.md`, then run `scripts/check.sh wiki`. |
| copilot-relay config | Edit `.copilot-relay/config.yaml`, then re-run `install.sh` if the symlink is not already installed. Never commit `github_token`, `copilot_token.json`, or `logs/`. |
| Editing an existing config | Edit the active source in this repo. Symlinks make changes live immediately; files under `archive/` are inert. |

After adding/editing, commit and push. Other machines pick up the change with
`git pull` (and `install.sh` again only if new files were introduced).

## Included configs

### Shell (`oh-my-zsh-custom/`)

#### `custom.zsh`

- Aliases: `ls=eza`, `ll=eza -l`, `c=cd ..`, `vim=nvim`, `proxy/unproxy`.
- `enable_proxy` / `disable_proxy` functions: toggle SOCKS5 proxy at
  `127.0.0.1:46971` for shell env vars, git, and npm in one call.
- Uses Homebrew-installed `eza`, `neovim`, `autojump`,
  `zsh-fast-syntax-highlighting`, and `zsh-completions`.
- Repairs group/world-writable completion directories before running
  `compinit -i`, avoiding zsh's insecure-directory interactive prompt.
- Adds `.NET` and Android SDK tooling to `PATH`.

#### `copilot.zsh`

Wraps every Copilot CLI process with `TERM_PROGRAM=WezTerm`,
`COLORTERM=truecolor`, and `FORCE_COLOR=3`, selecting Copilot's
WezTerm-compatible modern true-color UI even inside RMUX. The variables are
process-scoped, so the surrounding pane remains `TERM_PROGRAM=rmux`. After a
successful `copilot update`, it runs `~/.copilot/cleanup-legacy.sh`, pruning old
`~/.copilot/pkg/<platform>/<version>` payloads.

#### `gg.zsh` — `gg [title]`

Sets the current terminal tab and window title to `[title]` via OSC 1 / 2
escape sequences (works in SonicTerm and other OSC-compliant terminals). If
`title` is omitted, `gg` uses the current directory path so a bare session still
has a useful name. Inside RMUX, `gg` calls `rmux rename-window` directly so the
status-bar window name and outer `#S · #W` title stay aligned while automatic
rename is disabled. After updating titles, `gg` launches
`copilot --allow-all-tools --allow-all-paths --model claude-opus-5 --context long_context --effort max` with a process-scoped
`TERM_PROGRAM=WezTerm`, `COLORTERM=truecolor`, and `FORCE_COLOR=3`. This tells
Copilot to use its supported true-color terminal path without masking
`TERM_PROGRAM=rmux` from other pane processes.

Implementation notes:

- Sends OSC 1 (icon name / tab title) and OSC 2 (window title); compliant
  outer terminals pick these up automatically outside a multiplexer.
- Prepends a Nerd Font glyph (`fa-github`, U+F09B) to the title so Copilot
  tabs are visually distinct from plain shells / `cc` tabs at a glance.
  It requires a Nerd-patched font such as the installed Rec Mono builds.
- When `$RMUX` is set, runs `rmux rename-window -- "$title"`; no active tmux
  or WezTerm CLI fallback remains.
- Sets `DISABLE_AUTO_TITLE=true` while Copilot is running so oh-my-zsh's
  `precmd` / `preexec` hooks don't keep overwriting the title.
- Calls `command copilot ...` to bypass any shell alias of the same name.

### Archived WezTerm profile (`archive/wezterm/`)

The former `wezterm.lua` is retained for reference but is no longer linked.
The installer no longer installs WezTerm; SonicTerm is RMUX's actively managed
outer terminal. SonicTerm's WezTerm-compatible keymaps, palette names, and the
process-scoped Copilot identity remain intentional compatibility signals.

### Terminal — SonicTerm (`.sonicterm/`)

SonicTerm config is kept in-repo and auto-linked by `install.sh` into
`~/.sonicterm/`, but not as a whole-directory symlink. The installer links only
the tracked TOML files (`sonicterm.toml`, `keymaps/*.toml`, `themes/*.toml`) so
SonicTerm's `logs/` directory and runtime backup files remain local.

The tracked config uses the `wezterm` theme, `sonicterm-macos` keymap, Rec Mono
St.Helens 14 with line-height 1.2, `TERM_PROGRAM=WezTerm`, 1000-line scrollback,
no cursor blink, opaque Gruvbox Dark Hard chrome, software render mode auto, and
WezTerm-compatible keymaps for macOS/Linux/Windows.

### copilot-relay (`.copilot-relay/`)

The relay config is kept in-repo and auto-linked by `install.sh` to
`~/.copilot-relay/config.yaml`. It is intentionally limited to secret-free
settings: local bind address/port, logging retention, `claudeSetup: false`,
`thinkEffort: max`, `gptModel: gpt-5.6-sol`, and
`opusModel: claude-opus-5`.

Do not commit the rest of `~/.copilot-relay/`: `github_token`,
`copilot_token.json`, and `logs/` are machine-local auth/runtime state.

### Terminal multiplexer — RMUX (`.rmux.conf`)

RMUX 0.10.x is the active tab/split/session manager. It is an independent Rust
daemon and client, not a tmux wrapper and not a terminal emulator. The tracked
profile is linked to `~/.rmux.conf`; a native file prevents RMUX from falling
back to the executable TPM-enabled config now under `archive/tmux/`.

| Setting | Value |
|---|---|
| Theme | hand-rolled Gruvbox Dark Hard, top status bar |
| Prefix | `C-q`; `prefix + C-q` sends a literal `C-q` |
| Terminal | `tmux-256color` with RGB/undercurl declarations; preserves `TERM_PROGRAM=rmux` |
| Environment | clears stale `TERMINFO`, `TERMINFO_DIRS`, and `TERMCAP`; forces truecolor hints |
| Mouse | on; `prefix + T` toggles native terminal selection |
| History | 100000 lines |
| Window/pane base index | 1, with automatic window renumbering |
| Clipboard | `pbcopy` in copy mode plus trusted-pane OSC 52 (`set-clipboard on`) |
| Titles | automatic rename off; `#S · #W` bubbles to the outer terminal |

| Action | Shortcut |
|---|---|
| Reload `.rmux.conf` | `prefix + r` |
| Split right/down in current directory | `prefix + |` / `prefix + -` |
| New window in current directory | `prefix + c` |
| Pane focus | `prefix + h / j / k / l` |
| Repeatable resize | `prefix + H / J / K / L` |
| Previous window | `prefix + Tab` |
| Copy mode | `prefix + v`; then `v` select and `y` copy |
| Zoom / detach | `prefix + z` / `prefix + d` (RMUX defaults) |

`cc` and `gg` use `rmux rename-window` inside RMUX. `rmux claude` is the
explicit Claude teammate-mode launcher: it adds a private, process-scoped shim,
not a global replacement for `tmux`.

TPM, tmux-sensible, tmux-yank, resurrect, and continuum are retired rather
than copied into RMUX. Existing local plugin and resurrect data is preserved in
case of rollback. Full architecture, security, command, and migration details
are available in the bilingual `wiki/RMUX*.md` pages.

> **Validate locally** with `scripts/check.sh rmux`. The check uses an isolated
> named socket, sources the profile, asserts representative options and keys,
> and always kills the test daemon.

### Copilot CLI (`copilot/`)

Files in `copilot/` are linked into `~/.copilot/`. `install.sh` creates the
destination directory when missing, preserves executable bits on shell scripts,
and then runs `cleanup-legacy.sh` when the Copilot CLI is available.

#### `settings.json`

Copilot CLI configuration. Pinned model `claude-opus-5`,
`contextTier: long_context` (1M context), `effortLevel: max`, theme `dark`,
`keepAlive: busy`,
`continueOnAutoMode: true`, custom footer, and a custom status line provided
by `statusline.sh`. The `hooks` block wires `sessionStart`, `sessionEnd`,
`subagentStart`, and `subagentStop` to `~/.copilot/subagent-state.sh` so live
subagent rows are maintained without scanning the session event log on every
statusline redraw.

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
repo/branch/diff/stash/worktree. The default icon accent lattice avoids using
the same color for adjacent segments or for segments in the same visual column.
Copilot-only segments such as `api`, `cache_pct`, `last_call`, `gh_account`,
`ext_count`, and `venv` remain available via `COPILOT_STATUSLINE_SEGMENTS`.

Environment overrides:

- `COPILOT_STATUSLINE_NO_ICONS=1` — drop icons, keep text labels.
- `COPILOT_STATUSLINE_NO_COLOR=1` — drop color (legacy
  `COPILOT_STATUSLINE_NO_DIM=1` is honored as an alias for backwards-compat).
- `COPILOT_STATUSLINE_PAD_TOP=N` / `..._PAD_LEFT=N` / `..._PAD_RIGHT=N` —
  override per-side padding (defaults: top = 0, left = 0, right = 0).
- `COPILOT_STATUSLINE_SEGMENTS="…"` — override the segment list and order
  (e.g. add `diff`, drop `cache_pct`, reorder freely).
- `COPILOT_STATUSLINE_SUBAGENT_STATE_DIR=dir` — override the hook-maintained
  subagent rows directory (defaults to `$TMPDIR/copilot-subagents-$USER`).

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
> sub-agents. `seg_subagents` shows the live running-subagent count. When
> active subagent rows are shown below L5, they are preceded by a
> `----------------------------------------` separator. The root `main` row uses
> a terminal icon, and subagent rows use a magic-wand icon (U+F0D0). Those rows come from
> `subagent-state.sh`'s small per-session rows file first, with a
> signature-cached `events.jsonl` fallback if hook rows are missing.
> `seg_timer` shows `Nh Mm` once the session crosses one hour (v0.13.2).
> Override per-shell via
> `COPILOT_STATUSLINE_SEGMENTS`.

#### `subagent-state.sh`

Executable Copilot hook helper. `sessionStart` / `sessionEnd` reset the
per-session rows file; `subagentStart` appends `toolCallId`, `agentDisplayName`,
purpose, and start time; `subagentStop` removes by `toolCallId` first, then
falls back to FIFO by agent name/display name.

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
    "ANTHROPIC_MODEL": "claude-sonnet-5[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "Sonnet 5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION": "Sonnet 5 (1M context), routed by copilot-relay to gpt-5.6-sol",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.6-sol[1m]",
    "ANTHROPIC_SMALL_FAST_MODEL": "gpt-5.6-sol[1m]",
    "MODEL_REASONING_EFFORT": "max"
  },
  "permissions": { "allow": ["*"], "defaultMode": "auto" },
  "model": "claude-sonnet-5[1m]",
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0,
    "refreshInterval": 100
  },
  "effortLevel": "max",
  "theme": "dark-ansi",
  "skipAutoPermissionPrompt": true,
  "skipDangerousModePermissionPrompt": true
}
```

Defaults pinned globally (synced across machines via this repo):

- **Model: `claude-sonnet-5[1m]`** (default). This is the Claude-facing model
  identity used by `env.ANTHROPIC_MODEL`, the top-level `model`, and both zsh
  wrappers. The `[1m]` suffix keeps Claude Code's 1M-context accounting.
  Claude Code's `/model` picker shows the pinned row as **Sonnet 5**; the
  companion description identifies its actual relay destination.
- **The Sonnet-facing default uses the GPT relay lane.** `copilot-relay` sends
  every model name that does **not** contain `opus` to `gptModel`, currently
  `gpt-5.6-sol`. Therefore selecting Sonnet 5 in Claude Code still runs
  `gpt-5.6-sol` upstream, at max effort, while retaining Claude Code's native
  Sonnet picker identity and 1M accounting.
- **Family-aware routing via env vars + relay**:
  - **`ANTHROPIC_DEFAULT_SONNET_MODEL: claude-sonnet-5[1m]`** — binds the
    built-in `sonnet` alias and picker row to the Claude-facing Sonnet 5 ID.
    `_NAME="Sonnet 5"` guarantees the friendly label, while `_DESCRIPTION`
    discloses that copilot-relay maps it to `gpt-5.6-sol`.
  - **`ANTHROPIC_DEFAULT_HAIKU_MODEL: gpt-5.6-sol[1m]`** — Haiku tier for current
    Claude Code versions, including sub-agents and small-fast side tasks.
  - **`ANTHROPIC_SMALL_FAST_MODEL: gpt-5.6-sol[1m]`** — legacy alias for older
    Claude Code versions.
  - **Real Opus 5 remains available** via `/model claude-opus-5[1m]` or
    `--model 'claude-opus-5[1m]'`; its name contains `opus`, so the relay sends
    it to `opusModel: claude-opus-5`.
- **Effort: `max`** — applied two ways:
  `effortLevel: "max"` (Claude Code's client-side reasoning budget,
  applied to every session) and `thinkEffort: max` in
  `~/.copilot-relay/config.yaml` (linked by `install.sh`, hot-reloaded by
  the relay, and forwarded to Copilot upstream). `MODEL_REASONING_EFFORT`
  remains in `settings.json` so the statusline can display the pinned effort.
- `ANTHROPIC_BASE_URL` — the local `copilot-relay` proxy on port 4142.
  All model names above are Copilot-side identifiers the proxy knows how
  to route. Claude Code itself doesn't know about `gpt-5.6-sol`; the proxy
  translates every request and replies with Anthropic-shaped JSON.
- `ANTHROPIC_AUTH_TOKEN` — required by Claude Code's startup check.
  `dummy` is fine; real auth happens in `npx copilot-relay auth`.
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

#### Native concurrent-subagent limit

`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS=16` configures Claude Code's built-in
per-session limit (v2.1.217+). When 16 subagents are running, another Claude-
spawned `Agent` call fails with `Concurrent subagent limit reached`; admission
reopens when the running count drops. `install.sh` accepts an already-current
CLI, uses the Homebrew cask only when necessary, and refuses to complete the
Homebrew setup path if
the installed CLI still cannot satisfy v2.1.217.

This adopts Claude Code's documented native semantics rather than preserving an
absolute fail-closed hook. A user-started `/subtask` occupies a slot but is not
blocked, resuming a finished subagent can push the count above 16, and ultracode
sessions are exempt. Workflow agents and agent-team teammates follow their own
limits. The former `PreToolUse`/`PostToolUse`/`SubagentStop` hook chain, `jq`
payload parsing, locks, and per-session state files have been removed.

#### `statusline.sh`

Executable Claude Code statusline with the same five-line layout as the Copilot
statusline. Unlike the Copilot sibling, it renders **no** subagent rows — Claude
Code ships its own native subagent UI, so the inline `subagents` count and the
live-agent tree below L5 were removed (intentional divergence). Concurrent
admission is handled natively by Claude Code; the statusline needs no hook
state.

#### Wrappers (`oh-my-zsh-custom/claude.zsh`, `cc.zsh`)

Bare `claude` is wrapped as a shell function that always passes
`--permission-mode bypassPermissions`. The CLI flag is the only path
the binary honors for non-interactive bypass — the equivalent
settings.json key is gated off by feature flag.

Same applies to `cc [title]`: it renames the active terminal tab via
OSC 1/2 plus RMUX window naming (default title is the current directory
path) then launches Claude Code with
the bypass flag plus `--model 'claude-sonnet-5[1m]' --effort max`. The title is prefixed with a Nerd Font glyph
(`mdi-creation`, U+F0674 — sparkles) so Claude tabs are visually distinct
from Copilot's `gg` tabs (which use `fa-github`) and from plain shells.

To switch models mid-session, use Claude Code's `/model <name>` —
free-form names pass through the proxy unchanged.

One-time setup (after running `install.sh` on a fresh box):

```bash
npx copilot-relay auth  # browser device-code login (GitHub)
claude              # in another shell — shows Sonnet 5 1M @ max; relay serves gpt-5.6-sol
```

Project-specific Claude Code config is synced by committing files to each
project repo (`.claude/settings.json`, `.claude/CLAUDE.md`, and `.mcp.json`).
`install.sh` intentionally does **not** copy per-project state from
`~/.claude.json`: that file is machine-local, path-keyed, and can include trust,
OAuth, cache, and local MCP state. The only `~/.claude.json` mutation here is the
safe user-scope MCP import from Copilot's MCP file.

> **Caveat:** Claude Code rewrites `settings.json` at runtime to add fields
> like `firstStartTime`, telemetry IDs, etc. Same atomic
> read–mutate–write–commit pattern as Copilot CLI's `settings.json`. If a
> spurious diff appears in the working tree, restore the committed shape
> rather than committing the runtime addition.

## Requirements

### Apps and npm CLIs (auto-installed on macOS)

- [oh-my-zsh](https://ohmyz.sh/) — installed unattended if missing so
  `oh-my-zsh-custom/` files can be linked
- [GitHub Copilot CLI](https://github.com/github/copilot) — existing non-npm
  install is preserved; npm `@github/copilot` is installed only when `copilot`
  is missing or already npm-managed
- [Claude Code CLI](https://github.com/anthropics/claude-code) — installed via
  Homebrew cask `claude-code`
- [`copilot-relay`](https://www.npmjs.com/package/copilot-relay) — installed as
  an npm global; `install.sh` configures and starts the launchd proxy on port
  4142
- [`wakatime/copilot-cli-wakatime`](https://github.com/wakatime/copilot-cli-wakatime)
  — installed as a Copilot plugin; handles Copilot CLI activity upload
- [`gh`](https://cli.github.com/) — optional; `statusline.sh` calls
  `gh auth status` (cached 5 minutes) to render the GH segment

### Tools (auto-installed via Homebrew on macOS)

- [Homebrew](https://brew.sh/) — bootstrapped by `install.sh` if missing
- [Node.js](https://nodejs.org/) / npm — installed via Homebrew for the npm
  global CLIs
- [`jq`](https://jqlang.github.io/jq/) — used to merge MCP config and remove
  legacy WakaTime MCP entries
- [RMUX](https://github.com/Helvesec/rmux) 0.10.x — daemon-backed terminal
  multiplexer; `.rmux.conf` is parsed and exercised by `scripts/check.sh`.
- `git` — installed via Homebrew; required by oh-my-zsh and repository workflows.

### Fonts (installed automatically)

- Recursive base fonts — Homebrew cask `font-recursive`
- Recursive Mono Nerd Font — Homebrew cask `font-recursive-mono-nerd-font`
- RecMonoBaker + RecMonoSt.Helens TTFs — downloaded from
  [`MOSconfig/recursive-code-config`](https://github.com/MOSconfig/recursive-code-config/releases)
  latest release into `~/Library/Fonts`
- Symbols Only Nerd Font — `font-symbols-only-nerd-font`
- Noto Color Emoji — `font-noto-color-emoji`

### Shell helper formulae used by `custom.zsh`

- `eza`, `neovim`, `autojump`, `zsh-fast-syntax-highlighting`, and
  `zsh-completions` are installed by `install.sh`.

## License

See [LICENSE](LICENSE).
