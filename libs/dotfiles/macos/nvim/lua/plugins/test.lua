return {
  { "nvim-neotest/neotest-plenary" },
  { "haydenmeade/neotest-jest" },
  { "marilari88/neotest-vitest" },
  {
    "thenbe/neotest-playwright",
    -- opts = {
    --   keys = {
    --     {
    --       "<leader>ta",
    --       function()
    --         require("neotest-playwright").attachment()
    --       end,
    --       desc = "Launch test attachment",
    --     },
    --   },
    -- },
  },
  {
    "nvim-neotest/neotest",
    setup = {},
    -- consumers = {
    --   -- add to your list of consumers
    --   playwright = require("neotest-playwright.consumers").consumers,
    -- },
    opts = {
      adapters = {
        "neotest-plenary",
        "neotest-jest",
        "neotest-vitest",
        ["neotest-playwright"] = {
          dependencies = "nvim-telescope/telescope.nvim",
          -- Add more Playwright configurations here
          persist_project_selection = true,
          enable_dynamic_test_discovery = true,

          get_project_root = function()
            return vim.fs.root(0, "package.json")
          end,

          get_playwright_config = function()
            local playwright_config_path = get_project_root() .. "/playwright.config.ts"
            return playwright_config_path
          end,

          get_playwright_binary = function()
            local playwright_binary_path = get_project_root() .. "/node_modules/.bin/playwright"
            return playwright_binary_path
          end,

          experimental = {
            telescope = {
              -- If true, a telescope picker will be used for `:NeotestPlaywrightProject`.
              -- Otherwise, `vim.ui.select` is used.
              -- In normal mode, `<Tab>` toggles the project under the cursor.
              -- `<CR>` (enter key) applies the selection.
              enabled = true,
              opts = {},
            },
          },
        },
      },
      keys = {
        -- { "<leader>ta", "<cmd>NeotestAdapterName<CR>", desc = "View Adapter" },
        -- { "<leader>tc", "<cmd>NeotestConfigModule<CR>", desc = "View Configuration" },
        -- { "<leader>tp", "<cmd>NeotestPlaywrightPreset<CR>", desc = "Set Playwright Preset" },
        -- { "<leader>tr", "<cmd>NeotestPlaywrightProject<CR>", desc = "Set Playwright Browsers" },
        -- { "<leader>tR", "<cmd>NeotestPlaywrightRefresh<CR>", desc = "Refresh Playwright Configuration" },
      },
    },
  },
}
