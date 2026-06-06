#!/usr/bin/env bash
set -euo pipefail

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest_dir="${HOME}"
timestamp="$(date +"%Y%m%d%H%M%S")"
install_log="${DOT_CONFIGS_INSTALL_LOG:-${HOME}/Library/Logs/dot-configs-install.log}"

setup_logging() {
  local log_dir
  log_dir="$(dirname "$install_log")"
  mkdir -p "$log_dir"
  if touch "$install_log" >/dev/null 2>&1; then
    exec > >(while IFS= read -r line; do
      printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line"
    done | tee -a "$install_log") 2>&1
    echo "Install log: $install_log"
  else
    echo "Warning: cannot write install log at $install_log"
  fi
}

setup_logging

is_macos() {
  [ "$(uname -s)" = "Darwin" ]
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

log_command() {
  local arg
  printf '+'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
  "$@"
}

prepend_path_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) PATH="${dir}:${PATH}" ;;
  esac
  export PATH
}

refresh_homebrew_path() {
  prepend_path_dir /usr/local/bin
  prepend_path_dir /opt/homebrew/bin
}

ensure_homebrew() {
  local installer=""

  refresh_homebrew_path
  if have_cmd brew; then
    return 0
  fi

  if ! have_cmd curl; then
    echo "Error: Homebrew is missing and curl is not available to install it."
    return 1
  fi

  echo "Homebrew not found. Installing Homebrew (this may prompt for your macOS password)."
  installer="$(mktemp -t homebrew-install.XXXXXX)"
  if ! log_command curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer" \
      || ! log_command /bin/bash "$installer"; then
    rm -f "$installer"
    echo "Error: Homebrew installation failed. Install it from https://brew.sh/ and re-run."
    return 1
  fi
  rm -f "$installer"

  refresh_homebrew_path
  if ! have_cmd brew; then
    echo "Error: Homebrew installed but brew is not on PATH."
    return 1
  fi
}

ensure_oh_my_zsh() {
  local installer=""

  if [ -d "${HOME}/.oh-my-zsh/custom" ]; then
    return 0
  fi

  if ! have_cmd curl; then
    echo "Warning: oh-my-zsh is missing and curl is not available to install it (skipping)"
    return 1
  fi

  echo "Installing oh-my-zsh (unattended; shell is not changed)."
  installer="$(mktemp -t oh-my-zsh-install.XXXXXX)"
  if ! log_command curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$installer" \
      || ! log_command env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$installer" "" --unattended; then
    rm -f "$installer"
    echo "Warning: oh-my-zsh installation failed (skipping)"
    return 1
  fi
  rm -f "$installer"
}

