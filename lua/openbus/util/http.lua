local _G = require "_G"
local error = _G.error
local tonumber = _G.tonumber
local tostring = _G.tostring

local table = require "table"
local concat = table.concat
local unpack = table.unpack

local coroutine = require "coroutine"
local running = coroutine.running

local cothread = require "cothread"
cothread.plugin(require "cothread.plugin.socket")
local socket = require "cothread.socket"
local newtcp = socket.tcp

local url = require "socket.url"
local parseurl = url.parse
local http = require "socket.http"

local ltn12 = require "ltn12"
local strsrc = ltn12.source.string
local tabsnk = ltn12.sink.table

local class = require("openbus.util.oo").class
local log = require "openbus.util.logger"
local msg = require "openbus.core.messages"

local http = class({}, http)
local httprequest = http.request

function http.connect(endpoint, location, credentials)
  local parsed = parseurl(endpoint)
  local url = endpoint..( location or "" )
  local sock, errmsg = newtcp()
  local threadid = tostring(running())
  if sock ~= nil then
    local ok, errmsg = sock:connect(parsed.host, parsed.port or http.PORT)
    if not ok then
      -- close socket as soon as possible
      sock:close()
      sock = nil
      log:exception(msg.HttpConnectFailed:tag{url=url, errmsg=errmsg, thread=threadid})
    end
  else
    log:exception(msg.UnableToCreateTcpSocket:tag{url=url, errmsg=errmsg, thread=threadid})
  end
  
  return 
  function (request, method, mimetype)
    local threadid = tostring(running())
    local body = {}
    local mimetype = mimetype or "application/json"
    local method = request and (method or "POST") or "GET"
    local ok, ret, code, headers, status = pcall(httprequest, {
      url = url,
      connection = sock,
      source = request and strsrc(request) or nil,
      sink = tabsnk(body),
      headers = {
        ["authorization"] = (credentials and "Basic "..credentials) or nil,
        ["content-length"] = request and #request or nil,
        ["content-type"] = mimetype..";charset=utf-8",
        ["accept"] = mimetype,
        ["connection"] = sock and "keep-alive" or nil,
      },
      method = method,
    })
    if not ok then
      error{msg.HttpRequestFailed:tag{url=url, details=ret}}
    elseif (code ~= 200 and code ~= 201) then
      -- as keep-alive is used, we must close the socket by ourselves
      if sock ~= nil then
        sock:close()
        sock = nil
      end
      local response
      if code >= 300 and code < 400 then
        response = {headers = headers} -- just log headers
      elseif code >= 500 then
        response = {body = concat(body or {}):gsub("[\r\n]","")}
      end
      error{msg.UnexpectedHttpResponse:tag{url=url, method=method, thread=threadid,
        code=code, status=status, response=response}}
    else
      return body, headers
    end
  end
end

function http.setproxy(proxyurl)
  http.PROXY = proxyurl or nil
end

return http
