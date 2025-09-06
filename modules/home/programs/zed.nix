{
  programs.zed-editor = {
    enable = true;
    themes = {};
    userKeymaps = [];
    userTasks = [];
    installRemoteServer = true;
    userSettings = {
      vim_mode = true;
      features = {
        copilot = false;
      };
      "base_keymap" = "VSCode";
      telemetry = {
        metrics = false;
        diagnostics = false;
      };
      # "ui_font_size" = 16;
      # "buffer_font_size" = 16;
      # theme = {
      #   mode = "system";
      #   light = "One Light";
      #   dark = "Gruvbox Dark Hard";
      # };
      "pane_split_direction_vertical" = "left";
      "project_panel" = {
        dock = "right";
      };
      "outline_panel" = {
        dock = "right";
      };
      "git_panel" = {
        dock = "right";
      };
    };

    extensions = [
      "html"
      "toml"
      "dockerfile"
      "git-firefly"
      "nix"
      "vue"
      "sql"
      "ruby"
      "latex"
      "svelte"
      "lua"
      "docker-compose"
      "graphql"
      "csv"
      "basher"
      "nginx"
      "solidity"
      "unocss"
      "stylint"
    ];
  };
}
