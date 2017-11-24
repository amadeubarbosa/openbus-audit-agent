-- Project: LOOP Class Library
-- Title  : Alternative version of loop.object.Publisher
-- Author : Amadeu A. Barbosa Junior <amadeu@tecgraf.puc-rio.br>
-- Changes: 
--  * 2017-11-17
--    SortedPublisher only accepts ordered sets and invocations respect that same order
--    New mandatory usage: SortedPublisher { object1, object2 }
--    SortedPublisher callable now pass object as first parameter (self)

local _G = require "_G"
local pairs = _G.pairs

local table = require "loop.table"
local memoize = table.memoize

local oo = require "loop.base"
local class = oo.class


local SortedPublisher = class{
	__index = memoize(function(method)
		return function(self, ...)
			for _, object in ipairs(self) do
				if object[method] then
					object[method](object, ...)
				end
			end
		end
	end, "k"),
}

function SortedPublisher:__newindex(key, value)
	for _, object in ipairs(self) do
		object[key] = value
	end
end

function SortedPublisher:__call(...)
	for _, object in ipairs(self) do
		object(object,...)
	end
end

return SortedPublisher
