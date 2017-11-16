local mode, maxrequests = ...
local oil = require "oil"
local orb = oil.init()

orb:loadidl[[
interface Hello {
  exception AnError { string mymsg; };
  void sayhello(in string msg) raises (AnError);
};
]]
local max = maxrequests or 10000
local hello do
	if mode == "async" then
		hello = orb:newproxy("corbaloc::127.0.0.1:2266/Hello", "asynchronous", "IDL:Hello:1.0");
		hello.futures = {}
	else
		hello = orb:newproxy("corbaloc::127.0.0.1:2266/Hello", "synchronous", "IDL:Hello:1.0");
	end
end

local start = oil.time()
for i=1,max do
  	local future = hello:sayhello("message"..i)
  	if mode == "async" then
  		hello.futures[i] = future
	end
end

if mode == "async" then
	hello.futures[#hello.futures+1] = hello:sayhello("except")
	for i=1,#hello.futures do
		hello.futures[i]:results()
	end
end
local finish = oil.time()
print(string.format("client finished, mode = %s max = %d, duration = %0.2f", mode or "sync", max, finish - start))
orb:shutdown()