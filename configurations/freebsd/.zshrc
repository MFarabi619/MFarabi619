# Enable Powerlevel10k instant prompt. Keep near the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

zstyle ':omz:plugins:eza' 'icons' yes
zstyle ':omz:plugins:eza' 'dirs-first' yes
zstyle ':omz:plugins:eza' 'header' yes
zstyle ':omz:plugins:eza' 'show-group' no

plugins=(
  uv
  git
  sudo
  ssh
  fzf
  eza
  rust
  direnv
  pulumi
  kubectl
  colorize
  tailscale
  zsh-256color
  command-not-found
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

alias ..='cd ..'
alias ...='cd ../..'
alias .3='cd ../../..'
alias .4='cd ../../../..'
alias .5='cd ../../../../..'

alias c='clear'
alias cat='bat'
alias yy='yazi'
alias lg='lazygit'
alias lsh='lazyssh'
alias mkdir='mkdir -p'
alias lt='eza --tree --icons=auto'
alias nvim="XDG_CONFIG_HOME=$HOME/MFarabi619/configurations/freebsd/.config nvim"
alias fastfetch='fastfetch --config $HOME/MFarabi619/modules/home/programs/fastfetch/config.jsonc'

eval "$(tv init zsh)"
eval "$(docker-machine env)"
