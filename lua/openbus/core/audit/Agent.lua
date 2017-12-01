local _G = require "_G"
local assert = _G.assert
local ipairs = _G.ipairs
local pcall = _G.pcall
local tostring = _G.tostring

local coroutine = require "coroutine"
local running = coroutine.running
local status = coroutine.status
local newthread = coroutine.create

local cothread = require "cothread"
local schedule = cothread.schedule
local unschedule = cothread.unschedule

cothread.plugin(require "cothread.plugin.socket")
local waitfor = require("cothread.socket").sleep

local msg = require "openbus.core.messages"
local log = require "openbus.util.logger"

local class = require("openbus.util.oo").class
local http = require "openbus.util.http"
http.TIMEOUT = 5 -- seconds
-- http.PROXY = "http://localhost:3128" -- proxy settings

local FIFO = class {
  _head = 1,
  _tail = 1,
}

function FIFO:empty()
  local remaining = (self[self._tail] == nil)
  if remaining then
    -- prevent huge counters
    self._head = 1
    self._tail = 1
  end
  return remaining
end

function FIFO:pop()
  local event = self[self._tail]
  if event ~= nil then
    self[self._tail] = nil
    self._tail = self._tail + 1
  end
  return event
end

function FIFO:push(event)
  if (event ~= nil) then
    self[self._head] = event
    self._head = self._head + 1
  end
end

function FIFO:count()
  return self._head - self._tail
end

local Agent = class {
  _threads = {}, -- cothreads
  _waiting = {}, -- critical regions
  _concurrency = 5, -- max cothreads using fifo
  _retrytimeout = 1, -- seconds to wait before retry http post
  _discardonexit = false, -- option to discard events when shuts down
  _endpoint = "http://localhost:8080/", -- url of audit REST service
  _fifo = false, -- FIFO object
  _fifolimit = 1000000, -- FIFO limit before discard events
}

function Agent:__init()
  local newconnection = function()
    return http.connect(self._endpoint)
  end

  local httppost = newconnection()
  self._fifo = FIFO()

  local fifo = self._fifo
  local timeout = self._retrytimeout
  local waiting = self._waiting
  local threads = self._threads
  for i=1, self._concurrency do
    local agent = newthread(function()
      local threadid = tostring(running())
      while true do
        if fifo:empty() then -- wait
          log:action(msg.AuditAgentWaitingForData:tag{agent=threadid})
          waiting[i] = true
          cothread.suspend()
        else -- pop
          local event = fifo:pop()
          local json = event:json()
          local ok, result = pcall(httppost, json)
          if not ok then
            local exception = result[1]
            -- prevent IO-bound task when service is offline
            waitfor(timeout)
            -- recreate the connection and try again
            httppost = newconnection()
            fifo:push(event)
            log:exception(msg.AuditAgentReconnecting:tag{error=exception or result, agent=threadid, request=json})
          end
          cothread.last()
        end
      end
    end)
    waiting[i] = false
    threads[i] = agent
    cothread.schedule(agent, "last")
  end
  log:uptime(msg.AuditAgentStarted)
end

function Agent:publish(...)
  local fifo = self._fifo
  local fifolimit = self._fifolimit
  if fifo:count() > fifolimit then
    log:exception(msg.AuditAgentDiscardingDataAfterFifoLimitReached:tag{limit=fifolimit})
  else
    fifo:push(...)
  end
  -- resume workers to process the event
  local threads = self._threads
  local waiting = self._waiting
  for i=1, #threads do
    if (waiting[i] == true) then
      waiting[i] = false
      cothread.schedule(threads[i], "last") -- wake up
    end
  end
end

function Agent:haspending()
  local running = 0
  local waiting = self._waiting
  for _, suspended in ipairs(waiting) do
    if suspended == false then
      running = running + 1
    end
  end
  return (running ~= 0), running
end

function Agent:unschedule()
  for i, thread in ipairs(self._threads) do
    cothread.unschedule(thread)
  end
end

function Agent:shutdown()
  local fifo = self._fifo
  local discardonexit = self._discardonexit
  cothread.schedule(newthread(function()
    if discardonexit then
      local _, threads = self:haspending()
      log:exception(msg.AuditAgentDiscardingDataOnShutdown:tag{discarded=fifo:count(), pendingthreads=threads})
      self:unschedule() -- just remove all threads from cothread scheduler
    else
      repeat
        local haspending, count = self:haspending()
        if haspending then -- only for verbose
          log:action(msg.AuditAgentWaitingForPendingThreads:tag{threads=count})
        end
        waitfor(.5)
      until (haspending == false)
    end
    log:uptime(msg.AuditAgentTerminated)
  end), "last")
end

return Agent