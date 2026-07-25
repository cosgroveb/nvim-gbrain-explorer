return function(t)
  local buffer = require "gbrain-explorer.buffer"
  local explorer = require "gbrain-explorer.explorer"

  local function fake_client(overrides)
    return setmetatable(overrides or {}, {
      __index = {
        get_page = function(_, slug, callback)
          callback {
            slug = slug,
            type = "project",
            title = "Loaded page",
            compiled_truth = "# Loaded page",
          }
        end,
        put_page = function(_, _, _, callback)
          callback({ ok = true }, nil)
        end,
        delete_page = function(_, _, callback)
          callback({ ok = true }, nil)
        end,
      },
    })
  end

  local function wipe(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  local function mapping(bufnr, lhs)
    for _, value in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if value.lhs == lhs then
        return value.callback
      end
    end
    error("missing mapping " .. lhs)
  end

  local function with_override(target, key, value, callback)
    local old = target[key]
    target[key] = value
    local ok, err = pcall(callback)
    target[key] = old
    if not ok then
      error(err, 0)
    end
  end

  t.test("page buffer is editable and reused by slug", function()
    local instance = fake_client()
    local bufnr = buffer.create_buffer(instance, "test/page-buffer", "first\nsecond\n", false)

    t.equal("gbrain://test/page-buffer", vim.api.nvim_buf_get_name(bufnr))
    t.equal("acwrite", vim.api.nvim_get_option_value("buftype", { buf = bufnr }))
    t.equal("markdown", vim.api.nvim_get_option_value("filetype", { buf = bufnr }))
    t.equal(true, vim.api.nvim_get_option_value("modifiable", { buf = bufnr }))
    t.equal(bufnr, buffer.create_buffer(instance, "test/page-buffer", "replacement\n", false))
    t.equal({ "first", "second" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    wipe(bufnr)
  end)

  t.test("write sends exact Markdown and clears modified after success", function()
    local saved
    local instance = fake_client {
      put_page = function(_, slug, content, callback)
        saved = { slug = slug, content = content }
        callback({ ok = true }, nil)
      end,
    }
    local bufnr = buffer.create_buffer(instance, "test/save-success", "old\n", false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "new", "content" })

    vim.api.nvim_exec_autocmds("BufWriteCmd", { buffer = bufnr })

    t.equal({ slug = "test/save-success", content = "new\ncontent\n" }, saved)
    t.equal(false, vim.api.nvim_get_option_value("modified", { buf = bufnr }))
    wipe(bufnr)
  end)

  t.test("failed write preserves modified", function()
    local instance = fake_client {
      put_page = function(_, _, _, callback)
        callback(nil, "server unavailable")
      end,
    }
    local bufnr = buffer.create_buffer(instance, "test/save-failure", "old\n", false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "changed" })

    vim.api.nvim_exec_autocmds("BufWriteCmd", { buffer = bufnr })

    t.equal(true, vim.api.nvim_get_option_value("modified", { buf = bufnr }))
    wipe(bufnr)
  end)

  t.test("newer edits remain modified after an in-flight save", function()
    local finish
    local instance = fake_client {
      put_page = function(_, _, _, callback)
        finish = callback
      end,
    }
    local bufnr = buffer.create_buffer(instance, "test/save-race", "old\n", false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "sent" })
    vim.api.nvim_exec_autocmds("BufWriteCmd", { buffer = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "newer" })
    finish({ ok = true }, nil)

    t.equal(true, vim.api.nvim_get_option_value("modified", { buf = bufnr }))
    wipe(bufnr)
  end)

  t.test("second write is rejected while a save is in flight", function()
    local calls = 0
    local finish
    local instance = fake_client {
      put_page = function(_, _, _, callback)
        calls = calls + 1
        finish = callback
      end,
    }
    local bufnr = buffer.create_buffer(instance, "test/save-in-flight", "old\n", false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "sent" })
    vim.api.nvim_exec_autocmds("BufWriteCmd", { buffer = bufnr })
    vim.api.nvim_exec_autocmds("BufWriteCmd", { buffer = bufnr })

    t.equal(1, calls)
    finish({ ok = true }, nil)
    wipe(bufnr)
  end)

  t.test("fallback explorer loads entries and refreshes", function()
    local loads = 0
    local view = {
      load = function(callback)
        loads = loads + 1
        callback {
          { slug = "pages/one", type = "project", title = "One" },
          { slug = "references/two", type = "reference", title = "Two" },
        }
      end,
    }
    local bufnr = explorer.open_fallback(fake_client(), view)

    t.equal({
      "One [project] - pages/one",
      "Two [reference] - references/two",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    explorer.refresh_fallback(bufnr)
    t.equal(2, loads)

    local first_name = vim.api.nvim_buf_get_name(bufnr)
    local other_bufnr = explorer.open_fallback(fake_client(), view)
    t.equal(false, first_name == vim.api.nvim_buf_get_name(other_bufnr))
    wipe(other_bufnr)
    wipe(bufnr)
  end)

  t.test("fallback explorer opens the selected page", function()
    local loaded_slug
    local instance = fake_client {
      get_page = function(_, slug, callback)
        loaded_slug = slug
        callback {
          slug = slug,
          type = "project",
          title = "Selected",
          compiled_truth = "# Selected",
        }
      end,
    }
    local bufnr = explorer.open_fallback(instance, {
      load = function(callback)
        callback { { slug = "pages/selected", title = "Selected" } }
      end,
    })

    mapping(bufnr, "<CR>")()

    t.equal("pages/selected", loaded_slug)
    local page_bufnr = vim.api.nvim_get_current_buf()
    t.equal("gbrain://pages/selected", vim.api.nvim_buf_get_name(page_bufnr))
    wipe(page_bufnr)
  end)

  t.test("fallback explorer creates a page from a prompted slug", function()
    local instance = fake_client {
      get_page = function(_, _, callback)
        callback(nil, "Page not found")
      end,
    }
    local bufnr = explorer.open_fallback(instance, {
      load = function(callback)
        callback {}
      end,
    })

    with_override(vim.ui, "input", function(_, callback)
      callback "pages/new-page"
    end, function()
      mapping(bufnr, "c")()
    end)

    local page_bufnr = vim.api.nvim_get_current_buf()
    t.equal("gbrain://pages/new-page", vim.api.nvim_buf_get_name(page_bufnr))
    t.equal(true, vim.api.nvim_get_option_value("modified", { buf = page_bufnr }))
    wipe(page_bufnr)
  end)

  t.test("fallback explorer confirms deletion and refreshes after success", function()
    local deleted_slug
    local instance = fake_client {
      delete_page = function(_, slug, callback)
        deleted_slug = slug
        callback({ ok = true }, nil)
      end,
    }
    local loads = 0
    local bufnr = explorer.open_fallback(instance, {
      load = function(callback)
        loads = loads + 1
        if deleted_slug then
          callback {}
        else
          callback { { slug = "pages/delete-me", title = "Delete me" } }
        end
      end,
    })

    with_override(vim.fn, "confirm", function()
      return 1
    end, function()
      mapping(bufnr, "d")()
    end)

    t.equal("pages/delete-me", deleted_slug)
    t.equal(2, loads)
    t.equal({ "No GBrain pages found" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    wipe(bufnr)
  end)

  t.test("commands register and use configured state", function()
    dofile "plugin/gbrain-explorer.lua"
    t.equal(2, vim.fn.exists ":GBrainExplorer")
    t.equal(2, vim.fn.exists ":GBrainSearch")
    t.equal(2, vim.fn.exists ":GBrainCreate")

    local searches = {}
    local instance = fake_client {
      list_pages = function(_, _, callback)
        callback {}
      end,
      search = function(_, query, options, callback)
        table.insert(searches, { query = query, limit = options.limit })
        callback {}
      end,
    }
    require("gbrain-explorer")._set_state_for_test(instance, {
      ui_mode = "buffer",
      page_limit = 100,
      search_limit = 7,
    })

    vim.cmd "GBrainSearch exact phrase"
    t.equal({ { query = "exact phrase", limit = 7 } }, searches)
    wipe(vim.api.nvim_get_current_buf())
  end)

  t.test("argument-free search prompts and submits the query", function()
    local prompted
    local searches = {}
    local instance = fake_client {
      search = function(_, query, options, callback)
        table.insert(searches, { query = query, limit = options.limit })
        callback {}
      end,
    }
    require("gbrain-explorer")._set_state_for_test(instance, {
      ui_mode = "buffer",
      search_limit = 7,
    })

    with_override(vim.ui, "input", function(options, callback)
      prompted = options.prompt
      callback "  project metadata  "
    end, function()
      vim.cmd "GBrainSearch"
    end)

    t.equal("Search GBrain: ", prompted)
    t.equal({ { query = "project metadata", limit = 7 } }, searches)
    wipe(vim.api.nvim_get_current_buf())
  end)

  t.test("cancelled and blank prompted searches do nothing", function()
    local searches = {}
    local instance = fake_client {
      search = function(_, query, options, callback)
        table.insert(searches, { query = query, limit = options.limit })
        callback {}
      end,
    }
    require("gbrain-explorer")._set_state_for_test(instance, {
      ui_mode = "buffer",
      search_limit = 7,
    })

    with_override(vim.ui, "input", function(_, callback)
      callback(nil)
    end, function()
      vim.cmd "GBrainSearch"
    end)
    with_override(vim.ui, "input", function(_, callback)
      callback "   "
    end, function()
      vim.cmd "GBrainSearch"
    end)

    t.equal({}, searches)
  end)
end
