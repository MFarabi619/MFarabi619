# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-autosuggestions zsh-syntax-highlighting web-search)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Environment variables for Perl and CPAN
PATH="/Users/mfarabi/perl5/bin${PATH:+:${PATH}}"; export PATH;
PERL5LIB="/Users/mfarabi/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="/Users/mfarabi/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"/Users/mfarabi/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=/Users/mfarabi/perl5"; export PERL_MM_OPT;

# Alias eza to ls
alias ld="eza -lD"
alias lf="eza -lf --color=always | grep -v /"
alias lh="eza -dl .* --group-directories-first"
alias ll="eza -al --group-directories-first"
# alias ls="eza -alf --color=always --sort=size | grep -v /"
# alias ls="eza -a --color=always --group-directories-first"
# alias ls="eza -a --color=always --long --git --group-directories-first --no-filesize --icons=always --no-time --no-user --no-permissions"
alias ls="eza -a --color=always --git --group-directories-first --no-filesize --icons=always --no-time --no-user --no-permissions"
alias lt="eza -al --sort=modified"

# For fzf
eval "$(fzf --zsh)"

# Alias cat to bat
alias cat="bat"

######################## For easy editing of configuration files ########################

# Define an associative array with configuration mappings
typeset -A config_paths
config_paths=(
    [zshrc]="$HOME/.zshrc"
    [bashrc]="$HOME/.bashrc"
    [vimrc]="$HOME/.vimrc"
    [tmuxconf]="$HOME/.tmux.conf"
    [tmuxconflocal]="$HOME/.tmux.conf.local"
    [yabairc]="$HOME/.config/yabai/yabairc"
    [skhdrc]="$HOME/config/skhd/skhdrc"
    [p10krc]="$HOME/.p10k.zsh"
)

# General function to edit and optionally source configurations
edit_and_source_config() {
    local config_name=$1
    local config_path=${config_paths[$config_name]}

    # Check if the configuration name is valid
    if [[ -z "$config_path" ]]; then
        echo "Config file not recognized."
        return 1
    fi

    # Open the configuration file with nvim
    nvim "$config_path"

    # Source the file if it is not the tmux configuration
    if [[ "$config_name" != "tmuxconf" || "$config_name" != "tmuxconflocal" ]]; then
      # tmux source-file "$HOME/.tmux.conf"
        source "$config_path"
    fi
}

alias zshrc='edit_and_source_config zshrc'
alias bashrc='edit_and_source_config bashrc'
alias vimrc='edit_and_source_config vimrc'
alias tmuxconf='edit_and_source_config tmuxconf'
alias tmuxconflocal='edit_and_source_config tmuxconflocal'
alias yabairc='edit_and_source_config yabairc'
alias skhdrc='edit_and_source_config skhdrc'
alias p10krc='edit_and_source_config p10krc'

# Created by `pipx` on 2024-07-09 21:42:36
export PATH="$PATH:/Users/mfarabi/.local/bin"

# Set default editor to NeoVim
export EDITOR=nvim