fix_zsh_compaudit_permissions() {
  local insecure_dirs=""
  local dir=""
  local remaining=""

  if ! have_cmd zsh; then
    echo "Skipping zsh compaudit permission fix: zsh not found."
    return 0
  fi

  insecure_dirs="$(zsh -fc '
    if command -v brew >/dev/null 2>&1; then
      brew_prefix="$(brew --prefix 2>/dev/null || true)"
      if [ -n "$brew_prefix" ] && [ -d "$brew_prefix/share/zsh-completions" ]; then
        fpath=("$brew_prefix/share/zsh-completions" $fpath)
      fi
    fi
    autoload -Uz compaudit
    compaudit 2>/dev/null
  ' || true)"

  if [ -z "$insecure_dirs" ]; then
    echo "zsh compaudit: completion directories are secure."
    return 0
  fi

  echo "zsh compaudit: fixing insecure completion directory permissions."
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    case "$dir" in
      /*) ;;
      *) continue ;;
    esac
    [ -e "$dir" ] || continue
    if chmod go-w "$dir" 2>/dev/null; then
      echo "Fixed zsh completion permissions: $dir"
    else
      echo "Warning: could not chmod go-w '$dir' (check owner/permissions)"
    fi
  done <<EOF
$insecure_dirs
EOF

  remaining="$(zsh -fc '
    if command -v brew >/dev/null 2>&1; then
      brew_prefix="$(brew --prefix 2>/dev/null || true)"
      if [ -n "$brew_prefix" ] && [ -d "$brew_prefix/share/zsh-completions" ]; then
        fpath=("$brew_prefix/share/zsh-completions" $fpath)
      fi
    fi
    autoload -Uz compaudit
    compaudit 2>/dev/null
  ' || true)"
  if [ -n "$remaining" ]; then
    echo "Warning: zsh compaudit still reports insecure directories:"
    printf '%s\n' "$remaining"
  fi
}

ensure_npm_cli_latest() {
  local package="$1"
  local binary="$2"
  local current=""
  local latest=""

  if ! have_cmd npm; then
    echo "Warning: npm not found; cannot install or update $package (skipping)"
    return 1
  fi

  latest="$(npm view "$package" version || true)"
  if [ -z "$latest" ]; then
    echo "Warning: could not check latest npm version for $package (skipping)"
    return 1
  fi

  if have_cmd "$binary"; then
    current="$(npm list -g "$package" --depth=0 --json 2>/dev/null \
      | node -e '
          let input = "";
          process.stdin.on("data", chunk => input += chunk);
          process.stdin.on("end", () => {
            try {
              const parsed = JSON.parse(input);
              const dep = parsed.dependencies && parsed.dependencies[process.argv[1]];
              if (dep && dep.version) process.stdout.write(dep.version);
            } catch {}
          });
        ' "$package" 2>/dev/null || true)"
    if [ "$current" = "$latest" ]; then
      echo "$package is up to date ($current)."
      return 0
    fi
    if [ -n "$current" ]; then
      echo "Updating $package from $current to $latest."
    else
      echo "$binary is installed, but $package is not tracked by npm; installing $package@$latest."
    fi
  else
    echo "Installing $package@$latest."
  fi

  log_command npm install -g "${package}@latest" || {
    echo "Warning: failed to install npm package '$package' (skipping)"
    return 1
  }
}

install_npm_global_clis() {
  if ! have_cmd npm; then
    echo "Warning: npm not found; cannot install npm global CLIs (skipping)"
    return 1
  fi

  ensure_npm_cli_latest @github/copilot copilot || true
  ensure_npm_cli_latest copilot-relay copilot-relay || true
}

uninstall_npm_package_if_installed() {
  local package="$1"

  if ! have_cmd npm; then
    echo "Skipping npm uninstall for $package: npm not found."
    return 0
  fi

  if npm list -g "$package" --depth=0 >/dev/null 2>&1; then
    echo "Removing npm-installed $package."
    log_command npm uninstall -g "$package" || echo "Warning: failed to uninstall npm package '$package'"
  else
    echo "npm package '$package' is not installed globally."
  fi
}

uninstall_legacy_npm_binary() {
  local binary="$1"
  local expect_absent="${2:-1}"
  local npm_root=""
  local packages=""
  local package=""

  if ! have_cmd npm; then
    echo "Skipping legacy npm cleanup for $binary: npm not found."
    return 0
  fi
  if ! have_cmd node; then
    echo "Skipping legacy npm cleanup for $binary: node not found."
    return 0
  fi

  npm_root="$(npm root -g 2>/dev/null || true)"
  if [ -z "$npm_root" ] || [ ! -d "$npm_root" ]; then
    echo "Skipping legacy npm cleanup for $binary: cannot locate global npm root."
    return 0
  fi

  packages="$(node - "$npm_root" "$binary" <<'NODE' 2>/dev/null || true
const fs = require("node:fs");
const path = require("node:path");

const [, , root, binary] = process.argv;
const packageDirs = [];

for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
  if (!entry.isDirectory() || entry.name.startsWith(".")) continue;
  if (entry.name.startsWith("@")) {
    const scopeDir = path.join(root, entry.name);
    for (const scoped of fs.readdirSync(scopeDir, { withFileTypes: true })) {
      if (scoped.isDirectory() && !scoped.name.startsWith(".")) {
        packageDirs.push(path.join(scopeDir, scoped.name));
      }
    }
  } else {
    packageDirs.push(path.join(root, entry.name));
  }
}

for (const packageDir of packageDirs) {
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(packageDir, "package.json"), "utf8"));
    if (pkg.bin && typeof pkg.bin === "object" && Object.prototype.hasOwnProperty.call(pkg.bin, binary)) {
      process.stdout.write(`${pkg.name}\n`);
    }
  } catch {}
}
NODE
)"

  if [ -n "$packages" ]; then
    while IFS= read -r package; do
      [ -n "$package" ] || continue
      echo "Removing legacy npm package $package (provides $binary)."
      log_command npm uninstall -g "$package" || echo "Warning: failed to uninstall legacy package '$package'"
    done <<EOF
$packages
EOF
  fi

  if [ "$expect_absent" = "1" ] && have_cmd "$binary"; then
    echo "Warning: legacy command '$binary' is still on PATH after cleanup"
  fi
}

install_recursive_code_config_fonts() {
  local api_url="https://api.github.com/repos/MOSconfig/recursive-code-config/releases/latest"
  local fonts_dir="${HOME}/Library/Fonts"
  local release_json=""
  local tag=""
  local marker=""
  local needs_install=0
  local installed=0
  local font=""
  local url=""
  local digest=""
  local expected_sha=""
  local actual_sha=""
  local tmp_font=""
  local target=""
  local font_names=(
    RecMonoBaker-Bold.ttf
    RecMonoBaker-BoldItalic.ttf
    RecMonoBaker-Italic.ttf
    RecMonoBaker-Regular.ttf
    RecMonoSt.Helens-Bold.ttf
    RecMonoSt.Helens-BoldItalic.ttf
    RecMonoSt.Helens-Italic.ttf
    RecMonoSt.Helens-Regular.ttf
  )

  if ! have_cmd curl; then
    echo "Warning: curl not found; cannot download recursive-code-config fonts (skipping)"
    return 1
  fi
  if ! have_cmd jq; then
    echo "Warning: jq not found; cannot parse recursive-code-config release (skipping)"
    return 1
  fi

  mkdir -p "$fonts_dir"
  marker="${fonts_dir}/.recursive-code-config.version"
  release_json="$(mktemp -t recursive-code-config-release.XXXXXX)"
  if ! log_command curl -fsSL "$api_url" -o "$release_json"; then
    rm -f "$release_json"
    echo "Warning: failed to fetch recursive-code-config latest release metadata (skipping)"
    return 1
  fi

  tag="$(jq -r '.tag_name // empty' "$release_json")"
  if [ -z "$tag" ]; then
    rm -f "$release_json"
    echo "Warning: recursive-code-config release metadata did not include tag_name (skipping)"
    return 1
  fi

  if [ ! -f "$marker" ] || [ "$(cat "$marker" 2>/dev/null || true)" != "$tag" ]; then
    needs_install=1
  fi
  for font in "${font_names[@]}"; do
    if [ ! -f "${fonts_dir}/${font}" ]; then
      needs_install=1
      break
    fi
  done

  if [ "$needs_install" = "0" ]; then
    echo "recursive-code-config fonts are up to date ($tag)."
    rm -f "$release_json"
    return 0
  fi

  echo "Installing recursive-code-config fonts from MOSconfig release $tag."
  for font in "${font_names[@]}"; do
    url="$(jq -r --arg name "$font" '.assets[] | select(.name == $name) | .browser_download_url // empty' "$release_json")"
    digest="$(jq -r --arg name "$font" '.assets[] | select(.name == $name) | .digest // empty' "$release_json")"
    target="${fonts_dir}/${font}"

    if [ -z "$url" ]; then
      echo "Warning: recursive-code-config release $tag is missing asset $font"
      continue
    fi

    tmp_font="$(mktemp -t recursive-code-font.XXXXXX)"
    if ! log_command curl -fL "$url" -o "$tmp_font"; then
      rm -f "$tmp_font"
      echo "Warning: failed to download $font"
      continue
    fi

    if [ -n "$digest" ] && have_cmd shasum; then
      expected_sha="${digest#sha256:}"
      actual_sha="$(shasum -a 256 "$tmp_font" | awk '{print $1}')"
      if [ "$actual_sha" != "$expected_sha" ]; then
        rm -f "$tmp_font"
        echo "Warning: sha256 mismatch for $font (expected $expected_sha, got $actual_sha)"
        continue
      fi
    fi

    mv "$tmp_font" "$target"
    chmod 644 "$target"
    installed=$((installed + 1))
    echo "Installed font ${target#${HOME}/}"
  done

  rm -f "$release_json"
  if [ "$installed" -eq "${#font_names[@]}" ]; then
    printf '%s\n' "$tag" >"$marker"
    echo "Installed recursive-code-config font set $tag."
  else
    echo "Warning: installed ${installed}/${#font_names[@]} recursive-code-config fonts"
    return 1
  fi
}

configure_copilot_relay() {
  local relay_dir="${HOME}/.copilot-relay"
  local relay_config="${relay_dir}/config.yaml"
  local tmp_config

  mkdir -p "$relay_dir"
  if [ -f "$relay_config" ]; then
    tmp_config="$(mktemp)"
    if grep -Eq '^[[:space:]]*claudeSetup[[:space:]]*:' "$relay_config"; then
      sed -E 's/^[[:space:]]*claudeSetup[[:space:]]*:.*/claudeSetup: false/' "$relay_config" >"$tmp_config"
    elif grep -Eq '^[[:space:]]*claude_setup[[:space:]]*:' "$relay_config"; then
      sed -E 's/^[[:space:]]*claude_setup[[:space:]]*:.*/claudeSetup: false/' "$relay_config" >"$tmp_config"
    else
      cp "$relay_config" "$tmp_config"
      {
        printf '\n'
        printf '# Managed by dot-configs: ~/.claude/settings.json is symlinked from this repo.\n'
        printf 'claudeSetup: false\n'
      } >>"$tmp_config"
    fi
    mv "$tmp_config" "$relay_config"
  else
    {
      printf '# copilot-relay configuration\n'
      printf '# Managed by dot-configs; copilot-relay hot-reloads this file.\n'
      printf 'host: 127.0.0.1\n'
      printf 'port: 4142\n'
      printf 'copilotBaseUrl: https://api.githubcopilot.com\n'
      printf 'claudeSetup: false\n'
      printf 'logLevel: info\n'
      printf 'logRetentionDays: 3\n'
      printf 'thinkEffort: xhigh\n'
      printf 'gptModel: gpt-5.5\n'
      printf 'opusModel: claude-opus-4.8\n'
    } >"$relay_config"
  fi
  chmod 600 "$relay_config"
  echo "Configured copilot-relay at $relay_config (claudeSetup=false)"
}

