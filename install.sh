#!/usr/bin/env bash
set -euo pipefail

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest_dir="${HOME}"
timestamp="$(date +"%Y%m%d%H%M%S")"

is_macos() {
  [ "$(uname -s)" = "Darwin" ]
}

# Windows-running-bash detection. install.sh is the POSIX installer — we
# want to gracefully skip zsh-only files (oh-my-zsh customs, .tmux.conf)
# when someone runs it under Git Bash / MSYS2 / Cygwin / WSL on Windows.
# The recommended Windows path is install.ps1; this is the safety net for
# users who get here anyway.
is_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
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

# Top-level dotfiles (.tmux.conf etc.) — POSIX-only. Skip on Windows where
# tmux isn't the typical session manager (Windows Terminal / WezTerm panes
# replace it).
if is_windows; then
  echo "Skipping top-level dotfiles (.tmux.conf etc.): POSIX-only on Windows"
else
  while IFS= read -r -d '' entry; do
    base="$(basename "$entry")"
    link_file "$entry" "${dest_dir}/${base}"
  done < <(find "$src_dir" -maxdepth 1 -mindepth 1 -name ".*" -type f -print0)
fi

# Link oh-my-zsh custom files (oh-my-zsh-custom/* -> ~/.oh-my-zsh/custom/*).
# Skipped on Windows — zsh isn't the default shell, and the .zsh files use
# zsh-specific syntax (`emulate -L zsh`, `(( $+commands[...] ))`, etc.).
# The PowerShell equivalents of cc/gg ship via install.ps1's profile snippet.
omz_custom_src="${src_dir}/oh-my-zsh-custom"
omz_custom_dest="${HOME}/.oh-my-zsh/custom"
if is_windows; then
  echo "Skipping oh-my-zsh custom files: zsh not the typical Windows shell (use install.ps1 for PowerShell equivalents)"
elif [ -d "$omz_custom_src" ]; then
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
      # Skip the PowerShell statusline on POSIX — it's only meaningful on
      # Windows (linked by install.ps1). Symlinking it here would just
      # clutter ~/.copilot with a script that never runs.
      # Skip settings-windows.json — POSIX uses the canonical settings.json.
      case "$base" in
        *.ps1) continue ;;
        settings-windows.json) continue ;;
      esac
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
    # Skip the PowerShell statusline on POSIX (Windows-only — see install.ps1).
    # Skip settings-windows.json — POSIX uses the canonical settings.json.
    case "$base" in
      README*) continue ;;
      *.ps1) continue ;;
      settings-windows.json) continue ;;
    esac
    link_file "$entry" "${claude_dest}/${base}"
    # Preserve executable bit on shell scripts (e.g., statusline.sh) so
    # Claude Code can run them directly without chmod each time.
    case "$base" in
      *.sh) chmod +x "$entry" ;;
    esac
  done < <(find "$claude_src" -maxdepth 1 -mindepth 1 -type f -print0)
  echo "Linked Claude Code config files to $claude_dest"

  # Merge tracked, secret-free MCP servers from this repo into the user's
  # Copilot MCP config. mcp-shared.json carries entries that are safe to
  # commit (e.g. the GitHub remote MCP — OAuth, no PAT in the file). Per-
  # machine secret-bearing entries (WAKATIME_API_KEY etc.) stay in the
  # gitignored ~/.config/github-copilot/mcp.json and are preserved by the
  # merge. shared > local on key collision so the synced version wins.
  shared_mcp="${src_dir}/mcp-shared.json"
  copilot_mcp_pre="${HOME}/.config/github-copilot/mcp.json"
  if have_cmd jq && [ -f "$shared_mcp" ]; then
    mkdir -p "$(dirname "$copilot_mcp_pre")"
    if [ ! -f "$copilot_mcp_pre" ]; then
      # Bootstrap with just the shared entries.
      jq '{mcpServers: (.mcpServers // {})}' "$shared_mcp" >"$copilot_mcp_pre" \
        && echo "Created $copilot_mcp_pre with $(jq '.mcpServers | length' "$copilot_mcp_pre") shared MCP servers"
    else
      tmp_mcp="$(mktemp)"
      if jq -s '
            .[0].mcpServers as $local
            | .[1].mcpServers as $shared
            | .[0] + {mcpServers: ($local + $shared)}
          ' "$copilot_mcp_pre" "$shared_mcp" >"$tmp_mcp" 2>/dev/null; then
        mv "$tmp_mcp" "$copilot_mcp_pre"
        echo "Merged shared MCP servers into $copilot_mcp_pre (shared wins on collision)"
      else
        rm -f "$tmp_mcp"
        echo "Warning: jq merge of shared MCP into $copilot_mcp_pre failed; skipped"
      fi
    fi
  fi

  # wakatime-mcp: vendored Python MCP server (server.py + wakatime_client.py
  # under wakatime-mcp/ in this repo). Bootstrap a venv at the canonical
  # ~/.local/share/wakatime-mcp location and register an mcpServers entry
  # pointing at it. Idempotent — venv is reused if already present;
  # requirements.txt drives pip install (no-op when nothing changed).
  #
  # Skipped if the user has no ~/.wakatime.cfg (i.e. they don't use
  # WakaTime). The key is read from that file rather than committed
  # because it's a secret.
  wm_src="${src_dir}/wakatime-mcp"
  wm_dest="${HOME}/.local/share/wakatime-mcp"
  wm_cfg="${HOME}/.wakatime.cfg"
  if [ -d "$wm_src" ] && have_cmd python3; then
    if [ ! -f "$wm_cfg" ]; then
      echo "wakatime-mcp: ~/.wakatime.cfg not found — skipping (run 'wakatime --help' or visit https://wakatime.com/settings to set up)"
    else
      wm_key="$(awk -F'= *' '/^api_key/{print $2; exit}' "$wm_cfg" | tr -d ' \r')"
      if [ -z "$wm_key" ]; then
        echo "wakatime-mcp: no api_key in $wm_cfg — skipping"
      else
        mkdir -p "$wm_dest"
        cp "$wm_src/server.py" "$wm_src/wakatime_client.py" "$wm_dest/"
        if [ ! -d "$wm_dest/venv" ]; then
          echo "wakatime-mcp: bootstrapping venv at $wm_dest/venv (one-time, ~30s)"
          python3 -m venv "$wm_dest/venv" \
            && "$wm_dest/venv/bin/pip" install -q --upgrade pip \
            && "$wm_dest/venv/bin/pip" install -q -r "$wm_src/requirements.txt" \
            && echo "wakatime-mcp: venv ready" \
            || echo "Warning: wakatime-mcp venv bootstrap failed"
        else
          # Refresh deps quietly only if requirements.txt is newer than
          # the venv's marker. Cheap mtime check; pip itself is idempotent.
          if [ "$wm_src/requirements.txt" -nt "$wm_dest/venv/pyvenv.cfg" ]; then
            "$wm_dest/venv/bin/pip" install -q -r "$wm_src/requirements.txt" \
              && touch "$wm_dest/venv/pyvenv.cfg"
          fi
        fi
        # Register the MCP entry into the user's per-machine mcp.json so
        # the existing copilot->claude pipeline lifts it into ~/.claude.json.
        # We write directly here (not via mcp-shared.json) because the
        # entry carries the WAKATIME_API_KEY secret.
        if [ -d "$wm_dest/venv" ]; then
          tmp_mcp="$(mktemp)"
          jq --arg cmd "$wm_dest/venv/bin/python3" \
             --arg srv "$wm_dest/server.py" \
             --arg key "$wm_key" \
             --arg pp  "$wm_dest" \
            '.mcpServers.wakatime = {
                type: "stdio",
                command: $cmd,
                args: [$srv],
                env: { WAKATIME_API_KEY: $key, PYTHONPATH: $pp }
              }' "$copilot_mcp_pre" >"$tmp_mcp" 2>/dev/null \
            && mv "$tmp_mcp" "$copilot_mcp_pre" \
            && echo "wakatime-mcp: registered in $copilot_mcp_pre" \
            || { rm -f "$tmp_mcp"; echo "Warning: wakatime-mcp jq registration failed"; }
        fi
      fi
    fi
  fi

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

