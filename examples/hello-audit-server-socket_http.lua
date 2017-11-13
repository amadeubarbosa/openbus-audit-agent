local _G = require "_G"
local pairs = _G.pairs
local assert = _G.assert

local date = require "os".date

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
http.TIMEOUT = 15 -- seconds

local RETRY_TIMEOUT = 1      -- seconds
local CONCURRENT_CLIENTS = 5 -- seconds

local ltn12 = require "ltn12"
local strsrc = ltn12.source.string
local tabsnk = ltn12.sink.table

local url = require "socket.url"

local uuid = require "uuid"

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
        ["connection"] = "close",
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
-- local httpfactory = function() return httpconnection("http://localhost:51400", "/") end
local httpfactory = function() return httpconnection("http://localhost:51398", "/") end
local httppost = httpfactory()

function consumer:reschedule()
  for i=1, CONCURRENT_CLIENTS do
    if (self._sleep[i] == true) then
      self._sleep[i] = false
      cothread.schedule(self._thread[i], "last") -- wake up
    end
  end
end

local function dateformat(timestamp)
  local mili = string.format("%.3f", timestamp):match("%.(%d%d%d)")
  return date("%Y-%m-%d %H:%M:%S.", math.modf(timestamp))..mili
end

local function jsonstringfy(event)
  if type(event.interfaceName) ~= "string" then
    event.interfaceName = tostring(event.interfaceName)
  end
  if type(event.ipOrigin) ~= "string" then
    local address = event.ipOrigin
    event.ipOrigin = string.format("%s:%d ", assert(address.host), assert(address.port))
  end
  if type(event.timestamp) == "number" then
    event.timestamp = dateformat(event.timestamp) -- date format stringfy
  end

  local json = ""
  for k,v in pairs(event) do
    json = json .."\"".. k .. "\":\"" .. v .."\","
  end
  json = json:gsub(",$","")
  return "{"..json.."}"
end

for i=1, CONCURRENT_CLIENTS do
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
        local json = type(data) == "table" and jsonstringfy(data) or (type(data) == "string" and data) or error("data collected is unknown")
        -- local ok, result = pcall(httppost, '[{"body":"'..json..'"}]')
        local ok, result = pcall(httppost, json)
        if not ok then
          local exception = result[1]
          -- prevent IO-bound task when service is offline, no route to host or refused
          socket.sleep(RETRY_TIMEOUT)
          -- recreate the connection and try again
          httppost = httpfactory()
          fifo:push(data)
          log:exception(msg.AuditAgentReconnecting:tag{error=exception, agent=threadid, request=json})
        end
        cothread.last()
      end
      print("memory in use:", collectgarbage("count"))
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

local NullValue = "<EMPTY>"
local UnknownUser = "UNKNOWN_USER"

local interceptor = {audit={}}
function interceptor:receiverequest(request)
  local id = uuid.new()
  self.audit[running()] = {
    id = id,
    solutionCode = "BEEP",
    actioName = request.operation_name,
    timestamp = cothread.now(),
    userName = "UserBoss",
    input = NullValue, --TODO: request parameters
    output = NullValue, --TODO: results
    resultCode = (request.success and "true") or
      ((request.success == false) and "false") or NullValue,
    environment = "TST",
    openbusProtocol = "v0_9",
    interfaceName = request.interface.repID,
    ipOrigin = request.channel_address,
    loginId = id,
  }
end

function interceptor:sendreply(request)
  local event = self.audit[running()]
  self.audit[running()] = nil
  event.duration = cothread.now() - event.timestamp -- duration (miliseconds)
  fifo:push(event)
end

orb:setinterceptor(interceptor, "corba.server")

orb:newservant(
  {sayhello = function(self, msg)
    print("server receive a message:",msg)
  end},
  "Hello",
  "IDL:Hello:1.0");

orb:run()