install_macos_deps() {
  ensure_homebrew || exit 1

  local app_casks=(
    claude-code
    wezterm
  )
  local font_casks=(
    font-recursive # Provides the Recursive Mono variable family (St.Helens, Casual, Linear, Duotone)
    font-recursive-mono-nerd-font
    font-symbols-only-nerd-font
    font-noto-color-emoji
  )
  local formulae=(
    autojump
    eza
    git
    jq
    neovim
    node
    python
    tmux
    zsh-completions
    zsh-fast-syntax-highlighting
  )

  local formula
  for formula in "${formulae[@]}"; do
    if brew list --formula "$formula" >/dev/null 2>&1; then
      echo "Homebrew formula '$formula' is already installed."
      continue
    fi
    log_command brew install "$formula" || echo "Warning: failed to install formula '$formula' (skipping)"
  done

  uninstall_npm_package_if_installed @anthropic-ai/claude-code

  local cask
  for cask in "${app_casks[@]}" "${font_casks[@]}"; do
    if brew list --cask "$cask" >/dev/null 2>&1; then
      echo "Homebrew cask '$cask' is already installed."
      continue
    fi
    log_command brew install --cask "$cask" || echo "Warning: failed to install cask '$cask' (skipping)"
  done

  install_recursive_code_config_fonts || true
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
  if [ "${SKIP_NPM_GLOBALS:-0}" = "1" ]; then
    echo "Skipping npm global CLI step (SKIP_NPM_GLOBALS=1)."
  else
    install_npm_global_clis
  fi
  if [ "${SKIP_OH_MY_ZSH:-0}" = "1" ]; then
    echo "Skipping oh-my-zsh step (SKIP_OH_MY_ZSH=1)."
  else
    ensure_oh_my_zsh
  fi
  fix_zsh_compaudit_permissions
else
  echo "Auto-install only supports macOS + Homebrew. Install apps/fonts/CLIs manually."
fi

# Top-level dotfiles (.tmux.conf etc.).
while IFS= read -r -d '' entry; do
  base="$(basename "$entry")"
  link_file "$entry" "${dest_dir}/${base}"
done < <(find "$src_dir" -maxdepth 1 -mindepth 1 -name ".*" -type f -print0)

# Link oh-my-zsh custom files (oh-my-zsh-custom/* -> ~/.oh-my-zsh/custom/*).
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
  mkdir -p "$copilot_dest"
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
  if [ -x "${copilot_src}/cleanup-legacy.sh" ]; then
    if have_cmd copilot; then
      log_command "${copilot_src}/cleanup-legacy.sh" || echo "Warning: Copilot legacy cleanup reported errors (skipping)"
    else
      echo "Skipping Copilot legacy cleanup: copilot CLI not on PATH."
    fi
  fi
fi

# Link WezTerm config (wezterm/wezterm.lua -> ~/.wezterm.lua). WezTerm reads
# this path directly on macOS, so a fresh install gets the terminal config
# without a manual opt-in step.
wezterm_src="${src_dir}/wezterm/wezterm.lua"
wezterm_dest="${HOME}/.wezterm.lua"
if [ -f "$wezterm_src" ]; then
  link_file "$wezterm_src" "$wezterm_dest"
  echo "Linked WezTerm config to $wezterm_dest"
fi

# Link Claude Code config files (claude/* -> ~/.claude/*). Claude Code
# normally creates ~/.claude on first launch; mkdir -p so install.sh can
# wire things up on a fresh box without requiring a Claude Code launch
# first. Used to point Claude Code at the local copilot-relay proxy so it
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

  # Link the hooks/ subdirectory (claude/hooks/*.sh -> ~/.claude/hooks/*).
  # These are invoked by Claude Code's hook system (PreToolUse,
  # PostToolUse, SubagentStop, …) per ~/.claude/settings.json.
  if [ -d "${claude_src}/hooks" ]; then
    mkdir -p "${claude_dest}/hooks"
    while IFS= read -r -d '' entry; do
      base="$(basename "$entry")"
      link_file "$entry" "${claude_dest}/hooks/${base}"
      case "$base" in
        *.sh) chmod +x "$entry" ;;
      esac
    done < <(find "${claude_src}/hooks" -maxdepth 1 -mindepth 1 -type f -print0)
    echo "Linked Claude Code hooks to ${claude_dest}/hooks"
  fi

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
          ' "$copilot_mcp_pre" "$shared_mcp" >"$tmp_mcp"; then
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
            && "$wm_dest/venv/bin/pip" install --upgrade pip \
            && "$wm_dest/venv/bin/pip" install -r "$wm_src/requirements.txt" \
            && echo "wakatime-mcp: venv ready" \
            || echo "Warning: wakatime-mcp venv bootstrap failed"
        else
          # Refresh deps quietly only if requirements.txt is newer than
          # the venv's marker. Cheap mtime check; pip itself is idempotent.
          if [ "$wm_src/requirements.txt" -nt "$wm_dest/venv/pyvenv.cfg" ]; then
            "$wm_dest/venv/bin/pip" install -r "$wm_src/requirements.txt" \
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
              }' "$copilot_mcp_pre" >"$tmp_mcp" \
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
    src_mcp_json="$(jq -c '.mcpServers // {}' "$copilot_mcp" || echo '{}')"
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
    log_command git clone --depth=1 https://github.com/tmux-plugins/tpm "$tpm_dir" \
      || echo "Warning: failed to clone TPM (run prefix+I in tmux to retry)"
  fi
  if [ -d "$tpm_dir" ]; then
    # install_plugins uses `tmux start-server; show-environment` to discover
    # TMUX_PLUGIN_MANAGER_PATH. That requires the default tmux socket to
    # load .tmux.conf (which exports the var via the tpm init line). The
    # script below handles the server start/stop transparently.
    log_command "$tpm_dir/bin/install_plugins" \
      || echo "Warning: TPM plugin install reported errors (run prefix+I in tmux to retry)"
  fi
