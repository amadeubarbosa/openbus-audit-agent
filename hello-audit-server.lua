local oil = require "oil"

local coroutine = require "coroutine"
local newthread = coroutine.create
local cothread = require "cothread"
local schedule = cothread.schedule
local unschedule = cothread.unschedule

cothread.plugin(require "cothread.plugin.socket")
local socket = require "cothread.socket"

local consumer = { -- forward declaration
	_running = false, -- critical region
	_thread = false, -- cothread
}

function consumer:wait()
	self._running = false
	cothread.suspend()
	self._running = true
end

function consumer:suspended()
	return self._running == false
end

function consumer:reschedule()
	self._running = true
	cothread.schedule(self._thread, "last") -- wake up
end

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
	if consumer:suspended() then
		--print("waking up ", consumer._thread)
		consumer:reschedule()
	else
		--print("is not necessary wake up ", consumer._thread)
	end
end



-- consumer
consumer._thread = newthread(function()
	while true do
		if fifo:empty() then -- wait
			print(string.format("[%s] waiting for data", oil.time()))
			consumer:wait()
		else -- pop
			local data = fifo:pop()
			print(string.format("[%s] consuming data { count = %d }", oil.time(), data.count))
			consumer:reschedule()
		end
	end
end)

-- main
local orb = oil.init({port=2266})

orb:loadidl[[
interface Hello {
	void sayhello(in string msg);
};
]]

local count = 0
orb:newservant(
	{sayhello = function(self, msg)  
		count = count + 1
		fifo:push({count = count})
		--print("received ".. msg)
	end},
	"Hello",
	"IDL:Hello:1.0");

orb:run()