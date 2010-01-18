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
		ret:Append("{}")

		local k,v
		for k,v in pairs(val) do
			local field = string.format("%s[%s]",name,BasicSerialize(k))

			ret:Append("\n")
			Serialize(field,v,saved,ret)
		end

		return ""
	end
end

-- State protection
do
	ProtectedEnvironment = function()
		-- Create a table for the environment
		local env = {
			-- Environment
			getfenv = RAIL._G.getfenv,
			setfenv = RAIL._G.setfenv,

			-- The ^ operator function
			__pow = RAIL._G.__pow,

			-- Lua loading
			loadfile = RAIL._G.loadfile,

			-- Ragnarok API
			TraceAI = RAIL._G.TraceAI,
			MoveToOwner = RAIL._G.MoveToOwner,
			Move = RAIL._G.Move,
			Attack = RAIL._G.Attack,
			GetV = RAIL._G.GetV,
			GetActors = RAIL._G.GetActors,
			GetTick = RAIL._G.GetTick,
			GetMsg = RAIL._G.GetMsg,
			GetResMsg = RAIL._G.GetResMsg,
			SkillObject = RAIL._G.SkillObject,
			SkillGround = RAIL._G.SkillGround,
			IsMonster = RAIL._G.IsMonster,
		}

		-- Create a new require function so setfenv on the original function won't result in strange behavior
		local private_key = {}
		env[private_key] = {}
		env.require = function(file)
			local _G = getfenv(0)
			if _G[private_key][file] then
				return
			end

			local f = loadfile(file)
			if f then
				_G[private_key][file] = true
				f()
			end
		end
		setfenv(env.require,env)

		-- return the environment
		return env
	end
end

-- Config validation
do
	RAIL.Validate = {
		-- Name = {type, default, numerical min, numerical max }
		-- Subtable = {is_subtable = true}
	}

	setmetatable(RAIL.Validate,{
		__call = function(self,data,validate)
			-- Verify the validation info
			if type(validate) ~= "table" or (validate[1] == nil and validate.is_subtable == nil) then
				return data
			end

			-- Verify the type
			local t = type(data)
			if
				(not validate.is_subtable and t ~= validate[1]) or
				(validate.is_subtable and t ~= "table")
			then
				-- If it should be a table, return a brand new table
				if validate.is_subtable then
					return {}
				end

				-- Return default
				return validate[2]
			end

			-- Non-numericals are now valid
			if t ~= "number" then
				return data
			end

			-- Validate that the number is greater or equal to the minimum
			if validate[3] and data < validate[3] then
				-- Below the minimum, so return minimum instead
				return validate[3]
			end

			-- Validate that the number is less or equal to the maximum
			if validate[4] and data > validate[4] then
				-- Above the maximum, so return maximum instead
				return validate[4]
			end

			-- Return the number, it's in range
			return data
		end,
	})
end

