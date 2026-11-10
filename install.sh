#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_root="${repo_root}/config"
scripts_root="${repo_root}/scripts"
manifest="${config_root}/manifest.tsv"
# A fork or private overlay keeps its own files here. Upstream never tracks
# local/, so these files never conflict with an upstream merge.
local_root="${DOT_CONFIGS_LOCAL:-${repo_root}/local}"
local_manifest="${local_root}/manifest.tsv"
install_log="${DOT_CONFIGS_INSTALL_LOG:-${HOME}/Library/Logs/dot-configs-install.log}"
source "${scripts_root}/apollo-theme.sh"
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

# --all also sets up Firefox. uu passes its own options through to here.
install_all=0
install_usage() {
  cat <<'USAGE'
Usage: ./install.sh [--all]

  --all   also set up Firefox: link user.js into each default profile and
          update the oh-my-firefox theme. Plain runs leave Firefox alone.
USAGE
}

parse_install_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --all) install_all=1 ;;
      -h|--help) install_usage; exit 0 ;;
      *) echo "install.sh: unknown option: $arg" >&2; install_usage >&2; exit 2 ;;
    esac
  done
}

if [ "${DOT_CONFIGS_INSTALL_LIB_ONLY:-0}" != "1" ]; then
  parse_install_args "$@"
  setup_logging
fi

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

version_at_least() {
  awk -v current="$1" -v required="$2" '
    BEGIN {
      if (split(current, have, "[.]") != 3 || split(required, need, "[.]") != 3) exit 1
      for (i = 1; i <= 3; i++) {
        if (have[i] !~ /^[0-9]+$/ || need[i] !~ /^[0-9]+$/) exit 1
        if ((have[i] + 0) > (need[i] + 0)) exit 0
        if ((have[i] + 0) < (need[i] + 0)) exit 1
      }
      exit 0
    }
  '
}

claude_code_version() {
  local output=""

  have_cmd claude || return 1
  output="$(command claude --version 2>/dev/null || true)"
  printf '%s\n' "$output" | sed -nE 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | sed -n '1p'
}

ensure_claude_code_min_version() {
  local required="$1"
  local current=""

  current="$(claude_code_version || true)"
  if [ -n "$current" ] && version_at_least "$current" "$required"; then
    echo "Claude Code $current satisfies the required minimum v$required."
    return 0
  fi

  if brew list --cask claude-code >/dev/null 2>&1; then
    echo "Claude Code ${current:-unknown} is below required v$required; upgrading the Homebrew cask."
    if ! log_command brew upgrade --cask claude-code; then
      echo "Warning: Homebrew could not upgrade the claude-code cask."
    fi
  else
    if ! log_command brew install --cask claude-code; then
      echo "Warning: Homebrew could not install the claude-code cask."
    fi
  fi
  hash -r 2>/dev/null || true

  current="$(claude_code_version || true)"
  if [ -z "$current" ] || ! version_at_least "$current" "$required"; then
    action_required "Claude Code v$required or later is required for the native concurrent-subagent limit; found ${current:-no usable claude binary}."
    return 1
  fi
  echo "Claude Code $current satisfies the required minimum v$required."
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

install_rec_mountain_fonts() {
  local api_url="https://api.github.com/repos/D0n9X1n/rec-mountain-fonts/releases/latest"
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
    RecMonoSt.Helens-Bold.ttf
    RecMonoSt.Helens-BoldItalic.ttf
    RecMonoSt.Helens-Italic.ttf
    RecMonoSt.Helens-Regular.ttf
    RecSansMt.Baker-Bold.ttf
    RecSansMt.Baker-BoldItalic.ttf
    RecSansMt.Baker-Italic.ttf
    RecSansMt.Baker-Regular.ttf
    RecSerifMt.Adams-Bold.ttf
    RecSerifMt.Adams-BoldItalic.ttf
    RecSerifMt.Adams-Italic.ttf
    RecSerifMt.Adams-Regular.ttf
  )
  # Fonts from the retired MOSconfig/recursive-code-config release
  local retired_fonts=(
    RecMonoBaker-Bold.ttf
    RecMonoBaker-BoldItalic.ttf
    RecMonoBaker-Italic.ttf
    RecMonoBaker-Regular.ttf
  )

  if ! have_cmd curl; then
    echo "Warning: curl not found; cannot download Rec Mountain Fonts (skipping)"
    return 1
  fi
  if ! have_cmd jq; then
    echo "Warning: jq not found; cannot parse Rec Mountain Fonts release (skipping)"
    return 1
  fi

  mkdir -p "$fonts_dir"
  rm -f "${fonts_dir}/.recursive-code-config.version" "${fonts_dir}/.m-fonts.version"
  for font in "${retired_fonts[@]}"; do
    if [ -f "${fonts_dir}/${font}" ]; then
      rm -f "${fonts_dir}/${font}"
      echo "Removed retired font ${font}"
    fi
  done

  marker="${fonts_dir}/.rec-mountain-fonts.version"
  release_json="$(mktemp -t rec-mountain-fonts-release.XXXXXX)"
  if ! log_command curl -fsSL "$api_url" -o "$release_json"; then
    rm -f "$release_json"
    echo "Warning: failed to fetch Rec Mountain Fonts latest release metadata (skipping)"
    return 1
  fi

  tag="$(jq -r '.tag_name // empty' "$release_json")"
  if [ -z "$tag" ]; then
    rm -f "$release_json"
    echo "Warning: Rec Mountain Fonts release metadata did not include tag_name (skipping)"
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
    echo "Rec Mountain Fonts are up to date ($tag)."
    rm -f "$release_json"
    return 0
  fi

  echo "Installing Rec Mountain Fonts release $tag."
  for font in "${font_names[@]}"; do
    url="$(jq -r --arg name "$font" '.assets[] | select(.name == $name) | .browser_download_url // empty' "$release_json")"
    digest="$(jq -r --arg name "$font" '.assets[] | select(.name == $name) | .digest // empty' "$release_json")"
    target="${fonts_dir}/${font}"

    if [ -z "$url" ]; then
      echo "Warning: Rec Mountain Fonts release $tag is missing asset $font"
      continue
    fi

    tmp_font="$(mktemp -t rec-mountain-fonts-font.XXXXXX)"
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
    echo "Installed Rec Mountain Fonts $tag."
  else
    echo "Warning: installed ${installed}/${#font_names[@]} Rec Mountain Fonts"
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

# Feature-Crew and mux-agents each ship as one plugin from a marketplace of the
# same name. Install or update one in each CLI on PATH; both settings files also
# declare the marketplace, so later runs update it instead of re-adding it.
ensure_cli_plugin() {
  local name="$1" repo="$2" cli
  local -a scope
  if ! have_cmd jq; then
    echo "$name plugin: jq not found — skipping plugin setup"
    return 0
  fi
  for cli in claude copilot; do
    have_cmd "$cli" || continue
    # Claude Code can hold a project or local copy too; manage only the user copy.
    scope=()
    [ "$cli" = claude ] && scope=(--scope user)
    if "$cli" plugin marketplace list --json 2>/dev/null | jq -e --arg name "$name" 'any(.[]; .name == $name)' >/dev/null; then
      log_command "$cli" plugin marketplace update "$name" \
        || echo "Warning: $cli $name marketplace update failed"
    else
      log_command "$cli" plugin marketplace add "$repo" \
        || { echo "Warning: $cli $name marketplace add failed"; continue; }
    fi
    if "$cli" plugin list --json 2>/dev/null | jq -e --arg cli "$cli" --arg name "$name" 'any(.[];
        (if $cli == "claude" then .id == "\($name)@\($name)" and .scope == "user"
         else .name == $name and .marketplace == $name end) and .enabled == true)' >/dev/null; then
      log_command "$cli" plugin update "$name@$name" ${scope[@]+"${scope[@]}"} \
        || echo "Warning: $cli $name plugin update failed"
    else
      log_command "$cli" plugin install "$name@$name" ${scope[@]+"${scope[@]}"} \
        || echo "Warning: $cli $name plugin install failed"
    fi
  done
}

