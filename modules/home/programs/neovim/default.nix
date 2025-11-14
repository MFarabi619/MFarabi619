# {
#   pkgs,
#   ...
# }:

{
  imports = [
    # ./nvf.nix
    ./lazyvim.nix
  ];

  # programs.neovim = {
  #   enable = false;
  #   viAlias = false;
  #   vimAlias = false;
  #   withRuby = true;
  #   withNodeJs = true;
  #   withPython3 = true;
  #   defaultEditor = true;

  #   plugins = with pkgs.vimPlugins; [
  #     LazyVim
  #     qmk-nvim
  #   ];
  # };

  # home.file = {
  #   ".config/nvim/init.lua" = {
  #     enable = false;
  #     text = ''
  #       -- bootstrap lazy.nvim, LazyVim and your plugins
  #       require("config.lazy")
  #     '';
  #   };

  #   ".config/nvim/lua/plugins" = {
  #     enable = false;
  #     source = ./plugins;
  #     recursive = true;
  #   };

  #   ".config/nvim/lua/config" = {
  #     enable = false;
  #     source = ./config;
  #     recursive = true;
  #   };

  #   ".config/nvim/lazyvim.json" = {
  #     enable = false;
  #     source = ./lazyvim.json;
  #   };

  #   ".config/nvim/.neoconf.json" = {
  #     enable = false;
  #     text = ''
  #       {
  #         "neodev": {
  #           "library": {
  #             "enabled": true,
  #             "plugins": true
  #           }
  #         },
  #         "neoconf": {
  #           "plugins": {
  #             "lua_ls": {
  #               "enabled": true
  #             }
  #           }
  #         }
  #       }
  #     '';
  #   };

  #   ".config/nvim/stylua.toml" = {
  #     enable = false;
  #     text = ''
  #       indent_width = 2
  #       column_width = 120
  #       indent_type = "Spaces"
  #     '';
  #   };
  # };
}
