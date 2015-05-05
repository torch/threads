local threads = require 'threads'

for i=1,1000 do
   io.write(string.format('%04d.', tonumber(i)))
   io.flush()
   local pool =
      threads.Threads(
         4,
         function(threadid)
            require 'torch'
         end
      )
end
print()
print('PASSED')
