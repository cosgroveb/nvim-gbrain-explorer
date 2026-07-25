local M = {}

function M.text(entry)
  local kind = entry.type and (" [" .. entry.type .. "]") or ""
  if entry.title and entry.title ~= "" then
    return entry.title .. kind .. " - " .. entry.slug
  end
  return entry.slug .. kind
end

return M
