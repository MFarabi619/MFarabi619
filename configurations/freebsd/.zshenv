. "$HOME/.cargo/env"

# export GOTELEMETRY=off
export NIX_CONF_DIR="$HOME/MFarabi619/configurations/freebsd"
export DOOMDIR="$HOME/MFarabi619/modules/home/programs/emacs"
export YAZI_CONFIG_HOME="$HOME/MFarabi619/configurations/freebsd/.config/yazi"
export ZELLIJ_CONFIG_DIR="$HOME/MFarabi619/configurations/freebsd/.config/zellij"
export TELEVISION_CONFIG="$HOME/MFarabi619/configurations/freebsd/.config/television"
export LG_CONFIG_FILE="$HOME/MFarabi619/configurations/freebsd/.config/lazygit/config.yml"

export EDITOR=nvim
# export EDITOR="emacs -nw"
export PATH="$HOME/.config/emacs/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.platformio/penv/bin:$PATH"

export PNPM_HOME="/home/mfarabi/.local/share/pnpm"
case ":$PATH:" in
*":$PNPM_HOME:"*) ;;
*) export PATH="$PNPM_HOME:$PATH" ;;
esac
