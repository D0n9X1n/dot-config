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
    esac
    link_file "$entry" "${claude_dest}/${base}"
    # Preserve executable bit on shell scripts (e.g., statusline.sh) so
    # Claude Code can run them directly without chmod each time.
    case "$base" in
      *.sh) chmod +x "$entry" ;;
    esac
  done < <(find "$claude_src" -maxdepth 1 -mindepth 1 -type f -print0)
  echo "Linked Claude Code config files to $claude_dest"

  # Import Copilot CLI's MCP servers into Claude Code's user-scope config.
  # Claude Code reads MCP servers from ~/.claude.json (top-level
  # `mcpServers` key) — NOT from ~/.claude/settings.json — so we have to
  # merge them into that file. The copilot list lives at
  # ~/.config/github-copilot/mcp.json (symlinked at ~/.copilot/mcp-config.json
  # on disk; never in this repo because it carries WAKATIME_API_KEY etc.).
  #
  # Idempotent: re-running install.sh just rewrites the same merged
  # mcpServers map. If jq isn't installed, or the copilot MCP file is
  # missing, this step is a silent no-op and Claude Code's existing
  # mcpServers (or absence thereof) is left untouched.
  copilot_mcp="${HOME}/.config/github-copilot/mcp.json"
  claude_user_json="${HOME}/.claude.json"
  if have_cmd jq && [ -f "$copilot_mcp" ]; then
    # Read the source servers map (defaults to {} if the file is malformed).
    src_mcp_json="$(jq -c '.mcpServers // {}' "$copilot_mcp" 2>/dev/null || echo '{}')"
    if [ "$src_mcp_json" != '{}' ] && [ "$src_mcp_json" != "null" ]; then
      tmp_user="$(mktemp -t claude-user-json.XXXXXX)"
      if [ -f "$claude_user_json" ]; then
        # Replace .mcpServers (no per-server merge — copilot's file is
        # authoritative); preserve every other key (telemetry IDs, project
        # state, settings cache, etc.).
        if jq --argjson src "$src_mcp_json" '.mcpServers = $src' \
            "$claude_user_json" >"$tmp_user"; then
          backup_path "$claude_user_json"
          mv "$tmp_user" "$claude_user_json"
          chmod 600 "$claude_user_json"
          echo "Imported $(echo "$src_mcp_json" | jq 'length') MCP servers into $claude_user_json (from $copilot_mcp)"
        else
          rm -f "$tmp_user"
          echo "Warning: jq merge into $claude_user_json failed; MCP import skipped"
        fi
      else
        # Fresh box — Claude Code hasn't run yet. Seed the file with just
        # the mcpServers map; Claude Code will fill in the rest on launch.
        printf '{"mcpServers":%s}\n' "$src_mcp_json" >"$tmp_user"
        mv "$tmp_user" "$claude_user_json"
        chmod 600 "$claude_user_json"
        echo "Created $claude_user_json with $(echo "$src_mcp_json" | jq 'length') MCP servers (from $copilot_mcp)"
      fi
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
