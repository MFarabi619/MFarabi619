{
  lib,
  config,
  ...
}:
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
      # "ctrl+shift+v" = "paste_from_selection";
      "ctrl+c" = "copy_and_clear_or_interrupt";
    };

    environment = {
      LS_COLORS = "1";
    };

    settings = {
      # cursor_trail = 1;
      copy_on_select = "yes";
      window_padding_width = 5;
      enable_audio_bell = "yes";
      focus_follows_mouse = "yes";

      background_blur = 40;
      # background_opacity = 0.60;
      dynamic_background_opacity = "yes";

      tab_fade = 1;
      tab_bar_edge = "top";
      tab_bar_align = "left";
      tab_bar_margin_width = 0;
      tab_bar_style = "powerline";
      tab_powerline_style = "angled";
      active_tab_font_style = "bold";
      inactive_tab_font_style = "bold";

      macos_option_as_alt = "yes";
      macos_colorspace = "default";
      hide_window_decorations = "titlebar-only";
      macos_quit_when_last_window_closed = "yes";

      # confirm_os_window_close = 0;
    };

    extraConfig = lib.mkIf config.targets.genericLinux.enable ''
      include theme.conf
      include $HOME/MFarabi619/modules/home/programs/kitty/userprefs.conf
    '';
  };
}
