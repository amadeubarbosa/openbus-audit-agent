-- The MIT License (MIT)
-- Copyright (c) 2017 Amadeu A. Barbosa Junior (amadeu@tecgraf.puc-rio.br)
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

---
-- Base64 encoding was ported back to Lua5.2 from http://lua-users.org/wiki/BaseSixtyFour
-- Base64 decoding was written by Patrick Donnelly <batrick@batbytes.com> 
--        and its original version is available https://svn.nmap.org/nmap/nselib/base64.lua


local bit32 = require "bit32"
local rshift = bit32.rshift
local lshift = bit32.lshift
local band = bit32.band
local bor = bit32.bor

local table = require "table"
local concat = table.concat

local b64table = { [0] =
   'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
   'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
   'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
   'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/',
}

---
-- Encodes a string to Base64. Reference: http://lua-users.org/wiki/BaseSixtyFour
-- @param bdata Data to be encoded.
-- @return Base64-encoded string.
local function encode(str)
   local pad = 2 - ((#str-1) % 3)
   str = string.gsub(str..string.rep('\0', pad), "...", function(cs)
      local a, b, c = string.byte(cs, 1, 3)
      return b64table[rshift(a,2)] ..
             b64table[bor(lshift(band(a,0x3),4),rshift(b,4))] ..
             b64table[bor(lshift(band(b,0xf),2),rshift(c,6))] ..
             b64table[band(c,0x3f)]
   end)
   return string.sub(str, 1, #str-pad) .. string.rep('=', pad)
end

local db64table = setmetatable({}, {__index = 
  function (t, k) error "invalid encoding: invalid character" end
  })
do
  local r = {["="] = 0}
  for i, v in ipairs(b64table) do
      r[v] = i
  end
  for i = 0, 255 do
      db64table[i] = r[string.char(i)]
  end
end

---
-- Decodes Base64-encoded data. Reference: https://svn.nmap.org/nmap/nselib/base64.lua
-- @param b64data Base64 encoded data.
-- @return Decoded data.
local function decode(b64)
  local out = {}
  local i = 1
  local done = false

  local b64 = string.gsub(b64, "%s+", "")

  local m = #b64 % 4
  if m ~= 0 then
    error "invalid encoding: input is not divisible by 4"
  end

  while i+3 <= #b64 do
    if done then
      error "invalid encoding: trailing characters"
    end

    local a, b, c, d = string.byte(b64, i, i+3)

    local x = bor(band(lshift(db64table[a],2),0xfc), band(rshift(db64table[b],4),0x03))
    local y = bor(band(lshift(db64table[b],4),0xf0), band(rshift(db64table[c],2),0x0f))
    local z = bor(band(lshift(db64table[c],6),0xc0), band(db64table[d],0x3f))

    if c == 0x3d then
      assert(d == 0x3d, "invalid encoding: invalid character")
      out[#out+1] = string.char(x)
      done = true
    elseif d == 0x3d then
      out[#out+1] = string.char(x, y)
      done = true
    else
      out[#out+1] = string.char(x, y, z)
    end
    i = i + 4
  end

  return concat(out)
end

return {
  encode = encode,
  decode = decode
}
