if vim.g.loaded_gbrain_explorer == 1 then
  return
end
vim.g.loaded_gbrain_explorer = 1

vim.g.gbrain_explorer_version = "0.1.0"

vim.api.nvim_create_user_command("GBrainExplorer", function()
  require("gbrain-explorer").open()
end, { desc = "Browse recent GBrain pages" })

vim.api.nvim_create_user_command("GBrainSearch", function(command)
  require("gbrain-explorer").search(command.args)
end, { nargs = "*", desc = "Search GBrain pages" })

vim.api.nvim_create_user_command("GBrainCreate", function(command)
  require("gbrain-explorer").create(command.args)
end, { nargs = "?", desc = "Create a GBrain page" })
