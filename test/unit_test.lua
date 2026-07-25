return function(t)
  local transport = require "gbrain-explorer.transport"
  local client = require "gbrain-explorer.client"
  local config_module = require "gbrain-explorer.config"
  local document = require "gbrain-explorer.document"
  local entry = require "gbrain-explorer.entry"
  local picker = require "gbrain-explorer.picker"

  local function response(body, status, content_type, session)
    return table.concat({
      body,
      "__NVIM_GBRAIN_HTTP__"
        .. (status or 200)
        .. "\t"
        .. (content_type or "application/json")
        .. "\t"
        .. (session or ""),
    }, "\n")
  end

  t.test("config requires an explicit endpoint", function()
    local ok, err = pcall(config_module.resolve)

    t.equal(false, ok)
    t.match("endpoint must be a non%-empty string", err)
    t.equal(
      "https://gbrain.example.com/mcp",
      config_module.resolve({
        endpoint = "https://gbrain.example.com/mcp",
      }).endpoint
    )
  end)

  t.test("entry text puts nonempty titles first", function()
    t.equal(
      "Useful title [concept] - pages/long-slug",
      entry.text {
        slug = "pages/long-slug",
        type = "concept",
        title = "Useful title",
      }
    )
    t.equal(
      "pages/no-title [concept]",
      entry.text {
        slug = "pages/no-title",
        type = "concept",
      }
    )
    t.equal(
      "pages/empty-title [concept]",
      entry.text {
        slug = "pages/empty-title",
        type = "concept",
        title = "",
      }
    )
    t.equal(
      "Useful title - pages/no-type",
      entry.text {
        slug = "pages/no-type",
        title = "Useful title",
      }
    )
  end)

  t.test("picker entries share display and fuzzy text", function()
    local value = {
      slug = "pages/example",
      type = "concept",
      title = "Example",
    }
    local result = picker.make_entry(value)

    t.equal("Example [concept] - pages/example", result.display)
    t.equal(result.display, result.ordinal)
    t.equal(value, result.value)
  end)

  t.test("transport decodes JSON and selects the matching response ID", function()
    local decoded, meta, err = transport.parse_response(
      response('{"jsonrpc":"2.0","id":7,"result":{"ok":true}}', 200, "application/json", "session-1"),
      7
    )

    t.equal(nil, err)
    t.equal("session-1", meta.session)
    t.equal(true, decoded.result.ok)
  end)

  t.test("transport decodes multiple SSE events", function()
    local body = table.concat({
      "event: message",
      'data: {"jsonrpc":"2.0","id":4,"result":{"wrong":true}}',
      "",
      "event: message",
      'data: {"jsonrpc":"2.0","id":5,"result":{"right":true}}',
      "",
    }, "\n")
    local decoded, _, err = transport.parse_response(response(body, 200, "text/event-stream"), 5)

    t.equal(nil, err)
    t.equal(true, decoded.result.right)
  end)

  t.test("transport reports malformed responses and server errors", function()
    local _, _, json_err = transport.parse_response(response("{", 200), 1)
    t.match("invalid JSON response", json_err)

    local _, _, sse_err = transport.parse_response(response("event: ping\n\n", 200, "text/event-stream"), 1)
    t.match("no data events", sse_err)

    local _, _, http_err =
      transport.parse_response(response('{"error":{"message":"denied"}}', 401, "application/json"), 9)
    t.equal("HTTP 401: denied", http_err)

    local _, _, mcp_err =
      transport.parse_response(response('{"jsonrpc":"2.0","id":3,"error":{"message":"broken"}}', 200), 3)
    t.equal("MCP error: broken", mcp_err)
  end)

  t.test("transport initializes once before draining queued calls", function()
    local requests = {}
    local config = {
      endpoint = "https://example.invalid/mcp",
      token_env = "GBRAIN_TEST_TOKEN",
      timeout_ms = 1000,
    }
    vim.env.GBRAIN_TEST_TOKEN = "secret"

    local runner = function(command, options, callback)
      local request = vim.json.decode(options.stdin)
      table.insert(requests, {
        command = command,
        request = request,
      })

      if request.method == "initialize" then
        callback {
          code = 0,
          stderr = "",
          stdout = response(
            'event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18"}}\n',
            200,
            "text/event-stream",
            "abc"
          ),
        }
      elseif request.method == "notifications/initialized" then
        callback { code = 0, stderr = "", stdout = response("", 202) }
      else
        callback {
          code = 0,
          stderr = "",
          stdout = response(
            vim.json.encode {
              jsonrpc = "2.0",
              id = request.id,
              result = { content = { { type = "text", text = "[]" } } },
            },
            200,
            "application/json"
          ),
        }
      end
    end

    local instance = transport.new(config, runner)
    local results = 0
    instance:call("list_pages", {}, function(result, err)
      t.equal(nil, err)
      t.equal("text", result.content[1].type)
      results = results + 1
    end)
    instance:call("search", { query = "gbrain" }, function(result, err)
      t.equal(nil, err)
      t.equal("text", result.content[1].type)
      results = results + 1
    end)

    t.equal(4, #requests)
    t.equal("initialize", requests[1].request.method)
    t.equal(false, vim.islist(requests[1].request.params.capabilities))
    t.equal("notifications/initialized", requests[2].request.method)
    t.equal("list_pages", requests[3].request.params.name)
    t.equal(false, vim.islist(requests[3].request.params.arguments))
    t.equal("search", requests[4].request.params.name)
    t.match("MCP%-Protocol%-Version: 2025%-06%-18", table.concat(requests[3].command, "\n"))
    t.match("Mcp%-Session%-Id:", table.concat(requests[3].command, "\n"))
    t.equal(nil, table.concat(requests[3].command, "\n"):find("secret", 1, true))
    t.equal(2, results)
    vim.env.GBRAIN_TEST_TOKEN = nil
  end)

  t.test("client builds each page operation", function()
    local calls = {}
    local fake_transport = {
      call = function(_, name, arguments, callback)
        table.insert(calls, { name = name, arguments = arguments })
        callback {
          content = {
            { type = "text", text = '{"ok":true}' },
          },
        }
      end,
    }
    local instance = client.new(fake_transport)

    instance:list_pages({ limit = 10 }, function() end)
    instance:search("term", { limit = 20 }, function() end)
    instance:get_page("pages/example", function() end)
    instance:put_page("pages/example", "body\n", function() end)
    instance:delete_page("pages/example", function() end)

    t.equal({
      { name = "list_pages", arguments = { limit = 10 } },
      { name = "search", arguments = { limit = 20, query = "term" } },
      { name = "get_page", arguments = { slug = "pages/example" } },
      { name = "put_page", arguments = { slug = "pages/example", content = "body\n" } },
      { name = "delete_page", arguments = { slug = "pages/example" } },
    }, calls)
  end)

  t.test("client reports tool errors", function()
    local value, err = client.decode_result {
      isError = true,
      content = {
        { type = "text", text = '{"error":"missing","suggestion":"check the slug"}' },
      },
    }

    t.equal(nil, value)
    t.equal("missing. check the slug", err)
  end)

  t.test("document renders deterministic frontmatter and timeline", function()
    local content = document.render {
      slug = "pages/example",
      type = "project",
      title = "Example",
      tags = { "one", "two" },
      frontmatter = {
        zeta = true,
        alpha = { nested = "value" },
        title = "ignored duplicate",
      },
      compiled_truth = "# Example\n\nBody",
      timeline = "## Update\n\nDone",
    }

    t.equal(
      table.concat({
        "---",
        'type: "project"',
        'title: "Example"',
        'tags: ["one","two"]',
        'alpha: {"nested":"value"}',
        "zeta: true",
        "---",
        "",
        "# Example",
        "",
        "Body",
        "",
        "<!-- timeline -->",
        "",
        "## Update",
        "",
        "Done",
        "",
      }, "\n"),
      content
    )
  end)

  t.test("document omits an empty timeline and creates a slug-derived template", function()
    local rendered = document.render {
      type = "project",
      title = "No Timeline",
      compiled_truth = "Body",
      timeline = "",
    }
    t.equal(nil, rendered:find("timeline", 1, true))
    t.equal(
      table.concat({
        "---",
        'title: "Example page"',
        "---",
        "",
        "# Example page",
        "",
      }, "\n"),
      document.new "pages/example-page"
    )
  end)
end