# mermaid-tty is a Claude Code plugin that draws mermaid fences as box-drawing
# diagrams. Install or update it in Claude Code; settings.json declares and enables it.
ensure_mermaid_tty_plugin() {
  if ! have_cmd jq; then
    echo "mermaid-tty plugin: jq not found — skipping plugin setup"
    return 0
  fi
  have_cmd claude || return 0
  if claude plugin marketplace list --json 2>/dev/null | jq -e 'any(.[]; .name == "mermaid-tty")' >/dev/null; then
    log_command claude plugin marketplace update mermaid-tty \
      || echo "Warning: claude mermaid-tty marketplace update failed"
  else
    log_command claude plugin marketplace add D0n9X1n/mermaid-tty \
      || { echo "Warning: claude mermaid-tty marketplace add failed"; return 0; }
  fi
  if claude plugin list --json 2>/dev/null | jq -e 'any(.[]; .id == "mermaid-tty@mermaid-tty" and .scope == "user" and .enabled == true)' >/dev/null; then
    log_command claude plugin update mermaid-tty@mermaid-tty --scope user \
      || echo "Warning: claude mermaid-tty plugin update failed"
  else
    log_command claude plugin install mermaid-tty@mermaid-tty --scope user --config theme=default \
      || echo "Warning: claude mermaid-tty plugin install failed"
  fi
  # Claude Code reports an option as not yet set until a value is saved, so save the
  # default theme once; a theme the user chose is kept.
  if ! claude plugin configure mermaid-tty@mermaid-tty --json 2>/dev/null | jq -e '.inputs.theme' >/dev/null; then
    echo '{"theme":"default"}' | log_command claude plugin configure mermaid-tty@mermaid-tty --values-stdin \
      || echo "Warning: claude mermaid-tty theme setup failed"
  fi
}

# uu runs install.sh, so refresh every Claude Code marketplace and update each
# enabled user plugin too, such as the official LSP and WakaTime plugins. Project
# and local plugins belong to their repos and are left alone.
update_claude_plugins() {
  local ids id
  have_cmd claude && have_cmd jq || return 0
  log_command claude plugin marketplace update \
    || echo "Warning: claude plugin marketplace update failed"
  if ! ids="$(claude plugin list --json 2>/dev/null \
      | jq -r '.[] | select(.enabled == true and .scope == "user") | .id')"; then
    echo "Warning: claude plugin list failed; skipping plugin updates"
    return 0
  fi
  for id in $ids; do
    log_command claude plugin update "$id" --scope user \
      || echo "Warning: claude $id plugin update failed"
  done
}

# An old script install of Feature-Crew put fc-* agents and skills in
# ~/.claude, where they shadow the plugin. Remove those exact names once Claude
# Code lists the plugin enabled; leave linked folders and other files alone.
cleanup_legacy_feature_crew() {
  local claude_dir="${HOME}/.claude" name path
  local agents="fc-architect fc-developer fc-pm fc-qa-code fc-qa-spec fc-tech-lead"
  local skills="fc-brainstorm fc-build-or-fix fc-debug fc-explain fc-grill-me fc-research fc-review fc-second-opinion fc-ship fc-update"
  have_cmd claude && have_cmd jq || return 0
  claude plugin list --json 2>/dev/null \
    | jq -e 'any(.[]; .id == "feature-crew@feature-crew" and .enabled == true)' >/dev/null || return 0

  if [ ! -L "${claude_dir}/agents" ]; then
    for name in $agents; do
      path="${claude_dir}/agents/${name}.md"
      if [ -e "$path" ] || [ -L "$path" ]; then
        rm -rf "$path" && echo "Removed old Feature-Crew file: $path"
      fi
    done
  fi
  if [ ! -L "${claude_dir}/skills" ]; then
    for name in $skills; do
      path="${claude_dir}/skills/${name}"
      if [ -e "$path" ] || [ -L "$path" ]; then
        rm -rf "$path" && echo "Removed old Feature-Crew skill: $path"
      fi
    done
  fi
  path="${claude_dir}/feature-crew.sha256"
  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -f "$path" && echo "Removed old Feature-Crew file: $path"
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

install_macos_deps() {
  ensure_homebrew || exit 1

  local claude_min_version="2.1.217"
  local font_casks=(
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
    shellcheck
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
  ensure_claude_code_min_version "$claude_min_version" || exit 1

  # Recursive casks retired in favor of Rec Mountain Fonts (Rec Mono St.Helens / Rec Sans Mt.Baker / Rec Serif Mt.Adams)
  local retired_font_casks=(
    font-recursive
    font-recursive-mono-nerd-font
  )

  local cask
  for cask in "${retired_font_casks[@]}"; do
    if brew list --cask "$cask" >/dev/null 2>&1; then
      echo "Removing retired Homebrew cask '$cask'; Rec Mountain Fonts replaces it."
      log_command brew uninstall --cask "$cask" || echo "Warning: failed to uninstall cask '$cask'"
    fi
  done

  for cask in "${font_casks[@]}"; do
    if brew list --cask "$cask" >/dev/null 2>&1; then
      echo "Homebrew cask '$cask' is already installed."
      continue
    fi
    log_command brew install --cask "$cask" || echo "Warning: failed to install cask '$cask' (skipping)"
  done

  install_rec_mountain_fonts || true
}

# Remove installer backups (<path>.bak.<digit>...) of one path. The quoted
# prefix keeps glob characters and newlines literal, so only this path's own
# backups match, never its parent folder or another file.
remove_backups_of() {
  local path="$1" dir backup status=0
  # Not $(dirname): command substitution drops trailing newlines in a name.
  case "$path" in
    */*) dir="${path%/*}"; dir="${dir:-/}" ;;
    *) dir=. ;;
  esac
  # A folder behind an unsearchable one looks missing; check the nearest
  # folder that exists before treating the parent as absent.
  while [ ! -e "$dir" ] && [ ! -L "$dir" ]; do
    case "$dir" in
      */*) dir="${dir%/*}"; dir="${dir:-/}" ;;
      *) dir=. ;;
    esac
  done
  if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
    echo "Error: cannot read $dir to remove old backups of $path" >&2
    return 1
  fi
  for backup in "$path".bak.[0-9]*; do
    [ -e "$backup" ] || [ -L "$backup" ] || continue
    rm -rf -- "$backup" || status=1
  done
  return "$status"
}

