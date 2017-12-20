-- Audit Inteceptor to publish data in a HTTP REST service
-- 
-- FIXME: 
--   [x] audit http authentication
--   [ ] audit interceptor should be inject in busservices
--   [x] audit event mapping should be configurable (request, caller) -> (audit event class)
--   [ ] should serialize on disk/sqlite when shutding down ?
--   [i] should serialize under cache overflow ? (i: FIFO now has limits)
--   [ ] should log entire event collected or just an ID ?
--   [ ] should log in a new 'audit' level ?

local _G = require "_G"
local error = _G.error
local print = _G.print
local setmetatable = _G.setmetatable

local coroutine = require "coroutine"
local running = coroutine.running

local oil = require "oil"
local newuuid = require("uuid").new
local b64encode = require("base64").encode

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

local interceptor = {
  auditevents = setmetatable({},{__mode = "k"}),
  agent = AuditAgent{
    config = {
      httpendpoint = "http://localhost:51398/",
      httpcredentials = b64encode("fulano:silva"),
    }
  },
}

function interceptor:receiverequest(request)
  local event = AuditEvent()
  event:incoming(request, {caller={entity="UserBoss", id=newuuid()}})
  self.auditevents[running()] = event
end

function interceptor:sendreply(request)
  local thread = running()
  local event = self.auditevents[thread]
  if event ~= nil then
    event:outgoing(request)
    self.agent:publish(event)
    self.auditevents[thread] = nil
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

local function shutdownhook(self, orb)
  orb:shutdown(true)
  self.agent:shutdown()
end

local servant = {
  sayhello = function(self, msg)
    print("server receive a message:",msg)
    if msg == "except" then
      error(orb:newexcept{"IDL:Hello/AnError:1.0", mymsg="some context related"})
    end
    if msg == "shutdown" then
      shutdownhook(interceptor, orb)
    end
  end
}

orb:newservant(
  servant,
  "Hello",
  "IDL:Hello:1.0");

orb:run()

log:uptime(msg.CorbaServerFinished)
