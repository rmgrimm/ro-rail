-- State validation
RAIL.Validate.DebugLevel = {"number",50,nil,99}
RAIL.Validate.DebugFile = {"string","RAIL_Log.txt"}
RAIL.Validate.ProfileMark = {"number",20000,2000,nil}

-- Log Levels:
--
--	 0 - Errors / critical information
--	 1 - User commands
--	 3 - State load/save
--	 7 - Cycle operation change
--	20 - Actor ignore
--	40 - Actor creation/expiration; actor type-change
--	50 - RAIL.AI Performance logging
--	55 - MobID save/load
--	60 - Skill commands (sent to server)
--	75 - Attack commands (sent to server)
--	80 - Movement estimation
--	85 - Move commands (sent to server)
--	90 - TODO: Actor data tracking
--	95 - Targetting sieves
--	98 - TODO: Performance logging; all calls
--
--

-- Logging
do
	-- Function to validate the input to string.format
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

	-- Function to format using {arg1}, {arg2}, ..., {argn} instead of %d %s %q
	local function formatT(base,...)
		local front = nil
		local back = 0
		local buf = StringBuffer.New()
		while true do
			-- Save the position of the back
			local prev = back

			-- Find the next match
			front,back = string.find(base,"{%d+}",back)

			-- Check for no match
			if front == nil then
				-- Append the rest of the string to the buffer
				buf:Append(string.sub(base,prev+1))

				-- Return the buffer
				return buf:Get()
			end

			-- Copy data to the string buffer
			buf:Append(string.sub(base,prev+1,front-1))

			-- Get the argument number
			local n = tonumber(string.sub(base,front+1,back-1))

			-- Append the argument to the string buffer
			buf:Append(arg[n])
		end
	end

	-- Log output function
	local log_out = TraceAI

	-- If not using TraceAI, generate a function to output to a file
	if not RAIL.UseTraceAI then
		log_out = function(str)
			-- Get the filename
			local filename = RAIL.State.DebugFile

			-- Open the file for appending
			local file = io.open(filename,"a")

			-- Check for non-nil
			if file ~= nil then
				-- Get the date and time
				local date_t = os.date("!*t")

				-- Write the string, with a date stamp on it too
				file:write(string.format("%4.4d-%2.2d-%2.2d %2.2d:%2.2d:%2.2d UTC %s\n",
					date_t.year,date_t.month,date_t.day,date_t.hour,date_t.min,date_t.sec,
					str))

				-- Close the file
				file:close()
			end
		end
	end

	-- Generalized log function
	local antidup = ""
	local function log(func,t,level,text,...)
		if type(level) ~= "number" then
			RAIL.LogT(0,"Missing level parameter for base text: {1}",level)
			return RAIL.LogT(0,level,text,unpack(arg))
		end
		if level > RAIL.State.DebugLevel then
			return
		end

		-- TODO: Finish translation support
		if t and false then
			local translate_table = {}
			text = translate_table[text]
		end

		-- Build the string to send to TraceAI
		local buf = StringBuffer.New():Append("(")

		-- Insert the args into the base text
		local str = func(text,unpack(arg))

		-- Check for a duplicate
		if str == antidup then
			-- Duplicate lines get level replaced with "D"
			buf:Append("DD")

			-- Don't anti-dup next time
			antidup = nil
		else
			-- Add the level to the line
			buf:Append(string.format("%2d",level))

			-- Don't duplicate if the next log is the same
			antidup = str
		end

		-- Add the mercenary or homunculus flag
		if RAIL.Mercenary then
			buf:Append("m")
		else
			buf:Append("h")
		end

		-- Add the string to the buffer
		buf:Append(") "):Append(str)

		-- And send it to the Log-output function (usually TraceAI)
		log_out(buf:Get())
	end

	-- Old-style logging
	RAIL.Log = {
		-- Hidden flag to disable logging
		Disabled = false,
	}
	setmetatable(RAIL.Log,{
		__call = function(self,level,text,...)
			if not self.Disabled then
				return log(format,false,level,text,unpack(arg))
			end
		end,
	})

	-- New-style logging; translatable
	RAIL.LogT = function(level,text,...)
		if not RAIL.Log.Disabled then
			return log(formatT,true,level,text,unpack(arg))
		end
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
				RAIL.LogT(self.level,
					" -- {1} mark ({2}ms since last; {3}ms longest; {4}ms avg cycle; {5}ms avg between) -- ",
					self.name,
					GetTick() - self.last_output,
					self.TicksLongest,
					RoundNumber(self.TicksSpent / self.CyclesRun),
					RoundNumber(self.TicksBetween / self.CyclesRun)
				)

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