link_file() {
  local src="$1"
  local dest="$2"

  # A trailing slash would make rm follow a symlinked folder.
  case "$dest" in
    ''|*/|*/.|*/..|*/../*) echo "Error: unsafe link destination: $dest" >&2; return 1 ;;
  esac
  remove_backups_of "$dest" || return 1
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return 0
  fi
  if [ -L "$dest" ]; then
    rm -f "$dest" || return 1
  elif [ -e "$dest" ]; then
    rm -rf "$dest" || return 1
    echo "Replaced $dest"
  fi
  mkdir -p "$(dirname "$dest")" || return 1
  ln -s "$src" "$dest"
}

old_source_for_destination() {
  case "$1" in
    .rmux.conf) printf '%s\n' "${repo_root}/.rmux.conf" ;;
    .tmux.conf) printf '%s\n' "${repo_root}/.tmux.conf" ;;
    .sonicterm/*) printf '%s\n' "${repo_root}/$1" ;;
    .claude/*) printf '%s\n' "${repo_root}/claude/${1#.claude/}" ;;
    .copilot/*) printf '%s\n' "${repo_root}/copilot/${1#.copilot/}" ;;
    .oh-my-zsh/custom/*) printf '%s\n' "${repo_root}/oh-my-zsh-custom/${1#.oh-my-zsh/custom/}" ;;
    .copilot-relay/config.yaml) printf '%s\n' "${repo_root}/.copilot-relay/config.yaml" ;;
  esac
}

migrate_managed_link() {
  local dest_rel="$1"
  local dest="${HOME}/${dest_rel}"
  local old_src=""
  local target=""

  old_src="$(old_source_for_destination "$dest_rel")"
  if [ -n "$old_src" ] && [ -L "$dest" ]; then
    target="$(readlink "$dest")"
    if [ "$target" = "$old_src" ]; then
      rm -f "$dest"
      echo "Migration: removed old managed link $dest"
    fi
  fi
}

# Herdr: config/herdr is the herdr-config submodule. Its update never stops
# the install; a conflict with local edits keeps the current checkout. Rows
# whose source is missing (offline, or not checked out) are skipped and
# reported once by herdr_install_report.
HERDR_CONFLICT=0
HERDR_UPDATE_ERROR=""
herdr_submodule_update() {
  [ -f "$repo_root/.gitmodules" ] || return 0
  git config -f "$repo_root/.gitmodules" --get submodule.config/herdr.path >/dev/null 2>&1 || return 0
  local err
  err="$(git -C "$repo_root" submodule update --init config/herdr 2>&1)" && return 0
  case "$err" in
    *'would be overwritten'*|*'Please commit your changes'*|*'local changes'*)
      HERDR_CONFLICT=1
      echo "Herdr config: commit or discard local edits in config/herdr, then rerun ./install.sh" ;;
    *) HERDR_UPDATE_ERROR="$(printf '%s' "$err" | tail -n 1)" ;;
  esac
  return 0
}

# Live values win. Before the submodule step, live settings.json and keys.json
# are read (through any link) into one temp folder; after it, they are written
# into config/herdr/user/ when they differ, and the temp folder is removed in
# the same step. No seed copy and no backup is kept. On first adoption (a
# regular keys.json), keys equal to Herdr's defaults keep the tracked keymap;
# other keys get the tracked overrides merged over them.
HERDR_SKIP_LINKS=""
# herdr_skip <settings|keys> <reason>: that live file could not be kept in config/herdr/user/, so it is
# not linked and stays exactly as it is. One warning; the rest of the install goes on.
herdr_skip() {
  HERDR_SKIP_LINKS="${HERDR_SKIP_LINKS}.config/herdr-app/$1.json"$'\n'
  echo "Warning: Herdr config: could not keep your live $1.json ($2); left it as it is and did not link it." >&2
}

herdr_seed_capture() {
  local f live
  for f in settings keys; do
    live="$HOME/.config/herdr-app/$f.json"
    [ -e "$live" ] || continue
    if ! cp -L "$live" "$1/$f.json" 2>/dev/null; then
      rm -f "$1/$f.json"
      herdr_skip "$f" "could not read it"
      continue
    fi
    if [ -L "$live" ]; then echo link >"$1/$f.kind"; else echo file >"$1/$f.kind"; fi
  done
}

# herdr_seed_write <settings|keys> <file>: the value into config/herdr/user/, checked; else skip.
herdr_seed_write() {
  local dest="$repo_root/config/herdr/user/$1.json"
  cmp -s "$2" "$dest" && return 0
  if cat "$2" 2>/dev/null >"$dest" && cmp -s "$2" "$dest"; then
    echo "Herdr config: kept your live $1.json"
  else
    herdr_skip "$1" "could not write config/herdr/user/$1.json"
  fi
}

herdr_seed_apply() {
  local seed="$1" user="$repo_root/config/herdr/user" defaults="$repo_root/config/herdr/data/herdr-default-keys.json"
  [ -d "$user" ] || return 0
  [ -f "$seed/settings.json" ] && herdr_seed_write settings "$seed/settings.json"
  [ -f "$seed/keys.json" ] || return 0
  if [ "$(cat "$seed/keys.kind" 2>/dev/null)" = file ] && [ -f "$defaults" ] && cmp -s "$seed/keys.json" "$defaults"; then
    return 0
  fi
  if ! jq -e . "$seed/keys.json" >/dev/null 2>&1; then
    herdr_skip keys "it is not valid JSON"
    return 0
  fi
  if [ "$(cat "$seed/keys.kind" 2>/dev/null)" = file ] && [ -f "$user/keys.overrides.json" ]; then
    if ! jq -S -s '.[0] * .[1] | walk(if type == "object" then with_entries(select(.value != null)) else . end)' \
        "$seed/keys.json" "$user/keys.overrides.json" >"$seed/keys.merged" 2>/dev/null \
      || ! mv -f "$seed/keys.merged" "$seed/keys.json"; then
      herdr_skip keys "could not merge the Apollo key overrides"
      return 0
    fi
  fi
  herdr_seed_write keys "$seed/keys.json"
}

# With no temp folder the live values cannot be read safely: a live file that differs from
# config/herdr/user/ is skipped, not replaced.
herdr_seed_unavailable() {
  local f live
  for f in settings keys; do
    live="$HOME/.config/herdr-app/$f.json"
    [ -e "$live" ] || [ -L "$live" ] || continue
    cmp -s "$live" "$repo_root/config/herdr/user/$f.json" 2>/dev/null || herdr_skip "$f" "no temp folder"
  done
}

herdr_skip_link() {
  case $'\n'"$HERDR_SKIP_LINKS" in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

herdr_install_prepare() {
  local seed
  HERDR_SKIP_LINKS=""
  if ! seed="$(mktemp -d "${TMPDIR:-/tmp}/herdr-live.XXXXXX" 2>/dev/null)" || [ ! -d "$seed" ]; then
    herdr_submodule_update
    herdr_seed_unavailable
    return 0
  fi
  herdr_seed_capture "$seed"
  herdr_submodule_update
  herdr_seed_apply "$seed"
  rm -rf -- "$seed"
}

# True for a config/herdr row whose source is not here; such rows are skipped.
herdr_source_missing() {
  case "$1" in config/herdr/*) [ ! -f "${repo_root}/$1" ] ;; *) return 1 ;; esac
}

# Herdr.app, searched in ~/Applications then /Applications (HERDR_APP_ROOTS,
# colon-separated, overrides the list for tests).
herdr_app_path() {
  local IFS=: root
  for root in ${HERDR_APP_ROOTS:-${HOME}/Applications:/Applications}; do
    if [ -n "$root" ] && [ -d "$root/Herdr.app" ]; then
      printf '%s\n' "$root/Herdr.app"
      return 0
    fi
  done
  return 1
}

# macOS: install Herdr when there is no Herdr.app and no herdr-app on PATH.
# An existing install is never touched. A failure warns and install goes on.
ensure_herdr() {
  is_macos || return 0
  herdr_app_path >/dev/null && return 0
  have_cmd herdr-app && return 0
  if [ "${SKIP_BREW:-0}" = "1" ]; then
    echo "Herdr: not installed; skipped (SKIP_BREW=1)."
    return 0
  fi
  if ! have_cmd brew; then
    echo "Warning: Herdr is not installed and Homebrew is missing; skipped." >&2
    return 0
  fi
  echo "Herdr: not installed; running brew install --cask herdr-app"
  brew install --cask herdr-app || echo "Warning: brew install --cask herdr-app failed; Herdr is not installed." >&2
  return 0
}

# macOS: a Herdr update replaces the app and drops its custom icon, so put the
# Apollo Dock icon back when it is missing. A failure warns and install goes on.
herdr_dock_icon() {
  is_macos || return 0
  local app script="${repo_root}/config/herdr/scripts/set-app-icon.sh"
  app="$(herdr_app_path)" || return 0
  [ -x "$script" ] || return 0
  "$script" --check --app "$app" >/dev/null 2>&1 && return 0
  "$script" --app "$app" || echo "Warning: could not set the Apollo Dock icon on $app; skipped." >&2
  return 0
}

herdr_install_report() {
  local skipped
  skipped="$(awk -F'\t' '$2 ~ /^config\/herdr\// {print $2}' "$manifest" | while IFS= read -r src; do
    [ -f "${repo_root}/${src}" ] || echo x; done | grep -c x || true)"
  [ "$HERDR_CONFLICT" = 1 ] && return 0
  if [ "${skipped:-0}" -gt 0 ]; then
    echo "Herdr config: config/herdr is not checked out${HERDR_UPDATE_ERROR:+ ($HERDR_UPDATE_ERROR)}; skipped ${skipped} Herdr rows. Rerun ./install.sh when online."
  fi
}

validate_manifest() {
  local type source destination extra
  local seen_destinations=""

  [ -f "$manifest" ] || {
    echo "Error: missing config manifest: $manifest" >&2
    return 1
  }

  while IFS=$'\t' read -r type source destination extra; do
    case "$type" in
      ''|'#'*) continue ;;
      link|copy|merge|render|firefox) ;;
      *) echo "Error: unknown manifest type '$type'" >&2; return 1 ;;
    esac
    [ -z "$extra" ] || {
      echo "Error: manifest row has more than three fields: $source" >&2
      return 1
    }
    [ -n "$source" ] && [ -n "$destination" ] || {
      echo "Error: incomplete manifest row" >&2
      return 1
    }
    case "$source" in
      /*|*'..'*) echo "Error: unsafe manifest source: $source" >&2; return 1 ;;
      config/*|scripts/*) ;;
      *) echo "Error: manifest source must be under config/ or scripts/: $source" >&2; return 1 ;;
    esac
    case "$destination" in
      /*|*'..'*|*/|*/.) echo "Error: unsafe manifest destination: $destination" >&2; return 1 ;;
    esac
    if [ ! -f "${repo_root}/${source}" ] && ! herdr_source_missing "$source"; then
      echo "Error: missing manifest source: $source" >&2
      return 1
    fi
    case $'\n'"${seen_destinations}"$'\n' in
      *$'\n'"${destination}"$'\n'*) echo "Error: duplicate manifest destination: $destination" >&2; return 1 ;;
    esac
    seen_destinations="${seen_destinations}${seen_destinations:+$'\n'}${destination}"
  done <"$manifest"
}

