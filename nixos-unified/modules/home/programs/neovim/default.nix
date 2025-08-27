{
  pkgs,
  ...
}:

{
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
    # lazyvim = {
    #   enable = true;
    #   plugins = with pkgs.vimPlugins; [
    #     base16-nvim
    #     undotree
    #     dashboard-nvim
    #     yazi-nvim
    #   ];
    #   pluginsFile = {
    #     "yazi-nvim.lua".source = ./plugins/yazi-nvim.lua;
    #     "dashboard.lua".source = ./plugins/dashboard.lua;
    #   };
    #   pluginsSpecs = {
    #     "undotree.lua" = [
    #       {
    #         ref = "mbbill/undotree";
    #         keys = [
    #           [
    #             "<leader>uu"
    #             "<cmd>UndotreeToggle<cr>"
    #           ]
    #         ];
    #       }
    #     ];
    #     "yazi.lua" = [
    #       {
    #         ref = "mikavilpas/yazi.nvim";
    #         version = "*";
    #         event = "VeryLazy";
    #         dependencies = [
    #           [
    #             "niv-lua/plenary.nvim"
    #             "lazy = true"
    #           ]
    #         ];
    #         keys = [
    #           [
    #             "<leader>uu"
    #             "<cmd>UndotreeToggle<cr>"
    #           ]
    #         ];
    #       }
    #     ];
    #   };
    #   extras = {
    #     # test.core.enable = true;
    #     dap.core.enable = true;
    #     linting.eslint.enable = true;
    #     ui.mini-animate.enable = true;
    #     ai = {
    #       copilot-chat.enable = false;
    #       copilot.enable = false;
    #     };
    #     util = {
    #       dot.enable = true;
    #       mini-hipatterns.enable = true;
    #     };
    #     editor = {
    #       fzf.enable = true;
    #       # snacks_explorer.enable = true;
    #       # snacks_picker.enable = true;
    #       # inc-rename.enable = true;
    #     };
    #     lang = {
    #       # astro.enable = true;
    #       nix.enable = true;
    #       json.enable = true;
    #       # markdown.enable = true;
    #       tailwind.enable = true;
    #       typescript.enable = true;
    #       python.enable = true;
    #       go.enable = true;
    #     };
    #   };
    # };
    # nixvim.enable = true;
  };
  imports = [
    # ./nixvim.nix
  ];
}
