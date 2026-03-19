typeset -U path PATH

. "$HOME/.cargo/env"

export NIX_CONF_DIR="$HOME/MFarabi619/configurations/freebsd"
export DOOMDIR="$HOME/MFarabi619/modules/home/programs/emacs"
export YAZI_CONFIG_HOME="$HOME/MFarabi619/configurations/freebsd/.config/yazi"
export ZELLIJ_CONFIG_DIR="$HOME/MFarabi619/configurations/freebsd/.config/zellij"
export TELEVISION_CONFIG="$HOME/MFarabi619/configurations/freebsd/.config/television"
export LG_CONFIG_FILE="$HOME/MFarabi619/configurations/freebsd/.config/lazygit/config.yml"

export EDITOR="nvim"
export PNPM_HOME="$HOME/.local/share/pnpm"

path=(
  "$HOME/.platformio/penv/bin"
  "$HOME/go/bin"
  "$HOME/.config/emacs/bin"
  "$PNPM_HOME"
  $path
)

export PATH
