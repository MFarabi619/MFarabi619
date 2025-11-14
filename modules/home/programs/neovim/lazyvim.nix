{
  pkgs,
  ...
}:
{
  programs.lazyvim = {
    enable = true;
    # pluginSource = "latest";
    # installCoreDependencies = false;
    ignoreBuildNotifications = false;

    config = {
      options = '''';

      keymaps = ''
        -- Keymaps are automatically loaded on the VeryLazy event
        -- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
        -- Add any additional keymaps here

        vim.keymap.set("i", "jk", "<Esc>", { noremap = true })
        vim.keymap.set("i", "<C-g>", "<Esc>", { noremap = true })
        vim.keymap.set("n", "<C-g>", "<Esc>", { noremap = true })
        -- vim.keymap.set("n", "<leader>fs", "<cmd>w<cr>", { desc = "Save" })
        vim.keymap.set("n", "<leader>e", "<cmd>Yazi<cr>", { noremap = true, desc = "Open yazi at the current file" })
      '';

      autocmds = ''
          vim.api.nvim_create_autocmd("FocusLost", {
          command = "silent! wa",
          desc = "Auto-save on focus loss",
        })
      '';
    };

    plugins = {
      colorscheme = ''
        return {
          { "ellisonleao/gruvbox.nvim" },
          -- {
          --   "catppuccin/nvim",
          --   lazy = true,
          --   name = "catppuccin",
          --   opts = {
          --     lsp_styles = {
          --       underlines = {
          --         errors = { "undercurl" },
          --         hints = { "undercurl" },
          --         warnings = { "undercurl" },
          --         information = { "undercurl" },
          --       },
          --     },
          --     integrations = {
          --       aerial = true,
          --       alpha = true,
          --       cmp = true,
          --       dashboard = true,
          --       flash = true,
          --       fzf = true,
          --       grug_far = true,
          --       gitsigns = true,
          --       headlines = true,
          --       illuminate = true,
          --       indent_blankline = { enabled = true },
          --       leap = true,
          --       lsp_trouble = true,
          --       mason = true,
          --       mini = true,
          --       navic = { enabled = true, custom_bg = "lualine" },
          --       neotest = true,
          --       neotree = true,
          --       noice = true,
          --       notify = true,
          --       snacks = true,
          --       telescope = true,
          --       treesitter_context = true,
          --       which_key = true,
          --     },
          --   },
          --   specs = {
          --     {
          --       "akinsho/bufferline.nvim",
          --       optional = true,
          --       opts = function(_, opts)
          --         if (vim.g.colors_name or ""):find("catppuccin") then
          --           opts.highlights = require("catppuccin.special.bufferline").get_theme()
          --         end
          --       end,
          --     },
          --   },
          -- },

          {
            "LazyVim/LazyVim",
            opts = {
              -- colorscheme = "catppuccin",
              colorscheme = "gruvbox",
            },
          },
        }
      '';

      dashboard-nvim = ''
        return {
          "nvimdev/dashboard-nvim",
          lazy = false, -- As https://github.com/nvimdev/dashboard-nvim/pull/450, dashboard-nvim shouldn't be lazy-loaded to properly handle stdin.
          opts = function()
            local logo = [[
                  (              )               (     *
           (      )\ )   (    ( /(                )\ ) (  `
           )\    (()/(   )\   )\())     (     (  (()/( )\))(
        ((((_)(   /(_))(((_) ((_)\      )\    )\  /(_))((_)()\
        )\ _ )\  (_))  )\___  _((_)    ((_)  ((_)(_))  (_()((_)
         █████╗ ██████╗  ██████╗██╗  ██╗██╗   ██╗██╗███╗   ███╗
        ██╔══██╗██╔══██╗██╔════╝██║  ██║██║   ██║██║████╗ ████║
        ███████║██████╔╝██║     ███████║██║   ██║██║██╔████╔██║
        ██╔══██║██╔══██╗██║     ██╔══██║╚██╗ ██╔╝██║██║╚██╔╝██║
        ██║  ██║██║  ██║╚██████╗██║  ██║ ╚████╔╝ ██║██║ ╚═╝ ██║
        ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝     ╚═╝

        "Do not proceed with a mess; messes just grow with time.” ― Bjarne Stroustrup
            ]]

            logo = string.rep("\n", 8) .. logo .. "\n\n"

            local opts = {
              theme = "doom",
              hide = {
                -- this is taken care of by lualine
                -- enabling this messes up the actual laststatus setting after loading a file
                statusline = false,
              },
              config = {
                header = vim.split(logo, "\n"),
                -- stylua: ignore
                center = {
                  { action = 'lua LazyVim.pick()()',                           desc = " Find File",       icon = " ", key = "f" },
                  { action = "ene | startinsert",                              desc = " New File",        icon = " ", key = "n" },
                  { action = 'lua LazyVim.pick("oldfiles")()',                 desc = " Recent Files",    icon = " ", key = "r" },
                  { action = 'lua LazyVim.pick("live_grep")()',                desc = " Find Text",       icon = " ", key = "g" },
                  { action = 'lua LazyVim.pick.config_files()()',              desc = " Config",          icon = " ", key = "c" },
                  { action = 'lua require("persistence").load()',              desc = " Restore Session", icon = " ", key = "s" },
                  { action = "LazyExtras",                                     desc = " Lazy Extras",     icon = " ", key = "x" },
                  { action = "Lazy",                                           desc = " Lazy",            icon = "󰒲 ", key = "l" },
                  { action = function() vim.api.nvim_input("<cmd>qa<cr>") end, desc = " Quit",            icon = " ", key = "q" },
                },
                footer = function()
                  local stats = require("lazy").stats()
                  local ms = (math.floor(stats.startuptime * 100 + 0.5) / 100)
                  return { "⚡ Neovim loaded " .. stats.loaded .. "/" .. stats.count .. " plugins in " .. ms .. "ms" }
                end,
              },
            }

            for _, button in ipairs(opts.config.center) do
              button.desc = button.desc .. string.rep(" ", 43 - #button.desc)
              button.key_format = "  %s"
            end

            -- open dashboard after closing lazy
            if vim.o.filetype == "lazy" then
              vim.api.nvim_create_autocmd("WinClosed", {
                pattern = tostring(vim.api.nvim_get_current_win()),
                once = true,
                callback = function()
                  vim.schedule(function()
                    vim.api.nvim_exec_autocmds("UIEnter", { group = "dashboard" })
                  end)
                end,
              })
            end

            return opts
          end,
        }
      '';

      nvim-orgmode = ''
        ---@type LazySpec
        return {
            "nvim-orgmode/orgmode",
            event = "VeryLazy",
            config = function()
              -- Setup orgmode
              require("orgmode").setup({
                org_agenda_files = "~/Documents/org/**/*",
                org_default_notes_file = "~/Documents/org/refile.org",
              })
            end,
          }
      '';

      yazi-nvim = ''
        ---@type LazySpec
        return {
          -- https://github.com/mikavilpas/yazi.nvim
          "mikavilpas/yazi.nvim",
          version = "*", -- use the latest stable version
          event = "VeryLazy",
          dependencies = {
            { "nvim-lua/plenary.nvim", lazy = true },
          },
          keys = {
            {
              "<leader>cw",
              "<cmd>Yazi cwd<cr>",
              desc = "Open the file manager in nvim's working directory",
            },
            {
              "<c-up>",
              "<cmd>Yazi toggle<cr>",
              desc = "Resume the last yazi session",
            },
          },
          ---@type YaziConfig | {}
          opts = {
            -- if you want to open yazi instead of netrw, see below for more info
            open_for_directories = true,
            keymaps = {
              show_help = "<f1>",
            },
          },
          -- 👇 if you use `open_for_directories=true`, this is recommended
          init = function()
            -- mark netrw as loaded so it's not loaded at all.
            --
            -- More details: https://github.com/mikavilpas/yazi.nvim/issues/802
            vim.g.loaded_netrwPlugin = 1
          end,
        }
      '';

      lsp-config = ''
        return {
          "neovim/nvim-lspconfig",
          opts = function(_, opts)
            opts.servers = opts.servers or {}

            opts.servers.likec4 = {
              cmd = {"pnpx", "@likec4/language-server", "--stdio" },
            }

            return opts
          end,
        }
      '';
    };

    extras = {
      ai = {
        copilot_chat.enable = true;
      };

      dap = {
        core.enable = true;
        # nlua.enable = true;
      };

      test = {
        core.enable = true;
      };

      ui = {
        edgy.enable = true;
        # treesitter_context = true; # FIXME: supposed to be submodules?
        mini_animate.enable = true;
        dashboard_nvim.enable = true;
        mini_indentscope.enable = true;
      };

      editor = {
        aerial.enable = true;
        # neo_tree.enable = true;
        overseer.enable = true;
        telescope.enable = true;
        refactoring.enable = true;
      };

      coding = {
        # luasnip.enable =true;
        # mini_comment = true;
        yanky.enable = true;
        mini_surround.enable = true;
      };

      lang = {
        # go.enable  =true;
        # git.enable = true;
        # ruby.enable = true;
        # docker.enable = true;
        # svelte.enbale = true;
        # tailwind.enable = true;

        nix.enable = true;

        json.enable = true;
        toml.enable = true;
        yaml.enable = true;
        tex.enable = true;
        markdown.enable = true;

        # sql.enable = true; # FIXME: results in fixed output derivation error resulting from dadbod
        rust.enable = true;

        clang.enable = true;
        cmake.enable = true;
        python.enable = true;
        typescript.enable = true;
      };

      util = {
        # dot.enable = true;
        gh.enable = true;
        octo.enable = true;
        rest.enable = true;
        project.enable = true;
        startuptime.enable = true;
        mini_hipatterns.enable = true;
      };
    };

    # treesitterParsers = with pkgs.tree-sitter-grammars; [
    #   tree-sitter-nix
    #   tree-sitter-python
    # ];

    # extraPackages = with pkgs; [
    #   nixd
    #   alejandra

    #   black
    #   pyright
    # ];
  };
}
