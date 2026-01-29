{
  programs.lazyvim.config = {
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
}
