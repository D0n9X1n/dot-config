#!/usr/bin/env bash
set -euo pipefail

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest_dir="${HOME}"
timestamp="$(date +"%Y%m%d%H%M%S")"

is_macos() {
  [ "$(uname -s)" = "Darwin" ]
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_macos_deps() {
  if ! have_cmd brew; then
    echo "Homebrew not found. Install it from https://brew.sh/ and re-run."
    exit 1
  fi

  # homebrew/cask-fonts was deprecated in 2024 and merged into homebrew/cask;
  # ignore failures so older clones don't error here.
  brew tap homebrew/cask-fonts >/dev/null 2>&1 || true

  local app_casks=(
    wezterm
  )
  local font_casks=(
    font-recursive # Provides the Recursive Mono variable family (St.Helens, Casual, Linear, Duotone)
    font-recursive-mono-nerd-font
    font-symbols-only-nerd-font
    font-noto-color-emoji
  )
  local formulae=(
    tmux
  )

  local cask
  for cask in "${app_casks[@]}" "${font_casks[@]}"; do
    if brew list --cask "$cask" >/dev/null 2>&1; then
      continue
    fi
    brew install --cask "$cask" || echo "Warning: failed to install cask '$cask' (skipping)"
  done

  local formula
  for formula in "${formulae[@]}"; do
    if brew list --formula "$formula" >/dev/null 2>&1; then
      continue
    fi
    brew install "$formula" || echo "Warning: failed to install formula '$formula' (skipping)"
  done
}

backup_path() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    mv "$path" "${path}.bak.${timestamp}"
  fi
}

link_file() {
  local src="$1"
  local dest="$2"

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return 0
  fi

  backup_path "$dest"
  ln -s "$src" "$dest"
}

if is_macos; then
  if [ "${SKIP_BREW:-0}" = "1" ]; then
    echo "Skipping Homebrew step (SKIP_BREW=1)."
  else
    install_macos_deps
  fi
else
  echo "Auto-install only supports macOS + Homebrew. Install apps/fonts manually."
fi

while IFS= read -r -d '' entry; do
  base="$(basename "$entry")"
  link_file "$entry" "${dest_dir}/${base}"
done < <(find "$src_dir" -maxdepth 1 -mindepth 1 -name ".*" -type f -print0)

# Link oh-my-zsh custom files (oh-my-zsh-custom/* -> ~/.oh-my-zsh/custom/*)
omz_custom_src="${src_dir}/oh-my-zsh-custom"
omz_custom_dest="${HOME}/.oh-my-zsh/custom"
if [ -d "$omz_custom_src" ]; then
  if [ -d "$omz_custom_dest" ]; then
    while IFS= read -r -d '' entry; do
      base="$(basename "$entry")"
      link_file "$entry" "${omz_custom_dest}/${base}"
    done < <(find "$omz_custom_src" -maxdepth 1 -mindepth 1 -type f -print0)
    echo "Linked oh-my-zsh custom files to $omz_custom_dest"
  else
    echo "Skipping oh-my-zsh custom files: $omz_custom_dest does not exist (oh-my-zsh not installed?)"
  fi
fi

# Link Copilot CLI config files (copilot/* -> ~/.copilot/*)
copilot_src="${src_dir}/copilot"
copilot_dest="${HOME}/.copilot"
if [ -d "$copilot_src" ]; then
  if [ -d "$copilot_dest" ]; then
    while IFS= read -r -d '' entry; do
      base="$(basename "$entry")"
      link_file "$entry" "${copilot_dest}/${base}"
      # Preserve executable bit on shell scripts (e.g., statusline.sh) so
      # Copilot CLI can run them directly without chmod each time.
      case "$base" in
        *.sh) chmod +x "$entry" ;;
      esac
    done < <(find "$copilot_src" -maxdepth 1 -mindepth 1 -type f -print0)
    echo "Linked Copilot CLI config files to $copilot_dest"
  else
    echo "Skipping Copilot config files: $copilot_dest does not exist (copilot CLI not installed?)"
  fi
fi

