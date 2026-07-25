local M = {}

local Transport = {}
Transport.__index = Transport

local META_MARKER = "__NVIM_GBRAIN_HTTP__"
local SESSION_ENV = "NVIM_GBRAIN_MCP_SESSION_ID"
local supported_protocols = {
  ["2025-03-26"] = true,
  ["2025-06-18"] = true,
}

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function value_message(value)
  if type(value) ~= "table" then
    return tostring(value)
  end
  local message = value.message or value.error or "unknown error"
  if value.suggestion then
    message = message .. ". " .. value.suggestion
  end
  return message
end

local function decode_json(value)
  local ok, decoded = pcall(vim.json.decode, value)
  if not ok then
    return nil, tostring(decoded)
  end
  return decoded
end

local function decode_sse(body)
  local messages = {}
  body = body:gsub("\r\n", "\n") .. "\n\n"

  for event in body:gmatch "(.-)\n\n" do
    local data = {}
    for line in (event .. "\n"):gmatch "(.-)\n" do
      if line:sub(1, 5) == "data:" then
        table.insert(data, (line:sub(6):gsub("^ ", "")))
      end
    end
    if #data > 0 then
      local decoded, err = decode_json(table.concat(data, "\n"))
      if not decoded then
        return nil, "invalid SSE JSON: " .. err
      end
      table.insert(messages, decoded)
    end
  end

  if #messages == 0 then
    return nil, "SSE response contained no data events"
  end
  return messages
end

local function split_http_output(output)
  local pattern = "^(.*)\n" .. META_MARKER .. "(%d+)\t([^\t]*)\t([^\n]*)\n?$"
  local body, status, content_type, session = (output or ""):match(pattern)
  if not body then
    return nil, "curl response did not include HTTP metadata"
  end

  return {
    body = body,
    status = tonumber(status),
    content_type = content_type,
    session = trim(session) ~= "" and trim(session) or nil,
  }
end

local function find_response(messages, expected_id)
  if expected_id == nil then
    return messages[1]
  end
  for _, message in ipairs(messages) do
    if message.id == expected_id then
      return message
    end
  end
  return nil
end

function M.parse_response(output, expected_id)
  local meta, meta_error = split_http_output(output)
  if not meta then
    return nil, nil, meta_error
  end

  local body = trim(meta.body)
  if meta.status == 202 or meta.status == 204 then
    if body == "" then
      return nil, meta, nil
    end
  end

  local messages
  if body ~= "" then
    if meta.content_type:find("text/event-stream", 1, true) or body:match "^event:" or body:match "^data:" then
      local err
      messages, err = decode_sse(meta.body)
      if not messages then
        return nil, meta, err
      end
    else
      local decoded, err = decode_json(body)
      if not decoded then
        return nil, meta, "invalid JSON response: " .. err
      end
      messages = { decoded }
    end
  else
    messages = {}
  end

  local response = find_response(messages, expected_id)
  if meta.status < 200 or meta.status >= 300 then
    local error_response = response or messages[1]
    local message = error_response and value_message(error_response.error or error_response) or body
    return nil, meta, string.format("HTTP %d: %s", meta.status, trim(message))
  end
  if expected_id ~= nil and not response then
    return nil, meta, "MCP response did not contain request id " .. expected_id
  end
  if response and response.error then
    return nil, meta, "MCP error: " .. value_message(response.error)
  end

  return response, meta, nil
end

local function default_runner(command, options, callback)
  local ok, err = pcall(function()
    vim.system(
      command,
      options,
      vim.schedule_wrap(function(completed)
        callback(completed, nil)
      end)
    )
  end)
  if not ok then
    vim.schedule(function()
      callback(nil, "failed to start curl: " .. tostring(err))
    end)
  end
end

local function insert_before_url(command, ...)
  local values = { ... }
  local url = table.remove(command)
  vim.list_extend(command, values)
  table.insert(command, url)
end

function Transport:_command()
  local command = {
    "curl",
    "--silent",
    "--show-error",
    "--variable",
    "%" .. self.config.token_env,
    "--expand-header",
    "Authorization: Bearer {{" .. self.config.token_env .. "}}",
    "--header",
    "Content-Type: application/json",
    "--header",
    "Accept: application/json, text/event-stream",
    "--data-binary",
    "@-",
    "--write-out",
    "\n" .. META_MARKER .. "%{http_code}\t%{content_type}\t%header{mcp-session-id}",
    self.config.endpoint,
  }

  if self.protocol then
    insert_before_url(command, "--header", "MCP-Protocol-Version: " .. self.protocol)
  end
  if self.session then
    insert_before_url(
      command,
      "--variable",
      "%" .. SESSION_ENV,
      "--expand-header",
      "Mcp-Session-Id: {{" .. SESSION_ENV .. "}}"
    )
  end
  return command
end

