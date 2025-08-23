return {
  {
    "Equilibris/nx.nvim",

    dependencies = {
      "nvim-telescope/telescope.nvim",
    },

    opts = {
      -- See below for config options
      nx_cmd_root = "pnpx nx",
    },

    -- Plugin will load when you use these keys
    keys = {
      { "<leader>nx", "<cmd>Telescope nx actions<CR>", desc = "nx actions" },
    },
  },
}
