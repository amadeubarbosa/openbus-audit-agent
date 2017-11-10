local oil = require "oil"
local orb = oil.init({port=2266})

orb:loadidl[[
interface Hello {
	void sayhello(in string msg);
};
]]

orb:newservant({sayhello = function(self, msg) print(msg) end}, "Hello", "IDL:Hello:1.0");

orb:run()
