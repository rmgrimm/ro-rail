-- State validation
RAIL.Validate.DebugLevel = {"number",10,nil,99}
RAIL.Validate.ProfileMark = {"number",20000,2000,nil}

-- Log Levels:
--
--	 1 - User commands
--	 2 - Actor ignore
--	 3 - State load/save
--	 5 - Performance data
--	 7 - Cycle operation change
--	10 - Actor creation; actor expiration; actor-type Change
--
--

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
		if tonumber(level) > RAIL.State.DebugLevel then
			return
		end

		local str = format(text,unpack(arg))

		-- Check for a duplicate
		if str == antidup then
			-- Duplicate lines get level replaced with "D"
			TraceAI("(DD) " .. str)

			-- Don't anti-dup next time
			str = nil
		else
			-- Prepend the debug level
			TraceAI(string.format("(%2d) %s",level,str))
		end

		antidup = str
	end
end

-- Performance Monitoring
do
	-- metatable
	local mt = {
		__call = function(self,...)
			-- Note the beginning time
			self.begin = GetTick()

			-- Determine the time between calls
			if self.end_time ~= nil then
				self.TicksBetween = self.TicksBetween + (self.begin - self.end_time)
			end

			-- Call the function
			local ret = {self.func(unpack(arg))}

			-- Get the end time
			self.end_time = GetTick()

			-- Update variables
			local delta = self.end_time - self.begin

			self.TicksSpent = self.TicksSpent + delta
			if delta > self.TicksLongest then
				self.TicksLongest = delta
			end
			self.CyclesRun = self.CyclesRun + 1

			-- Output the data if enough time has passed
			if self.last_output + RAIL.State.ProfileMark < GetTick() then
				RAIL.Log(self.level,string.format(
					" -- %s mark (%dms since last; %dms longest; %dms avg cycle; %dms avg between) -- ",
					self.name,
					GetTick() - self.last_output,
					self.TicksLongest,
					self.TicksSpent / self.CyclesRun,
					self.TicksBetween / self.CyclesRun
				))

				self.TicksLongest = 0
				self.TicksSpent = 0
				self.TicksBetween = 0
				self.CyclesRun = 0
				self.last_output = GetTick()
			end


		end,
	}

	ProfilingHook = function(n,f,l)
		local ret = {
			name = n,
			func = f,
			level = l,
			last_output = GetTick(),
			TicksBetween = 0,
			TicksSpent = 0,
			TicksLongest = 0,
			CyclesRun = 0,
		}

		setmetatable(ret,mt)

		return ret
	end
end