# local/manifest.tsv takes link rows only. Sources are relative to the
# overlay; destinations may not reuse an upstream destination or the reserved
# zzz-local-* zsh names.
validate_local_overlay() {
  local type source destination extra upstream_destinations
  local seen_destinations=""

  if [ -n "${DOT_CONFIGS_LOCAL:-}" ]; then
    case "$DOT_CONFIGS_LOCAL" in
      /*) ;;
      *) echo "Error: DOT_CONFIGS_LOCAL must be an absolute path: $DOT_CONFIGS_LOCAL" >&2; return 1 ;;
    esac
    [ -d "$local_root" ] || {
      echo "Error: DOT_CONFIGS_LOCAL folder not found: $local_root" >&2
      return 1
    }
  fi
  [ -f "$local_manifest" ] || return 0

  upstream_destinations="$(grep -Ev '^(#|$)' "$manifest" | awk -F'\t' '$1 != "firefox" {print $3}')"
  while IFS=$'\t' read -r type source destination extra || [ -n "$type" ]; do
    case "$type" in
      ''|'#'*) continue ;;
      link) ;;
      *) echo "Error: local manifest supports only link rows, not '$type'" >&2; return 1 ;;
    esac
    [ -z "$extra" ] || {
      echo "Error: local manifest row has more than three fields: $source" >&2
      return 1
    }
    [ -n "$source" ] && [ -n "$destination" ] || {
      echo "Error: incomplete local manifest row" >&2
      return 1
    }
    case "$source" in
      /*|*'..'*) echo "Error: unsafe local manifest source: $source" >&2; return 1 ;;
    esac
    case "$destination" in
      /*|*'..'*|*/|*/.) echo "Error: unsafe local manifest destination: $destination" >&2; return 1 ;;
      .oh-my-zsh/custom/zzz-local-*)
        echo "Error: $destination is reserved for local/zsh/*.zsh" >&2
        return 1
        ;;
    esac
    [ -f "${local_root}/${source}" ] || {
      echo "Error: missing local manifest source: ${local_root}/${source}" >&2
      return 1
    }
    case $'\n'"${upstream_destinations}"$'\n' in
      *$'\n'"${destination}"$'\n'*)
        echo "Error: local manifest destination is managed upstream: $destination" >&2
        return 1
        ;;
    esac
    case $'\n'"${seen_destinations}"$'\n' in
      *$'\n'"${destination}"$'\n'*) echo "Error: duplicate local manifest destination: $destination" >&2; return 1 ;;
    esac
    seen_destinations="${seen_destinations}${seen_destinations:+$'\n'}${destination}"
  done <"$local_manifest"
}

