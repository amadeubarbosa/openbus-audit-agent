local _G = require "_G"
local assert = _G.assert
local package = _G.package
local pairs = _G.pairs
local tostring = _G.tostring
local type = _G.type

local math = require "math"
local table = require "table"
local string = require "string"
local date = require("os").date
local newuuid = require("uuid").new
local cothread = require "cothread"
cothread.plugin(require "cothread.plugin.socket")
local gettimeofday = cothread.now
local viewer = require "loop.debug.Viewer"
local b64encode = require("base64").encode
local oil = require "oil" -- package.loaded usage depends on it
local class = require("openbus.util.oo").class

--
-- AuditEventKeys {
--     -- instance information
--     solutionCode,
--     environment,
--     -- request
--     id,
--     timestamp,
--     actionName,
--     userName,
--     loginId,
--     interfaceName,
--     openbusProtocol,
--     ipOrigin,
--     input,
--     -- reply
--     duration,
--     output,
--     resultCode,
-- }
--

local serializer = viewer{
  maxdepth = 3, --FIXME: object serialization could fail, skipping
  metaonly = true,
}

local Default = {
  application = "OPENBUS",
  instance = newuuid(),
  nullvalue = "null",
  unknownuser = "<unknown>",
  dateformat = "%Y-%m-%d %H:%M:%S",
  miliformat = "%.4f",
}

local AuditEvent = class{}

function AuditEvent:__init()
  local config = class(self.config or {}, Default)
  self.data = {
    solutionCode = config.application,
    environment = config.instance,
    id = newuuid(),
  }
  self.config = config
  self.id = self.data.id
end

function AuditEvent:incoming(request, callerchain)
  local data = self.data
  local unknownuser = self.config.unknownuser
  local nullvalue = self.config.nullvalue
  data.timestamp = gettimeofday()
  data.actionName = request.operation_name
  data.userName = callerchain and callerchain.caller.entity or unknownuser
  data.input = request.parameters
  -- optional data
  if callerchain then
    data.openbusProtocol = (callerchain.islegacy and "v2_0") or "v2_1"
  else
    data.openbusProtocol = nullvalue
  end
  data.interfaceName = request.interface and request.interface.repID or nullvalue
  data.loginId = callerchain and callerchain.caller.id or unknownuser
  data.ipOrigin = request.channel_address
end

function AuditEvent:outgoing(request)
  local data = self.data
  data.duration = gettimeofday() - data.timestamp
  data.resultCode = request.success
  data.output = request.results
end

local function stringfyparams(params, nullvalue)
  if params and #params > 0 then
    return b64encode(serializer:tostring(params))
  else
    return nullvalue
  end
end

local function dateformat(timestamp, datepattern)
  local mili = string.format("%.3f", timestamp):match("(%.%d%d%d)") or ""
  return date(datepattern, math.modf(timestamp))..mili
end

function AuditEvent:format()
  local datepattern = self.config.dateformat
  local milipattern = self.config.miliformat
  local nullvalue = self.config.nullvalue
  local data = self.data

  if type(data.timestamp) ~= "string" then
    data.timestamp = dateformat(data.timestamp, datepattern)
  end
  if type(data.interfaceName) ~= "string" then
    data.interfaceName = tostring(data.interfaceName)
  end
  if type(data.ipOrigin) ~= "string" then
    local address = data.ipOrigin
    data.ipOrigin = string.format("%s:%d", assert(address.host), assert(address.port))
  end
  if type(data.input) ~= "string" then
    data.input = stringfyparams(data.input, nullvalue)
  end
  if type(data.output) ~= "string" then
    data.output = stringfyparams(data.output, nullvalue)
  end
  if type(data.resultCode) ~= "string" then
    data.resultCode = tostring(data.resultCode)
  end
  if type(data.duration) ~= "string" then
    data.duration = string.format(milipattern, data.duration * 1000)
  end
end

function AuditEvent:json()
  if self.jsondata == nil then
    self:format()
    local result = {}
    for k,v in pairs(self.data) do
      table.insert(result, string.format("%q:%q", k,v))
    end
    self.jsondata = "{"..table.concat(result, ",").."}"
    self.data = nil
  end
  return self.jsondata
end

return AuditEvent
