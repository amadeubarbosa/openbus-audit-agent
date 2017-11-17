local oil = require "oil"
local orb = oil.init({port=2266})

orb:loadidl[[
interface Hello {
  exception AnError { string mymsg; };
  void sayhello(in string msg) raises (AnError);
};
]]

orb:newservant(
  {
    sayhello = function(self, msg)
      print(msg)
      if msg == "except" then
        error(orb:newexcept{"IDL:Hello/AnError:1.0", mymsg="some context related"})
      end
    end,
  },
  "Hello", "IDL:Hello:1.0");

orb:run()
