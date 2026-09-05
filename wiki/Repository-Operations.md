# Repository operations

English | [简体中文](Repository-Operations-zh-CN.md)

This page explains where files live and how `install.sh` moves them into your home folder.

## Folder rule

```text
config/   config used now
scripts/  code that runs and external release pins
wiki/     full help
```

These files stay at fixed paths because tools look for them there:

```text
.claude/CLAUDE.md
.github/copilot-instructions.md
.github/workflows/*.yml
.gitignore
install.sh
ReadMe.md
```

## The manifest

`config/manifest.tsv` is the active install list. The installer does not scan the root for random dotfiles.

Each row has three tab-separated fields:

```text
type<TAB>source<TAB>home destination
```

Types:

| Type | Work |
|---|---|
| `link` | Make a symlink in `$HOME` |
| `merge` | Merge safe shared data into a local file |
| `render` | Fill a template and write a local file |

The installer checks that every source exists, every destination is unique, and every source is under `config/` or `scripts/`.

## Active paths

| Repository source | Home destination or work |
|---|---|
| `config/git/ignore` | `~/.config/git/ignore` |
| `config/rmux/rmux.conf` | `~/.rmux.conf` |
| `config/sonicterm/**.toml` | matching files under `~/.sonicterm/` |
| `config/zsh/**` | matching files under `~/.oh-my-zsh/custom/` |
| `config/claude/**` | `~/.claude/` |
| `config/copilot/**` | `~/.copilot/` |
| `config/copilot-relay/config.yaml` | `~/.copilot-relay/config.yaml` |
| `config/mcp/mcp-shared.json` | merge into local Copilot MCP data |
| `config/launchd/*.plist` | render into `~/Library/LaunchAgents/` |
| `scripts/copilot/cleanup-legacy.sh` | `~/.copilot/cleanup-legacy.sh` |

The manifest rejects archived sources. Wiki pages are never installed.

## External theme assets

Apollo theme files are not stored in Git or listed as manifest sources. `scripts/apollo-releases.tsv` pins exact upstream tags and SHA-256 values. `install.sh` verifies those files, builds a complete local set under `~/.local/share/dot-configs/apollo/`, and links the active SonicTerm, RMUX, eza, and Claude theme paths to that set.

Generated status-line, shell-prompt, and Claude theme files are local runtime state derived from the verified canonical palette. A failed download or checksum does not replace the active set. See [Apollo theme](Apollo-Theme.md).

## Safe links

For each `link` row, `install.sh` does this:

1. Leave the link alone when it already points to the right source.
2. Remove an old link only when it points to the exact old repo path.
3. Move any other file or link to `<name>.bak.YYYYMMDDHHMMSS`.
4. Make the new link.
5. Keep the newest backup for that destination.

A user file is not silently deleted. A foreign symlink is not silently deleted. Both become backups before the managed link is made.

The move from old root paths to `config/` is handled in the same install run.

## Add or change config

Edit the repository source. Do not edit the linked file in `$HOME`.

To add a managed file:

1. Put it under `config/` or `scripts/`.
2. Add one row to `config/manifest.tsv`.
3. Add or update its bilingual Wiki page.
4. Run `scripts/check.sh all`.
5. Run `./install.sh` twice.
6. Check the link or rendered file.

A second install should make no unwanted change.

## Installer switches

Use these only when needed:

```sh
SKIP_BREW=1 ./install.sh
SKIP_NPM_GLOBALS=1 ./install.sh
SKIP_OH_MY_ZSH=1 ./install.sh
DOT_CONFIGS_INSTALL_LOG=/tmp/install.log ./install.sh
```

The normal log is `~/Library/Logs/dot-configs-install.log`.

## Shared and secret MCP data

`config/mcp/mcp-shared.json` may contain only safe, public server data.

The installer merges it into:

```text
~/.config/github-copilot/mcp.json
```

Local Copilot entries are kept. Shared entries win when the same server name exists. The merged Copilot server map then replaces the top-level `mcpServers` field in `~/.claude.json`.

A server added only to `~/.claude.json` will be removed by the next install. Put a server in the local Copilot MCP file when both tools need it.

Tokens and API keys for optional MCP servers belong only in the local Copilot MCP file. Do not add them to this repo.

Copilot includes `github-mcp-server` and uses its existing GitHub login. Claude uses authenticated `gh` for GitHub work. This repo does not provision a separate GitHub MCP entry or PAT; shared MCP sync remains in place for Playwright and other configured servers.

Claude's local-scope entries live under `projects[].mcpServers` in `~/.claude.json`. They replace same-name user entries; headers are not merged. The MCP import leaves these local entries untouched.

## Local state

These paths are local and are not config sources:

- `~/.claude.json` — Claude onboarding, approvals, selected Apollo theme, project state, and MCP state
- `~/.local/share/dot-configs/apollo/` — verified Apollo releases and generated runtime adapters
- `~/.copilot-relay/github_token` — relay auth
- `~/.copilot-relay/copilot_token.json` — relay token cache
- `~/.copilot-relay/logs/` — relay logs
- `~/.sonicterm/logs/` — SonicTerm logs
- SonicTerm save locks and backups
- `~/.tmux/plugins/` and old resurrect files

Local state is not the same as a user global. `~/.claude/CLAUDE.md` and `~/.copilot/copilot-instructions.md` are user globals: links to tracked sources in `config/`, edited here and reinstalled. `~/.claude.json` is local state the tools own. The MCP import replaces only its top-level `mcpServers` field and leaves per-project overrides alone. Other installer steps can update local preferences, such as the selected Apollo theme.

## Retired links

The installer no longer installs tmux or WezTerm. It removes `~/.tmux.conf`, `~/.wezterm.lua`, and the retired SonicTerm `wezterm.toml` only when they still point to this repo's exact old managed paths. User-owned files and links stay. Manually installed editor themes are never removed.

The duplicate `~/.copilot/AGENTS.md` link is also removed only when it points to this repo's current or former managed source. User files and foreign links stay.

Retired tmux and WezTerm configs remain in Git history. Inspect the v2.4.0 copies with:

```sh
git show v2.4.0:archive/tmux/.tmux.conf
git show v2.4.0:archive/wezterm/wezterm.lua
```

These are reference copies, not active config. Any future managed file must follow the current manifest rules.

## Apply and check

```sh
./install.sh
./install.sh
scripts/check.sh all
```

Then check the main links:

```sh
ls -l ~/.rmux.conf ~/.claude/settings.json ~/.copilot/settings.json \
  ~/.copilot-relay/config.yaml ~/.sonicterm/sonicterm.toml
```

More service checks are in [Services and automation](Services-and-Automation.md).
