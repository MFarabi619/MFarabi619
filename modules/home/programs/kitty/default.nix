{
  programs.kitty = {
    enable = true;
    enableGitIntegration = true;

    shellIntegration = {
      enableZshIntegration = true;
      enableBashIntegration = true;
    };

    # themeFile = "SpaceGray_Eighties";

    # font = {
    #   size = 9;
    #   name = "JetBrainsMono Nerd Font";
    #   package = pkgs.nerd-fonts.jetbrains-mono;
    # };

    keybindings = {
     "ctrl+c" = "copy_or_interrupt";
     "ctrl+shift+v" = "paste_from_selection";
    };

    environment = {
      LS_COLORS = "1";
    };

    settings = {
      cursor_trail = 1;
      copy_on_select = "yes";
      tab_bar_margin_width = 0;
      window_padding_width = 2;

      tab_fade = 1;
      background_blur = 30;
      tab_bar_edge = "top";
      tab_bar_align = "left";
      tab_bar_style = "powerline";
      tab_powerline_style = "angled";
      active_tab_font_style = "bold";
      inactive_tab_font_style = "bold";
      dynamic_background_opacity = "yes";
    };

    # extraConfig = ''
    # '';
  };

}
