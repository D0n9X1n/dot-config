# Repository operations

English | [简体中文](Repository-Operations-zh-CN.md)

This page explains where files live and how `install.sh` moves them into your home folder.

## Folder rule

```text
config/   config used now
archive/  old config; never installed
scripts/  code that runs
themes/   color files
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
| `config/zsh/*.zsh` | `~/.oh-my-zsh/custom/` |
| `config/claude/**` | `~/.claude/` |
| `config/copilot/**` | `~/.copilot/` |
| `config/copilot-relay/config.yaml` | `~/.copilot-relay/config.yaml` |
| `config/mcp/mcp-shared.json` | merge into local Copilot MCP data |
| `config/launchd/*.plist` | render into `~/Library/LaunchAgents/` |
| `scripts/copilot/cleanup-legacy.sh` | `~/.copilot/cleanup-legacy.sh` |

`archive/`, `themes/`, and `wiki/` are never linked by the installer.

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

Put tokens and API keys only in the local Copilot MCP file. Do not add them to this repo.

The hosted GitHub MCP uses a Bearer PAT header. Its OAuth dynamic client registration does not work with this setup.

## Local state

These paths are local and are not config sources:

- `~/.claude.json` — Claude onboarding, approvals, project state, and MCP state
- `~/.copilot-relay/github_token` — relay auth
- `~/.copilot-relay/copilot_token.json` — relay token cache
- `~/.copilot-relay/logs/` — relay logs
- `~/.sonicterm/logs/` — SonicTerm logs
- SonicTerm save locks and backups
- `~/.tmux/plugins/` and old resurrect files

## Retired links

The installer no longer installs tmux or WezTerm. It removes `~/.tmux.conf` and `~/.wezterm.lua` only when they still point to this repo's old managed paths. User-owned files and links stay.

See [Archived tmux](Archive-Tmux.md) and [Archived WezTerm](Archive-WezTerm.md).

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
