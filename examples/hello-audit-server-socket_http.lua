local _G = require "_G"
local pairs = _G.pairs
local assert = _G.assert

local table = require "table"
local string = require "string"
local coroutine = require "coroutine"
local running = coroutine.running
local newthread = coroutine.create
local cothread = require "cothread"
local schedule = cothread.schedule
local unschedule = cothread.unschedule
cothread.plugin(require "cothread.plugin.socket")
local socket = require "cothread.socket"
local newtcp = socket.tcp

local oil = require "oil"

local oo = require "openbus.util.oo"
local log = require "openbus.util.logger"
local setuplog = require("openbus.util.server").setuplog
local msg = require "openbus.core.messages"

-- lib extension
function threadid()
    return tostring(running())
end

local http = require "socket.http"
local httpreq = http.request

local ltn12 = require "ltn12"
local strsrc = ltn12.source.string
local tabsnk = ltn12.sink.table

function httppost(url, request, sock)
  local body = {}
  log:action(msg.HttpAgentSendingPost:tag{url=url, connection = tostring(sock.__object), request=request, thread=threadid()})
  local ok, code, headers, status = httpreq{
    url = url,
    connection = sock,
    create = newtcp,
    source = strsrc(request),
    sink = tabsnk(body),
    headers = {
      ["content-length"] = #request,
      ["content-type"] = "application/json;charset=utf-8",
      ["accept"] = "application/json",
      ["connection"] = "keep-alive",
    },
    method = "POST",
  }
  if not ok or tonumber(code) ~= 200 then
    error(msg.HttpPostFailed:tag{code = code, status = status, request = request, result = body})
  else
    return body
  end
end

--[[
  http.PROXY = http://localhost:3128
]]

setuplog(log, 5)

local consumer = { -- forward declaration
  _running = false, -- critical region
  _thread = false, -- cothread
}

function consumer:wait()
  self._running = false
  cothread.suspend()
  self._running = true
end

function consumer:suspended()
  return self._running == false
end

function consumer:reschedule()
  self._running = true
  cothread.schedule(self._thread, "last") -- wake up
end

local fifo = {
  _first = 1,
  _last = 1,
}

function fifo:empty()
  return self[self._last] == nil
end

function fifo:pop()
  local data = self[self._last]
  self[self._last] = nil
  self._last = self._last + 1
  return data
end

function fifo:push(event)
  self[self._first] = event
  self._first = self._first + 1
  if consumer:suspended() then
    -- print("waking up ", consumer._thread)
    consumer:reschedule()
  else
    -- print("is not necessary wake up ", consumer._thread)
  end
end

-- consumer
local endpoint = "http://localhost:51400"

consumer._thread = newthread(function()
  local sock = socket.tcp()
  sock:connect("localhost", 51400)
  while true do
    if fifo:empty() then -- wait
      log:action(msg.AuditAgentIsWaitingForData)
      consumer:wait()
    else -- pop
      local data = fifo:pop()
      local str = string.format("audit data { count = %d }", data.count)
      local ok, result = pcall(httppost, endpoint, '[{"body":"'..str..'"}]', sock)
      if not ok then
        log:exception(msg.AuditAgentFailure:tag{error=result})
      end
    end
    -- print("memory in use:", collectgarbage("count"))
  end
end)

-- main
local orb = oil.init({port=2266, flavor="cooperative;corba.intercepted"})

orb:loadidl[[
interface Hello {
  void sayhello(in string msg);
};
]]

local count = 0

local interceptor = {hold={}}
function interceptor:receiverequest(request)
  count = count + 1
  self.hold[running()] = count
end

function interceptor:sendreply(request)
  fifo:push{ count = self.hold[running()] }
  self.hold[running()] = nil
end

orb:setinterceptor(interceptor, "corba.server")

orb:newservant(
  {sayhello = function(self, msg)
    print("server receive a message:",msg)
  end},
  "Hello",
  "IDL:Hello:1.0");

orb:run()