local _G = require "_G"
local pairs = _G.pairs
local assert = _G.assert
local tostring = _G.tostring

local date = require "os".date
local table = require "table"
local concat = table.concat
local insert = table.insert

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

local url = require "socket.url"
local http = require "socket.http"
local httprequest = http.request
http.TIMEOUT = 15 -- seconds

local ltn12 = require "ltn12"
local strsrc = ltn12.source.string
local tabsnk = ltn12.sink.table

local uuid = require "uuid"

local oil = require "oil"

local stringstream = require "loop.serial.StringStream"
local base64 = require "base64"

local oo = require "openbus.util.oo"
local log = require "openbus.util.logger"
local setuplog = require("openbus.util.server").setuplog
local msg = require "openbus.core.messages"

function httpconnect(endpoint, location)
  local parsed = url.parse(endpoint)
  local sock = newtcp()
  sock:connect(parsed.host, parsed.port)
  local url = endpoint..( location or "" )
  
  return 
  function (request)
    local threadid = tostring(running())
    local body = {}
    local ok, code, headers, status = httprequest{
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
    if not ok or (tonumber(code) ~= 200 and tonumber(code) ~= 201) then
      -- using error almost like an exception
      error{msg.HttpPostFailed:tag{url=url, request=request, agent=threadid, code=code, status=status, body=concat(body)}}
    else
      log:action(msg.HttpPostSuccessfullySent:tag{url=url, request=request, agent=threadid})
      return body
    end
  end
end

--[[
  http.PROXY = http://localhost:3128
]]

setuplog(log, 5)

local consumer = { -- forward declaration
  _threads = {}, -- cothreads
  _waiting = {}, -- critical regions
  _maxclients = 5, -- max cothreads using fifo
  _retrytimeout = 1, -- seconds to wait before retry http post
}

local fifo = {
  _first = 1,
  _last = 1,
}

function fifo:empty()
  return self[self._last] == nil
end

function fifo:pop()
  local event = self[self._last]
  self[self._last] = nil
  self._last = self._last + 1
  return event
end

function fifo:push(event)
  self[self._first] = event
  self._first = self._first + 1
  consumer:reschedule()
end

-- consumer
local httpfactory = function() return httpconnect("http://localhost:51398", "/") end
local httppost = httpfactory()

function consumer:reschedule()
  local threads = self._threads
  local waiting = self._waiting
  for i=1, #threads do
    if (waiting[i] == true) then
      waiting[i] = false
      cothread.schedule(threads[i], "last") -- wake up
    end
  end
end

local function dateformat(timestamp)
  local mili = string.format("%.3f", timestamp):match("%.(%d%d%d)")
  return date("%Y-%m-%d %H:%M:%S.", math.modf(timestamp))..mili
end

local function serialize(data)
  local stream = stringstream()
  stream:put(data)
  return base64.encode(stream:__tostring())
end

local function jsonstringfy(event)
  if type(event.interfaceName) ~= "string" then
    event.interfaceName = tostring(event.interfaceName)
  end
  if type(event.ipOrigin) ~= "string" then
    local address = event.ipOrigin
    event.ipOrigin = string.format("%s:%d", assert(address.host), assert(address.port))
  end
  if type(event.timestamp) == "number" then
    event.timestamp = dateformat(event.timestamp) -- date format stringfy
  end
  if type(event.input) ~= "string" then
    if #event.input > 0 then
      event.input = serialize(event.input)
    else
      event.input = "null"
    end
  end
  if type(event.output) ~= "string" then
    if #event.output > 0 then
      if event.resultCode == false then
        local exception = {} -- avoids to serialize OiL exception metatables
        for k,v in pairs(event.output[1]) do
          exception[k] = v
        end
        event.output = exception
      end
      event.output = serialize(event.output)
    else
      event.output = "null"
    end

  end
  if type(event.resultCode) ~= "string" then
    event.resultCode = tostring(event.resultCode)
  end
  if type(event.duration) ~= "string" then
    event.duration = string.format("%.4f", event.duration)
  end

  local result = {}
  for k,v in pairs(event) do
    insert(result, string.format("%q:%q", k,v))
  end
  return "{"..concat(result, ",").."}"
end

function consumer:init()
  local retrytimeout = self._retrytimeout
  local waitfor = socket.sleep
  local waiting = self._waiting
  local threads = self._threads
  for i=1, self._maxclients do
    local agent = newthread(function()
      local threadid = tostring(running())
      while true do
        if fifo:empty() then -- wait
          log:action(msg.AuditAgentIsWaitingForData:tag{agent=threadid})
          waiting[i] = true
          cothread.suspend()
        else -- pop
          local data = fifo:pop()
          local datatype = type(data)
          if datatype == "table" or datatype == "string" then
            local json = (datatype == "table" and jsonstringfy(data)) or data
            local ok, result = pcall(httppost, json)
            if not ok then
              local exception = result[1]
              -- prevent IO-bound task when service is offline
              waitfor(retrytimeout)
              -- recreate the connection and try again
              httppost = httpfactory()
              fifo:push(json)
              log:exception(msg.AuditAgentReconnecting:tag{error=exception, agent=threadid, request=json})
            end
          else
            log:exception(msg.AuditAgentDiscardedUnsupportedData:tag{datatype=datatype, data=data})
          end
          cothread.last()
        end
      end
    end)
    waiting[i] = false
    threads[i] = agent
    cothread.schedule(agent, "last")
  end
end

-- corba interceptor

local NullValue = "null"
local UnknownUser = "UNKNOWN_USER"

local interceptor = {audit=setmetatable({},{__mode = "k"}), fifo=fifo}
function interceptor:receiverequest(request)
  local id = uuid.new()
  local thread = running()
  self.audit[thread] = {
    id = id,
    solutionCode = "BEEP",
    actionName = request.operation_name,
    timestamp = cothread.now(),
    userName = "UserBoss",
    input = request.parameters or NullValue,
    environment = "TST",
    openbusProtocol = "v0_9",
    interfaceName = request.interface.repID,
    ipOrigin = request.channel_address,
    loginId = id,
  }
end

function interceptor:sendreply(request)
  local thread = running()
  if self.audit[thread] ~= nil then
    local event = self.audit[thread]
    self.audit[thread] = nil
    event.duration = (cothread.now() - event.timestamp) * 1000 -- duration (ms)
    event.resultCode = request.success
    event.output = request.results or NullValue
    self.fifo:push(event)
  end
end

-- main

consumer:init()

local orb = oil.init({port=2266, flavor="cooperative;corba.intercepted"})

orb:loadidl[[
interface Hello {
  exception AnError { string mymsg; };
  void sayhello(in string msg) raises (AnError);
};
]]
orb:setinterceptor(interceptor, "corba.server")

local servant = {
  sayhello = function(self, msg)
    print("server receive a message:",msg)
    if msg == "except" then
      error(orb:newexcept{"IDL:Hello/AnError:1.0", mymsg="some context related"})
    end
  end
}

orb:newservant(
  servant,
  "Hello",
  "IDL:Hello:1.0");

orb:run()
