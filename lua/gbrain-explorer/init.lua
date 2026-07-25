local M = {}

local state

local function configured()
  if state then
    return state
  end

  M.setup()
  return state
end

function M.setup(opts)
  local config = require("gbrain-explorer.config").resolve(opts)
  local transport = require("gbrain-explorer.transport").new(config)
  local client = require("gbrain-explorer.client").new(transport)
  state = {
    client = client,
    config = config,
  }
  return config
end

function M.open()
  local current = configured()
  return require("gbrain-explorer.explorer").open(current.client, current.config)
end

local function with_input(value, prompt, callback)
  value = vim.trim(value or "")
  if value ~= "" then
    callback(value)
    return
  end
  vim.ui.input({ prompt = prompt }, function(input)
    input = input and vim.trim(input) or ""
    if input ~= "" then
      callback(input)
    end
  end)
end

function M.search(query)
  local current = configured()
  with_input(query, "Search GBrain: ", function(value)
    require("gbrain-explorer.explorer").search(current.client, current.config, value)
  end)
end

function M.create(slug)
  local current = configured()
  with_input(slug, "GBrain page slug: ", function(value)
    require("gbrain-explorer.explorer").create(current.client, value)
  end)
end

function M.get_config()
  return configured().config
end

function M._set_state_for_test(client, config)
  state = {
    client = client,
    config = config,
  }
end

return M
