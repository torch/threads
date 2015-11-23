local threads = require 'threads'

local t = threads.Threads(1)

-- PUC Lua 5.1 doesn't support coroutine.yield within pcall
if _VERSION == 'Lua 5.1' then
  print('Unsupported test for PUC Lua 5.1')
  return 0
end

local function loop()
  t:addjob(function() return 1 end, coroutine.yield)
  t:addjob(function() return 2 end, coroutine.yield)
  t:synchronize()
end

local function test1()
  local expected = 1
  for r in coroutine.wrap(loop) do
    assert(r == expected)
    expected = expected + 1
  end
  assert(expected == 3)
end

local function test2()
  for r in coroutine.wrap(loop) do
    if r == 2 then
      error('error at two')
    end
  end
end

test1()

local ok = pcall(test2)
assert(not ok)
t:synchronize()

print('Done')
