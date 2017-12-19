local mode = "sync"
local maxrequests = 10000

local nargs = select("#", ...)
local help = select(1, ...)
if help and help:find("help") then
	io.stderr:write("Usage : client [mode] <maxrequests>\n")
	io.stderr:write("\t mode        - optional flavor for client requests: 'sync' (default) or 'async'\n")
	io.stderr:write("\t maxrequests - how many requests will be sent: 10000 (default)\n")
	io.stderr:write("\n")
	io.stderr:write("\n")
	io.stderr:flush()
	os.exit()
end

if nargs > 0 then
	maxrequests = tonumber(select(nargs, ...)) or maxrequests
	mode = (nargs - 1) > 0 and select(nargs - 1, ...) or mode
end

local oil = require "oil"
local orb = oil.init()

orb:loadidl[[
interface Hello {
  exception AnError { string mymsg; };
  void sayhello(in string msg) raises (AnError);
};
]]
local hello do
	if mode == "async" then
		hello = orb:newproxy("corbaloc::127.0.0.1:2266/Hello", "asynchronous", "IDL:Hello:1.0");
		hello.futures = {}
	else
		hello = orb:newproxy("corbaloc::127.0.0.1:2266/Hello", "synchronous", "IDL:Hello:1.0");
	end
end

local start = oil.time()
for i=1,maxrequests do
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
print(string.format("client finished, mode = %s max = %d, duration = %0.2f", mode or "sync", maxrequests, finish - start))

--hello:sayhello("shutdown")

orb:shutdown()
