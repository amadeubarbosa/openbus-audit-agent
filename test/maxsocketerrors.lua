local socket=require "cothread.socket"
local array={}
for i=1,2000 do
  local c, errmsg = socket.tcp()
  if not c then
    assert(errmsg ~= nil, "no error message was return from socket library")
    for k=1,#array do
      array[k]:close()
    end
    break
  end
  array[#array+1]=c
end
