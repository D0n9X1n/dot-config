# Put files in this folder to add your own custom functionality.
# See: https://github.com/ohmyzsh/ohmyzsh/wiki/Customization
#
# Files in the custom/ directory will be:
# - loaded automatically by the init script, in alphabetical order
# - loaded last, after all built-ins in the lib/ directory, to override them
# - ignored by git by default
#

[ -f /opt/homebrew/etc/profile.d/autojump.sh ] && . /opt/homebrew/etc/profile.d/autojump.sh

export EZA_CONFIG_DIR="$HOME/.config/eza-apollo-theme"
export FAST_WORK_DIR="$HOME/.local/share/dot-configs/apollo/fsh"
ZSH_THEME=apollo

alias 'ls'='eza'
alias 'll'='eza -l'
alias 'c'='cd ..'
alias 'vim'='nvim'

# Codex sessions launched from this shell have unrestricted tool and sandbox
# access. `command` bypasses this alias and invokes the real Codex executable.
alias codex='command codex --dangerously-bypass-approvals-and-sandbox'

# Copilot loads AGENTS.md from custom instruction directories. Keep the
# repository-managed ~/.copilot/AGENTS.md global without replacing other paths.
case ",${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:-}," in
  *,"$HOME/.copilot",*) ;;
  ,,) export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$HOME/.copilot" ;;
  *) export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="${COPILOT_CUSTOM_INSTRUCTIONS_DIRS},$HOME/.copilot" ;;
esac

##############################################################################
# {{{ Proxy Start
##############################################################################
# Proxy Address
export PROXY_ADDRESS="127.0.0.1:46971"

# Function to enable socks5 proxy
enable_proxy() {
    echo "Enabling SOCKS5 proxy..."

    # Shell (environment variable) proxy settings
    export http_proxy="socks5://$PROXY_ADDRESS"
    export https_proxy="socks5://$PROXY_ADDRESS"
    export all_proxy="socks5://$PROXY_ADDRESS"

    # Git proxy settings
    git config --global http.proxy "socks5://$PROXY_ADDRESS"
    git config --global https.proxy "socks5://$PROXY_ADDRESS"

    # npm proxy settings
    npm config set proxy "socks5://$PROXY_ADDRESS"
    npm config set https-proxy "socks5://$PROXY_ADDRESS"

    echo "SOCKS5 Proxy enabled: $PROXY_ADDRESS"
}

# Function to disable socks5 proxy
disable_proxy() {
    echo "Disabling SOCKS5 proxy..."

    # Shell (environment variable) proxy settings
    unset http_proxy
    unset https_proxy
    unset all_proxy

    # Git proxy settings
    git config --global --unset http.proxy
    git config --global --unset https.proxy

    # npm proxy settings
    npm config delete proxy
    npm config delete https-proxy

    echo "SOCKS5 Proxy disabled"
}

# Aliases for convenience
alias proxy="enable_proxy"
alias unproxy="disable_proxy"
##############################################################################
# }}} Proxy End
##############################################################################

# Zsh syntax highlight
[ -f /opt/homebrew/opt/zsh-fast-syntax-highlighting/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh ] && \
  source /opt/homebrew/opt/zsh-fast-syntax-highlighting/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

# Zsh complete
if type brew &>/dev/null; then
  FPATH=$(brew --prefix)/share/zsh-completions:$FPATH

  # Homebrew completion directories can become group-writable after installs.
  # Fix what we can, then ignore any remaining insecure paths instead of
  # blocking every new shell with compinit's interactive prompt.
  fix_compaudit_permissions() {
    emulate -L zsh
    local dir
    local -a insecure_dirs

    autoload -Uz compaudit
    insecure_dirs=()
    while IFS= read -r dir; do
      insecure_dirs+=("$dir")
    done < <(compaudit 2>/dev/null)
    for dir in "${insecure_dirs[@]}"; do
      [[ -n "$dir" && -e "$dir" ]] || continue
      chmod go-w "$dir" 2>/dev/null || true
    done
  }

  fix_compaudit_permissions
  unfunction fix_compaudit_permissions

  autoload -Uz compinit
  compinit -i
fi


# .net sdk
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools

# Android sdk
export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk/
export PATH=$PATH:$ANDROID_SDK_ROOT:$ANDROID_SDK_ROOT/platform-tools
