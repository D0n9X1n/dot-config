#!/usr/bin/env bash

apollo_release_file() {
  if [ -n "${APOLLO_RELEASES_FILE:-}" ]; then
    printf '%s\n' "$APOLLO_RELEASES_FILE"
  elif [ -n "${scripts_root:-}" ]; then
    printf '%s\n' "${scripts_root}/apollo-releases.tsv"
  else
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/apollo-releases.tsv"
  fi
}

apollo_root() {
  printf '%s\n' "${APOLLO_ROOT:-${HOME}/.local/share/dot-configs/apollo}"
}

apollo_sha256() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    printf 'Error: Apollo installation requires shasum or sha256sum.\n' >&2
    return 1
  fi
}

apollo_bundle_hash() {
  local lock="${1:-$(apollo_release_file)}"
  local script="${APOLLO_THEME_SCRIPT:-${BASH_SOURCE[0]}}"
  if command -v shasum >/dev/null 2>&1; then
    {
      printf 'apollo-bundle-v1\n'
      apollo_sha256 "$lock"
      apollo_sha256 "$script"
    } | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    {
      printf 'apollo-bundle-v1\n'
      apollo_sha256 "$lock"
      apollo_sha256 "$script"
    } | sha256sum | awk '{print $1}'
  else
    printf 'Error: Apollo installation requires shasum or sha256sum.\n' >&2
    return 1
  fi
}

