# Apollo theme

English | [简体中文](Apollo-Theme-zh-CN.md)

Apollo is the shared theme for the active terminal, multiplexer, shell, CLI status lines, and file listings.

The canonical palette and application adapters live in the [Apollo Theme organization](https://github.com/apollo-theme). This repository does not store palette values or generated theme artifacts.

## Active surfaces

| Surface | Source |
|---|---|
| SonicTerm | Tagged `sonicterm-apollo-theme` release asset |
| RMUX | Tagged `rmux-apollo-theme` release asset |
| eza | Tagged `eza-apollo-theme` release asset |
| Claude Code UI | Generated locally from the tagged canonical palette |
| Claude and Copilot status lines | One local include generated from the tagged canonical palette |
| Oh My Zsh prompt | Structure in this repo; colors generated locally |
| fast-syntax-highlighting | Its Base16 theme, using the terminal ANSI palette |
| Copilot CLI UI | Built-in `default` theme, using the terminal ANSI palette |

Neovim is managed in a different repository. This installer does not modify Neovim config, plugins, or runtime state.

## Release lock

`scripts/apollo-releases.tsv` pins each upstream repository, tag, artifact, and SHA-256. Child projects have independent versions; do not infer their tags from the canonical palette release.

The installer downloads exact tagged files. It does not follow `main` or query `latest`. An online maintainer check verifies published bytes:

```sh
scripts/check.sh apollo-online
```

Ordinary `scripts/check.sh all` remains offline.

## Local bundle

Verified files live under:

```text
~/.local/share/dot-configs/apollo/
  blobs/
  sets/
  current -> sets/<bundle-hash>
  fsh/
```

The bundle hash covers the release lock and adapter code. The installer verifies every download before creating a complete set, then switches `current` only after all release files and generated adapters validate. A valid bundle works offline. A failed download or checksum leaves the previous bundle active.

Installed consumers link to `current`:

```text
~/.sonicterm/themes/apollo.toml
~/.config/rmux-apollo-theme/apollo-rmux.conf
~/.config/eza-apollo-theme/theme.yml
~/.claude/themes/apollo.json
```

Generated runtime files are local state. Do not commit them.

### Status-line color roles

The shared include generates `C_FG_BRIGHT` from the canonical `foregroundBright` color. Copilot uses it for Model, Effort, Path, and Branch values. Older bundles fall back to the normal foreground; no-color mode remains plain text. Claude keeps its existing colors.

## Updates

To update Apollo:

1. Review the new release in its Apollo repository.
2. Change only that row in `scripts/apollo-releases.tsv`.
3. Update its SHA-256.
4. Run `scripts/check.sh apollo-online`.
5. Run `scripts/check.sh all`.
6. Run `./install.sh` twice.
7. Reload SonicTerm and RMUX, then start new Claude and Copilot sessions.

Do not copy colors from upstream into config, scripts, or Wiki pages.

## Safe cleanup

The old `themes/apollo/` copies are gone. The installer removes the former SonicTerm `wezterm.toml` only when it is the exact symlink previously managed by this repository.

Manual Vim, Neovim, VS Code, Windows Terminal, or WezTerm theme files are user-owned and are never removed.

See [SonicTerm and shell](SonicTerm-and-Shell.md), [RMUX](RMUX.md), and [Development and releases](Development-and-Releases.md).
