-- Serialization Functions
--	(based loosely on http://www.lua.org/pil/12.1.2.html)
do
	BasicSerialize = {
		string = function(val)
			return string.format("%q",val)
		end,
	}
	setmetatable(BasicSerialize,{
		__call = function(self,val)
			local t = type(val)

			-- Specialized functions
			if self[t] ~= nil then
				return self[t](val)
			end

			-- Generic serialization
			return string.format("%s",tostring(val))
		end
	})

	Serialize = {}
	setmetatable(Serialize,{
		__call = function(self,name,val,saved,ret)
			ret = ret or StringBuffer:New()
			local t = type(val)

			ret:Append(name):Append(" = ")

			-- Specialized serialization
			if self[t] ~= nil then
				ret:Append(self[t](name,val,saved,ret))

			-- Generic serialization
			else
				ret:Append(BasicSerialize(val))
			end

			return ret:Get()
		end,
	})

	Serialize.table = function(name,val,saved,ret)
		saved = saved or {}

		-- If it's already been serialized, use the existing name
		if saved[val] then
			return saved[val]
		end

		-- Save this name
		saved[val] = name

		-- Serialize each element
		ret:Append("{}\n")

		local k,v
		for k,v in pairs(val) do
			local field = string.format("%s[%s]",name,BasicSerialize(k))

			Serialize(field,v,saved,ret)
			ret:Append("\n")
		end

		return ""
	end
end

-- Config validation
do
	RAIL.Validate = {
		-- Name = {type, default, numerical min, numerical max }
	}

	setmetatable(RAIL.Validate,{
		__call = function(self,key,value)
			-- If it's not in our table, then it doesn't need to be validated
			local validate = self[key]
			if not validate then
				return value
			end

			-- Verify the type
			local t = type(value)
			if t ~= validate[1] then
				-- Return default
				return validate[2]
			end

			-- Non-numericals are now valid
			if t ~= "number" then
				return value
			end

			-- Validate that the number is greater or equal to the minimum
			if validate[3] and value < validate[3] then
				-- Below the minimum, so return minimum instead
				return validate[3]
			end

			-- Validate that the number is less or equal to the maximum
			if validate[4] and value > validate[4] then
				-- Above the maximum, so return maximum instead
				return validate[4]
			end

			-- Return the number, it's in range
			return value
		end,
	})
end

-- State persistence
do
	-- Private key to keep track of "dirty" (unsaved) state data
	local dirty = {}

	-- Private key to hold the table of state data
	local state = {}

	-- Private key to hold the state filename
	local filename = {}

	-- Main interface to state information
	RAIL.State = {
		-- Is data "dirty"?
		[dirty] = false,

		-- Persistent data table
		[state] = {},

		[filename] = "",

		-- Function to save the data
		Save = function(self,forced)
			-- Only save the state if it's changed
			if not forced and not self[dirty] then
				return
			end

			-- Unset dirty state
			self[dirty] = false

			-- Save the state to a file
			local file = io.open(self[filename],"w")
			if file ~= nil then
				file:write(Serialize("rail_state",self[state]))
				file:close()
			end

			RAIL.Log(0,"Saved state to %s",self[filename])
		end,
		Load = function(self,forced)
			-- Make sure we have a proper filename
			if self[filename] == "" then
				self[filename] = string.format("RAIL_State.%d.lua",RAIL.Owner.ID)
			end

			-- Do nothing if the file doesn't exist
			local f,err = loadfile(self[filename])

			if f == nil then
				if forced then
					RAIL.Log(0,"Failed to load state from %s: %s",self[filename],tostring(err))
				end
				return
			end

			-- Run the function
			f()

			-- See if it left us with a workable state
			if type(rail_state) ~= "table" then
				-- TODO: Log invalid state?
				return
			end

			-- Decide if we should load this state
			if rail_state.update or forced then
				self[state] = rail_state
				self[dirty] = false
				RAIL.Log(0,"Loaded state from %s",self[filename])

				-- Resave with the update flag off if we need to
				if self[state].update then
					self[state].update = false

					-- Save the state to a file
					local file = io.open(self[filename],"w")
					if file ~= nil then
						file:write(Serialize("rail_state",self[state]))
						file:close()
					end
				end
			end

			-- Reset the rail_state object back to normal
			rail_state = nil
		end,
	}

	-- TODO:
	--	setup some functions to apply proxying metatables to sub-tables within
	--	RAIL.State[state]
	--		* - clear them whenever the table reloaded via RAIL.State.Load

	-- Force RAIL.State to act as a proxy to sub state table
	setmetatable(RAIL.State,{
		__index = function(t,key)
			-- Validate the data from our proxied table
			local v = RAIL.Validate(key,t[state][key])

			-- Check if the validated data is different
			if v ~= t[state][key] then
				-- Save new data, and set dirty
				t[state][key] = v
				t[dirty] = true
			end

			-- And return it
			return t[state][key]
		end,
		__newindex = function(t,key,val)
			-- Don't set to the same value
			if t[state][key] == val then
				return
			end

			-- Set dirty
			t[dirty] = true

			-- Set the state value
			t[state][key] = val
		end,
	})
end