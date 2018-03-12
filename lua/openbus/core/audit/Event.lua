local _G = require "_G"
local assert = _G.assert
local package = _G.package
local pairs = _G.pairs
local type = _G.type
local tostring = _G.tostring
local setmetatable = _G.setmetatable

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
local json = require "json"
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
--     input,
--     -- reply
--     duration,
--     output,
--     resultCode,
--     -- extra properties
--     openbusProtocol,
--     interfaceName,
--     loginId,
--     ipOrigin,
-- }
--

local serializer = viewer{
  maxdepth = 3, --FIXME: object serialization could fail, skipping
  metaonly = true,
}

local Default = {
  application = "OPENBUS",
  environment = newuuid(),
  nullvalue = "null",
  unknownuser = "<unknown>",
  dateformat = "%Y-%m-%d %H:%M:%S",
  miliformat = "%.4f",
}

local AuditEvent = class{}

function AuditEvent:__init()
  local config = setmetatable(self.config or {}, {__index=Default})
  self.data = {
    solutionCode = config.application,
    environment = config.environment,
    id = newuuid(),
    properties = {},
  }
  self.config = config
  self.id = self.data.id
end

function AuditEvent:incoming(request, callerchain)
  local data = self.data
  local extra = data.properties
  local unknownuser = self.config.unknownuser
  local nullvalue = self.config.nullvalue

  data.timestamp = gettimeofday()
  data.actionName = request.operation_name or nullvalue
  data.input = request.parameters
  if callerchain then
    data.userName = callerchain and callerchain.caller.entity or unknownuser
    extra.loginId = callerchain and callerchain.caller.id or unknownuser
    extra.openbusProtocol = (callerchain and (callerchain.islegacy and "v2_0" or "v2_1")) or nullvalue
  else
    data.userName = unknownuser
    extra.loginId = unknownuser
    extra.openbusProtocol = nullvalue
  end
  extra.interfaceName = request.interface and request.interface.repID or nullvalue
  extra.ipOrigin = request.channel_address or nullvalue
end

function AuditEvent:outgoing(request)
  local data = self.data
  data.duration = gettimeofday() - data.timestamp
  data.resultCode = request.success
  data.output = request.results
end

local function stringfyparams(params)
  if type(params) == "table" and #params > 0 then
    return b64encode(serializer:tostring(params))
  else
    return nil
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
  local extra = data.properties

  if type(data.timestamp) ~= "string" then
    data.timestamp = dateformat(data.timestamp, datepattern)
  end
  if type(data.input) ~= "string" then
    data.input = stringfyparams(data.input) or nullvalue
  end
  if type(data.output) ~= "string" then
    data.output = stringfyparams(data.output) or nullvalue
  end
  if type(data.resultCode) ~= "string" then
    data.resultCode = tostring(data.resultCode)
  end
  if type(data.duration) ~= "string" then
    data.duration = string.format(milipattern, data.duration * 1000)
  end
  if type(extra.interfaceName) ~= "string" then
    extra.interfaceName = tostring(extra.interfaceName)
  end
  if type(extra.ipOrigin) ~= "string" then
    local address = extra.ipOrigin
    extra.ipOrigin = address and string.format("%s:%d", assert(address.host), assert(address.port)) or nullvalue
  end
end

function AuditEvent:json()
  if self.jsondata == nil then
    self:format()
    self.jsondata = json.encode(self.data)
    self.data = nil
  end
  return self.jsondata
end

return AuditEvent