-- State persistence
do
	-- Is data "dirty" ?
	local dirty = false

	-- Filename to load/save from
	local filename

	-- Alternate filename to load from
	local alt_filename

	-- Private keys to data and validation tables
	local data_t = {}
	local vali_t = {}

	-- Metatable (built after ProxyTable)
	local metatable = {}

	-- Proxy tables to track "dirty"ness
	local ProxyTable = function(d,v)
		local ret = {
			[data_t] = d,
			[vali_t] = v,
		}

		setmetatable(ret,metatable)

		return ret
	end

	-- Metatable
	metatable.__index = function(t,key)
		-- Get the data from proxied table
		local data = t[data_t][key]

		-- Validate it
		local valid = t[vali_t][key]
		local v = RAIL.Validate(data,valid)

		-- Check if the validated data is different
		if v ~= data then
			-- Save new data, and set dirty
			t[data_t][key] = v
			dirty = true
		end

		-- Check if it's a table
		if type(v) == "table" then
			-- Proxy it
			return ProxyTable(v,valid)
		end

		-- Return validated data
		return v
	end
	metatable.__newindex = function(t,key,value)
		-- Don't do anything if the value stays the same
		if t[data_t][key] == value then
			return
		end

		-- Set dirty
		dirty = true

		-- Set the value
		t[data_t][key] = value
	end

	-- Setup RAIL.State
	RAIL.State = ProxyTable({},RAIL.Validate)

	-- Save function
	rawset(RAIL.State,"Save",function(self,forced)
		-- Only save the state if it's changed
		if not forced and not dirty then
			return
		end

		-- Unset dirty state
		dirty = false

		-- Save the state to a file
		local file = io.open(filename,"w")
		if file ~= nil then
			file:write(Serialize("rail_state",self[data_t]).."\n")
			file:close()
		end

		RAIL.Log(3,"Saved state to %q",filename)
	end)

	local KeepInState = { Load = true, Save = true, [data_t] = true, [vali_t] = true }

	-- Load function
	rawset(RAIL.State,"Load",function(self,forced)
		-- Make sure we have a proper filename
		if not filename then
			local base = string.format("RAIL_State.%d.",RAIL.Owner.ID)
			local homu = base .. "homu.lua"
			local merc = base .. "merc.lua"
			if RAIL.Mercenary then
				filename = merc
				alt_filename = homu
			else
				filename = homu
				alt_filename = merc
			end
		end

		-- Do nothing if the file doesn't exist
		local f,err = loadfile(filename)
		local from_alt = false

		if f == nil then
			if forced then
				RAIL.Log(3,"Failed to load state from %q: %s",filename,tostring(err))

				if RAIL.Mercenary then
					RAIL.LogT(3,"Loading state from homunculus's state file.")
				else
					RAIL.LogT(3,"Loading state from mercenary's state file.")
				end

				f,err = loadfile(alt_filename)
				from_alt = true

				if f == nil then
					RAIL.Log(3,"Failed to load state from %q: %s",alt_filename,tostring(err))
					return
				end
			else
				-- Can't load, and not forced
				return
			end
		end

		-- Generate a clean state for loading the config
		local f_G = ProtectedEnvironment()

		-- Set the environment that the function will run in; protect RAIL from config-file code
		setfenv(f,f_G)

		-- Run the function
		f()

		-- See if it left us with a workable state
		local rail_state = f_G.rail_state
		if type(rail_state) ~= "table" then
			-- TODO: Log invalid state?
			return
		end

		-- Decide if we should load this state
		if rail_state.update or forced then
			self[data_t] = rail_state
			dirty = false
			if from_alt then
				RAIL.Log(3,"Loaded state from %q.",alt_filename)
			else
				RAIL.Log(3,"Loaded state from %q.",filename)
			end

			-- Resave with the update flag off if we need to
			if self[data_t].update then
				self[data_t].update = false

				-- Save the state to a file
				local file = io.open(filename,"w")
				if file ~= nil then
					file:write(Serialize("rail_state",self[data_t]))
					file:close()
				end
			end

			-- Clear any proxied tables in RAIL.State
			local k,v
			for k,v in pairs(RAIL.State) do
				if not KeepInState[k] then
					RAIL.State[k] = nil
				end
			end
		end
	end)
end

-- MobID
do
	-- Mob ID file
	RAIL.Validate.MobIDFile = {"string","./AI/USER_AI/Mob_ID.lua"}

	-- Update-time private key
	local priv_key = {}

	-- Default MobID table
	MobID = {
		[priv_key] = 0,
	}

	if RAIL.Mercenary then
		-- Mercenaries load the Mob ID file
		MobID.Update = function(self)
			-- Check if it's too soon to update
			if math.abs(self[priv_key] - GetTick()) < 100 then
				return
			end

			-- Try to load the MobID file into a function
			local f,err = loadfile(RAIL.State.MobIDFile)
	
			if not f then
				RAIL.Log(55,"MobID file %q failed to load: %s",RAIL.State.MobIDFile,err)
				return
			end
	
			-- Protect RAIL from any unwanted code
			local env = ProtectedEnvironment()
			setfenv(f,env)
	
			-- Run the MobID function
			f()
	
			-- Check for the creation of a MobID table
			if type(f.MobID) ~= "table" then
				RAIL.Log(55,"MobID file %q failed to load MobID table.",RAIL.State.MobIDFile)
				return
			end

			-- Log it
			RAIL.Log(55,"MobID table loaded from %q.",RAIL.State.MobIDFile)

			-- Add RAIL's MobID update function
			f.MobID.Update = self.Update

			-- Set the update time
			f.MobID[priv_key] = GetTick()

			-- Save it as our own MobID
			MobID = f.MobID
		end
	else
		-- And homunculi save the MobID file
		MobID.Update = function(self)
			-- Check if it's too soon to update
			if math.abs(self[priv_key] - GetTick()) < 100 then
				return
			end

			-- Temporarily remove the update function
			local update = self.Update
			self.Update = nil
	
			-- Save the state to a file
			local file = io.open(RAIL.State.MobIDFile,"w")
			if file ~= nil then
				file:write(Serialize("MobID",self).."\n")
				file:close()
			end
	
			RAIL.Log(55,"MobID table saved to %q.",RAIL.State.MobIDFile)
	
			-- Restore the save and load functions
			self.Update = update

			-- Set the update time
			self[priv_key] = GetTick()
		end
	end
end
