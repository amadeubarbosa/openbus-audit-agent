-- Audit Inteceptor to publish data in a HTTP REST service
-- 
-- FIXME: 
--   [ ] audit interceptor should be inject in busservices
--   [x] audit event mapping should be configurable (request, caller) -> (audit event class)
--   [ ] should serialize on disk/sqlite when shutding down ?
--   [ ] should serialize under cache overflow ?

local _G = require "_G"
local error = _G.error
local print = _G.print
local setmetatable = _G.setmetatable

local coroutine = require "coroutine"
local running = coroutine.running

local oil = require "oil"
local newuuid = require("uuid").new

local log = require "openbus.util.logger"
local setuplog = require("openbus.util.server").setuplog
local msg = require "openbus.core.messages"

local AuditEvent = require "openbus.core.audit.Event"
local AuditAgent = require "openbus.core.audit.Agent"

setuplog(log, 5)

-- configuration
AuditEvent.config = {
  application = "BEEP",
  instance = "TST",
}

-- main

local agent = AuditAgent{_endpoint = "http://localhost:51398/"}

local interceptor = {audit=setmetatable({},{__mode = "k"})}
function interceptor:receiverequest(request)
  local event = AuditEvent()
  event:collect("request", request, {caller={entity="UserBoss", id=newuuid()}})
  self.audit[running()] = event
end

function interceptor:sendreply(request)
  local thread = running()
  local event = self.audit[thread]
  if event ~= nil then
    event:collect("reply", request)
    agent:publish(event)
    self.audit[thread] = nil
  end
end

local orb = oil.init({port=2266, flavor="cooperative;corba.intercepted"})

orb:loadidl[[
interface Hello {
  exception AnError { string mymsg; };
  void sayhello(in string msg) raises (AnError);
};
]]

orb:setinterceptor(interceptor, "corba.server")

local function shutdownhook(orb)
  orb:shutdown(true)
  agent:shutdown()
end

local servant = {
  sayhello = function(self, msg)
    print("server receive a message:",msg)
    if msg == "except" then
      error(orb:newexcept{"IDL:Hello/AnError:1.0", mymsg="some context related"})
    end
    if msg == "shutdown" then
      shutdownhook(orb)
    end
  end
}

orb:newservant(
  servant,
  "Hello",
  "IDL:Hello:1.0");

orb:run()

log:uptime(msg.CorbaServerFinished)