# Link local/manifest.tsv rows, then local/zsh/*.zsh as zzz-local-NAME.zsh so
# oh-my-zsh loads them after every upstream helper.
link_local_overlay() {
  local type source destination extra file dest name
  local custom="${HOME}/.oh-my-zsh/custom"

  # zzz-local-* links belong to the overlay: drop any that no longer match it.
  for dest in "${custom}"/zzz-local-*.zsh; do
    [ -L "$dest" ] || continue
    name="${dest##*/zzz-local-}"
    if [ "$(readlink "$dest")" != "${local_root}/zsh/${name}" ] || [ ! -f "${local_root}/zsh/${name}" ]; then
      rm -f "$dest" && echo "Removed old local link: $dest"
    fi
  done
  [ -d "$local_root" ] || return 0

  if [ -f "$local_manifest" ]; then
    while IFS=$'\t' read -r type source destination extra || [ -n "$type" ]; do
      [ "$type" = "link" ] || continue
      link_file "${local_root}/${source}" "${HOME}/${destination}"
    done <"$local_manifest"
  fi
  for file in "${local_root}"/zsh/*.zsh; do
    [ -f "$file" ] || continue
    link_file "$file" "${custom}/zzz-local-${file##*/}"
  done
  echo "Linked local overlay from $local_root"
}

# Run local/install.sh last, with Bash from the overlay folder, when it
# exists. DOT_CONFIGS_LOCAL holds the overlay path. Its failure only warns:
# private steps never stop an upstream install.
run_local_install_hook() {
  [ -f "${local_root}/install.sh" ] || return 0
  echo "Local install hook: ${local_root}/install.sh"
  (cd "$local_root" && DOT_CONFIGS_LOCAL="$local_root" bash ./install.sh) ||
    echo "Warning: local install hook failed (exit $?); continuing"
}