function Transport:_next_id()
  self.request_id = self.request_id + 1
  return self.request_id
end

function Transport:_post(method, params, id, callback)
  local token = vim.env[self.config.token_env]
  if not token or token == "" then
    callback(nil, nil, self.config.token_env .. " is absent from Neovim's environment")
    return
  end

  local message = {
    jsonrpc = "2.0",
    method = method,
  }
  if params ~= nil then
    message.params = params
  end
  if id ~= nil then
    message.id = id
  end

  local child_env = {
    [self.config.token_env] = token,
  }
  if self.session then
    child_env[SESSION_ENV] = self.session
  end

  self.runner(self:_command(), {
    env = child_env,
    stdin = vim.json.encode(message),
    text = true,
    timeout = self.config.timeout_ms,
  }, function(completed, runner_error)
    if runner_error then
      callback(nil, nil, runner_error)
      return
    end
    if not completed then
      callback(nil, nil, "curl did not return a result")
      return
    end
    if completed.code == 124 then
      callback(nil, nil, "GBrain request timed out after " .. self.config.timeout_ms .. "ms")
      return
    end

    local response, meta, parse_error = M.parse_response(completed.stdout or "", id)
    if completed.code ~= 0 and (not meta or meta.status == 0) then
      local stderr = trim(completed.stderr)
      if stderr:find("variable", 1, true) or stderr:find("expand-header", 1, true) then
        stderr = "curl 8.3 or newer is required: " .. stderr
      end
      callback(nil, meta, string.format("curl failed with exit code %d: %s", completed.code, stderr))
      return
    end
    if parse_error then
      if meta and meta.status == 404 and self.session then
        self.ready = false
        self.protocol = nil
        self.session = nil
      end
      callback(nil, meta, parse_error)
      return
    end
    if completed.code ~= 0 then
      local stderr = trim(completed.stderr)
      if stderr:find("variable", 1, true) or stderr:find("expand-header", 1, true) then
        stderr = "curl 8.3 or newer is required: " .. stderr
      end
      callback(nil, meta, string.format("curl failed with exit code %d: %s", completed.code, stderr))
      return
    end
    callback(response, meta, nil)
  end)
end

function Transport:_fail_pending(err)
  self.initializing = false
  self.ready = false
  self.protocol = nil
  self.session = nil

  local pending = self.pending
  self.pending = {}
  for _, call in ipairs(pending) do
    call.callback(nil, err)
  end
end

function Transport:_send_tool(call)
  local id = self:_next_id()
  self:_post(
    "tools/call",
    {
      name = call.name,
      arguments = vim.tbl_isempty(call.arguments) and vim.empty_dict() or call.arguments,
    },
    id,
    function(response, _, err)
      if err then
        call.callback(nil, err)
        return
      end
      if type(response) ~= "table" or response.result == nil then
        call.callback(nil, "GBrain returned an invalid MCP tool response")
        return
      end
      call.callback(response.result, nil)
    end
  )
end

function Transport:_drain()
  local pending = self.pending
  self.pending = {}
  for _, call in ipairs(pending) do
    self:_send_tool(call)
  end
end

function Transport:_initialize()
  if self.initializing or self.ready then
    return
  end
  self.initializing = true

  local id = self:_next_id()
  self:_post(
    "initialize",
    {
      protocolVersion = "2025-06-18",
      capabilities = vim.empty_dict(),
      clientInfo = {
        name = "nvim-gbrain-explorer",
        version = "0.1.0",
      },
    },
    id,
    function(response, meta, err)
      if err then
        self:_fail_pending(err)
        return
      end

      local result = response and response.result
      local protocol = result and result.protocolVersion
      if not supported_protocols[protocol] then
        self:_fail_pending("GBrain returned unsupported MCP protocol " .. tostring(protocol))
        return
      end

      self.protocol = protocol
      self.session = meta and meta.session or nil
      self:_post("notifications/initialized", nil, nil, function(_, _, notification_error)
        if notification_error then
          self:_fail_pending(notification_error)
          return
        end
        self.initializing = false
        self.ready = true
        self:_drain()
      end)
    end
  )
end

function Transport:call(name, arguments, callback)
  if type(name) ~= "string" or name == "" then
    callback(nil, "MCP tool name must be a non-empty string")
    return
  end
  if type(arguments) ~= "table" then
    callback(nil, "MCP tool arguments must be a table")
    return
  end

  local call = {
    name = name,
    arguments = arguments,
    callback = callback,
  }
  if self.ready then
    self:_send_tool(call)
    return
  end

  table.insert(self.pending, call)
  self:_initialize()
end

function M.new(config, runner)
  return setmetatable({
    config = config,
    initializing = false,
    pending = {},
    protocol = nil,
    ready = false,
    request_id = 0,
    runner = runner or default_runner,
    session = nil,
  }, Transport)
end

return M
