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
    alacritty
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

# Link Alacritty config files (alacritty/* -> ~/.config/alacritty/*).
# Like ghostty before it, the destination is created if missing because
# Alacritty doesn't create ~/.config/alacritty/ until first launch — we
# want install.sh to wire things up on a fresh box without requiring an
# Alacritty launch first.
alacritty_src="${src_dir}/alacritty"
alacritty_dest="${HOME}/.config/alacritty"
if [ -d "$alacritty_src" ]; then
  mkdir -p "$alacritty_dest"
  while IFS= read -r -d '' entry; do
    base="$(basename "$entry")"
    link_file "$entry" "${alacritty_dest}/${base}"
  done < <(find "$alacritty_src" -maxdepth 1 -mindepth 1 -type f -print0)
  echo "Linked Alacritty config files to $alacritty_dest"
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
