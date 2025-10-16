{
  programs.television = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    settings = {
      tick_rate = 50;
      default_channel = "nix-search-tv";
      ui = {
        ui_scale = 120;
        scrollbar = true;
        theme = "gruvbox dark";
        orientation = "landscape";
        use_nerd_font_icons = true;
      };
      # actions = {
      #   edit = {
      #     mode = "fork";
      #     command = "nvim {}";
      #     description = "Open selected file in editor";
      #   };
      # };
      keybindings = {
        ctrl-g = "quit";
        alt-x = "toggle_help";
        # enter = "actions:edit";
      };
    };
    # channels = { };
  };
}
