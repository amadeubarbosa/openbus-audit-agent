local _G = require "_G"
local pairs = _G.pairs
local assert = _G.assert

local table = require "table"
local string = require "string"
local coroutine = require "coroutine"
local running = coroutine.running
local status = coroutine.status
local newthread = coroutine.create
local cothread = require "cothread"
local schedule = cothread.schedule
local unschedule = cothread.unschedule
cothread.plugin(require "cothread.plugin.socket")
local socket = require "cothread.socket"
local newtcp = socket.tcp

local http = require "socket.http"
local httpreq = http.request
http.TIMEOUT = 15

local ltn12 = require "ltn12"
local strsrc = ltn12.source.string
local tabsnk = ltn12.sink.table

local url = require "socket.url"

local oil = require "oil"

local oo = require "openbus.util.oo"
local log = require "openbus.util.logger"
local setuplog = require("openbus.util.server").setuplog
local msg = require "openbus.core.messages"

function httpconnection(endpoint, location)
  local parsed = url.parse(endpoint)
  local sock = newtcp()
  sock:connect(parsed.host, parsed.port)
  local url = endpoint..( location or "" )
  
  return 
  function(request)
    local thread = tostring(running())
    local body = {}
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
      error(msg.HttpPostFailed:tag{code = code, status = status, request = request, agent=thread, result = body})
    else
      log:action(msg.HttpPostSuccessfullySent:tag{url=url, request=request, agent=thread})
      return body
    end
  end
end

--[[
  http.PROXY = http://localhost:3128
]]

setuplog(log, 5)

local consumer = { -- forward declaration
  _running = false, -- critical region
  _thread = {}, -- cothreads
  _sleep = {},
}

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
  consumer:reschedule()
end

-- consumer
local httpfactory = function() return httpconnection("http://localhost:51400", "/") end
local httppost = httpfactory()
local httpmaxclients = 5

function consumer:reschedule()
  for i=1, httpmaxclients do
    if (self._sleep[i] == true) then
      self._sleep[i] = false
      cothread.schedule(self._thread[i], "last") -- wake up
    end
  end
end

for i=1, httpmaxclients do
  consumer._sleep[i] = false
  consumer._thread[i] = newthread(function()
    local threadid = tostring(running())
    while true do
      if fifo:empty() then -- wait
        log:action(msg.AuditAgentIsWaitingForData:tag{agent=threadid})
        consumer._sleep[i] = true
        cothread.suspend()
        consumer._sleep[i] = false
      else -- pop
        local data = fifo:pop()
        local str = string.format("audit data { count = %d }", data.count)
        local ok, result = pcall(httppost, '[{"body":"'..str..'"}]')
        if not ok then
          local exception = result[1]
          if exception == "timeout" or exception == "closed" then -- reconnect
            httppost = httpfactory()
            fifo:push(data)
            log:action(msg.AuditAgentReconnecting:tag{cause=exception, agent=threadid, request=str})
          else
            log:exception(msg.AuditAgentFailure:tag{error=result, agent=threadid})
          end
        end
        cothread.last()
      end
      -- print("memory in use:", collectgarbage("count"))
    end
  end)
  cothread.schedule(consumer._thread[i], "last")
end

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