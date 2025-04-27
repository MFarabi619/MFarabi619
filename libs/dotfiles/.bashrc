#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
[ -r /home/mfarabi/.config/byobu/prompt ] && . /home/mfarabi/.config/byobu/prompt   #byobu-prompt#
. "/home/mfarabi/.deno/env"
source /home/mfarabi/.local/share/bash-completion/completions/deno.bash
. "$HOME/.local/bin/env"