# Link Claude Code config files (claude/* -> ~/.claude/*). Claude Code
# normally creates ~/.claude on first launch; mkdir -p so install.sh can
# wire things up on a fresh box without requiring a Claude Code launch
# first. Used to point Claude Code at the local copilot-api proxy so it
# can talk to GitHub Copilot models (see ReadMe.md).
claude_src="${src_dir}/claude"
claude_dest="${HOME}/.claude"
if [ -d "$claude_src" ]; then
  mkdir -p "$claude_dest"
  while IFS= read -r -d '' entry; do
    base="$(basename "$entry")"
    # Skip in-folder docs (README*) — they belong next to the config in the
    # repo but shouldn't pollute ~/.claude/ where Claude Code keeps state.
    case "$base" in
      README*) continue ;;
      # settings.json is GENERATED below (jq-merged with copilot's MCP
      # config so the WAKATIME_API_KEY secret stays out of the repo).
      # Skip the bare symlink here so the merge step doesn't fight it.
      settings.json) continue ;;
    esac
    link_file "$entry" "${claude_dest}/${base}"
    # Preserve executable bit on shell scripts (e.g., statusline.sh) so
    # Claude Code can run them directly without chmod each time.
    case "$base" in
      *.sh) chmod +x "$entry" ;;
    esac
  done < <(find "$claude_src" -maxdepth 1 -mindepth 1 -type f -print0)
  echo "Linked Claude Code config files to $claude_dest"

  # ~/.claude/settings.json — generated, NOT symlinked. We merge the
  # committed claude/settings.json with the user's local copilot MCP
  # config (~/.config/github-copilot/mcp.json) so Claude Code sees the
  # same MCP servers Copilot CLI does, without committing the secret-
  # bearing mcp.json to this public repo. Same reason copilot/'s
  # mcp-config.json is gitignored upstream.
  #
  # Idempotent: rewrites the file every time, but only when the source
  # files actually exist. If jq isn't installed, falls back to a plain
  # symlink (no MCP merge) so a fresh box can still get the rest of the
  # config wired up.
  claude_settings_src="${claude_src}/settings.json"
  claude_settings_dest="${claude_dest}/settings.json"
  copilot_mcp="${HOME}/.config/github-copilot/mcp.json"
  if [ -f "$claude_settings_src" ]; then
    if have_cmd jq && [ -f "$copilot_mcp" ]; then
      backup_path "$claude_settings_dest"
      tmp_settings="$(mktemp -t claude-settings.XXXXXX)"
      # `* { mcpServers: ... }` recursively merges, but mcpServers gets
      # FULLY replaced by the right-hand value (no per-server merge),
      # which is what we want: the copilot file is authoritative.
      if jq -s '.[0] * { mcpServers: (.[1].mcpServers // {}) }' \
          "$claude_settings_src" "$copilot_mcp" >"$tmp_settings"; then
        mv "$tmp_settings" "$claude_settings_dest"
        chmod 600 "$claude_settings_dest"
        echo "Generated ${claude_settings_dest} (claude/settings.json + copilot mcp.json)"
      else
        rm -f "$tmp_settings"
        echo "Warning: jq merge failed for $claude_settings_dest — falling back to plain link"
        link_file "$claude_settings_src" "$claude_settings_dest"
      fi
    else
      # No jq, or no copilot MCP config — link the bare settings file so
      # the rest of the Claude Code wiring still works.
      link_file "$claude_settings_src" "$claude_settings_dest"
    fi
  fi
fi

# Bootstrap TPM (Tmux Plugin Manager) and install plugins listed in
# .tmux.conf. Skipped if tmux isn't on PATH. Idempotent: re-running
# install.sh is a no-op once everything is in place.
if have_cmd tmux && [ -f "${HOME}/.tmux.conf" ]; then
  tpm_dir="${HOME}/.tmux/plugins/tpm"
  if [ ! -d "$tpm_dir" ]; then
    git clone --depth=1 https://github.com/tmux-plugins/tpm "$tpm_dir" \
      || echo "Warning: failed to clone TPM (run prefix+I in tmux to retry)"
  fi
  if [ -d "$tpm_dir" ]; then
    # install_plugins uses `tmux start-server; show-environment` to discover
    # TMUX_PLUGIN_MANAGER_PATH. That requires the default tmux socket to
    # load .tmux.conf (which exports the var via the tpm init line). The
    # script below handles the server start/stop transparently.
    "$tpm_dir/bin/install_plugins" >/dev/null \
      || echo "Warning: TPM plugin install reported errors (run prefix+I in tmux to retry)"
  fi
fi

echo "Linked dotfiles from $src_dir to $dest_dir"
