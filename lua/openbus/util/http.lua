local _G = require "_G"
local tostring = _G.tostring
local tonumber = _G.tonumber

local table = require "table"
local unpack = table.unpack

local coroutine = require "coroutine"
local running = coroutine.running

local cothread = require "cothread"
cothread.plugin(require "cothread.plugin.socket")
local socket = require "cothread.socket"
local newtcp = socket.tcp

local url = require "socket.url"
local http = require "socket.http"

local ltn12 = require "ltn12"
local strsrc = ltn12.source.string
local tabsnk = ltn12.sink.table

local class = require("openbus.util.oo").class
local log = require "openbus.util.logger"
local msg = require "openbus.core.messages"

local http = class({}, http)
local httprequest = http.request

function http.connect(endpoint, location)
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

return http