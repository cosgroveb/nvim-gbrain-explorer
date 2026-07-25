local buffer = require "gbrain-explorer.buffer"
local entry_format = require "gbrain-explorer.entry"

local M = {}

local fallback_states = {}

local function notify(message, level)
  vim.notify("gbrain-explorer: " .. message, level)
end

local function entry_line(entry)
  return entry_format.text(entry)
end

local function current_entry(bufnr)
  local state = fallback_states[bufnr]
  if not state then
    return
  end
  return state.entries[vim.api.nvim_win_get_cursor(0)[1]]
end

local function display(bufnr, lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
end

local function refresh_fallback(bufnr)
  local state = fallback_states[bufnr]
  if not state then
    return
  end

  display(bufnr, { "Loading GBrain pages..." })
  state.view.load(function(entries, err)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if err then
      notify(err, vim.log.levels.ERROR)
      if #state.entries > 0 then
        local old_lines = {}
        for _, entry in ipairs(state.entries) do
          table.insert(old_lines, entry_line(entry))
        end
        display(bufnr, old_lines)
      else
        display(bufnr, { "Failed to load GBrain pages: " .. err })
      end
      return
    end

    state.entries = entries
    if #entries == 0 then
      display(bufnr, { "No GBrain pages found" })
      return
    end
    local lines = {}
    for _, entry in ipairs(entries) do
      table.insert(lines, entry_line(entry))
    end
    display(bufnr, lines)
  end)
end

local function delete_selected(bufnr)
  local state = fallback_states[bufnr]
  local entry = current_entry(bufnr)
  if not state or not entry then
    notify("no GBrain page selected", vim.log.levels.WARN)
    return
  end

  local choice =
    vim.fn.confirm(string.format("Soft-delete GBrain page '%s'? Recoverable for 72 hours.", entry.slug), "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end

  state.client:delete_page(entry.slug, function(_, err)
    if err then
      notify("failed to soft-delete " .. entry.slug .. ": " .. err, vim.log.levels.ERROR)
      return
    end
    notify("Soft-deleted " .. entry.slug .. "; recoverable for 72 hours", vim.log.levels.INFO)
    refresh_fallback(bufnr)
  end)
end

local function create_page(state)
  vim.ui.input({ prompt = "GBrain page slug: " }, function(slug)
    if slug and not slug:match "^%s*$" then
      buffer.create(state.client, vim.trim(slug))
    end
  end)
end

local function open_fallback(client, view)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "GBrain Explorer " .. bufnr)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "gbrain-explorer", { buf = bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

  fallback_states[bufnr] = {
    client = client,
    entries = {},
    view = view,
  }

  local keymap = { buffer = bufnr, silent = true, noremap = true }
  vim.keymap.set("n", "<CR>", function()
    local entry = current_entry(bufnr)
    if entry then
      buffer.open(client, entry.slug)
    end
  end, keymap)
  vim.keymap.set("n", "d", function()
    delete_selected(bufnr)
  end, keymap)
  vim.keymap.set("n", "r", function()
    refresh_fallback(bufnr)
  end, keymap)
  vim.keymap.set("n", "c", function()
    create_page(fallback_states[bufnr])
  end, keymap)
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end, keymap)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      fallback_states[bufnr] = nil
    end,
    desc = "Forget GBrain explorer buffer",
  })

  vim.api.nvim_set_current_buf(bufnr)
  refresh_fallback(bufnr)
  return bufnr
end

local function pages_view(client, config)
  return {
    title = "Recent GBrain Pages",
    load = function(callback)
      client:list_pages({
        limit = config.page_limit,
        sort = "updated_desc",
      }, callback)
    end,
  }
end

local function search_view(client, config, query)
  return {
    title = "GBrain Search: " .. query,
    load = function(callback)
      client:search(query, { limit = config.search_limit }, function(results, err)
        if err then
          callback(nil, err)
          return
        end

        local entries = {}
        local seen = {}
        for _, result in ipairs(results) do
          if result.slug and not seen[result.slug] then
            seen[result.slug] = true
            table.insert(entries, result)
          end
        end
        callback(entries, nil)
      end)
    end,
  }
end

local function open_view(client, config, view)
  if require("gbrain-explorer.config").ui_mode(config) == "telescope" then
    return require("gbrain-explorer.picker").open(client, view)
  end
  return open_fallback(client, view)
end

function M.open(client, config)
  return open_view(client, config, pages_view(client, config))
end

function M.search(client, config, query)
  return open_view(client, config, search_view(client, config, query))
end

function M.create(client, slug)
  return buffer.create(client, slug)
end

M.entry_line = entry_line
M.open_fallback = open_fallback
M.refresh_fallback = refresh_fallback

return M
