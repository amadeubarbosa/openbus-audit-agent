-- load namespace
local socket = require "socket"
local cothread = require "cothread"
local date = require "os".date

local function is_empty(line)
  return line == "\r\n" or line == "\n"
end
local function dateformat(timestamp)
  local mili = string.format("%.3f", timestamp):match("%.(%d%d%d)")
  return date("%Y-%m-%d %H:%M:%S.", math.modf(timestamp))..mili
end

-- create a TCP socket and bind it to the local host, at any port
local server = assert(socket.bind("*", 51399))
-- find out which port the OS chose for us
local ip, port = server:getsockname()
-- print a message informing what's up
print("HTTP server started ".. dateformat(cothread.now()) .. " localhost:" .. port)
print("After connecting, timeout is configured to 10s")
-- loop forever waiting for clients
while 1 do
  print("Waiting a new client..")
  -- wait for a connection from any client
  local client = server:accept()
  local thread = coroutine.create(function()
    local host, port = client:getpeername()
    local threadid = tostring(coroutine.running())
    print(string.format("[%s] [%s:%d] connection created", threadid, host, port))
    -- make sure we don't block waiting for this client's line
    client:settimeout(10)
    -- receive the line
    local line, err
    repeat
      line, err = client:receive("*l")
      if line and (#line <= 2) then
        print("-------> emtpy line received, receiving body now:")
        print(line,err, string.byte(line, 1, #line))
        line, err = client:receive("*l")
      end
      print(string.format("[%s] [%s:%d] message received %s (error=%s)", 
        threadid, host, port, line, err))
    until (line == nil or is_empty(line))
    local response = "HTTP/1.1 200 OK\r\n"
    response = response .. "Date: "..dateformat(cothread.now()).."\r\n"
    response = response .. "Server: Dummy\r\n"
    response = response .. "Content-Length: 0\r\n"
    response = response .. "Keep-Alive: timeout=15, max=100\r\n"
    response = response .. "Connection: Keep-Alive\r\n"
    response = response .. "Content-Type: text/plain\r\n\r\n"
    -- if there was no error, send it back to the client
    if not err then client:send(response) end
    -- done with client, close the object
    client:close()
  end)
  cothread.schedule(thread)
  cothread.last()
end

