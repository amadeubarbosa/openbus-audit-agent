local url = "http://localhost:51398/block"

local socket = require "cothread.socket"
local server = require "openbus.util.server"
local log = require "openbus.util.logger"
server.setuplog(log,5)

function agenttest()
  local Agent = require "openbus.core.audit.Agent"
  local Event = require "openbus.core.audit.Event"
  local event = Event()
  local data = event.data
  data.timestamp=129837843
  data.actionName="test"
  data.userName="tester"
  data.openbusProtocol="v0_0"
  data.interfaceName="INone"
  data.loginId="23842193890"
  data.ipOrigin="127.0.0.1:0000"
  data.duration=129837899
  data.resultCode=true

  local agent = Agent{config = {httpendpoint = url}}
  local max=1000005
  for i=1,max do
    agent:publish(event)
  end
  print("published "..max.." events")
  local timeout=600
  print("waiting for "..timeout.." seconds")
  socket.sleep(timeout)
  assert(agent.config.fifolimit-agent._fifo:count() == agent.config.concurrency, string.format("wrong number of events being processed: limit=%d #fifo=%d #agents=%d", max, agent._fifo:count(), agent.config.concurrency))
end

agenttest()