# Each Firefox install's default profile, one absolute path per line, from the
# [Install*] sections of profiles.ini.
firefox_profiles() {
  local base="${HOME}/Library/Application Support/Firefox" rel
  [ -f "${base}/profiles.ini" ] || return 0
  awk -F= '/^\[/{install=($0 ~ /^\[Install/)} install && $1=="Default"{print $2}' "${base}/profiles.ini" \
    | while IFS= read -r rel; do
      case "$rel" in
        ''|/*|*'..'*) continue ;;
      esac
      [ -d "${base}/${rel}" ] && printf '%s\n' "${base}/${rel}"
    done
}

# Keep the oh-my-firefox theme in a profile's chrome/ folder current: clone it
# when missing, fast-forward it when clean, and otherwise leave it alone.
ensure_oh_my_firefox() {
  local chrome="$1" origin branch tmp
  local url="${DOT_CONFIGS_OH_MY_FIREFOX_URL:-https://github.com/MOSconfig/oh-my-firefox.git}"
  local -a git_env=(GIT_TERMINAL_PROMPT=0)
  [ -n "${GIT_SSH_COMMAND:-}" ] || git_env+=(GIT_SSH_COMMAND='ssh -o BatchMode=yes')

  if [ ! -e "$chrome" ]; then
    # Clone beside the profile, then move it in, so a failed clone never
    # leaves a partial chrome/ behind.
    tmp="$(mktemp -d "${chrome}.clone.XXXXXX")" || return 0
    if env "${git_env[@]}" git clone --quiet "$url" "${tmp}/repo" 2>/dev/null \
        && mv "${tmp}/repo" "$chrome"; then
      echo "Cloned oh-my-firefox into $chrome"
    else
      echo "Warning: could not clone oh-my-firefox into $chrome"
    fi
    case "$tmp" in
      "${chrome}".clone.??????) rm -rf -- "$tmp" ;;
    esac
    return 0
  fi
  if [ ! -d "${chrome}/.git" ]; then
    echo "Leaving $chrome alone: it is not a Git checkout of oh-my-firefox."
    return 0
  fi
  origin="$(git -C "$chrome" remote get-url origin 2>/dev/null || true)"
  case "$origin" in
    *[/:]MOSconfig/oh-my-firefox|*[/:]MOSconfig/oh-my-firefox.git|"$url") ;;
    *) echo "Leaving $chrome alone: origin is ${origin:-missing}, not oh-my-firefox."; return 0 ;;
  esac
  if [ -n "$(git -C "$chrome" status --porcelain --untracked-files=no)" ] \
      || ! branch="$(git -C "$chrome" symbolic-ref --quiet --short HEAD)" \
      || ! git -C "$chrome" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    echo "Leaving $chrome alone: it has local changes, a detached HEAD, or no upstream."
    return 0
  fi
  if env "${git_env[@]}" git -C "$chrome" pull --ff-only --quiet 2>/dev/null; then
    echo "oh-my-firefox in $chrome is at $(git -C "$chrome" rev-parse --short HEAD) ($branch)"
  else
    echo "Warning: could not fast-forward oh-my-firefox in $chrome; update it by hand."
  fi
}

# Link the managed user.js into every default profile and keep its theme
# current. Firefox reads both at its next start.
install_firefox_config() {
  local profile source destination type
  while IFS= read -r profile; do
    while IFS=$'\t' read -r type source destination; do
      [ "$type" = "firefox" ] || continue
      link_file "${repo_root}/${source}" "${profile}/${destination}"
    done <"$manifest"
    ensure_oh_my_firefox "${profile}/chrome"
    echo "Firefox profile configured: $profile"
  done < <(firefox_profiles)
}

# Firefox changes only with --all, so a routine uu never touches it. Existing
# user.js links still follow the repo.
install_firefox_step() {
  if [ "$install_all" = 1 ]; then
    install_firefox_config
  else
    echo "Firefox: skipped; run uu --all or ./install.sh --all to set it up."
  fi
}

manifest_source_for_destination() {
  local expected_type="$1"
  local expected_destination="$2"
  local type source destination

  while IFS=$'\t' read -r type source destination; do
    if [ "$type" = "$expected_type" ] && [ "$destination" = "$expected_destination" ]; then
      printf '%s\n' "${repo_root}/${source}"
      return 0
    fi
  done <"$manifest"

  echo "Error: manifest has no $expected_type entry for $expected_destination" >&2
  return 1
}

link_manifest_files() {
  local type source destination
  while IFS=$'\t' read -r type source destination; do
    [ "$type" = "link" ] || continue
    herdr_source_missing "$source" && continue
    herdr_skip_link "$destination" && continue
    migrate_managed_link "$destination"
    link_file "${repo_root}/${source}" "${HOME}/${destination}"
    case "$source" in
      *.sh) chmod +x "${repo_root}/${source}" ;;
    esac
  done <"$manifest"
}

# copy rows install real files: Herdr does not load a mod's svg()/image() assets
# through links. No backup is made. A destination that is a link into this
# repo's worktrees is replaced by the copy; any other link, or a folder, is left
# alone with a warning. The state file records "<sha256>  <destination>" for
# every installed copy, so when a row goes away its copy is removed only while
# its bytes are still the ones installed; an edited copy is kept and dropped.
copy_state_file() { printf '%s\n' "${HOME}/.local/state/dot-configs/copy-manifest"; }

file_sha256() {
  if have_cmd shasum; then shasum -a 256 "$1"; else sha256sum "$1"; fi | cut -c1-64
}

link_points_into_repo() {
  local link="$1" target dir root
  target="$(readlink "$link")" || return 1
  case "$target" in /*) ;; *) target="$(dirname "$link")/$target" ;; esac
  dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || return 1
  while IFS= read -r root; do
    root="$(cd "$root" 2>/dev/null && pwd -P)" || continue
    case "$dir/" in "$root"/*) return 0 ;; esac
  done < <(git -C "$repo_root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  return 1
}

copy_file() {
  local src="$1" dest="$2"
  case "$dest" in
    ''|*/|*/.|*/..|*/../*) echo "Error: unsafe copy destination: $dest" >&2; return 1 ;;
  esac
  if [ -L "$dest" ]; then
    link_points_into_repo "$dest" || {
      echo "Warning: $dest is a link outside this repo; left it alone" >&2
      return 1
    }
    rm -f "$dest" || return 1
  elif [ -d "$dest" ]; then
    echo "Warning: $dest is a folder; left it alone" >&2
    return 1
  elif [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    return 0
  elif [ -e "$dest" ]; then
    echo "Replaced $dest"
  fi
  mkdir -p "$(dirname "$dest")" || return 1
  install -m 0644 "$src" "$dest"
}

# The state line for one destination (sha and two spaces are 66 characters).
copy_state_line() { awk -v d="$1" 'substr($0, 67) == d' "$2" 2>/dev/null || true; }

copy_manifest_files() {
  local type source destination dest state tmp line sum path dests status=0
  state="$(copy_state_file)"
  dests="$(awk -F'\t' -v h="$HOME" '$1 == "copy" { print h "/" $3 }' "$manifest")"
  [ -n "$dests" ] || [ -f "$state" ] || return 0
  mkdir -p "$(dirname "$state")" || return 1
  tmp="$(mktemp "${state}.XXXXXX")" || return 1
  while IFS=$'\t' read -r type source destination; do
    [ "$type" = copy ] || continue
    dest="${HOME}/${destination}"
    # A missing source (an offline submodule) keeps the old copy and its state.
    if [ ! -f "${repo_root}/${source}" ]; then
      copy_state_line "$dest" "$state" >>"$tmp"
      continue
    fi
    if copy_file "${repo_root}/${source}" "$dest"; then
      printf '%s  %s\n' "$(file_sha256 "$dest")" "$dest" >>"$tmp"
    else
      status=1
      copy_state_line "$dest" "$state" >>"$tmp"
    fi
  done <"$manifest"
  if [ -f "$state" ]; then
    while IFS= read -r line; do
      sum="${line:0:64}"; path="${line:66}"
      [ -n "$path" ] || continue
      printf '%s\n' "$dests" | grep -qxF -- "$path" && continue
      [ -f "$path" ] && [ ! -L "$path" ] || continue
      if [ "$(file_sha256 "$path")" = "$sum" ]; then
        rm -f "$path" && echo "Removed $path (its source is gone)"
        rmdir "$(dirname "$path")" 2>/dev/null || true
      else
        echo "Kept $path (edited since install; no longer managed)"
      fi
    done <"$state"
  fi
  if [ -f "$state" ] && cmp -s "$tmp" "$state"; then
    rm -f "$tmp"
  else
    mv -f "$tmp" "$state" || { rm -f "$tmp"; return 1; }
  fi
  return "$status"
}

remove_legacy_claude_subagent_hook() {
  local hooks_dir="${HOME}/.claude/hooks"
  remove_repo_symlink "${hooks_dir}/subagent-counter.sh" \
    "${repo_root}/claude/hooks/subagent-counter.sh" "Claude subagent hook"
  if [ -d "$hooks_dir" ]; then
    rmdir "$hooks_dir" 2>/dev/null || true
  fi
}

remove_repo_symlink() {
  local path="$1"
  local former_target="$2"
  local label="$3"
  local target=""

  if [ -L "$path" ]; then
    target="$(readlink "$path")"
    if [ "$target" = "$former_target" ]; then
      rm -f "$path"
      echo "Migration: removed retired ${label} symlink."
    fi
  fi
}

xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

sed_replacement_escape() {
  sed 's/[\\&|]/\\&/g'
}

render_launchd_template() {
  local template="$1"
  local dest="$2"
  local escaped_home=""
  local escaped_repo=""

  remove_backups_of "$dest" || return 1
  escaped_home="$(xml_escape "$HOME" | sed_replacement_escape)"
  escaped_repo="$(xml_escape "$repo_root" | sed_replacement_escape)"
  mkdir -p "$(dirname "$dest")"
  mkdir -p "${HOME}/Library/Logs"
  sed -e "s|__HOME__|${escaped_home}|g" \
    -e "s|__REPO_ROOT__|${escaped_repo}|g" \
    "$template" >"$dest"
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

install_copilot_relay_healthcheck() {
  local uid="$1"
  local label="com.d0n9x1n.copilot-relay-healthcheck"
  local plist="${HOME}/Library/LaunchAgents/${label}.plist"
  local template=""
  local script="${scripts_root}/launchd/copilot-relay-healthcheck.sh"
  local launcher_dest=".local/libexec/Copilot Relay Health Check"
  local launcher=""

  template="$(manifest_source_for_destination render "Library/LaunchAgents/${label}.plist")"
  launcher="$(manifest_source_for_destination link "$launcher_dest")"
  [ -f "$template" ] && [ -f "$script" ] && [ -f "$launcher" ] || return 0

  chmod +x "$launcher"
  link_file "$launcher" "${HOME}/${launcher_dest}"
  chmod +x "$script" 2>/dev/null || true
  render_launchd_template "$template" "$plist"

  if ! have_cmd copilot-relay || [ ! -f "${HOME}/.copilot-relay/github_token" ]; then
    if launchctl print "gui/${uid}/${label}" >/dev/null 2>&1; then
      launchctl bootout "gui/${uid}/${label}" 2>/dev/null || true
    fi
    echo "Skipping copilot-relay healthcheck until the relay is installed and authenticated."
    return 0
  fi

  if bootstrap_launchd_agent "$uid" "$label" "$plist"; then
    log_command launchctl kickstart -k "gui/${uid}/${label}" || true
    echo "Loaded launchd agent $label (GET /healthz every 60s; logs: ~/Library/Logs/copilot-relay-healthcheck.log)"
  else
    echo "Warning: launchctl bootstrap failed for $label"
  fi
}

install_copilot_relay() {
  local uid="$1"
  local mode="${2:-normal}"
  local launchd_dest="${HOME}/Library/LaunchAgents/com.d0n9x1n.copilot-relay.plist"
  local launchd_src=""
  local launcher_dest=".local/libexec/Copilot Relay"
  local launcher=""
  local relay_ready=0 attempt=1

  launchd_src="$(manifest_source_for_destination render Library/LaunchAgents/com.d0n9x1n.copilot-relay.plist)"
  launcher="$(manifest_source_for_destination link "$launcher_dest")"
  [ -f "$launchd_src" ] && [ -f "$launcher" ] || return 0

  if [ "$mode" != "stage-only" ] && ! have_cmd copilot-relay; then
    if [ "${SKIP_NPM_GLOBALS:-0}" = "1" ]; then
      echo "Skipping copilot-relay launchd agent: SKIP_NPM_GLOBALS=1 and copilot-relay is not on PATH."
    else
      echo "Warning: copilot-relay not on PATH — skipping agent install (fix npm/global CLI install, then re-run install.sh)"
    fi
    return 0
  fi

  chmod +x "$launcher"
  link_file "$launcher" "${HOME}/${launcher_dest}"
  render_launchd_template "$launchd_src" "$launchd_dest"

  # Scoped naming only stages the next launch; never recover or reload the relay.
  if [ "$mode" = "stage-only" ]; then
    return 0
  fi

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
}

install_npm_cache_clean() {
  local uid="$1"
  local npmclean_dest="${HOME}/Library/LaunchAgents/com.d0n9x1n.npm-cache-clean.plist"
  local npmclean_src=""
  local npmclean_script="${scripts_root}/launchd/clean-npm-caches.sh"
  local launcher_dest=".local/libexec/Weekly npm Cache Cleanup"
  local launcher=""

  npmclean_src="$(manifest_source_for_destination render Library/LaunchAgents/com.d0n9x1n.npm-cache-clean.plist)"
  launcher="$(manifest_source_for_destination link "$launcher_dest")"
  if [ -f "$npmclean_src" ] && [ -f "$npmclean_script" ] && [ -f "$launcher" ]; then
    chmod +x "$launcher"
    link_file "$launcher" "${HOME}/${launcher_dest}"
    chmod +x "$npmclean_script" 2>/dev/null || true
    render_launchd_template "$npmclean_src" "$npmclean_dest"

    if bootstrap_launchd_agent "$uid" "com.d0n9x1n.npm-cache-clean" "$npmclean_dest"; then
      echo "Loaded launchd agent com.d0n9x1n.npm-cache-clean (weekly Sun 03:17; logs: ~/Library/Logs/npm-cache-clean.log)"
    else
      echo "Warning: launchctl bootstrap failed for com.d0n9x1n.npm-cache-clean"
    fi
  fi
}

# Merge the shared MCP servers into local Copilot MCP data; shared wins.
merge_shared_mcp() {
  local shared_mcp="$1"
  local copilot_mcp_pre="${HOME}/.config/github-copilot/mcp.json"
  local tmp_mcp
  remove_backups_of "$copilot_mcp_pre" || return 1
  have_cmd jq && [ -f "$shared_mcp" ] || return 0
  mkdir -p "$(dirname "$copilot_mcp_pre")"
  if [ ! -f "$copilot_mcp_pre" ]; then
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
}

# Import Copilot's merged MCP server map into Claude Code's local state file.
# Skips the rewrite when .mcpServers already matches. Never backs up the file.
import_copilot_mcp_into_claude() {
  local copilot_mcp="${HOME}/.config/github-copilot/mcp.json"
  local claude_user_json="${HOME}/.claude.json"
  local src_mcp_json tmp_user
  remove_backups_of "$claude_user_json" || return 1
  have_cmd jq && [ -f "$copilot_mcp" ] || return 0
  src_mcp_json="$(jq -c '.mcpServers // {}' "$copilot_mcp" || echo '{}')"
  if [ "$src_mcp_json" = '{}' ] || [ "$src_mcp_json" = "null" ]; then
    return 0
  fi
  if [ -f "$claude_user_json" ] &&
      jq -e --argjson src "$src_mcp_json" '.mcpServers == $src' "$claude_user_json" >/dev/null 2>&1; then
    echo "MCP servers in $claude_user_json already match $copilot_mcp"
    return 0
  fi
  tmp_user="$(mktemp -t claude-user-json.XXXXXX)"
  if [ -f "$claude_user_json" ]; then
    if jq --argjson src "$src_mcp_json" '.mcpServers = $src' \
        "$claude_user_json" >"$tmp_user"; then
      mv "$tmp_user" "$claude_user_json"
      chmod 600 "$claude_user_json"
      echo "Imported $(echo "$src_mcp_json" | jq 'length') MCP servers into $claude_user_json (from $copilot_mcp)"
    else
      rm -f "$tmp_user"
      echo "Warning: jq merge into $claude_user_json failed; MCP import skipped"
    fi
  else
    printf '{"mcpServers":%s}\n' "$src_mcp_json" >"$tmp_user"
    mv "$tmp_user" "$claude_user_json"
    chmod 600 "$claude_user_json"
    echo "Created $claude_user_json with $(echo "$src_mcp_json" | jq 'length') MCP servers (from $copilot_mcp)"
  fi
}

# Keep the harbor-client desktop app's model keys in step with this Mac's
# relay. Only the keys in the tracked file change; every other key the app
# writes stays, and secrets.bin is never read. Skips when the app has no data
# folder yet, when settings.json is not a JSON object, or when it already
# matches. The write is atomic (temp file + rename in the same folder).
merge_harbor_client_settings() {
  local shared="$1"
  local app_dir="${HOME}/Library/Application Support/harbor-client"
  local dest="${app_dir}/settings.json"
  local tmp
  remove_backups_of "$dest" || return 1
  have_cmd jq && [ -f "$shared" ] || return 0
  if [ ! -d "$app_dir" ]; then
    echo "harbor-client: no app data folder; skipped"
    return 0
  fi
  if [ -f "$dest" ]; then
    if ! jq -e 'type == "object"' "$dest" >/dev/null 2>&1; then
      echo "Warning: $dest is not a JSON object; harbor-client settings left alone"
      return 0
    fi
    if jq -e --slurpfile s "$shared" '. as $cur | $s[0] | to_entries | all(.value == $cur[.key])' \
        "$dest" >/dev/null 2>&1; then
      echo "harbor-client settings already match $shared"
      return 0
    fi
  fi
  tmp="$(mktemp "${dest}.dot-configs.XXXXXX")" || return 1
  if [ -f "$dest" ]; then
    set -- jq -s '.[0] + .[1]' "$dest" "$shared"
  else
    set -- jq '.' "$shared"
  fi
  if "$@" >"$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$dest"; then
    echo "Merged harbor-client model settings into $dest (restart harbor-client to use them)"
  else
    rm -f "$tmp"
    echo "Warning: could not merge harbor-client settings into $dest; skipped"
  fi
}

if [ "${DOT_CONFIGS_INSTALL_LIB_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

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

ensure_herdr
herdr_install_prepare
validate_manifest
validate_local_overlay
install_apollo_themes
link_manifest_files
copy_manifest_files || echo "Warning: some copy rows were not installed (see above)" >&2
herdr_install_report
herdr_dock_icon
link_local_overlay
install_firefox_step
# RMUX is Windows-only. Keep retention while an older macOS install remains.
if is_macos && have_cmd python3 && have_cmd rmux; then
  log_command python3 -B "${scripts_root}/rmux/store.py" prepare || {
    action_required "RMUX runtime retention failed; do not upgrade RMUX until this is resolved."
    exit 1
  }
fi
remove_repo_symlink "${HOME}/.gitignore" "${repo_root}/.gitignore" "old global Git ignore"
remove_legacy_claude_subagent_hook
remove_repo_symlink "${HOME}/.copilot/AGENTS.md" \
  "${repo_root}/config/copilot/AGENTS.md" "duplicate Copilot instructions"
remove_repo_symlink "${HOME}/.copilot/AGENTS.md" \
  "${repo_root}/copilot/AGENTS.md" "old Copilot instructions"

echo "Linked active config from $manifest"

cleanup_script="$(manifest_source_for_destination link .copilot/cleanup-legacy.sh)"
if [ -x "$cleanup_script" ]; then
  if have_cmd copilot; then
    log_command "$cleanup_script" || echo "Warning: Copilot legacy cleanup reported errors (skipping)"
  else
    echo "Skipping Copilot legacy cleanup: copilot CLI not on PATH."
  fi
fi

# Merge tracked, secret-free MCP servers into the user's Copilot MCP config.
merge_shared_mcp "$(manifest_source_for_destination merge .config/github-copilot/mcp.json)"

# The official Copilot plugin supersedes the old vendored WakaTime MCP.
cleanup_legacy_wakatime_mcp

# The Copilot plugin manages its own WakaTime CLI on session start.
ensure_copilot_wakatime_plugin

# Feature-Crew: one plugin for Claude Code and Copilot CLI.
ensure_cli_plugin feature-crew D0n9X1n/feature-crew
cleanup_legacy_feature_crew

# mermaid-tty: Mermaid diagrams drawn in the terminal, for Claude Code.
ensure_mermaid_tty_plugin

# mux-agents: helper agents in tmux or RMUX panes, for Claude Code and Copilot CLI.
ensure_cli_plugin mux-agents D0n9X1n/mux-agents

# Every other enabled Claude Code plugin.
update_claude_plugins

# Import Copilot's merged MCP server map into Claude Code's local state file.
import_copilot_mcp_into_claude

# harbor-client: model address and names follow the local copilot-relay.
if is_macos; then
  merge_harbor_client_settings \
    "$(manifest_source_for_destination merge "Library/Application Support/harbor-client/settings.json")"
fi

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

  install_copilot_relay "$uid"
  install_copilot_relay_healthcheck "$uid"
fi

# launchd agent: weekly npm/npx cache cleaner (macOS only). Renders the
# template (substituting __HOME__ and __REPO_ROOT__) into ~/Library/LaunchAgents
# and bootstraps it. Unlike copilot-relay this has no auth/PATH gating — the
# tracked script is always present in this repo, and it runs on a schedule
# (Sun 03:17), not at load. Idempotent: bootout+bootstrap is a no-op restart
# when content is unchanged, and replaces the agent when it differs.
if is_macos; then
  uid="$(id -u)"
  install_npm_cache_clean "$uid"
fi

# Last: the overlay's own install hook, for private work upstream cannot know.
run_local_install_hook
