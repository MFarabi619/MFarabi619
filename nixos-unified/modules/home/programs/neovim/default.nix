{
  pkgs,
  ...
}:

{
  programs = {
    neovim = {
      enable = true;
      defaultEditor = true;
      # vimAlias = true;
      withNodeJs = true;
      withPython3 = true;
      withRuby = true;
      plugins = with pkgs.vimPlugins; [
        LazyVim
      ];
    };
  };

  home = {
    file = {
      ".config/nvim/init.lua" = {
        enable = true;
        text = ''
          -- bootstrap lazy.nvim, LazyVim and your plugins
          require("config.lazy")
        '';
      };
      ".config/nvim/lua/plugins" = {
        enable = true;
        source = ./plugins;
        recursive = true;
      };
      ".config/nvim/lua/config" = {
        enable = true;
        source = ./config;
        recursive = true;
      };
      ".config/nvim/lazyvim.json" = {
        enable = true;
        source = ./lazyvim.json;
      };
      ".config/nvim/.neoconf.json" = {
        enable = true;
        text = ''
          {
            "neodev": {
              "library": {
                "enabled": true,
                "plugins": true
              }
            },
            "neoconf": {
              "plugins": {
                "lua_ls": {
                  "enabled": true
                }
              }
            }
          }
        '';
      };
      ".config/nvim/stylua.toml" = {
        enable = true;
        text = ''
          indent_type = "Spaces"
          indent_width = 2
          column_width = 120
        '';
      };
    };
  };
}