apollo_validate_lock() {
  local lock="${1:-$(apollo_release_file)}"
  local id kind repository tag artifact sha extra seen=""

  [ -f "$lock" ] || {
    printf 'Error: missing Apollo release lock: %s\n' "$lock" >&2
    return 1
  }

  while IFS=$'\t' read -r id kind repository tag artifact sha extra; do
    case "$id" in
      ''|'#'*) continue ;;
    esac
    [ -z "$extra" ] || {
      printf 'Error: Apollo lock row has more than six fields: %s\n' "$id" >&2
      return 1
    }
    case "$id" in
      palette|sonicterm|rmux|eza) ;;
      *) printf 'Error: unknown Apollo release id: %s\n' "$id" >&2; return 1 ;;
    esac
    case "$kind" in
      raw|release) ;;
      *) printf 'Error: unknown Apollo source kind for %s: %s\n' "$id" "$kind" >&2; return 1 ;;
    esac
    if [ "$id" = "palette" ] && [ "$kind" != "raw" ]; then
      printf 'Error: Apollo palette must use a tagged raw source.\n' >&2
      return 1
    fi
    if [ "$id" != "palette" ] && [ "$kind" != "release" ]; then
      printf 'Error: Apollo application %s must use a release asset.\n' "$id" >&2
      return 1
    fi
    printf '%s\n' "$repository" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || {
      printf 'Error: unsafe Apollo repository for %s: %s\n' "$id" "$repository" >&2
      return 1
    }
    printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || {
      printf 'Error: invalid Apollo release tag for %s: %s\n' "$id" "$tag" >&2
      return 1
    }
    case "$artifact" in
      ''|/*|*'..'*) printf 'Error: unsafe Apollo artifact for %s: %s\n' "$id" "$artifact" >&2; return 1 ;;
    esac
    printf '%s\n' "$artifact" | grep -Eq '^[A-Za-z0-9_./-]+$' || {
      printf 'Error: unsafe Apollo artifact for %s: %s\n' "$id" "$artifact" >&2
      return 1
    }
    printf '%s\n' "$sha" | grep -Eq '^[0-9a-f]{64}$' || {
      printf 'Error: invalid Apollo SHA-256 for %s.\n' "$id" >&2
      return 1
    }
    case $'\n'"$seen"$'\n' in
      *$'\n'"$id"$'\n'*) printf 'Error: duplicate Apollo release id: %s\n' "$id" >&2; return 1 ;;
    esac
    seen="${seen}${seen:+$'\n'}${id}"
  done <"$lock"

  for id in palette sonicterm rmux eza; do
    case $'\n'"$seen"$'\n' in
      *$'\n'"$id"$'\n'*) ;;
      *) printf 'Error: Apollo release lock is missing %s.\n' "$id" >&2; return 1 ;;
    esac
  done
}

apollo_lock_row() {
  local wanted="$1"
  local lock="${2:-$(apollo_release_file)}"
  awk -F '\t' -v wanted="$wanted" '$1 == wanted { print; found += 1 } END { if (found != 1) exit 1 }' "$lock"
}

apollo_lock_sha() {
  apollo_lock_row "$1" "${2:-$(apollo_release_file)}" | awk -F '\t' '{print $6}'
}

apollo_source_url() {
  local kind="$1" repository="$2" tag="$3" artifact="$4"
  case "$kind" in
    raw) printf 'https://raw.githubusercontent.com/%s/%s/%s\n' "$repository" "$tag" "$artifact" ;;
    release) printf 'https://github.com/%s/releases/download/%s/%s\n' "$repository" "$tag" "$artifact" ;;
  esac
}

apollo_run_logged() {
  if declare -F log_command >/dev/null 2>&1; then
    log_command "$@" >&2
  else
    "$@"
  fi
}

apollo_fetch_blob() {
  local id="$1" kind="$2" repository="$3" tag="$4" artifact="$5" expected="$6"
  local root blob actual url tmp

  root="$(apollo_root)"
  blob="${root}/blobs/${expected}"
  if [ -f "$blob" ]; then
    actual="$(apollo_sha256 "$blob")" || return 1
    if [ "$actual" = "$expected" ]; then
      printf '%s\n' "$blob"
      return 0
    fi
  fi

  command -v curl >/dev/null 2>&1 || {
    printf 'Error: curl is required to download Apollo %s.\n' "$id" >&2
    return 1
  }
  mkdir -p "${root}/blobs"
  url="$(apollo_source_url "$kind" "$repository" "$tag" "$artifact")"
  tmp="$(mktemp "${root}/blobs/.${expected}.XXXXXX")"
  if ! apollo_run_logged curl -fL --connect-timeout 10 --max-time 60 "$url" -o "$tmp"; then
    rm -f "$tmp"
    printf 'Error: failed to download Apollo %s from %s.\n' "$id" "$url" >&2
    return 1
  fi
  actual="$(apollo_sha256 "$tmp")" || {
    rm -f "$tmp"
    return 1
  }
  if [ "$actual" != "$expected" ]; then
    rm -f "$tmp"
    printf 'Error: Apollo %s checksum mismatch (expected %s, got %s).\n' "$id" "$expected" "$actual" >&2
    return 1
  fi
  chmod 644 "$tmp"
  mv -f "$tmp" "$blob"
  printf '%s\n' "$blob"
}

apollo_validate_palette() {
  local palette="$1"
  jq -e '
    def hex: type == "string" and test("^#[0-9a-f]{6}$");
    .schemaVersion == 1 and
    .id == "apollo" and
    .appearance == "dark" and
    (.colors | [
      .background, .surface, .surfaceHover, .selection,
      .foreground, .foregroundSecondary, .foregroundInactive,
      .foregroundBright, .accent, .danger, .success, .info,
      .magenta, .cyan, .ansiBrightBlack
    ] | all(.[]; hex)) and
    .roles.canvas == "{colors.background}" and
    .roles.textPrimary == "{colors.foreground}" and
    .roles.textSecondary == "{colors.foregroundSecondary}" and
    .roles.textInactive == "{colors.foregroundInactive}" and
    .roles.focus == "{colors.accent}" and
    .roles.error == "{colors.danger}" and
    .roles.warning == "{colors.accent}" and
    .roles.success == "{colors.success}" and
    .roles.information == "{colors.info}" and
    (.terminal.foreground | hex) and
    (.terminal.background | hex) and
    (.terminal.cursor | hex) and
    (.terminal.cursorText | hex) and
    (.terminal.selection.color | hex) and
    .terminal.selection.alpha == 0.5 and
    .terminal.selection.foregroundMode == "preserve" and
    ((.terminal.ansi | length) == 8) and
    (.terminal.ansi | all(.[]; hex)) and
    ((.terminal.bright | length) == 8) and
    (.terminal.bright | all(.[]; hex))
  ' "$palette" >/dev/null
}

apollo_color() {
  jq -er --arg key "$2" '.colors[$key] | select(type == "string")' "$1"
}

apollo_rgb() {
  local value="${1#\#}"
  printf '%d %d %d\n' "$((16#${value:0:2}))" "$((16#${value:2:2}))" "$((16#${value:4:2}))"
}

apollo_append_ansi() {
  local name="$1" plane="$2" color="$3" output="$4"
  local rgb red green blue value code
  rgb="$(apollo_rgb "$color")"
  read -r red green blue <<<"$rgb"
  [ "$plane" = "fg" ] && code=38 || code=48
  printf -v value '\033[%s;2;%s;%s;%sm' "$code" "$red" "$green" "$blue"
  printf '%s=' "$name" >>"$output"
  printf '%q\n' "$value" >>"$output"
}

apollo_generate_statusline_colors() {
  local palette="$1" output="$2" value
  : >"$output"
  printf '# Generated from the installed Apollo release; do not edit.\n' >>"$output"
  printf -v value '\033[0m'; printf 'C_RESET=' >>"$output"; printf '%q\n' "$value" >>"$output"
  printf -v value '\033[2m'; printf 'C_DIM=' >>"$output"; printf '%q\n' "$value" >>"$output"
  apollo_append_ansi C_RED fg "$(apollo_color "$palette" danger)" "$output"
  apollo_append_ansi C_GREEN fg "$(apollo_color "$palette" success)" "$output"
  apollo_append_ansi C_YELLOW fg "$(apollo_color "$palette" accent)" "$output"
  apollo_append_ansi C_BLUE fg "$(apollo_color "$palette" info)" "$output"
  apollo_append_ansi C_PURPLE fg "$(apollo_color "$palette" magenta)" "$output"
  apollo_append_ansi C_AQUA fg "$(apollo_color "$palette" cyan)" "$output"
  apollo_append_ansi C_ORANGE fg "$(apollo_color "$palette" accent)" "$output"
  apollo_append_ansi C_FG fg "$(apollo_color "$palette" foreground)" "$output"
  apollo_append_ansi C_FG_DIM fg "$(apollo_color "$palette" foregroundInactive)" "$output"
  apollo_append_ansi C_FG_BRIGHT fg "$(apollo_color "$palette" foregroundBright)" "$output"
  apollo_append_ansi CB_RED bg "$(apollo_color "$palette" danger)" "$output"
  apollo_append_ansi CB_BLUE bg "$(apollo_color "$palette" info)" "$output"
  apollo_append_ansi CB_YELLOW bg "$(apollo_color "$palette" accent)" "$output"
  apollo_append_ansi CB_ORANGE bg "$(apollo_color "$palette" magenta)" "$output"
  apollo_append_ansi CB_GREEN bg "$(apollo_color "$palette" success)" "$output"
  apollo_append_ansi C_BG_FG fg "$(apollo_color "$palette" background)" "$output"
  chmod 644 "$output"
}

apollo_generate_zsh_colors() {
  local palette="$1" output="$2"
  cat >"$output" <<EOF
# Generated from the installed Apollo release; do not edit.
APOLLO_PROMPT_ACCENT='%F{$(apollo_color "$palette" accent)}'
APOLLO_PROMPT_INFO='%F{$(apollo_color "$palette" info)}'
APOLLO_PROMPT_SUCCESS='%F{$(apollo_color "$palette" success)}'
APOLLO_PROMPT_DANGER='%F{$(apollo_color "$palette" danger)}'
APOLLO_PROMPT_TEXT='%F{$(apollo_color "$palette" foreground)}'
APOLLO_PROMPT_MUTED='%F{$(apollo_color "$palette" foregroundInactive)}'
APOLLO_PROMPT_RESET='%f%k'
EOF
  chmod 644 "$output"
}

apollo_blend() {
  local foreground="${1#\#}" background="${2#\#}" percent="$3"
  local inverse red green blue
  inverse=$((100 - percent))
  red=$(((16#${foreground:0:2} * percent + 16#${background:0:2} * inverse + 50) / 100))
  green=$(((16#${foreground:2:2} * percent + 16#${background:2:2} * inverse + 50) / 100))
  blue=$(((16#${foreground:4:2} * percent + 16#${background:4:2} * inverse + 50) / 100))
  printf '#%02x%02x%02x\n' "$red" "$green" "$blue"
}

apollo_generate_claude_theme() {
  local palette="$1" output="$2" background success danger
  background="$(apollo_color "$palette" background)"
  success="$(apollo_color "$palette" success)"
  danger="$(apollo_color "$palette" danger)"
  jq -n \
    --arg background "$background" \
    --arg surface "$(apollo_color "$palette" surface)" \
    --arg surface_hover "$(apollo_color "$palette" surfaceHover)" \
    --arg selection "$(apollo_color "$palette" selection)" \
    --arg foreground "$(apollo_color "$palette" foreground)" \
    --arg foreground_secondary "$(apollo_color "$palette" foregroundSecondary)" \
    --arg foreground_inactive "$(apollo_color "$palette" foregroundInactive)" \
    --arg foreground_bright "$(apollo_color "$palette" foregroundBright)" \
    --arg accent "$(apollo_color "$palette" accent)" \
    --arg danger "$danger" \
    --arg success "$success" \
    --arg diff_added "$(apollo_blend "$success" "$background" 25)" \
    --arg diff_removed "$(apollo_blend "$danger" "$background" 25)" \
    --arg diff_added_dimmed "$(apollo_blend "$success" "$background" 15)" \
    --arg diff_removed_dimmed "$(apollo_blend "$danger" "$background" 15)" \
    --arg diff_added_word "$(apollo_blend "$success" "$background" 35)" \
    --arg diff_removed_word "$(apollo_blend "$danger" "$background" 35)" \
    --arg info "$(apollo_color "$palette" info)" \
    --arg magenta "$(apollo_color "$palette" magenta)" \
    --arg cyan "$(apollo_color "$palette" cyan)" '
      {
        name: "Apollo",
        base: "dark-ansi",
        overrides: {
          autoAccept: $accent,
          autoAcceptShimmer: $foreground_bright,
          skill: $magenta,
          bashBorder: $magenta,
          claude: $accent,
          claudeShimmer: $foreground_bright,
          permission: $info,
          planMode: $cyan,
          ide: $info,
          promptBorder: $foreground_inactive,
          promptBorderShimmer: $foreground_secondary,
          text: $foreground,
          inverseText: $background,
          inactive: $foreground_inactive,
          subtle: $foreground_inactive,
          suggestion: $info,
          success: $success,
          error: $danger,
          warning: $accent,
          merged: $magenta,
          diffAdded: $diff_added,
          diffRemoved: $diff_removed,
          diffAddedDimmed: $diff_added_dimmed,
          diffRemovedDimmed: $diff_removed_dimmed,
          diffAddedWord: $diff_added_word,
          diffRemovedWord: $diff_removed_word,
          red_FOR_SUBAGENTS_ONLY: $danger,
          blue_FOR_SUBAGENTS_ONLY: $info,
          green_FOR_SUBAGENTS_ONLY: $success,
          yellow_FOR_SUBAGENTS_ONLY: $accent,
          purple_FOR_SUBAGENTS_ONLY: $magenta,
          cyan_FOR_SUBAGENTS_ONLY: $cyan,
          professionalBlue: $info,
          chromeYellow: $accent,
          clawd_body: $accent,
          clawd_background: $background,
          userMessageBackground: $surface,
          userMessageBackgroundHover: $surface_hover,
          composerSidebarBackground: $surface,
          selectionBg: $selection,
          fastMode: $accent,
          effortUltra: $magenta,
          rainbow_red: $danger,
          rainbow_yellow: $accent,
          rainbow_green: $success,
          rainbow_blue: $info,
          rainbow_violet: $magenta
        }
      }
    ' >"$output"
  chmod 644 "$output"
}

apollo_validate_generated() {
  local bundle="$1" expected
  bash -n "${bundle}/generated/statusline-colors.sh" || return 1
  if command -v zsh >/dev/null 2>&1; then
    zsh -n "${bundle}/generated/zsh-colors.zsh" || return 1
  fi
  jq -e '
    .name == "Apollo" and
    .base == "dark-ansi" and
    (.overrides | type == "object") and
    (.overrides | length > 0) and
    ([.overrides[]] | all(.[]; type == "string" and test("^#[0-9a-f]{6}$")))
  ' "${bundle}/generated/claude/apollo.json" >/dev/null || return 1

  expected="$(mktemp -d)"
  mkdir -p "${expected}/claude"
  apollo_generate_statusline_colors "${bundle}/palette/apollo.json" "${expected}/statusline-colors.sh"
  apollo_generate_zsh_colors "${bundle}/palette/apollo.json" "${expected}/zsh-colors.zsh"
  apollo_generate_claude_theme "${bundle}/palette/apollo.json" "${expected}/claude/apollo.json"
  if ! cmp -s "${expected}/statusline-colors.sh" "${bundle}/generated/statusline-colors.sh" || \
      ! cmp -s "${expected}/zsh-colors.zsh" "${bundle}/generated/zsh-colors.zsh" || \
      ! cmp -s "${expected}/claude/apollo.json" "${bundle}/generated/claude/apollo.json"; then
    rm -rf "$expected"
    return 1
  fi
  rm -rf "$expected"
}

apollo_validate_bundle() {
  local bundle="$1" lock="$2" id file expected actual
  [ -f "${bundle}/.complete" ] || return 1
  apollo_validate_palette "${bundle}/palette/apollo.json" || return 1
  for id in palette sonicterm rmux eza; do
    case "$id" in
      palette) file="${bundle}/palette/apollo.json" ;;
      sonicterm) file="${bundle}/sonicterm/apollo.toml" ;;
      rmux) file="${bundle}/rmux/apollo-rmux.conf" ;;
      eza) file="${bundle}/eza/theme.yml" ;;
    esac
    expected="$(apollo_lock_sha "$id" "$lock")" || return 1
    actual="$(apollo_sha256 "$file")" || return 1
    [ "$actual" = "$expected" ] || return 1
  done
  apollo_validate_generated "$bundle"
}

apollo_build_bundle() {
  local stage="$1" lock="$2"
  local id kind repository tag artifact sha blob

  mkdir -p "${stage}/palette" "${stage}/sonicterm" "${stage}/rmux" \
    "${stage}/eza" "${stage}/generated/claude"

  for id in palette sonicterm rmux eza; do
    IFS=$'\t' read -r id kind repository tag artifact sha <<<"$(apollo_lock_row "$id" "$lock")"
    blob="$(apollo_fetch_blob "$id" "$kind" "$repository" "$tag" "$artifact" "$sha")" || return 1
    case "$id" in
      palette) cp "$blob" "${stage}/palette/apollo.json" ;;
      sonicterm) cp "$blob" "${stage}/sonicterm/apollo.toml" ;;
      rmux) cp "$blob" "${stage}/rmux/apollo-rmux.conf" ;;
      eza) cp "$blob" "${stage}/eza/theme.yml" ;;
    esac
  done

  apollo_validate_palette "${stage}/palette/apollo.json" || {
    printf 'Error: pinned Apollo palette has an unsupported schema.\n' >&2
    return 1
  }
  apollo_generate_statusline_colors "${stage}/palette/apollo.json" "${stage}/generated/statusline-colors.sh"
  apollo_generate_zsh_colors "${stage}/palette/apollo.json" "${stage}/generated/zsh-colors.zsh"
  apollo_generate_claude_theme "${stage}/palette/apollo.json" "${stage}/generated/claude/apollo.json"
  : >"${stage}/.complete"
  apollo_validate_bundle "$stage" "$lock"
}

apollo_validate_eza_version() {
  local current
  command -v eza >/dev/null 2>&1 || return 0
  current="$(eza --version 2>/dev/null | sed -nE 's/^v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | sed -n '1p')"
  if [ -z "$current" ] || ! version_at_least "$current" 0.23.5; then
    printf 'Error: Apollo requires eza v0.23.5 or later; found %s.\n' "${current:-unknown}" >&2
    return 1
  fi
}

apollo_validate_claude_state() {
  local state="${HOME}/.claude.json"
  [ ! -e "$state" ] || jq -e 'type == "object"' "$state" >/dev/null || {
    printf 'Error: %s is not a valid JSON object; Apollo theme selection was not changed.\n' "$state" >&2
    return 1
  }
}

apollo_set_claude_theme() {
  local state="${HOME}/.claude.json" tmp
  if [ -f "$state" ] && jq -e '.theme == "custom:apollo"' "$state" >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$(dirname "$state")"
  tmp="$(mktemp "${state}.tmp.XXXXXX")"
  if [ -f "$state" ]; then
    jq '.theme = "custom:apollo"' "$state" >"$tmp" || {
      rm -f "$tmp"
      return 1
    }
    backup_path_once "$state" || {
      rm -f "$tmp"
      return 1
    }
  else
    jq -n '{theme: "custom:apollo"}' >"$tmp"
  fi
  mv "$tmp" "$state"
  chmod 600 "$state"
}

apollo_switch_current() {
  local root="$1" target="$2" current tmp
  current="${root}/current"
  if [ -L "$current" ] && [ "$(readlink "$current")" = "$target" ]; then
    return 0
  fi
  if [ -e "$current" ] && [ ! -L "$current" ]; then
    printf 'Error: Apollo current path is not an installer-managed symlink: %s\n' "$current" >&2
    return 1
  fi
  tmp="${root}/.current.$$"
  rm -f "$tmp"
  ln -s "$target" "$tmp"
  if is_macos; then
    mv -fh "$tmp" "$current"
  else
    mv -fT "$tmp" "$current"
  fi
}

apollo_link_consumers() {
  local root="$1"
  link_file "${root}/current/sonicterm/apollo.toml" "${HOME}/.sonicterm/themes/apollo.toml" || return 1
  link_file "${root}/current/rmux/apollo-rmux.conf" "${HOME}/.config/rmux-apollo-theme/apollo-rmux.conf" || return 1
  link_file "${root}/current/eza/theme.yml" "${HOME}/.config/eza-apollo-theme/theme.yml" || return 1
  link_file "${root}/current/generated/claude/apollo.json" "${HOME}/.claude/themes/apollo.json" || return 1
}

apollo_install_fsh_base16() {
  local root="$1" plugin base work tmp stage theme staged_current staged_secondary
  [ "${APOLLO_SKIP_FSH:-0}" = "1" ] && return 0
  command -v zsh >/dev/null 2>&1 || return 0

  plugin="${APOLLO_FSH_PLUGIN:-/opt/homebrew/opt/zsh-fast-syntax-highlighting/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh}"
  base="$(dirname "$plugin")"
  [ -f "$plugin" ] && [ -f "${base}/themes/base16.ini" ] || return 0
  work="${root}/fsh"
  if [ -f "${work}/current_theme.zsh" ] && \
      grep -Fq 'FAST_THEME_NAME="base16"' "${work}/current_theme.zsh" && \
      zsh -n "${work}/current_theme.zsh"; then
    return 0
  fi

  tmp="$(mktemp -d "${root}/.fsh.XXXXXX")"
  stage="${tmp}/work"
  theme="${tmp}/base16.ini"
  mkdir -p "$stage"
  sed 's/^; secondary[[:space:]]*=.*/secondary =/' "${base}/themes/base16.ini" >"$theme"
  : >"${stage}/secondary_theme.zsh"
  if ! FAST_WORK_DIR="$stage" FSH_PLUGIN="$plugin" FSH_THEME="$theme" zsh -f <<'ZSH'
