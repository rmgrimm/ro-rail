-- Logging
do
	-- Function to validate the Log formatting
	local function format(base,...)
		-- Find all places that a % operator shows up
		local arg_i = 1
		local front = nil
		local back = 1
		while true do
			-- Find the next match
			front,back = string.find(base,"%%%d-%.?%d-[dfiqs]",back)

			-- Check if an operator was found
			if front == nil then
				-- No more matches, return the formatted string
				return string.format(base,unpack(arg))
			end

			-- Determine the data type required
			local t = string.sub(base,back,back)
			if t == "q" or t == "s" then
				-- String is required
				t = "string"
			else
				-- Number is required
				t = "number"
			end

			-- Check if the arg is correct type
			if type(arg[arg_i]) ~= t then
				-- Not correct type, invalid string
				-- Stop looping
				break
			end

			-- Increment arg number
			arg_i = arg_i + 1
		end

		-- Create a string buffer
		local str = StringBuffer:New()

		-- Fromat to an error
		str:Append(string.format("Invalid format: %q (",base))

		-- Add each argument
		local t
		for arg_i=1,Table.GetN(arg)-1 do
			-- Add the argument type
			str:Append(", "):Append(type(arg[arg_i]))
		end

		-- Add the ending parenthesis and return the string
		return str:Append(")"):Get()
	end

	local antidup = ""
	RAIL.Log = function(level,text,...)
		local str = format(text,unpack(arg))

		-- Check for a duplicate
		if str == antidup then
			-- Duplicate lines get level replaced with "D"
			TraceAI("(D)" .. str)
		else
			-- Prepend the debug level
			TraceAI("(" .. level .. ")" .. str)
		end

		antidup = str
	end
end