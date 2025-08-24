{
  programs.television = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      tick_rate = 50;
      ui = {
        use_nerd_font_icons = true;
        # ui_scale = 120;
      };
      # keybindings = {
      #  quit = [
      #    "esc"
      #    "ctrl-c"
      #    "ctrl-g"
      #  ];
      # };
    };
    # channels = { };
  };
}
