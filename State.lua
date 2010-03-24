-- Serialization Functions
--	(based loosely on http://www.lua.org/pil/12.1.2.html)
do
	BasicSerialize = {
		["string"] = function(val)
			return string.format("%q",val)
		end,
		["function"] = function(val)
			return string.format("\"base64:%s\"",RAIL.Base64:Encode(string.dump(val)))
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

-- Loadfile protection
do
	-- Protected loadfile
	RAIL.ploadfile = function(file)
		-- Check for pcall
		if RAIL._G.pcall == nil or type(RAIL._G.pcall) ~= "function" then
			return RAIL._G.loadfile(file)
		end

		-- Run a protected call for loadfile
		local ret1,ret2,ret3 = pcall(RAIL._G.loadfile,file)
	
		-- Check for success
		if ret1 then
			-- Succeeded
			return ret2,ret3
		else
			-- Failed
			return nil,ret2
		end
	end

	-- Protected loadstring
	RAIL.ploadstring = function(string)
		-- Check for pcall
		if RAIL._G.pcall == nil or type(RAIL._G.pcall) ~= "function" then
			return RAIL._G.loadstring(string)
		end

		-- Run a protected call for loadstring
		local ret1,ret2,ret3 = pcall(RAIL._G.loadstring,string)

		-- Check for success
		if ret1 then
			-- Succeeded
			return ret2,ret3
		else
			-- Failed
			return nil,ret2
		end
	end
end

-- State protection
do
	ProtectedEnvironment = function()
		-- Create a table for the environment
		local env = {
			-- Environment
			_VERSION = RAIL._G._VERSION,
			getfenv = RAIL._G.getfenv,
			setfenv = RAIL._G.setfenv,

			-- Memory
			gcinfo = RAIL._G.gcinfo,
			collectgarbage = RAIL._G.collectgarbage,

			-- The ^ operator function
			__pow = RAIL._G.__pow,

			-- Lua loading
			_LOADED = {},
			loadfile = RAIL.ploadfile,
			loadstring = RAIL.ploadstring,
			require = nil,	-- set later

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
		env.require = function(file)
			local _G = getfenv(0)
			if _G._LOADED[file] then
				return _G._LOADED[file]
			end

			-- TODO: Make this function aware of LUA_PATH

			local f = RAIL.ploadfile(file)
			if f then
				_G._LOADED[file] = f() or true
				return _G._LOADED[file]
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

	local types = {
		["function"] = function(data,validate)
			local t = type(data)
			local pregenerated = false

			-- If it's a function return it
			if t == "function" then
				return data
			end

			-- If it's not a string, return the default
			if t ~= "string" then
				return validate[2]
			end

			-- Check if the function is base64 encoded
			if string.sub(data,1,7) == "base64:" then
				-- Decode it
				data = RAIL.Base64:Decode(string.sub(data,8))
				pregenerated = true
			end

			-- Attempt to convert it to a function
			data = RAIL.ploadstring(data)

			-- Check if its nil
			if data == nil then
				-- Return default
				return validate[2]
			end

			-- Check if we need to generate a function
			if not pregenerated then
				data = data()

				-- And again check sanity
				if type(data) ~= "function" then
					return validate[2]
				end
			end

			return data
		end,
		number = function(data,validate)
			-- Check that the data is a number
			if type(data) ~= "number" then
				-- Not a number, so use default instead
				return validate[2]
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
		table = function(data,validate)
			if type(data) ~= "table" then
				return {}
			end

			return data
		end,
		default = function(data,validate)
			if type(data) ~= validate[1] then
				return validate[2]
			end

			return data
		end,
	}
	setmetatable(types,{
		__index = function(t,key)
			return t.default
		end,
	})

	setmetatable(RAIL.Validate,{
		__call = function(self,data,validate)
			-- Verify the validation info
			if type(validate) ~= "table" or (validate[1] == nil and validate.is_subtable == nil) then
				-- Validation impossible
				return data
			end

			-- Use specialized functions to verify data
			if validate.is_subtable then
				return types.table(data,validate)
			else
				return types[validate[1]](data,validate)
			end
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
	local unsaved_t = {}
	local vali_t = {}
	local unsaved_tree = {}

	-- Metatable (built after ProxyTable)
	local metatable = {}

	-- Proxy tables to track "dirty"ness
	local ProxyTable = function(d,v)
		local ret = {
			[data_t] = d,
			[unsaved_t] = {},
			[vali_t] = v,
		}

		setmetatable(ret,metatable)

		return ret
	end

	-- Metatable
	metatable.__index = function(t,key)
		-- Get the data from proxied table
		local data_table = rawget(t,data_t)
		local unsaved_table = rawget(t,unsaved_t)

		local data = unsaved_table[key]
		if data == nil then
			data = data_table[key]
		end

		-- Get the validation information
		local valid = rawget(t,vali_t)
		if type(valid) == "table" and type(valid[key]) == "table" then
			valid = valid[key]
		else
			-- No validating for this
			return data
		end

		-- Check if it's optional
		if data == nil and valid.optional then
			return nil
		end

		-- Validate the data
		local v = RAIL.Validate(data,valid)

		-- Check if the validated data is different
		if v ~= data then
			-- Check if the data was nil and unsaved flag is set
			if data_table[key] == nil and valid.unsaved then
				t[unsaved_t][key] = v
			else
				-- Save new data, and set dirty
				t[data_t][key] = v
				dirty = true
			end
		end

		-- Check if it's a table
		if type(v) == "table" then
			-- Proxy it
			rawset(t,key,ProxyTable(v,valid))

			-- Check if it's an unsaved table
			if t[unsaved_t][key] == v or rawget(t,unsaved_tree) then
				-- Set the unsaved tree information
				rawset(t[key],unsaved_tree,{t,key})
			end

			return t[key]
		end

		-- Return validated data
		return v
	end
	metatable.__newindex = function(t,key,value)
		-- Don't do anything if the value stays the same
		if t[key] == value then
			return
		end

		-- Set dirty
		dirty = true

		-- Set the value
		t[data_t][key] = value

		-- Check if we have unsaved tree information to convert to saved
		while true do
			-- Get tree info for the current table
			local tree_info = rawget(t,unsaved_tree)

			-- Check if it doesn't exist (aka, it's not unsaved)
			if not tree_info then
				-- Stop looping
				break
			end

			-- Remove tree info from table
			rawset(t,unsaved_tree,nil)

			-- Go up a step
			t = tree_info[1]

			-- Convert to saved
			if t[unsaved_t][tree_info[2]] then
				t[data_t][tree_info[2]] = t[unsaved_t][tree_info[2]]
				t[unsaved_t][tree_info[2]] = nil
			end
		end
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

	local KeepInState = { SetOwnerID = true, Load = true, Save = true, [data_t] = true, [unsaved_t] = true, [vali_t] = true }

	-- Set OwnerID function
	rawset(RAIL.State,"SetOwnerID",function(self,id)
		local base = StringBuffer.New():Append("RAIL_State.")
		if not RAIL.SingleStateFile then
			base:Append("%d.")
		end
		base = string.format(base:Get(),id)

		local homu = base .. "homu.lua"
		local merc = base .. "merc.lua"

		if RAIL.Mercenary then
			filename = merc
			alt_filename = homu
		else
			filename = homu
			alt_filename = merc
		end
	end)

	-- Load function
	rawset(RAIL.State,"Load",function(self,forced)
		-- Load file for both ourself and other
		local from_file = filename
		local f_self,err_self = RAIL.ploadfile(filename)
		local f_alt,err_alt = RAIL.ploadfile(alt_filename)

		-- Get the other's name for logging purposes
		local alt_name = "mercenary"
		if RAIL.Mercenary then
			alt_name = "homunculus"
		end

		-- Check if self is nil, but we're forcing a load
		if f_self == nil and forced then
			-- Log it
			RAIL.LogT(3,"Failed to load state from \"{1}\": {2}",filename,err_self)
			RAIL.LogT(3," --> Trying from {1}'s state file.",alt_name)

			-- Check if alt is also nil
			if f_alt == nil then
				-- Log it
				RAIL.LogT(3,"Failed to load state from \"{1}\": {2}",alt_filename,err_alt)

				-- Can't load, just return
				return
			end

			-- Load from the alternate state file
			f_self = f_alt
			from_file = alt_filename
		end

		-- First, load alternate state, to see if we can find RAIL.Other's ID
		if f_alt ~= nil then
			-- Get a clean, safe environment to load into
			local f_G = ProtectedEnvironment()
			setfenv(f_alt,f_G)

			-- Run the function
			f_alt()

			-- Try to find the other's ID
			local id
			if
				type(f_G.rail_state) == "table" and
				type(f_G.rail_state.Information) == "table" and 
				type(f_G.rail_state.Information.SelfID) == "number"
			then
				id = f_G.rail_state.Information.SelfID
			end

			-- Check if we found the other's ID
			if id then
				-- Try to get it from the Actors table
				local other = rawget(Actors,id)

				-- Check if it exists, and isn't already set
				if other and other ~= RAIL.Other then
					-- Log it
					RAIL.LogT(40,"Found owner's {1} ({2}).",alt_name,other)

					-- Set it to RAIL.Other
					RAIL.Other = other

					-- Hook the expire function
					local expire = RAIL.Other.Expire
					RAIL.Other.Expire = function(self,...)
						-- Check if we're still the owner's other
						if RAIL.Other == self then
							-- Log it
							RAIL.LogT(40,"Owner's {1} expired; removing from friends.",alt_name)

							-- Unset (set to RAIL.Self)
							RAIL.Other = RAIL.Self
						end

						-- Return the expire function
						self.Expire = expire

						-- Forward the function call
						return self:Expire(unpack(arg))
					end
				end
			end
		end

		-- Load our state
		if f_self ~= nil then
			-- Get a clean environment
			local f_G = ProtectedEnvironment()
			setfenv(f_self,f_G)

			-- Run the contents of the state file
			f_self()

			-- See if it left us with a workable rail_state object
			local rail_state = f_G.rail_state
			if type(rail_state) ~= "table" then
				-- Log an invalid file
				RAIL.LogT(0,"Error loading state; invalid rail_state object.")
				return
			end
	
			-- Decide if we should load this state
			if rail_state.update or forced then
				self[data_t] = rail_state
				dirty = false

				-- Log it
				RAIL.LogT(3,"Loaded state from \"{1}\".",from_file)

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

				-- Remove all unsaved values
				RAIL.State[unsaved_t] = {}
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
			local f,err = RAIL.ploadfile(RAIL.State.MobIDFile)

			if not f then
				RAIL.LogT(55,"Failed to load MobID file \"{1}\": {2}",RAIL.State.MobIDFile,err)
				return
			end

			-- Protect RAIL from any unwanted code
			local env = ProtectedEnvironment()
			setfenv(f,env)

			-- Run the MobID function
			f()

			-- Check for the creation of a MobID table
			if type(env.MobID) ~= "table" then
				RAIL.LogT(55,"MobID file \"{1}\" failed to load MobID table.",RAIL.State.MobIDFile)
				return
			end

			-- Log it
			RAIL.LogT(55,"MobID table loaded from \"{1}\".",RAIL.State.MobIDFile)

			-- Add RAIL's MobID update function
			env.MobID.Update = self.Update

			-- Set the update time
			env.MobID[priv_key] = GetTick()

			-- Save it as our own MobID
			MobID = env.MobID
		end
	else
		-- And homunculi save the MobID file
		MobID.Update = function(self)
			-- Check if the MobID file needs to be saved
			if not self.Save then
				-- Nothing needs to be saved
				return
			else
				-- Unset the save flag
				self.Save = nil
			end

			-- Check if it's too soon to update
			if math.abs(self[priv_key] - GetTick()) < 100 then
				return
			end

			-- Create a simply serialized string (no need for full serialization)
			local buf = StringBuffer.New()
				:Append("MobID = {}\n")
			for key,value in self do
				if type(key) == "number" then
					buf:Append("MobID["):Append(key):Append("] = "):Append(value):Append("\n")
				end
			end

			-- Save the state to a file
			local file = io.open(RAIL.State.MobIDFile,"w")
			if file ~= nil then
				file:write(buf:Get())
				file:close()

				RAIL.Log(55,"MobID table saved to %q.",RAIL.State.MobIDFile)
			end

			-- Set the update time
			self[priv_key] = GetTick()
		end
	end
end
