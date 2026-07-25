local M = {}

local reserved_keys = {
  tags = true,
  title = true,
  type = true,
}

local function yaml_line(key, value)
  local rendered_key = key:match "^[%a_][%w_-]*$" and key or vim.json.encode(key)
  return rendered_key .. ": " .. vim.json.encode(value)
end

local function append_text(lines, text)
  vim.list_extend(lines, vim.split(text, "\n", { plain = true }))
end

function M.render(page)
  if type(page) ~= "table" then
    error "gbrain-explorer: page must be a table"
  end
  if type(page.type) ~= "string" or type(page.title) ~= "string" then
    error "gbrain-explorer: page type and title must be strings"
  end

  local lines = {
    "---",
    yaml_line("type", page.type),
    yaml_line("title", page.title),
  }

  if type(page.tags) == "table" and #page.tags > 0 then
    table.insert(lines, yaml_line("tags", page.tags))
  end

  local frontmatter = page.frontmatter or {}
  local keys = vim.tbl_keys(frontmatter)
  table.sort(keys)
  for _, key in ipairs(keys) do
    if not reserved_keys[key] then
      table.insert(lines, yaml_line(key, frontmatter[key]))
    end
  end

  table.insert(lines, "---")
  table.insert(lines, "")
  append_text(lines, page.compiled_truth or "")

  if page.timeline and page.timeline ~= "" then
    vim.list_extend(lines, { "", "<!-- timeline -->", "" })
    append_text(lines, page.timeline)
  end

  return table.concat(lines, "\n") .. "\n"
end

local function title_from_slug(slug)
  local segment = slug:match "([^/]+)$" or slug
  local title = segment:gsub("[-_]+", " ")
  return title:sub(1, 1):upper() .. title:sub(2)
end

function M.new(slug)
  if type(slug) ~= "string" or slug:match "^%s*$" then
    error "gbrain-explorer: slug must be a non-empty string"
  end

  local title = title_from_slug(slug)
  return table.concat({
    "---",
    yaml_line("title", title),
    "---",
    "",
    "# " .. title,
    "",
  }, "\n")
end

return M
