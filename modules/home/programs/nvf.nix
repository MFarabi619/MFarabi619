{
  programs.nvf = {
    enable = false;
    settings = {
      vim = {
        keymaps = [
          {
            key = "jk";
            mode = [ "i" ];
            action = "<Esc>";
            silent = true;
          }
        ];

        binds = {
          cheatsheet.enable = true;
          whichKey = {
            enable = true;
          };
        };

        terminal = {
          toggleterm = {
            enable = true;
            lazygit = {
              enable = true;
              direction = "float";
            };
          };
        };

        filetree = {
          neo-tree = {
            enable = true;
            setupOpts = {
              enable_git_status = true;
              enable_opened_markers = true;
            };
          };
        };

        ui = {
          borders = {
            enable = true;
          };
        };

        treesitter = {
          enable = true;
          context = {
            enable = true;
          };
        };

        notes = {
          neorg = {
            enable = true;
          };
        };

        utility = {
          direnv = {
            enable = true;
          };

          yazi-nvim = {
            enable = true;
            mappings = {
              openYazi = "<leader>-e";
              openYaziDir = "<leader>-e";
            };
            setupOpts = {
              open_for_directories = true;
            };
          };
        };

        statusline = {
          lualine = {
            enable = true;
          };
        };

        telescope = {
          enable = true;
        };

        lsp = {
          formatOnSave = true;
          inlayHints.enable = true;
          lightbulb = {
            enable = true;
          };
        };

        dashboard = {
          dashboard-nvim = {
            enable = true;
            setupOpts = {
              config = {
                header = [
                  "\"Do not proceed with a mess; messes just grow with time.\” ― Bjarne Stroustrup"
                ];
              };
            };
          };
        };

        languages = {
          enableTreesitter = true;

          nix.enable = true;
          rust.enable = true;
          markdown = {
            enable = true;
          };
        };
      };
    };
  };
}
