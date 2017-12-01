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
local strstream = require "loop.serial.StringStream"
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

local default = {
  application = "OPENBUS",
  instance = newuuid(),
  nullvalue = "null",
  unknownuser = "<unknown>",
  dateformat = "%Y-%m-%d %H:%M:%S",
  miliformat = "%.4f",
}

local AuditEvent = class{}

function AuditEvent:__init()
  local config = class(self.config or {}, default)
  self.data = {
    solutionCode = config.application,
    environment = config.instance,
  }
  self.config = config
end

function AuditEvent:collect(phase, request, callerchain)
  local data = self.data
  if phase == "request" then
    local unknownuser = self.config.unknownuser
    data.id = newuuid()
    data.timestamp = gettimeofday()
    data.actionName = request.operation_name
    data.userName = callerchain and callerchain.caller.entity or unknownuser
    data.input = request.parameters
    -- optional data
    data.interfaceName = request.interface.repID
    data.loginId = callerchain and callerchain.caller.id or unknownuser
    data.ipOrigin = request.channel_address
  elseif phase == "reply" then
    data.duration = gettimeofday() - data.timestamp
    data.resultCode = request.success
    data.output = request.results
  end
end

local function stringfyparams(params, nullvalue)
  if #params > 0 then
    local stream = strstream()
    stream:register(package.loaded) -- in order to serialize oil exceptions
    stream:put(params)
    return b64encode(stream:__tostring())
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
    -- optional data
    data.openbusProtocol = data.interfaceName:match("%/(v[%d%_]+)%/")
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