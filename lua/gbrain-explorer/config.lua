local M = {}

M.defaults = {
  token_env = "GBRAIN_REMOTE_TOKEN",
  ui_mode = "auto",
  timeout_ms = 10000,
  page_limit = 100,
  search_limit = 50,
}

local valid_ui_modes = {
  auto = true,
  buffer = true,
  telescope = true,
}

local function positive_integer(value, name)
  if type(value) ~= "number" or value <= 0 or value % 1 ~= 0 then
    error("gbrain-explorer: " .. name .. " must be a positive integer")
  end
end

function M.resolve(opts)
  if opts ~= nil and type(opts) ~= "table" then
    error "gbrain-explorer: configuration must be a table"
  end

  local config = vim.tbl_deep_extend("force", M.defaults, opts or {})

  if type(config.endpoint) ~= "string" or config.endpoint:match "^%s*$" then
    error "gbrain-explorer: endpoint must be a non-empty string"
  end
  if type(config.token_env) ~= "string" or not config.token_env:match "^[A-Za-z_][A-Za-z0-9_]*$" then
    error "gbrain-explorer: token_env must be an environment variable name"
  end
  if not valid_ui_modes[config.ui_mode] then
    error "gbrain-explorer: ui_mode must be auto, telescope, or buffer"
  end

  positive_integer(config.timeout_ms, "timeout_ms")
  positive_integer(config.page_limit, "page_limit")
  positive_integer(config.search_limit, "search_limit")

  if config.page_limit > 100 then
    error "gbrain-explorer: page_limit cannot exceed GBrain's limit of 100"
  end
  if config.search_limit > 100 then
    error "gbrain-explorer: search_limit cannot exceed GBrain's limit of 100"
  end

  return config
end

function M.ui_mode(config)
  local telescope_available = pcall(require, "telescope")

  if config.ui_mode == "auto" then
    return telescope_available and "telescope" or "buffer"
  end
  if config.ui_mode == "telescope" and not telescope_available then
    vim.notify("gbrain-explorer: Telescope unavailable; using buffer UI", vim.log.levels.WARN)
    return "buffer"
  end
  return config.ui_mode
end

return M
