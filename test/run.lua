local tests = {}

local function fail(message)
  error(message, 2)
end

local harness = {}

function harness.test(name, callback)
  table.insert(tests, { name = name, callback = callback })
end

function harness.equal(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    fail(
      string.format(
        "%s\nexpected: %s\nactual:   %s",
        message or "values differ",
        vim.inspect(expected),
        vim.inspect(actual)
      )
    )
  end
end

function harness.match(pattern, actual, message)
  if type(actual) ~= "string" or not actual:match(pattern) then
    fail(
      string.format("%s\npattern: %s\nactual:  %s", message or "pattern did not match", pattern, vim.inspect(actual))
    )
  end
end

dofile "test/unit_test.lua"(harness)
dofile "test/integration_test.lua"(harness)

local failures = {}
for _, case in ipairs(tests) do
  local ok, err = xpcall(case.callback, debug.traceback)
  if ok then
    print("ok - " .. case.name)
  else
    print("not ok - " .. case.name)
    table.insert(failures, case.name .. "\n" .. err)
  end
end

print(string.format("%d tests, %d failures", #tests, #failures))
if #failures > 0 then
  print(table.concat(failures, "\n\n"))
  vim.cmd "cquit 1"
else
  vim.cmd "quit"
end
