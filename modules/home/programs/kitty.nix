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
      tab_fade = 1;
      cursor_trail = 1;
      tab_bar_edge = "top";
      copy_on_select = "yes";
      tab_bar_margin_width = 0;
      window_padding_width = 10;
      tab_bar_style = "powerline";
      active_tab_font_style = "bold";
      inactive_tab_font_style = "bold";
    };
    extraConfig = ''
      # Clipboard
      map ctrl+shift+v paste_from_selection
    '';
  };

}
