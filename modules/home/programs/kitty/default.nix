{
  programs.kitty = {
    enable = true;
    enableGitIntegration = true;

    shellIntegration = {
      enableZshIntegration = true;
      enableBashIntegration = true;
    };

    # themeFile = "SpaceGray_Eighties";

    keybindings = {
      "ctrl+shift+v" = "paste_from_selection";
      "ctrl+c" = "copy_and_clear_or_interrupt";
    };

    environment = {
      LS_COLORS = "1";
    };

    settings = {
      # cursor_trail = 1;
      copy_on_select = "yes";
      tab_bar_margin_width = 0;
      window_padding_width = 0;

      tab_fade = 1;
      background_blur = 40;
      tab_bar_edge = "top";
      tab_bar_align = "left";
      tab_bar_style = "powerline";
      focus_follows_mouse = "yes";
      tab_powerline_style = "angled";
      active_tab_font_style = "bold";
      inactive_tab_font_style = "bold";
      dynamic_background_opacity = "yes";

      macos_option_as_alt = "yes";
      macos_colorspace = "default";
      hide_window_decorations = "titlebar-only";
      macos_quit_when_last_window_closed = "yes";
    };

    # extraConfig = ''
    # '';
  };

}
