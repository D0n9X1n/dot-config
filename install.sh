#!/usr/bin/env bash
set -euo pipefail

src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest_dir="${HOME}"
timestamp="$(date +"%Y%m%d%H%M%S")"
install_log="${DOT_CONFIGS_INSTALL_LOG:-${HOME}/Library/Logs/dot-configs-install.log}"
RED="$(printf '\033[31m')"
BOLD="$(printf '\033[1m')"
RESET="$(printf '\033[0m')"

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

action_required() {
  printf '%s%sACTION REQUIRED:%s %s\n' "$RED" "$BOLD" "$RESET" "$*" >&2
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

  run_zsh_compaudit() {
    zsh -fc '
    if command -v brew >/dev/null 2>&1; then
      brew_prefix="$(brew --prefix 2>/dev/null || true)"
      if [ -n "$brew_prefix" ] && [ -d "$brew_prefix/share/zsh-completions" ]; then
        fpath=("$brew_prefix/share/zsh-completions" $fpath)
      fi
    fi
    autoload -Uz compaudit
    compaudit 2>/dev/null
    ' || true
  }

  insecure_dirs="$(run_zsh_compaudit)"

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

  remaining="$(run_zsh_compaudit)"
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
    if [ -z "$current" ]; then
      echo "$binary already exists at $(command -v "$binary"), but $package is not tracked by npm; leaving it in place."
      return 0
    fi
  fi

  latest="$(npm view "$package" version || true)"
  if [ -z "$latest" ]; then
    echo "Warning: could not check latest npm version for $package (skipping)"
    return 1
  fi

  if [ -n "$current" ]; then
    if [ "$current" = "$latest" ]; then
      echo "$package is up to date ($current)."
      return 0
    fi
    echo "Updating $package from $current to $latest."
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

prompt_wakatime_api_key() {
  local first=""
  local second=""
  local attempt=1

  if [ ! -t 0 ] || [ ! -r /dev/tty ]; then
    action_required "WakaTime API key missing; non-interactive shell cannot prompt. Create ~/.wakatime.cfg, then re-run install.sh."
    return 1
  fi

  action_required "WakaTime API key missing. Enter it twice on the terminal; input is hidden and not written to the install log."
  while [ "$attempt" -le 3 ]; do
    printf '%s%sWakaTime API key:%s ' "$RED" "$BOLD" "$RESET" >/dev/tty
    IFS= read -r -s first </dev/tty
    printf '\n' >/dev/tty
    printf '%s%sWakaTime API key again:%s ' "$RED" "$BOLD" "$RESET" >/dev/tty
    IFS= read -r -s second </dev/tty
    printf '\n' >/dev/tty

    if [ -z "$first" ]; then
      action_required "WakaTime API key was empty; try again."
    elif [ "$first" != "$second" ]; then
      action_required "WakaTime API key entries did not match; try again."
    else
      printf '%s' "$first"
      return 0
    fi
    attempt=$((attempt + 1))
  done

  action_required "WakaTime API key was not written after 3 failed attempts."
  return 1
}

ensure_wakatime_cfg_api_key() {
  local cfg="$1"
  local key=""
  local tmp_cfg=""

  if [ -f "$cfg" ]; then
    key="$(awk -F'= *' '/^api_key[[:space:]]*=/{print $2; exit}' "$cfg" | tr -d ' \r')"
    if [ -n "$key" ]; then
      printf '%s' "$key"
      return 0
    fi
  fi

  key="$(prompt_wakatime_api_key || true)"
  if [ -z "$key" ]; then
    return 1
  fi

  mkdir -p "$(dirname "$cfg")"
  tmp_cfg="$(mktemp -t wakatime-cfg.XXXXXX)"
  if [ -f "$cfg" ]; then
    if grep -Eq '^[[:space:]]*api_key[[:space:]]*=' "$cfg"; then
      sed -E "s|^[[:space:]]*api_key[[:space:]]*=.*|api_key = ${key}|" "$cfg" >"$tmp_cfg"
    elif grep -Eq '^[[:space:]]*\[settings\][[:space:]]*$' "$cfg"; then
      awk -v key="$key" '
        /^[[:space:]]*\[settings\][[:space:]]*$/ && !inserted {
          print
          print "api_key = " key
          inserted = 1
          next
        }
        { print }
      ' "$cfg" >"$tmp_cfg"
    else
      cp "$cfg" "$tmp_cfg"
      printf '\n[settings]\n' >>"$tmp_cfg"
      printf 'api_key = %s\n' "$key" >>"$tmp_cfg"
    fi
  else
    {
      printf '[settings]\n'
      printf 'api_key = %s\n' "$key"
    } >"$tmp_cfg"
  fi
  mv "$tmp_cfg" "$cfg"
  chmod 600 "$cfg"
  echo "WakaTime: wrote API key to $cfg (secret not printed)" >&2
  printf '%s' "$key"
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

ensure_copilot_wakatime_plugin() {
  local wm_cfg="${HOME}/.wakatime.cfg"
  local wm_key=""
  local plugins=""

  if ! have_cmd copilot; then
    echo "copilot-cli-wakatime plugin: copilot CLI not on PATH — skipping plugin setup"
    return 0
  fi

  wm_key="$(ensure_wakatime_cfg_api_key "$wm_cfg" || true)"
  if [ -z "$wm_key" ]; then
    echo "copilot-cli-wakatime plugin: no WakaTime API key available — skipping plugin setup"
    return 0
  fi

  uninstall_npm_package_if_installed @geeknees/copilot-cli-wakatime

  plugins="$(copilot plugin list 2>/dev/null || true)"
  if printf '%s\n' "$plugins" | grep -Eq '(^|[[:space:]])copilot-cli-wakatime([[:space:]@]|$)'; then
    log_command copilot plugin update copilot-cli-wakatime \
      || echo "Warning: copilot-cli-wakatime plugin update failed"
  else
    log_command copilot plugin install wakatime/copilot-cli-wakatime \
      || echo "Warning: copilot-cli-wakatime plugin install failed"
  fi
}

cleanup_legacy_wakatime_mcp() {
  local wm_dest="${HOME}/.local/share/wakatime-mcp"
  local copilot_mcp_pre="${HOME}/.config/github-copilot/mcp.json"
  local claude_user_json="${HOME}/.claude.json"
  local tmp_json=""

  if [ -d "$wm_dest" ]; then
    rm -rf "$wm_dest"
    echo "Removed legacy WakaTime MCP runtime at $wm_dest"
  fi

  if ! have_cmd jq; then
    echo "Warning: jq not found; cannot remove legacy WakaTime MCP entries"
    return 0
  fi

  if [ -f "$copilot_mcp_pre" ] && jq -e '.mcpServers.wakatime? != null' "$copilot_mcp_pre" >/dev/null 2>&1; then
    tmp_json="$(mktemp)"
    jq 'del(.mcpServers.wakatime)' "$copilot_mcp_pre" >"$tmp_json" \
      && mv "$tmp_json" "$copilot_mcp_pre" \
      && echo "Removed legacy WakaTime MCP from $copilot_mcp_pre" \
      || { rm -f "$tmp_json"; echo "Warning: failed to remove WakaTime MCP from $copilot_mcp_pre"; }
  fi

  if [ -f "$claude_user_json" ] && jq -e '.mcpServers.wakatime? != null' "$claude_user_json" >/dev/null 2>&1; then
    tmp_json="$(mktemp)"
    jq 'del(.mcpServers.wakatime)' "$claude_user_json" >"$tmp_json" \
      && mv "$tmp_json" "$claude_user_json" \
      && echo "Removed legacy WakaTime MCP from $claude_user_json" \
      || { rm -f "$tmp_json"; echo "Warning: failed to remove WakaTime MCP from $claude_user_json"; }
  fi
}

configure_copilot_relay() {
  local relay_dir="${HOME}/.copilot-relay"
  local relay_config="${relay_dir}/config.yaml"
  local tracked_relay_config="${src_dir}/.copilot-relay/config.yaml"
  local tmp_config

  mkdir -p "$relay_dir"
  if [ -f "$tracked_relay_config" ]; then
    link_file "$tracked_relay_config" "$relay_config"
    echo "Linked copilot-relay config to $relay_config"
    return 0
  fi

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

  if brew list --formula wakatime-cli >/dev/null 2>&1; then
    echo "Removing legacy Homebrew wakatime-cli; the Copilot WakaTime plugin manages its own CLI."
    log_command brew uninstall wakatime-cli || echo "Warning: failed to uninstall legacy wakatime-cli formula"
  fi

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

should_link_dotfile() {
  local src="$1"
  local rel="${src#${src_dir}/}"

  if have_cmd git && [ -d "${src_dir}/.git" ] && git -C "$src_dir" check-ignore -q -- "$rel"; then
    echo "Skipping ignored top-level dotfile: $rel"
    return 1
  fi
  return 0
}

render_launchd_template() {
  local template="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"
  mkdir -p "${HOME}/Library/Logs"
  sed -e "s|__HOME__|${HOME}|g" -e "s|__SRC_DIR__|${src_dir}|g" "$template" >"$dest"
  echo "Wrote $dest"
}

bootstrap_launchd_agent() {
  local uid="$1"
  local label="$2"
  local plist="$3"
  local restart_suffix="${4:-}"
  local attempt loaded=0

  if launchctl print "gui/${uid}/${label}" >/dev/null 2>&1; then
    echo "Restarting launchd agent ${label}${restart_suffix}."
  else
    echo "Starting launchd agent ${label}."
  fi

  launchctl bootout "gui/${uid}/${label}" 2>/dev/null || true
  for attempt in 1 2 3 4 5; do
    if ! launchctl print "gui/${uid}/${label}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  for attempt in 1 2 3 4 5; do
    if log_command launchctl bootstrap "gui/${uid}" "$plist"; then
      loaded=1
      break
    fi
    echo "Warning: launchctl bootstrap attempt ${attempt}/5 failed for ${label}"
    sleep 1
  done

  [ "$loaded" = "1" ]
}

copilot_relay_health_ok() {
  local code
  have_cmd curl || return 1
  code="$(curl -sS -o /dev/null \
    --connect-timeout 1 \
    --max-time 3 \
    -w '%{http_code}' \
    http://127.0.0.1:4142/healthz \
    2>/dev/null || true)"
  [ "$code" = "200" ]
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
  should_link_dotfile "$entry" || continue
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

# Link SonicTerm config without taking over runtime state. SonicTerm stores logs
# and backups under ~/.sonicterm too, so keep ~/.sonicterm as a real directory
# and symlink only the tracked TOML config/keymap/theme files into it.
sonicterm_src="${src_dir}/.sonicterm"
sonicterm_dest="${HOME}/.sonicterm"
if [ -d "$sonicterm_src" ]; then
  mkdir -p "$sonicterm_dest"
  while IFS= read -r -d '' entry; do
    base="$(basename "$entry")"
    link_file "$entry" "${sonicterm_dest}/${base}"
  done < <(find "$sonicterm_src" -maxdepth 1 -mindepth 1 -type f -name '*.toml' -print0)

  for subdir in keymaps themes; do
    if [ -d "${sonicterm_src}/${subdir}" ]; then
      mkdir -p "${sonicterm_dest}/${subdir}"
      while IFS= read -r -d '' entry; do
        base="$(basename "$entry")"
        link_file "$entry" "${sonicterm_dest}/${subdir}/${base}"
      done < <(find "${sonicterm_src}/${subdir}" -maxdepth 1 -mindepth 1 -type f -name '*.toml' -print0)
    fi
  done
  echo "Linked SonicTerm config files to $sonicterm_dest"
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

  # The official Copilot plugin supersedes the old vendored WakaTime MCP.
  cleanup_legacy_wakatime_mcp

  # Copilot CLI WakaTime upload plugin. This must run after Copilot CLI and
  # ~/.wakatime.cfg are in place. The plugin installs/updates its own
  # ~/.wakatime/wakatime-cli binary on Copilot session start.
  ensure_copilot_wakatime_plugin

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
      render_launchd_template "$launchd_src" "$launchd_dest"

      if [ ! -f "${HOME}/.copilot-relay/github_token" ]; then
        if launchctl print "gui/${uid}/com.d0n9x1n.copilot-relay" >/dev/null 2>&1; then
          launchctl bootout "gui/${uid}/com.d0n9x1n.copilot-relay" 2>/dev/null || true
        fi
        action_required "copilot-relay is installed but not authenticated."
        action_required "Run 'npx copilot-relay auth', then re-run install.sh to start the launchd agent."
      else
        if copilot_relay_health_ok; then
          echo "copilot-relay /healthz is healthy; leaving the running process untouched."
        elif bootstrap_launchd_agent "$uid" "com.d0n9x1n.copilot-relay" "$launchd_dest" " after failed /healthz"; then
          log_command launchctl kickstart -k "gui/${uid}/com.d0n9x1n.copilot-relay" || true
          relay_ready=0
          attempt=1
          while [ "$attempt" -le 20 ]; do
            if copilot_relay_health_ok; then
              relay_ready=1
              break
            fi
            sleep 1
            attempt=$((attempt + 1))
          done
          if [ "$relay_ready" = "1" ]; then
            echo "copilot-relay is healthy at http://127.0.0.1:4142/healthz"
          else
            echo "Warning: copilot-relay launchd agent loaded, but /healthz is not healthy yet"
            echo "If authentication expired, run 'npx copilot-relay auth', then re-run install.sh."
          fi
          echo "Loaded launchd agent com.d0n9x1n.copilot-relay (logs: ~/Library/Logs/copilot-relay.{out,err}.log, ~/.copilot-relay/logs/copilot-relay.log)"
        else
          echo "Warning: launchctl bootstrap failed for com.d0n9x1n.copilot-relay"
        fi
      fi

      relay_health_src="${src_dir}/launchd/com.d0n9x1n.copilot-relay-healthcheck.plist"
      relay_health_dest="${HOME}/Library/LaunchAgents/com.d0n9x1n.copilot-relay-healthcheck.plist"
      relay_health_script="${src_dir}/launchd/copilot-relay-healthcheck.sh"
      if [ -f "$relay_health_src" ] && [ -f "$relay_health_script" ]; then
        chmod +x "$relay_health_script" 2>/dev/null || true
        render_launchd_template "$relay_health_src" "$relay_health_dest"

        if [ ! -f "${HOME}/.copilot-relay/github_token" ]; then
          if launchctl print "gui/${uid}/com.d0n9x1n.copilot-relay-healthcheck" >/dev/null 2>&1; then
            launchctl bootout "gui/${uid}/com.d0n9x1n.copilot-relay-healthcheck" 2>/dev/null || true
          fi
          echo "Skipping copilot-relay healthcheck agent until copilot-relay auth is complete."
        elif bootstrap_launchd_agent "$uid" "com.d0n9x1n.copilot-relay-healthcheck" "$relay_health_dest"; then
          log_command launchctl kickstart -k "gui/${uid}/com.d0n9x1n.copilot-relay-healthcheck" || true
          echo "Loaded launchd agent com.d0n9x1n.copilot-relay-healthcheck (GET /healthz every 60s; logs: ~/Library/Logs/copilot-relay-healthcheck.log)"
        else
          echo "Warning: launchctl bootstrap failed for com.d0n9x1n.copilot-relay-healthcheck"
        fi
      fi
    fi
  fi
fi

# launchd agent: weekly npm/npx cache cleaner (macOS only). Renders the
# template (substituting __HOME__ and __SRC_DIR__) into ~/Library/LaunchAgents
# and bootstraps it. Unlike copilot-relay this has no auth/PATH gating — the
# tracked script is always present in this repo, and it runs on a schedule
# (Sun 03:17), not at load. Idempotent: bootout+bootstrap is a no-op restart
# when content is unchanged, and replaces the agent when it differs.
if is_macos; then
  uid="$(id -u)"
  npmclean_src="${src_dir}/launchd/com.d0n9x1n.npm-cache-clean.plist"
  npmclean_dest="${HOME}/Library/LaunchAgents/com.d0n9x1n.npm-cache-clean.plist"
  npmclean_script="${src_dir}/launchd/clean-npm-caches.sh"

  if [ -f "$npmclean_src" ] && [ -f "$npmclean_script" ]; then
    chmod +x "$npmclean_script" 2>/dev/null || true
    render_launchd_template "$npmclean_src" "$npmclean_dest"

    if bootstrap_launchd_agent "$uid" "com.d0n9x1n.npm-cache-clean" "$npmclean_dest"; then
      echo "Loaded launchd agent com.d0n9x1n.npm-cache-clean (weekly Sun 03:17; logs: ~/Library/Logs/npm-cache-clean.log)"
    else
      echo "Warning: launchctl bootstrap failed for com.d0n9x1n.npm-cache-clean"
    fi
  fi
fi
