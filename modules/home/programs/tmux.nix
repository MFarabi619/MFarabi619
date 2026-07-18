{
  programs.tmux = {
    enable = true;

    mouse = true;
    shortcut = "a";
    keyMode = "vi";
    escapeTime = 0;
    focusEvents = true;
    historyLimit = 50000;
    aggressiveResize = true;
    terminal = "xterm-256color";

    extraConfig = ''
      bind | split-window -h
      bind - split-window -v

      bind a new-window

      bind -n C-h select-pane -L
      bind -n C-j select-pane -D
      bind -n C-k select-pane -U
      bind -n C-l select-pane -R

      set -g status-right "";
      set -g status-interval 5
      set -g status-keys emacs

      set -g display-time 4000
    '';
  };
}
