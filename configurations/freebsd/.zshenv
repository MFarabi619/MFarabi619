typeset -U path PATH

. "$HOME/.cargo/env"

# ZDOTDIR="$HOME/MFarabi619/configurations/freebsd"
ZSH="$HOME/.oh-my-zsh"
# ZSH_CACHE_DIR="$HOME/.cache/oh-my-zsh"

NIX_CONF_DIR="$HOME/MFarabi619/configurations/freebsd"
DOOMDIR="$HOME/MFarabi619/modules/home/programs/emacs"
YAZI_CONFIG_HOME="$HOME/MFarabi619/configurations/freebsd/.config/yazi"
ZELLIJ_CONFIG_DIR="$HOME/MFarabi619/configurations/freebsd/.config/zellij"
TELEVISION_CONFIG="$HOME/MFarabi619/configurations/freebsd/.config/television"
LG_CONFIG_FILE="$HOME/MFarabi619/configurations/freebsd/.config/lazygit/config.yml"

EDITOR="nvim"
PNPM_HOME="$HOME/.local/share/pnpm"

path=(
  "$HOME/.platformio/penv/bin"
  "$HOME/go/bin"
  "$HOME/.config/emacs/bin"
  "$PNPM_HOME"
  $path
)

export PATH

HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
