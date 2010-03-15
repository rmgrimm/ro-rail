-- Bitwise shift functions
local function lsh(v,shift)
	return math.mod((v*(2^shift)),256)
end
local function rsh(v,shift)
	return math.floor(v/2^shift)
end

RAIL.Base64 = {
	-- The 64 characters that will be used for Base64 encoding/decoding,
	--	plus one more for placeholding
	--	Note: Base64 encoding is NOT encryption.
	Table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=",

	-- The function to encode a set of data
	Encode = function(self,input)
		-- Sets of 3 characters get converted to sets of 4 character output

		local t = self.Table
		local output = StringBuffer.New()

		local len = string.len(input)
		local bytes = {}

		-- Encode three bytes at a time
		for i=0,len-1,3 do
			bytes[1] = 0
			for j=1,3 do
				local working = string.byte(input,i+j) or 0

				bytes[j] = string.byte(t,
					bytes[j] + rsh(working,j*2)
				+1)
				bytes[j+1] = math.mod(lsh(working,6-j*2),64)
			end
			bytes[4] = string.byte(t,math.mod(bytes[4],64)+1)

			-- Fix placeholders
			if len-i < 3 then bytes[4] = string.byte(t,65) end
			if len-i < 2 then bytes[3] = string.byte(t,65) end

			-- Add 4 bytes to the output buffer
			output:Append(string.char(unpack(bytes)))
		end

		return output:Get()
	end,
	Decode = function(self,input)
		-- Sets of 4 characters get converted back to sets of 3 ASCII characters

		local t = self.Table
		local output = StringBuffer.New()

		local len = string.len(input)
		for i=0,len-1,4 do
			for j=1,3 do
				-- Get the two bytes that make up the character
				local byte1 = string.find(t,string.sub(input,i+j,i+j),1,true) - 1
				local byte2 = string.find(t,string.sub(input,i+j+1,i+j+1),1,true) - 1

				-- Check for placeholders
				if byte1 == 64 or byte2 == 64 then break end

				-- Add the character
				output:Append(string.char(
					lsh(byte1,j*2) + rsh(byte2,6-j*2)
				))
			end
		end

		return output:Get()
	end,
}
