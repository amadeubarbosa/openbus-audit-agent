local _G = require "_G"
local pairs = _G.pairs
local assert = _G.assert

local table = require "table"
local string = require "string"
local coroutine = require "coroutine"
local newthread = coroutine.create
local cothread = require "cothread"
local schedule = cothread.schedule
local unschedule = cothread.unschedule
cothread.plugin(require "cothread.plugin.socket")
local socket = require "cothread.socket"

local oil = require "oil"

local oo = require "openbus.util.oo"
local log = require "openbus.util.logger"
local setuplog = require("openbus.util.server").setuplog
local msg = require "openbus.core.messages"

-- lib extension
function string.split(str,ch)
  local pat = string.len(ch) == 1 and "[^"..ch.."]*" or ch
  local tbl={}
  str:gsub(pat,function(x) if x ~= "" then tbl[#tbl+1]=x end end)
  return tbl
end
function coroutine.id()
    return tostring(coroutine.running())
end

local http = require "socket.http"
local httpreq = http.request

local ltn12 = require "ltn12"
local strsrc = ltn12.source.string
local tabsnk = ltn12.sink.table

function httppost(param)
  local url, result, request = param.url, param.result, param.request
  local body = {}
  log:action(msg.HttpAgentSendingPost:tag{host=url, thread=coroutine.id()})
  local ok, code, headers, status = httpreq{
    url = url,
    create = newtcp,
    source = strsrc(request),
    sink = tabsnk(body),
    headers = {
      ["content-length"] = #request,
      ["content-type"] = "application/json;charset=utf-8",
      ["accept"] = "application/json",
    },
    method = "POST",
  }
  if not ok or tonumber(code) ~= 200 then
    error(msg.HttpPostFailed:tag{code = code, result = body})
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
    --print("waking up ", consumer._thread)
    consumer:reschedule()
  else
    --print("is not necessary wake up ", consumer._thread)
  end
end

-- consumer
local endpoint = "http://localhost:51400"

consumer._thread = newthread(function()
  while true do
    if fifo:empty() then -- wait
      print(string.format("[%s] waiting for data", oil.time()))
      consumer:wait()
    else -- pop
      local data = fifo:pop()
      local str = string.format("[%s] consuming data { count = %d }", oil.time(), data.count)
      print(str)
      local ok, result = pcall(httppost, {
        url = endpoint,
        request = '[{"body":"'..str..'"}]',
        result = {},
        })
      log:print(
        ok and msg.DataSentToAuditService:tag{result = result} 
           or  msg.FailedToSendToAuditService:tag{error=result}
      )
      consumer:reschedule()
    end
  end
end)

-- main
local orb = oil.init({port=2266})

orb:loadidl[[
interface Hello {
  void sayhello(in string msg);
};
]]

local count = 0
orb:newservant(
  {sayhello = function(self, msg)  
    count = count + 1
    fifo:push({count = count})
    --print("received ".. msg)
  end},
  "Hello",
  "IDL:Hello:1.0");

orb:run()