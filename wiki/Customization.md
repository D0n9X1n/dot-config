# Customization

English | [简体中文](Customization-zh-CN.md)

This page shows how to add your own files without editing upstream files. Your changes then never conflict with an upstream update.

## The rule

Upstream never adds, changes, or tracks anything under `local/`. CI checks this. Put all of your own files there.

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

To change a tool that upstream manages, add a separate file the tool loads, not a second copy of the upstream file.

Removing a row does not remove its old link. Delete that link by hand.

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
| Nested local repo | `local/` is its own Git repo | yes | `uu` |
| Public fork | `local/` committed to your fork | no | Sync fork, then `uu` |

This repository is public, so a fork is public too. Never commit tokens, keys, or auth files to a fork. Use a private overlay for anything private.

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

### Nested local repo

Make `local/` its own Git repo inside the upstream clone:

```sh
cd ~/Public/dot-configs
git init local
echo local/ >> .git/info/exclude
```

`.git/info/exclude` hides `local/` from the outer repo without changing the tracked `.gitignore`. Add a remote to `local/` to keep a backup.

### Public fork

Fork upstream, then commit your files under `local/` in the fork. Upstream never touches `local/`, so syncing never conflicts:

```sh
gh repo sync YOU/dot-config
uu
```

You can also press **Sync fork** on GitHub, or run `git pull upstream main` and push.

## Update

`uu` fast-forwards the checkout, then runs `./install.sh`. When the overlay folder has its own `.git`, `uu` checks it first and fast-forwards it too. A dirty tree, a detached HEAD, a missing upstream, or a branch that cannot fast-forward stops `uu` before either checkout moves.

A fork's own commits make its `main` differ from upstream. Sync the fork on GitHub first; then `uu` can fast-forward.

## Check

```sh
scripts/check.sh local
scripts/check.sh all
./install.sh
ls -l ~/.oh-my-zsh/custom/zzz-local-*
```

See [Repository operations](Repository-Operations.md) for the upstream manifest and link rules.
