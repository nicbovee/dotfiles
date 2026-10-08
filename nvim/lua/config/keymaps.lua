-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Toggle comment with Cmd+/ (GUI nvim) and Ctrl+/ (terminal).
-- iTerm2 sends 0x1f for Cmd+/ via a key binding, which arrives here as <C-_>.
local toggle_comment = { remap = true, desc = "Toggle comment" }
for _, lhs in ipairs({ "<D-/>", "<C-_>", "<C-/>" }) do
  vim.keymap.set("n", lhs, "gcc", toggle_comment)
  vim.keymap.set("x", lhs, "gc", toggle_comment)
  vim.keymap.set("i", lhs, "<Esc>gcca", toggle_comment)
end
