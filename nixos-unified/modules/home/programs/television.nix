{
  programs.television = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      tick_rate = 50;
      default_channel = "files";
      ui = {
        ui_scale = 120;
        scrollbar = true;
        theme = "gruvbox dark";
        orientation = "landscape";
        use_nerd_font_icons = true;
      };
      actions = {
        edit = {
          mode = "fork";
          command = "nvim {}";
          description = "Open selected file in editor";
        };
      };
      keybindings = {
       ctrl-g = "quit";
       ctrl-e = "actions:edit";
       alt-x ="toggle_help";
      };
    };
    # channels = { };
  };
}
