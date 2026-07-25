local M = {}

function M.make_entry(entry)
  local display = require("gbrain-explorer.entry").text(entry)
  return {
    display = display,
    ordinal = display,
    value = entry,
  }
end

local function notify(message, level)
  vim.notify("gbrain-explorer: " .. message, level)
end

local function set_preview(bufnr, lines)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end
end

local function show_picker(client, view, entries)
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local conf = require("telescope.config").values
  local finders = require "telescope.finders"
  local pickers = require "telescope.pickers"
  local previewers = require "telescope.previewers"

  local preview_generation = 0
  local picker
  picker = pickers.new({}, {
    prompt_title = view.title,
    finder = finders.new_table {
      results = entries,
      entry_maker = M.make_entry,
    },
    sorter = conf.generic_sorter {},
    previewer = previewers.new_buffer_previewer {
      title = "GBrain Page",
      define_preview = function(self, entry)
        preview_generation = preview_generation + 1
        local generation = preview_generation
        set_preview(self.state.bufnr, { "Loading " .. entry.value.slug .. "..." })
        client:get_page(entry.value.slug, function(page, err)
          if generation ~= preview_generation or not vim.api.nvim_buf_is_valid(self.state.bufnr) then
            return
          end
          if err then
            set_preview(self.state.bufnr, { "Failed to load page:", err })
            return
          end
          local ok, content = pcall(require("gbrain-explorer.document").render, page)
          if not ok then
            set_preview(self.state.bufnr, { "Failed to render page:", content })
            return
          end
          set_preview(self.state.bufnr, vim.split(content:gsub("\n$", ""), "\n", { plain = true }))
          vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
        end)
      end,
    },
    attach_mappings = function(prompt_bufnr, map)
      local function selected()
        local selection = action_state.get_selected_entry()
        return selection and selection.value or nil
      end

      actions.select_default:replace(function()
        local entry = selected()
        if not entry then
          notify("no GBrain page selected", vim.log.levels.WARN)
          return
        end
        actions.close(prompt_bufnr)
        require("gbrain-explorer.buffer").open(client, entry.slug)
      end)

      local function reload()
        actions.close(prompt_bufnr)
        M.open(client, view)
      end

      local function create()
        actions.close(prompt_bufnr)
        vim.ui.input({ prompt = "GBrain page slug: " }, function(slug)
          if slug and not slug:match "^%s*$" then
            require("gbrain-explorer.buffer").create(client, vim.trim(slug))
          end
        end)
      end

      local function delete()
        local entry = selected()
        if not entry then
          notify("no GBrain page selected", vim.log.levels.WARN)
          return
        end
        local choice = vim.fn.confirm(
          string.format("Soft-delete GBrain page '%s'? Recoverable for 72 hours.", entry.slug),
          "&Yes\n&No",
          2
        )
        if choice ~= 1 then
          return
        end
        client:delete_page(entry.slug, function(_, err)
          if err then
            notify("failed to soft-delete " .. entry.slug .. ": " .. err, vim.log.levels.ERROR)
            return
          end
          notify("Soft-deleted " .. entry.slug .. "; recoverable for 72 hours", vim.log.levels.INFO)
          actions.close(prompt_bufnr)
          M.open(client, view)
        end)
      end

      for _, mode in ipairs { "i", "n" } do
        map(mode, "<C-d>", delete)
        map(mode, "<C-n>", create)
        map(mode, "<C-r>", reload)
      end
      return true
    end,
  })
  picker:find()
end

function M.open(client, view)
  vim.notify("gbrain-explorer: Loading GBrain pages...", vim.log.levels.INFO)
  view.load(function(entries, err)
    if err then
      notify(err, vim.log.levels.ERROR)
      return
    end
    show_picker(client, view, entries)
  end)
end

return M
