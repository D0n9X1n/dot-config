# Put files in this folder to add your own custom functionality.
# See: https://github.com/ohmyzsh/ohmyzsh/wiki/Customization
#
# Files in the custom/ directory will be:
# - loaded automatically by the init script, in alphabetical order
# - loaded last, after all built-ins in the lib/ directory, to override them
# - ignored by git by default
#

[ -f /opt/homebrew/etc/profile.d/autojump.sh ] && . /opt/homebrew/etc/profile.d/autojump.sh

alias 'ls'='eza'
alias 'll'='eza -l'
alias 'c'='cd ..'
alias 'vim'='nvim'

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

  autoload -Uz compinit
  compinit
fi


# .net sdk
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools

# Android sdk
export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk/
export PATH=$PATH:$ANDROID_SDK_ROOT:$ANDROID_SDK_ROOT/platform-tools