source "$FSH_PLUGIN"
function .fast-read-ini-file() {
  local ini_file="$1" output_hash="${2:-INI}" key_prefix="$3"
  local IFS='' line section="void" access
  local -a match mbegin mend
  [[ -r "$ini_file" ]] || return 1
  while read -r -t 1 line; do
    if [[ "$line" = [[:blank:]]#\;* ]]; then
      continue
    elif [[ "$line" = (#b)[[:blank:]]#\[([^\]]##)\][[:blank:]]# ]]; then
      section="${match[1]}"
    elif [[ "$line" = (#b)[[:blank:]]#([^[:blank:]=]##)[[:blank:]]#[=][[:blank:]]#(*) ]]; then
      match[2]="${match[2]%"${match[2]##*[! $'\t']}"}"
      access="${output_hash}[${key_prefix}<${section}>_${match[1]}]"
      : "${(P)access::=${match[2]}}"
    fi
  done <"$ini_file"
}
fast-theme -q "$FSH_THEME"
ZSH
  then
    rm -rf "$tmp"
    printf 'Error: could not select fast-syntax-highlighting Base16 theme.\n' >&2
    return 1
  fi
  if ! grep -Fq 'FAST_THEME_NAME="base16"' "${stage}/current_theme.zsh" || \
      ! zsh -n "${stage}/current_theme.zsh"; then
    rm -rf "$tmp"
    printf 'Error: fast-syntax-highlighting produced an invalid Base16 cache.\n' >&2
    return 1
  fi

  mkdir -p "$work"
  staged_current="${work}/.current_theme.zsh.$$"
  staged_secondary="${work}/.secondary_theme.zsh.$$"
  cp "${stage}/current_theme.zsh" "$staged_current"
  cp "${stage}/secondary_theme.zsh" "$staged_secondary"
  mv -f "$staged_current" "${work}/current_theme.zsh"
  mv -f "$staged_secondary" "${work}/secondary_theme.zsh"
  rm -f "${work}/current_theme.zsh.zwc"
  rm -rf "$tmp"
}

install_apollo_themes() {
  local lock root lock_hash final stage target
  lock="$(apollo_release_file)"
  root="$(apollo_root)"
  apollo_validate_lock "$lock" || return 1
  command -v jq >/dev/null 2>&1 || {
    printf 'Error: Apollo installation requires jq.\n' >&2
    return 1
  }
  apollo_validate_claude_state || return 1
  apollo_validate_eza_version || return 1

  lock_hash="$(apollo_bundle_hash "$lock")" || return 1
  final="${root}/sets/${lock_hash}"
  mkdir -p "${root}/sets" "${root}/blobs"
  if ! apollo_validate_bundle "$final" "$lock" >/dev/null 2>&1; then
    if [ -e "$final" ]; then
      printf 'Error: existing Apollo release set is incomplete or corrupt: %s\n' "$final" >&2
      return 1
    fi
    stage="$(mktemp -d "${root}/sets/.${lock_hash}.XXXXXX")"
    if ! apollo_build_bundle "$stage" "$lock"; then
      rm -rf "$stage"
      return 1
    fi
    mv "$stage" "$final"
  fi

  apollo_install_fsh_base16 "$root" || return 1
  apollo_link_consumers "$root" || return 1
  apollo_set_claude_theme || return 1
  target="sets/${lock_hash}"
  apollo_switch_current "$root" "$target" || return 1
  printf 'Apollo themes are active from %s.\n' "$final"
}

verify_apollo_release_pins() {
  local lock temp id kind repository tag artifact sha actual url
  lock="$(apollo_release_file)"
  apollo_validate_lock "$lock" || return 1
  temp="$(mktemp -d -t dot-configs-apollo-verify.XXXXXX)"
  while IFS=$'\t' read -r id kind repository tag artifact sha; do
    case "$id" in
      ''|'#'*) continue ;;
    esac
    url="$(apollo_source_url "$kind" "$repository" "$tag" "$artifact")"
    if ! curl -fL --connect-timeout 10 --max-time 60 "$url" -o "${temp}/${id}"; then
      rm -rf "$temp"
      return 1
    fi
    actual="$(apollo_sha256 "${temp}/${id}")"
    [ "$actual" = "$sha" ] || {
      printf 'Error: online Apollo checksum mismatch for %s.\n' "$id" >&2
      rm -rf "$temp"
      return 1
    }
  done <"$lock"
  rm -rf "$temp"
  printf 'Apollo release pins match their published files.\n'
}
