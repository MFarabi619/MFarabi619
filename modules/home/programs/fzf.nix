{
  # Type `<ctrl> + r` to fuzzy search your shell history
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    # defaultCommand = "";
    # defaultOptions = [ "" ];
    # changeDirWidgetCommand = "";
    # changeDirWidgetOptions = [ "" ];
    # historyWidgetOptions = [ "" ];
    # fileWidgetCommand = "";
    # fileWidgetOptions = [ "" ];
    tmux = {
      enableShellIntegration = false;
      shellIntegrationOptions = [ ];
    };
  };
}
