{
  programs.zed-editor = {
    enable = false;
    themes = {};
    userKeymaps = [];
    userTasks = [];
    installRemoteServer = true;

    userSettings = {
      vim_mode = true;
      "base_keymap" = "VSCode";

      features = {
        copilot = false;
      };

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
      "nix"
      "csv"
      "vue"
      "sql"
      "lua"
      "html"
      "toml"
      "ruby"
      "latex"
      "nginx"
      "unocss"
      "svelte"
      "basher"
      "stylint"
      "graphql"
      "solidity"
      "dockerfile"
      "git-firefly"
      "docker-compose"
    ];
  };
}
