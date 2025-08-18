{ pkgs, ... }:
{
  programs.kitty = {
    enable = true;
    #    font = {
    #  name = "JetBrainsMono Nerd Font";
    #  package = pkgs.nerd-fonts.jetbrains-mono;
    #  size = 9;
    # };
    enableGitIntegration = true;
    shellIntegration = {
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
    settings = {
      window_padding_width = 10;
      tab_bar_edge = "top";
      cursor_trail = 1;
      tab_fade = 1;
      active_tab_font_style = "bold";
      inactive_tab_font_style = "bold";
      tab_bar_margin_width = 0;
      tab_bar_style = "powerline";
    };
    extraConfig = ''
      # Clipboard
      map ctrl+shift+v paste_from_selection
    '';
  };

}
