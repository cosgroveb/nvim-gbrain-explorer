local M = {}

local Client = {}
Client.__index = Client

local function error_message(value, fallback)
  if type(value) ~= "table" then
    return fallback
  end

  local message = value.message or value.error or fallback
  if value.suggestion then
    message = message .. ". " .. value.suggestion
  end
  return message
end

local function decode_result(result)
  if type(result) ~= "table" or type(result.content) ~= "table" then
    return nil, "GBrain returned an invalid tool result"
  end

  local text
  for _, block in ipairs(result.content) do
    if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
      text = block.text
      break
    end
  end
  if not text then
    return nil, "GBrain returned no text result"
  end

  local ok, value = pcall(vim.json.decode, text)
  if not ok then
    if result.isError then
      return nil, text
    end
    return nil, "GBrain returned invalid JSON: " .. tostring(value)
  end

  if result.isError or (type(value) == "table" and value.error) then
    return nil, error_message(value, text)
  end
  return value, nil
end

local function validate_nonempty(value, name)
  if type(value) ~= "string" or value:match "^%s*$" then
    return nil, name .. " must be a non-empty string"
  end
  return value
end

function Client:_call(name, arguments, callback)
  self.transport:call(name, arguments, function(result, transport_error)
    if transport_error then
      callback(nil, transport_error)
      return
    end
    callback(decode_result(result))
  end)
end

function Client:list_pages(options, callback)
  self:_call("list_pages", options or {}, callback)
end

function Client:search(query, options, callback)
  local valid_query, err = validate_nonempty(query, "query")
  if not valid_query then
    callback(nil, err)
    return
  end

  local arguments = vim.tbl_extend("force", options or {}, { query = valid_query })
  self:_call("search", arguments, callback)
end

function Client:get_page(slug, callback)
  local valid_slug, err = validate_nonempty(slug, "slug")
  if not valid_slug then
    callback(nil, err)
    return
  end
  self:_call("get_page", { slug = valid_slug }, callback)
end

function Client:put_page(slug, content, callback)
  local valid_slug, err = validate_nonempty(slug, "slug")
  if not valid_slug then
    callback(nil, err)
    return
  end
  if type(content) ~= "string" then
    callback(nil, "content must be a string")
    return
  end
  self:_call("put_page", { slug = valid_slug, content = content }, callback)
end

function Client:delete_page(slug, callback)
  local valid_slug, err = validate_nonempty(slug, "slug")
  if not valid_slug then
    callback(nil, err)
    return
  end
  self:_call("delete_page", { slug = valid_slug }, callback)
end

function M.new(transport)
  if type(transport) ~= "table" or type(transport.call) ~= "function" then
    error "gbrain-explorer: client requires a transport"
  end
  return setmetatable({ transport = transport }, Client)
end

M.decode_result = decode_result

return M