# launchd agent: copilot-api proxy on login (macOS only). Renders the
# template (substituting absolute $HOME paths — launchd doesn't expand
# $HOME at runtime) into ~/Library/LaunchAgents and bootstraps it.
# Idempotent: if the agent is already loaded with the same content,
# bootout+bootstrap is a no-op restart; if content differs, the new
# version replaces the old.
if is_macos; then
  launchd_src="${src_dir}/launchd/com.d0n9x1n.copilot-api.plist"
  launchd_dest="${HOME}/Library/LaunchAgents/com.d0n9x1n.copilot-api.plist"
  if [ -f "$launchd_src" ]; then
    if ! have_cmd copilot-api; then
      echo "launchd: copilot-api not on PATH — skipping agent install (run 'npm i -g copilot-api' first, then re-run install.sh)"
    else
      mkdir -p "$(dirname "$launchd_dest")"
      mkdir -p "${HOME}/Library/Logs"
      # Render template — only touches __HOME__ tokens. Use sed -i'' for
      # BSD-sed compatibility on macOS (GNU-style `sed -i` would fail).
      sed "s|__HOME__|${HOME}|g" "$launchd_src" > "$launchd_dest"
      echo "Wrote $launchd_dest"
      # Bootstrap into the GUI domain of the current user. bootout first
      # so a content change actually replaces the running agent (load is
      # a no-op when the label already exists).
      uid="$(id -u)"
      launchctl bootout "gui/${uid}/com.d0n9x1n.copilot-api" 2>/dev/null || true
      if launchctl bootstrap "gui/${uid}" "$launchd_dest" 2>/dev/null; then
        echo "Loaded launchd agent com.d0n9x1n.copilot-api (logs: ~/Library/Logs/copilot-api.{out,err}.log)"
      else
        echo "Warning: launchctl bootstrap failed for com.d0n9x1n.copilot-api"
      fi
    fi
  fi
fi
