# Customization

English | [简体中文](Customization-zh-CN.md)

This page shows how to add your own files without editing upstream files. Your changes then never conflict with an upstream update.

## The rule

Upstream never adds, changes, or tracks anything under `local/`. CI checks this, and the tracked `.gitignore` ignores `/local/`, so your files never show in `git status` and never block `uu`. Put all of your own files there.

Do not edit upstream files such as `config/manifest.tsv`, `wiki/_Sidebar.md`, or `scripts/check.sh` for personal changes. If you need a change there, open an issue upstream.

## The overlay folder

The overlay is `local/` in your checkout. Set `DOT_CONFIGS_LOCAL` to an absolute path to use another folder.

```text
local/
  manifest.tsv   your own link rows
  zsh/*.zsh      your own shell files, loaded after every upstream helper
  check.sh       your own checks
  README.md      your own notes
```

Every part is optional. `install.sh` and `scripts/check.sh` do nothing when the folder is absent.

### `manifest.tsv`

It uses the same three tab-separated fields as `config/manifest.tsv`. Only `link` rows are allowed. Sources are relative to the overlay folder.

```text
# type	source	destination
link	config/npmrc	.npmrc
link	bin/my-tool	.local/bin/my-tool
```

`install.sh` stops before it changes anything when a row:

- is not a `link` row;
- has an absolute source or destination, or a `..` part;
- points to a missing source;
- repeats a destination;
- uses a destination that upstream already manages, such as `.tmux.conf`;
- uses a reserved `.oh-my-zsh/custom/zzz-local-*` name.

To change a tool that upstream manages, add a separate file the tool loads, not a second copy of the upstream file. Native tmux and RMUX load such a file last; see below.

Removing a row does not remove its old link. Delete that link by hand.

### tmux and RMUX overrides

`~/.tmux.conf` ends with `source-file -q ~/.tmux.local.conf`, and `~/.rmux.conf` ends with `source-file -q ~/.rmux.local.conf`. Upstream never ships either file. Because they load last, any option set there wins, including `window-status-current-style`, the active tab color.

```text
# local/manifest.tsv
link	tmux/local.conf	.tmux.local.conf
link	tmux/local.conf	.rmux.local.conf
```

```tmux
# local/tmux/local.conf
set -g window-status-current-style 'bg=#89b4fa,fg=#1e1e2e,bold'
```

New servers read it. To apply it to a running server, run `tmux source-file ~/.tmux.conf` (or the RMUX equivalent) yourself.

### `zsh/*.zsh`

Each `local/zsh/NAME.zsh` links to `~/.oh-my-zsh/custom/zzz-local-NAME.zsh`. Oh-my-zsh loads files in name order, so your files load last and can replace upstream aliases and functions.

When you delete or rename a file in `local/zsh/`, the next install removes its old `zzz-local-*` link. It never removes a regular file or a link that points somewhere else.

### `check.sh`

`scripts/check.sh all`, `smoke`, and `local` validate `local/manifest.tsv`, then run `local/check.sh` with Bash from the repository root. `DOT_CONFIGS_LOCAL` holds the overlay path. A non-zero exit fails the check.

Upstream ShellCheck skips `local/`. Lint your own files in `local/check.sh`. For zsh files, `zsh -n FILE` checks syntax.

### `README.md`

Keep your own notes here. The upstream Wiki check and the Wiki publisher read only `wiki/`, so your notes never touch the sidebar or the `-zh-CN` page rule.

## Choose a setup

| Setup | Your files | Private | Update |
|---|---|---|---|
| Private overlay repo (recommended) | a separate private Git repo | yes | `uu` |
| Local folder | `local/` in the checkout, ignored by Git | yes | `uu` |
| Fork mirror | a local folder or a private overlay | yes | `uu` (also pushes to the fork) |

In every setup, your files stay out of the upstream history, so `uu` can always fast-forward. This repository is public, so a fork is public too. Never commit tokens, keys, or auth files to a fork.

### Private overlay repo

Clone upstream, and keep your files in a separate private repo:

```sh
git clone git@github.com:D0n9X1n/dot-config.git ~/Public/dot-configs
git clone git@github.com:YOU/dot-config-local.git ~/Public/dot-configs-local
```

Add this line to `~/.zshrc` before oh-my-zsh loads:

```sh
export DOT_CONFIGS_LOCAL="$HOME/Public/dot-configs-local"
```

Then run `./install.sh`.

### Local folder

Create `local/` inside the upstream clone. Git already ignores it.

```sh
cd ~/Public/dot-configs
mkdir -p local/zsh
```

To keep a backup or history, make it its own Git repo with `git init local` and add a private remote. `uu` then fast-forwards it too.

### Fork mirror

Keep your fork equal to upstream, and keep your files in a local folder or a private overlay. Clone the fork, then make `main` track upstream:

```sh
git clone git@github.com:YOU/dot-config.git ~/Public/dot-configs
cd ~/Public/dot-configs
git remote add upstream https://github.com/D0n9X1n/dot-config.git
git fetch upstream
git branch --set-upstream-to=upstream/main main
```

`uu` then fast-forwards from upstream and pushes the same commits to `origin`, so both repos stay equal. Set `DOT_CONFIGS_FORK_REMOTE` when the fork remote has another name. The push never forces and never waits for a password or SSH passphrase. When it fails, for example because the fork has its own commits, `uu` shows Git's error, still updates the checkout, and installs; sync the fork once by hand. Set `DOT_CONFIGS_FORK_REMOTE=none` to turn the push off.

Do not commit your own files to the fork: the fork would no longer match upstream, and the push would stop working.

## Update

`uu` fast-forwards the checkout, then runs `./install.sh`. When the overlay folder has its own `.git`, `uu` checks it first and fast-forwards it too. A dirty tree, a detached HEAD, a missing upstream, or a branch that cannot fast-forward stops `uu` before either checkout moves.

`./install.sh` changes no tracked file. A second run makes no change, and it rewrites `~/.claude.json` only when the MCP server map differs.

## Check

```sh
scripts/check.sh local
scripts/check.sh all
./install.sh
ls -l ~/.oh-my-zsh/custom/zzz-local-*
```

See [Repository operations](Repository-Operations.md) for the upstream manifest and link rules.
