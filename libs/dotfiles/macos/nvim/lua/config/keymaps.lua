-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Use the Lua API to set key mappings
vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = true, silent = true })
