local document = require "gbrain-explorer.document"

local M = {}

local buffers_by_slug = {}
local clients_by_buffer = {}

local function notify(message, level)
  vim.notify("gbrain-explorer: " .. message, level)
end

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function content_lines(content)
  if content:sub(-1) == "\n" then
    content = content:sub(1, -2)
  end
  return vim.split(content, "\n", { plain = true })
end

local function set_content(bufnr, content, modified)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content_lines(content))
  vim.api.nvim_set_option_value("modified", modified, { buf = bufnr })
end

local function save(bufnr)
  if not valid_buffer(bufnr) then
    return
  end
  if vim.b[bufnr].gbrain_saving then
    notify("a save is already in progress", vim.log.levels.WARN)
    return
  end

  local slug = vim.b[bufnr].gbrain_slug
  local client = clients_by_buffer[bufnr]
  if not slug or not client then
    notify("buffer has no GBrain page metadata", vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  if vim.api.nvim_get_option_value("endofline", { buf = bufnr }) then
    content = content .. "\n"
  end

  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  vim.b[bufnr].gbrain_saving = true
  client:put_page(slug, content, function(_, err)
    if not valid_buffer(bufnr) then
      return
    end

    vim.b[bufnr].gbrain_saving = false
    if err then
      notify("failed to save " .. slug .. ": " .. err, vim.log.levels.ERROR)
      return
    end

    local current_tick = vim.api.nvim_buf_get_changedtick(bufnr)
    local line_count = #lines
    local line_word = line_count == 1 and "line" or "lines"
    if current_tick == changedtick then
      vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
      vim.notify(string.format('"%s" %d %s written', vim.api.nvim_buf_get_name(bufnr), line_count, line_word))
    else
      notify(string.format("%s saved; newer local edits remain", slug), vim.log.levels.WARN)
    end
  end)
end

local function create_buffer(client, slug, content, modified)
  local existing = buffers_by_slug[slug]
  if valid_buffer(existing) then
    vim.api.nvim_set_current_buf(existing)
    return existing
  end

  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, "gbrain://" .. slug)
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_set_option_value("endofline", true, { buf = bufnr })

  vim.b[bufnr].gbrain_slug = slug
  vim.b[bufnr].gbrain_saving = false
  buffers_by_slug[slug] = bufnr
  clients_by_buffer[bufnr] = client
  set_content(bufnr, content, modified)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      save(bufnr)
    end,
    desc = "Save GBrain page",
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      if buffers_by_slug[slug] == bufnr then
        buffers_by_slug[slug] = nil
      end
      clients_by_buffer[bufnr] = nil
    end,
    desc = "Forget GBrain page buffer",
  })

  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

local function open_page(client, page)
  local ok, content = pcall(document.render, page)
  if not ok then
    notify("failed to render " .. tostring(page.slug) .. ": " .. content, vim.log.levels.ERROR)
    return
  end
  return create_buffer(client, page.slug, content, false)
end

function M.open(client, slug)
  local existing = buffers_by_slug[slug]
  if valid_buffer(existing) then
    vim.api.nvim_set_current_buf(existing)
    return existing
  end

  client:get_page(slug, function(page, err)
    if err then
      notify("failed to load " .. slug .. ": " .. err, vim.log.levels.ERROR)
      return
    end
    open_page(client, page)
  end)
end

local function page_missing(err)
  return type(err) == "string" and err:lower():find("page not found", 1, true) ~= nil
end

function M.create(client, slug)
  local existing = buffers_by_slug[slug]
  if valid_buffer(existing) then
    vim.api.nvim_set_current_buf(existing)
    return existing
  end

  client:get_page(slug, function(page, err)
    if page then
      notify(slug .. " already exists; opened existing page", vim.log.levels.INFO)
      open_page(client, page)
      return
    end
    if not page_missing(err) then
      notify("could not check " .. slug .. ": " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    create_buffer(client, slug, document.new(slug), true)
  end)
end

M.create_buffer = create_buffer
M.save = save

return M
