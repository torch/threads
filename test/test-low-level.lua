local t = require 'threads'

local m = t.Mutex()
local c = t.Condition()
print(string.format('| main thread mutex: 0x%x', m:id()))
print(string.format('| main thread condition: 0x%x', c:id()))

local thread = t.Thread(string.format([[
  local t = require 'threads'
  local c = t.Condition(%d)
  print('|| hello from thread')
  print(string.format('|| thread condition: 0x%%x', c:id()))
  print('|| doing some stuff in thread...')
  local x = 0
  for i=1,10000 do
    for i=1,10000 do
      x = x + math.sin(i)
    end
    x = x / 10000
  end
  print(string.format('|| ...ok (x=%%f)', x))
  c:signal()
]], c:id()))

print('| waiting for thread...')
m:lock()
c:wait(m)
print('| thread finished!')

thread:free()
m:free()
c:free()

print('| done')