fi

echo "Linked dotfiles from $src_dir to $dest_dir"

# launchd agent: copilot-relay on login (macOS only). Renders the
# template (substituting absolute $HOME paths — launchd doesn't expand
# $HOME at runtime) into ~/Library/LaunchAgents and bootstraps it.
# Also unloads legacy Copilot proxy agents if present.
# Idempotent: if the agent is already loaded with the same content,
# bootout+bootstrap is a no-op restart; if content differs, the new
# version replaces the old.
if is_macos; then
  uid="$(id -u)"

  for legacy_label in com.d0n9x1n.copilot-api com.d0n9x1n.copilot-bridge; do
    legacy_plist="${HOME}/Library/LaunchAgents/${legacy_label}.plist"
    if launchctl print "gui/${uid}/${legacy_label}" >/dev/null 2>&1; then
      launchctl bootout "gui/${uid}/${legacy_label}" 2>/dev/null \
        && echo "Migration: unloaded legacy ${legacy_label}"
    fi
    [ -f "$legacy_plist" ] && rm -f "$legacy_plist" && echo "Migration: removed $legacy_plist"
  done
  uninstall_legacy_npm_binary copilot-bridge
  configure_copilot_relay

  launchd_src="${src_dir}/launchd/com.d0n9x1n.copilot-relay.plist"
  launchd_dest="${HOME}/Library/LaunchAgents/com.d0n9x1n.copilot-relay.plist"
  if [ -f "$launchd_src" ]; then
    if ! have_cmd copilot-relay; then
      if [ "${SKIP_NPM_GLOBALS:-0}" = "1" ]; then
        echo "Skipping copilot-relay launchd agent: SKIP_NPM_GLOBALS=1 and copilot-relay is not on PATH."
      else
        echo "Warning: copilot-relay not on PATH — skipping agent install (fix npm/global CLI install, then re-run install.sh)"
      fi
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
      if launchctl print "gui/${uid}/com.d0n9x1n.copilot-relay" >/dev/null 2>&1; then
        echo "Restarting launchd agent com.d0n9x1n.copilot-relay with the latest copilot-relay."
      else
        echo "Starting launchd agent com.d0n9x1n.copilot-relay."
      fi
      launchctl bootout "gui/${uid}/com.d0n9x1n.copilot-relay" 2>/dev/null || true
      for attempt in 1 2 3 4 5; do
        if ! launchctl print "gui/${uid}/com.d0n9x1n.copilot-relay" >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      loaded=0
      for attempt in 1 2 3 4 5; do
        if log_command launchctl bootstrap "gui/${uid}" "$launchd_dest"; then
          loaded=1
          break
        fi
        echo "Warning: launchctl bootstrap attempt ${attempt}/5 failed for com.d0n9x1n.copilot-relay"
        sleep 1
      done

      if [ "$loaded" = "1" ]; then
        log_command launchctl kickstart -k "gui/${uid}/com.d0n9x1n.copilot-relay" || true
        if have_cmd curl; then
          relay_ready=0
          for attempt in 1 2 3 4 5; do
            if curl -sS -o /dev/null --connect-timeout 1 http://127.0.0.1:4142/ 2>/dev/null; then
              relay_ready=1
              break
            fi
            sleep 1
          done
          if [ "$relay_ready" = "1" ]; then
            echo "copilot-relay is running at http://127.0.0.1:4142"
          elif [ ! -f "${HOME}/.copilot-relay/github_token" ]; then
            echo "Warning: copilot-relay is installed but not authenticated; run 'copilot-relay auth', then 'launchctl kickstart -k gui/$(id -u)/com.d0n9x1n.copilot-relay'"
          else
            echo "Warning: copilot-relay launchd agent loaded, but port 4142 is not accepting connections yet"
          fi
        fi
        echo "Loaded launchd agent com.d0n9x1n.copilot-relay (logs: ~/Library/Logs/copilot-relay.{out,err}.log, ~/.copilot-relay/logs/copilot-relay.log)"
      else
        echo "Warning: launchctl bootstrap failed for com.d0n9x1n.copilot-relay"
      fi
    fi
  fi
fi
