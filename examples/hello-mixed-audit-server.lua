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

-- a minimalist lib for http posting
local http = {
    connect = function(self, config)
        local function urlencode(tbl, resource)
          local server, port, url
          if tbl.proxy ~= nil then
            server = tbl.proxy:split(":")[1]
            port = tonumber(tbl.proxy:split(":")[2])
            url = "http://" .. tbl.host .. (resource or "/")
          else
            server = tbl.host:split(":")[1]
            port = tonumber(tbl.host:split(":")[2]) or 80
            url = resource or "/"
          end
          return url, server, port
        end

        local obj = oo.class({}, self)
        obj.closed = true
        obj.config = assert(config, "missing server configuration")
        obj.tcp = socket.tcp()
        local url, server, port = urlencode(config)
        assert(obj.tcp:connect(server, port))
        obj.server = server
        obj.port = port
        obj.url = url
        obj.closed = false
        return obj
    end,
    close = function(self)
        self.closed = true
        self.tcp:close()
    end,
    send = function(self, ...)
        if self.closed then
          self.tcp = socket.tcp()
          self.tcp:connect(self.server, self.port)
          self.closed = false
        end
        return self.tcp:send(...)
    end,
    receive = function(self, ...)
        local response = ""
        while true do
            self.tcp:settimeout(1) -- avoid busy wait
            local data, status = self.tcp:receive(...)
            response = response .. (data or "")
            if status == "closed" then break end
            coroutine.yield("delay", .1)
        end
        local _, _, version, code = string.find(response, "(HTTP/%d*%.%d*) (%d%d%d)")
        return tonumber(code), response, version
    end,
    post = function(self, resource, jsonstr)
      local function table2headers(tbl)
        local headers = ""
        for name, value in pairs(tbl) do
          headers = headers..name..": "..value.."\r\n"
        end
        return headers
      end

      --schedule(newthread(function ()
        local headers do
          headers = {}
          headers["Content-Length"] = string.len(jsonstr)
          headers["Content-Type"] = "application/json; charset=utf-8 "
          headers["Accept"] = "application/json"
          headers["Host"] = self.config.host
          headers["Connection"] = "close"
        end
        log:action(msg.HttpAgentSendingPost:tag{host=self.config.host, thread=coroutine.id(), payload=jsonstr})
        local result, status = self:send("POST "..self.url.." HTTP/1.1\r\n"..table2headers(headers).."\r\n"..jsonstr)
        if not result then
          self:close()
          return 500, status
        end
        local code, response, version = self:receive()
        log:action(msg.HttpAgentResponseReceived:tag{host=self.config.host, thread=coroutine.id(), status=code, protocol=version})
        self:close() --TODO: if self:send() returned closed state?
        return code, response, version
      --end))
    end,
}

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
    --print("waking up ", consumer._thread)
    consumer:reschedule()
  else
    --print("is not necessary wake up ", consumer._thread)
  end
end


local httpclient = http:connect({host = "localhost:51400"})
assert(httpclient)

-- consumer
consumer._thread = newthread(function()
  while true do
    if fifo:empty() then -- wait
      print(string.format("[%s] waiting for data", oil.time()))
      consumer:wait()
    else -- pop
      local data = fifo:pop()
      local msg = string.format("[%s] consuming data { count = %d }", oil.time(), data.count)
      print(msg)
      print("result of http post: ", httpclient:post("/", '[{"body":"'..msg..'"}]'))
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