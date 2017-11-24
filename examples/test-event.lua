local AuditEvent = require "examples.AuditEvent"

local event = AuditEvent()

local repID = {"IDL:openbus/v2_0/Hello:1.0"}
setmetatable(repID, {__tostring = function(t) return t[1] end})

event:collect("request", {
	interface={repID=repID,},
	channel_address={host="beep-prd", port = 2089}, 
	results={}, parameters={}})

event:collect("reply", {results={}, success=true})

print(event:json())
print(event.data == nil)
