-- A few persistent-state options used
RAIL.Validate.TempFriendRange = {"number",-1,-1,5}

-- Mob ID Support
do
	-- Mob ID State-Options
	RAIL.Validate.MobIDFile = {"string","./AI/USER_AI/Mob_ID.lua"}

	--	Note: Possible MobIDMode values are set in the RAIL.MobID.Init function
	RAIL.Validate.MobIDMode = {"string","automatic"}

	-- Private data key
	local key = {}

	GetType = {
		-- Modes take the form of:
		--	[1] -> boolean; load MobID table at start
		--	[2] -> function to get monster type from ID
		[true] = {
			["disabled"] = {
				false,
				function(self,id)
					-- Just return the type
					return GetV(self[key].SaneGetType,id)
				end,
			},
			["automatic"] = {
				false,
				function(self,id)
					if RAIL.Other == RAIL.Self or RAIL.Other == nil then
						-- If not paired with another RAIL, don't use Mob ID
						return GetType[true].disabled[2](self,id)
					end

					-- Otherwise, use "overwrite"
					return GetType[true].overwrite[2](self,id)
				end,
			},
			["update"] = {
				true,
				function(self,id)
					-- After the first init, works exactly like "overwrite"
					return GetType[true].overwrite[2](self,id)
				end,
			},
			["overwrite"] = {
				false,
				function(self,id)
					-- Get the type from disabled
					local type = GetType[true].disabled[2](self,id)

					-- Check for change
					if type ~= self[key].Map[id] then
						-- Force an update
						self[key].ForceUpdate = true
					end

					-- Store it in the MobID table
					self[key].Map[id] = type

					-- Return the type
					return type
				end,
			},
		},
		[false] = {
			["disabled"] = {
				false,
				function(self,id)
					return -2
				end,
			},
			["automatic"] = {
				false,
				function(self,id)
					if RAIL.Other == RAIL.Self or RAIL.Other == nil then
						-- If not paired with another RAIL, don't use Mob ID
						return GetType[false].disabled[2](self,id)
					end

					-- Otherwise, use "active"
					return GetType[false].active[2](self,id)
				end,
			},
			["once"] = {
				true,
				function(self,id)
					-- Return the Type ID if known, or disabled value
					return self[key].Map[id] or GetType[false].disabled[2](self,id)
				end,
			},
			["active"] = {
				false,
				function(self,id)
					local type = self[key].Map[id]

					if type == nil then
						-- Force an update
						self[key].ForceUpdate = true

						-- Get from disabled
						type = GetType[false].disabled[2](self,id)
					end

					return type
				end,
			},
		},
	}
	local GetType_mt = {
		__call = function(self,self2,id)
			return self[string.lower(RAIL.State.MobIDMode)][2](self2,id)
		end,
	}
	setmetatable(GetType[true],GetType_mt)
	setmetatable(GetType[false],GetType_mt)

	local Update = {
		-- Valid; save types
		[true] = function(self)
			-- Create a simply serialized string (no need for full serialization)
			local buf = StringBuffer.New()
				:Append("MobID = {}\n")
			for key,value in self[key].Map do
				buf:Append("MobID["):Append(key):Append("] = "):Append(value):Append("\n")
			end

			-- Save the state to a file
			local file = io.open(RAIL.State.MobIDFile,"w")
			if file ~= nil then
				file:write(buf:Get())
				file:close()

				RAIL.LogT(55,"MobID table saved to \"{1}\".",RAIL.State.MobIDFile)
			end
		end,
		-- Invalid; load types
		[false] = function(self)
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
				RAIL.LogT(55,"File \"{1}\" failed to load MobID table.",RAIL.State.MobIDFile)
				return
			end
	
			-- Log it
			RAIL.LogT(55,"MobID table loaded from \"{1}\".",RAIL.State.MobIDFile)

			-- Set it to our Map table
			self[key].Map = env.MobID
		end,
	}

	-- Setup RAIL's Mob ID table
	RAIL.MobID = {
		[key] = {
			Update = nil,		-- function; set later
			GetType = nil,		-- function; set later
			SaneGetType = nil,	-- number; set later
			ForceUpdate = false,
			Map = {}		-- table; map of ID->type
		},
	}
	setmetatable(RAIL.MobID,{
		__index = function(self,id)
			-- Make sure we're initialized
			if not self[key].GetType then
				return -1
			end

			-- Return the type
			return self[key].GetType(self,id)
		end,
	})

	local TypeNums = {
		V_HOMUNTYPE,
		-- never sane: V_MERTYPE,
	}

	RAIL.MobID.Init = function(self)
		-- Check for a sane GetType
		for i,V_ in TypeNums do
			if GetV(V_,RAIL.Owner.ID) ~= nil then
				self[key].SaneGetType = V_
				break
			end
		end

		-- Set valid options (and handlers) for MobIDMode
		local types = GetType[self[key].SaneGetType ~= nil]
		RAIL.Validate.MobIDMode[3] = types
		self[key].GetType = types

		-- Set the update function
		self[key].Update = Update[self[key].SaneGetType ~= nil]

		-- Check if the mode is set to load table on startup
		if types[string.lower(RAIL.State.MobIDMode)][1] then
			self[key].Update(self)
		end

		-- Setup a timeout to load/save the MobID file at regular intervals
		-- Note: RAIL._G.debug only appears in lua.exe, not in ragexe.exe
		if not RAIL._G.debug then
			self[key].Timeout = RAIL.Timeouts:New(250,true,function(self)
				-- Check if an update is forced
				if not self[key].ForceUpdate then
					return
				end

				-- Unset ForceUpdate
				self[key].ForceUpdate = false

				-- Run the update function
				return self[key].Update(self)
			end,self)
		end

		-- Remove the init function from self
		self.Init = nil
	end
end

-- Actor data-collection
do
	-- This unique table ID will be used as a key to identify Actor tables
	local actor_key = {}

	RAIL.IsActor = function(actor)
		if type(actor) ~= "table" then return false end
		if actor[actor_key] == nil then return false end
		return true
	end

	-- The Actor "class" is private, because they're generated by referencing Actors
	local Actor = { }

	-- Metatables
	local Actor_mt = {
		__eq = function(self,other)
			if not RAIL.IsActor(other) then return false end

			return self.ID == other.ID
		end,

		__index = Actor,

		-- When tostring() is called on Actors, we want sensible output
		__tostring = function(self)
			local buf = StringBuffer.New()
				:Append(self.ActorType):Append(" #"):Append(self.ID)
				:Append(" [Loc:(")
					:Append(self.X[0]):Append(","):Append(self.Y[0])
				:Append(")")

			if self.Type ~= -2 then
				buf:Append(", Type:"):Append(self.Type)
			end

			if self.BattleOpts.Name ~= RAIL.State.ActorOptions.Default.Name then
				buf:Append(", Name:"):Append(self.BattleOpts.Name)
			end

			return buf:Append("]"):Get()
		end
	}

	-- Private key for keeping closures
	local closures = {}

	-- Private key of TargetOf, to keep the time of last table update
	local targeted_time = {}

	-- Position tracking uses a specialty "diff" function
	local pos_diff = function(a,b)
		-- If a tile changed, then the position is different
		if math.abs(a[1]-b[1]) >= 1 then return true end

		-- If enough time has passed, count the position as different
		--	Note: This ensures that subvalues will be accurately calculated
		--	Note: This isn't really needed...
		--if math.abs(a[2]-b[2]) > 500 then return true end

		-- Otherwise, the position is still the same
		return false
	end

	-- BattleOpts metatable
	local battleopts_parent = {}
	local battleopts_mt = {
		__index = function(self,key)
			self = self[battleopts_parent]

			-- First, check ByID table
			local ret = RAIL.State.ActorOptions.ByID[self.ID][key]
			if ret ~= nil then
				return ret
			end

			-- Then, check ByType table
			if self.Type ~= -2 then
				ret = RAIL.State.ActorOptions.ByType[self.Type][key]
				if ret ~= nil then
					return ret
				end
			end

			-- If all else fails, use the defaults
			return RAIL.State.ActorOptions.Default[key]
		end,
	}

	-- Initialize a new Actor
	Actor.New = function(self,ID)
		local ret = { }
		setmetatable(ret,Actor_mt)

		ret.ActorType = "Actor"
		ret.ID = ID
		ret.Active = false		-- false = expired; true = active
		ret.Type = -1			-- "fixed" type (homus don't overlap players)
		ret.Hide = false		-- hidden?
		ret.LastUpdate = -1		-- GetTick() of last :Update() call
		ret.FullUpdate = false		-- Track position, motion, target, etc?
		ret.TargetOf = Table:New()	-- Other Actors that are targeting this one
		ret.IgnoreTime = -1		-- Actor isn't currently ignored
		ret.BattleOpts = { }		-- Battle options
		ret.BattleOpts[battleopts_parent] = ret

		-- Set defaults for battle options
		setmetatable(ret.BattleOpts,battleopts_mt)

		-- The following have their histories tracked
		ret.Target = History.New(-1,false)
		ret.Motion = History.New(MOTION_STAND,false)

		-- And they'll also predict sub-history positions
		ret.X = History.New(-1,true,pos_diff)
		ret.Y = History.New(-1,true,pos_diff)

		-- Set initial position
		local x,y = GetV(V_POSITION,ret.ID)
		if x ~= -1 then
			-- Hiding?
			if x == 0 and y == 0 then
				ret.Hide = true
			else
				History.Update(ret.X,RoundNumber(x))
				History.Update(ret.Y,RoundNumber(y))
			end
		end

		-- Set up the expiration timeout for 2.5 seconds...
		--	(it will be updated in Actor.Update)
		ret.ExpireTimeout = RAIL.Timeouts:New(2500,false,Actor.Expire,ret,"timeout")

		-- Create tables to hold the closures
		ret[closures] = {
			DistanceTo = {},
			BlocksTo = {},
			AngleTo = {},
			AngleFrom = {},
			AnglePlot = {},
		}

		-- Initialize the type
		Actor[actor_key](ret)

		-- Log
		if ID ~= -1 then
			RAIL.LogT(40,"Actor class generated for {1}.",ret)
			-- Extra data displayed for mercenary AIs
			if false and RAIL.Mercenary then
				-- Mercenaries should log extra information for Actors and NPCs
				if ret.ActorType == "Actor" or ret.ActorType == "NPC" then
					RAIL.LogT(40,"   --> {1}",StringBuffer.New()
						--:Append("V_TYPE="):Append(GetV(V_TYPE,ret.ID)):Append("; ")
						--:Append("V_HOMUNTYPE="):Append(GetV(V_HOMUNTYPE,ret.ID)):Append("; ")
						--:Append("V_MERTYPE="):Append(GetV(V_MERTYPE,ret.ID)):Append("; ")
						--:Append("V_MOTION="):Append(GetV(V_MOTION,ret.ID)):Append("; ")
						--:Append("V_TARGET="):Append(GetV(V_TARGET,ret.ID)):Append("; ")
						--:Append("IsMonster="):Append(IsMonster(ret.ID)):Append("; ")
						:Get()
					)
				end
			end
		end

		return ret
	end

	-- A temporary "false" return for IsEnemy, as long as an actor is a specific type
	local ret_false = function() return false end

	-- A "private" function to initialize new actor types
	do
		Actor[actor_key] = {
			[true] = function(self,t,notnpc)
				-- Set the new type
				self[actor_key] = t
				self.Type = t

				-- Check the type for sanity
				if (self.ID < 100000 or self.ID > 110000000) and
					-- Homunculus types
					((1 <= self.Type and self.Type <= 16) or
					-- Mercenary types
					(17 <= self.Type and self.Type <= 46)) and
					-- Not a portal
					(self.Type ~= 45 or notnpc)
				then
					self.Type = self.Type + 6000
				end
	
				-- Initialize differently based upon type
				if self.Type == -1 then
					-- Unknowns are never enemies, but track data
					return "Unknown",false,true
	
				-- Portals
				elseif self.Type == 45 then
					-- Portals are never enemies and shouldn't be tracked
					return "Portal",false,false
	
				-- Player Jobs
				elseif (0 <= self.Type and self.Type <= 25) or
					(161 <= self.Type and self.Type <= 181) or
					(4001 <= self.Type and self.Type <= 4049)
				then
					-- Players are potential enemies and should be tracked
					return "Player",true,true

				-- NPCs (non-player jobs that are below 1000)
				elseif self.Type < 1000 then
					-- NPCs are never enemies and shouldn't be tracked
					return "NPC",false,false
	
				-- All other types
				else
					-- All other actors are probably monsters or homunculi
					return "Actor",true,true
				end
			end,
			[false] = function(self,t,notnpc)
				self[actor_key] = t
				self.Type = t

				-- Find players based on ID
				if self.ID >= 100000 and self.ID <= 110000000 then
					-- Likely a player
					return "Player",true,true

				-- NPCs and Portals stand still and are never monsters
				elseif not notnpc and
					IsMonster(self.ID) == 0 and
					GetV(V_MOTION,self.ID) == MOTION_STAND and
					GetV(V_TARGET,self.ID) == 0
				then
					-- Likely an NPC
					return "NPC",false,false

				-- All other types
				else
					return "Actor",true,true
				end
			end,
		}
		setmetatable(Actor[actor_key],{
			__call = function(self,actor,...)
				-- Get the type from MobID handler
				local t = RAIL.MobID[actor.ID]

				-- Pass it to the proper function
				local possibleEnemy
				actor.ActorType,possibleEnemy,actor.FullUpdate = self[t ~= -2](actor,t,unpack(arg))

				if possibleEnemy then
					if rawget(actor,"IsEnemy") == ret_false then
						rawset(actor,"IsEnemy",nil)
					end
				else
					actor.IsEnemy = ret_false
				end
			end,
		})
	end

	-- Update information about the actor
	Actor.Update = function(self)
		-- Check if the actor is dead
		if self.Motion[0] == MOTION_DEAD then
			-- If the actor is still active, cause it to expire
			if self.ExpireTimeout[1] then
				self:Expire("death")
			end
			return self
		end

		-- Check for a type change
		if RAIL.MobID[self.ID] ~= self[actor_key] then
			-- Pre-log
			local str = tostring(self)

			-- Call the private type changing function
			Actor[actor_key](self)

			-- Log
			RAIL.LogT(40,"{1} changed type to {2}.",str,tostring(self))
		elseif self.Type == 45 and GetV(V_MOTION,self.ID) ~= MOTION_STAND then
			-- Call the private type changing function
			Actor[actor_key](self,true)

			-- Log
			RAIL.LogT(40,"Incorrectly identified {1} as a Portal; fixed.",self)
		elseif self.Type == -2 and self.ActorType == "NPC" and GetV(V_MOTION,self.ID) ~= MOTION_STAND then
			-- Call the private type changing function
			Actor[actor_key](self,true)

			-- Log
			RAIL.LogT(40,"Incorrectly identified {1} as an NPC; fixed.",self)
		end

		-- Update the expiration timeout
		self.ExpireTimeout[2] = GetTick()
		if not self.ExpireTimeout[1] and not self.Active then
			self.ExpireTimeout[1] = true
			RAIL.Timeouts:Insert(self.ExpireTimeout)

			-- Log its reactivation
			RAIL.LogT(40,"Reactivating {1}.",self)
		end

		-- Update ignore time
		if self.IgnoreTime > 0 then
			self.IgnoreTime = self.IgnoreTime - (GetTick() - self.LastUpdate)
		end

		-- Update the LastUpdate field
		self.LastUpdate = GetTick()

		-- The actor is active unless it expires
		self.Active = true

		-- Some actors don't require everything tracked
		if not self.FullUpdate then
			return self
		end

		-- Update the motion
		History.Update(self.Motion,GetV(V_MOTION,self.ID))

		-- Update the actor location
		local x,y = GetV(V_POSITION,self.ID)
		if x ~= -1 then
			-- Check for hidden
			if x == 0 and y == 0 then
				if not self.Hide then
					-- Log it
					self.Hide = true
				end
			else
				-- Make sure the X,Y integers are even
				x,y = RoundNumber(x,y)

				if self.Hide then
					-- Log it
					self.Hide = false
				end
				History.Update(self.X,x)
				History.Update(self.Y,y)
			end
		end

		-- Check if the actor is able to have a target
		if self.Motion[0] ~= MOTION_SIT then
			-- Get the current target
			local targ = GetV(V_TARGET,self.ID)

			-- Normalize it...
			if targ == 0 then
				targ = -1
			end

			-- Keep a history of it
			History.Update(self.Target,targ)

			-- Tell the other actor that it's being targeted
			if targ ~= -1 then
				Actors[targ]:TargetedBy(self)
			end
		else
			-- Can't target, so it should be targeting nothing
			History.Update(self.Target,-1)
		end

		-- Clear the targeted by table if it's old
		if math.abs((self.TargetOf[targeted_time] or 0) - GetTick()) > 50 then
			self.TargetOf = Table:New()
		end

		return self
	end

	-- Track when other actors target this one
	Actor.TargetedBy = function(self,actor)
		-- If something targets an NPC, it isn't an NPC
		if self.Type == -2 and self.ActorType == "NPC" then
			-- Call the private type changing function
			Actor[actor_key](self,true)

			-- Log
			RAIL.LogT(40,"Incorrectly identified {1} as an NPC; fixed.",self)
		elseif self.Type == 45 then
			-- Call the private type changing function
			Actor[actor_key](self,true)

			-- Log
			RAIL.LogT(40,"Incorrectly identified {1} as a Portal; fixed.",self)
		end

		-- Use a table to make looping through and counting it faster
		--	* to determine if an actor is targeting this one, use Actors[id].Target[0] == self.ID
		if math.abs((self.TargetOf[targeted_time] or 0) - GetTick()) > 50 then
			self.TargetOf = Table:New()
			self.TargetOf[targeted_time] = GetTick()
		end

		self.TargetOf:Insert(actor)
		return self
	end

	-- Clear out memory
	Actor.Expire = function(self,reason)
		-- Log
		RAIL.LogT(40,"Clearing history for {1} due to {2}.",self,reason)

		-- Unset any per-actor battle options
		for k,v in pairs(self.BattleOpts) do
			self.BattleOpts[k] = nil
		end
		self.BattleOpts[battleopts_parent] = self

		-- Clear the histories
		History.Clear(self.Motion)
		History.Clear(self.Target)
		History.Clear(self.X)
		History.Clear(self.Y)

		-- Disable the timeout
		self.ExpireTimeout[1] = false

		-- Disable the active flag
		self.Active = false
	end

	-------------
	-- Support --
	-------------
	-- The following functions support other parts of the script

	-- Check if the actor is an enemy (monster/pvp-player)
	Actor.IsEnemy = function(self)
		-- Check if it's a monster
		if IsMonster(self.ID) ~= 1 then
			return false
		end

		-- Check if it should be defended against only
		if self.BattleOpts.DefendOnly then
			-- Check if its target is owner, self, other, or a friend
			local target = Actors[self.Target[0]]
			if
				target ~= RAIL.Owner and
				target ~= RAIL.Self and
				target ~= RAIL.Other and
				not target:IsFriend()
			then
				-- Not attacking a friendly, so not an enemy
				return false
			end
		end

		-- Check if the monster is dead
		if self.Motion[0] == MOTION_DEAD then
			return false
		end

		-- Check if the monster is in a sane location
		if self.X[0] == -1 or self.Y[0] == -1 then
			return false
		end

		-- Default to true
		return true
	end

	-- Check if the actor is a friend
	Actor.IsFriend = function(self,no_temp)
		-- Make sure only players are counted as friends
		if self.ActorType ~= "Player" then
			return false
		end

		-- Check for temporary friends (players within <opt> range of owner)
		if not no_temp and RAIL.Owner:DistanceTo(self) <= RAIL.State.TempFriendRange then
			return true
		end

		-- Check if actor is on the friend list
		return self.BattleOpts.Friend
	end

	-- Set actor as a friend
	Actor.SetFriend = function(self,bool)
		-- Make sure only players are allowed on friend list
		if self.ActorType ~= "Player" then
			return
		end

		-- Check if there is already an ByID field for this actor
		if not RAIL.State.ActorOptions.ByID[self.ID] then
			-- No table exists for this actor, create it
			RAIL.State.ActorOptions.ByID[self.ID] = {
				["Friend"] = bool
			}
		else
			-- Table exists, update the friend section
			RAIL.State.ActorOptions.ByID[self.ID].Friend = bool
		end
	end

	-- Check if the actor is ignored
	Actor.IsIgnored = function(self)
		return self.IgnoreTime > 0
	end

	-- Ignore the actor for a specific amount of time
	Actor.Ignore = function(self,ticks)
		-- Use default ticks if needed
		if type(ticks) ~= "number" then
			ticks = self.BattleOpts.DefaultIgnoreTicks
		end

		-- If it's already ignored, do nothing
		if self:IsIgnored() then
			-- Update the ignore time to whichever is higher
			self.IgnoreTime = math.max(ticks,self.IgnoreTime)

			return self
		end

		RAIL.LogT(20,"{1} ignored for {2} milliseconds.",self,ticks)

		self.IgnoreTime = ticks
	end

	-- Estimate Movement Speed (in milliseconds per cell) and Direction
	local estimate_key = {}
	Actor.EstimateMove = function(self)
		-- Ensure we have a place to store estimation data
		if not self[estimate_key] then
			self[estimate_key] = {
				-- Default move-speed to regular walk
				--	according to http://forums.roempire.com/archive/index.php/t-137959.html:
				--		0.15 sec per cell at regular speed
				--		0.11 sec per cell w/ agi up
				--		0.06 sec per cell w/ Lif's emergency avoid
				--
				-- Default move-direction to straight north; the same as the server seems to
				speed = 150,
				angle = 90,

				-- Last time calculated was never
				last = 0,
				last_move = 0,
				last_non_move = 0,

				-- And the distance used to calculate speed was 1
				--	Note: Greater or equal distances will recalculate,
				--		to prevent infinite speeds (0 distance)
				dist = 1,
			}
		end

		-- Get the estimation data table
		local estimate = self[estimate_key]

		-- Don't estimate too often
		if GetTick() - estimate.last <= 250 then
			return estimate.speed, estimate.angle
		end

		-- Get the list of motions for the actor
		local motion_list = History.GetConstList(self.Motion)

		-- Loop from the most recent to the oldest
		local move
		local non_move
		for i=motion_list.last,motion_list.first,-1 do
			-- Check for a movement motion
			if motion_list[i][1] == MOTION_MOVE then
				-- Get the time of the motion start
				move = motion_list[i][2]

				-- Check if we're at the most recent motion
				if i == motion_list.last then
					-- Get the current time
					non_move = GetTick()
				else
					-- Get the time of the more-recent motion start
					non_move = motion_list[i+1][2]
				end

				-- Ensure that the motions are sufficiently far apart (in time or distance)
				local move_delta = GetTick() - move
				local non_move_d = GetTick() - non_move
				if
					non_move - move >= 100 or
					BlockDistance(self.X[non_move_d],self.Y[non_move_d],self.X[move_delta],self.Y[non_move_d]) > 0
				then
					-- Use these values
					break
				end

				-- Don't use these values
				move = nil
				non_move = nil
			end
		end

		-- If no new moves were found, return from estimate
		if
			-- No move found
			move == nil or
			-- Move is same as last estimation
			(move == estimate.last_move and non_move == estimate.last_non_move)
		then
			return estimate.speed, estimate.angle
		end

		-- Store the move and non_move times we're using
		estimate.last_move = move
		estimate.last_non_move = non_move

		-- Get the X and Y position lists
		local x_list = History.GetConstList(self.X)
		local y_list = History.GetConstList(self.Y)

		-- Find the position (in list) closest to non_move
		local begin_x = x_list:BinarySearch(non_move)
		local begin_y = y_list:BinarySearch(non_move)

		-- Begin searching backward into history
		local i_x,i_y = begin_x,begin_y
		while true do
			-- Get the X,Y coords
			local x = x_list[i_x][1]
			local y = y_list[i_y][1]

			-- Check to see if we can search further back
			local next_i_x = i_x
			if i_x-1 >= x_list.first and x_list[i_x-1][2] >= move then
				next_i_x = i_x - 1
			end
			local next_i_y = i_y
			if i_y-1 >= y_list.first and y_list[i_y-1][2] >= move then
				next_i_y = i_y - 1
			end

			-- Check if we've reached the back
			if next_i_x == i_x and next_i_y == i_y then
				break
			end

			-- Find the next changed point
			if x_list[next_i_x][2] > y_list[next_i_y][2] and next_i_x ~= i_x then
				next_i_y = i_y
			elseif x_list[next_i_x][2] < y_list[next_i_y][2] and next_i_y ~= i_y then
				next_i_x = i_x
			end

			-- Get the angle of the two adjacent points
			local angle = GetAngle(
				x_list[next_i_x][1],y_list[next_i_y][1],
				x,y
			)

			-- Get the angle of the beginning to our current point
			local angle2 = GetAngle(
				x,y,
				x_list[begin_x][1],y_list[begin_y][1]
			)

			-- If x,y are still at beginning position, move to next
			if angle ~= -1 and angle2 ~= -1 then
				-- Check to see if the angle is within 45 degrees either way
				if not CompareAngle(angle,angle2+45,90) then
					-- Doesn't match
					break
				end

				-- Check if the distance is great enough
				local blocks = BlockDistance(x,y,x_list[begin_x][1],y_list[begin_y][1])
				if blocks >= 6 then
					break
				end
			end

			i_x = next_i_x
			i_y = next_i_y
		end

		-- Get the beginning position and end position
		--	Note: begin refers to the most recent, so it becomes x2,y2
		local x2,y2 = x_list[begin_x][1],y_list[begin_y][1]
		local x1,y1 = x_list[i_x][1],y_list[i_y][1]

		-- Get the angle and the block distance
		local angle = GetAngle(x1,y1,x2,y2)
		local dist = BlockDistance(x1,y1,x2,y2)

		-- Ensure we're still sane
		--	Note: And don't repeat logs for the same angle
		if angle ~= -1 and angle ~= estimate.angle then
			-- Store our estimated angle
			estimate.angle = angle

			-- Log it
			RAIL.LogT(80,"Movement angle for {1} estimated at {2} degrees.",
				self,RoundNumber(estimate.angle))
		end

		-- Check if we've calculated a better speed than before
		if dist >= estimate.dist then
			-- Store our speed and distance

			estimate.dist = dist

			-- Get the tick delta
			local tick_delta_x = x_list[begin_x][2] - x_list[i_x][2]
			local tick_delta_y = y_list[begin_y][2] - y_list[i_y][2]
			local tick_delta = math.max(tick_delta_x,tick_delta_y)

			estimate.speed = tick_delta / dist

			-- Store the time of last estimation
			estimate.last = GetTick()

			-- Log it
			RAIL.LogT(80,"Movement speed for {1} estimated at {2}ms/tile (dist={3}).",
				self,RoundNumber(estimate.speed),estimate.dist)
		end

		-- And return
		return estimate.speed, estimate.angle
	end

	--------------------
	-- Battle Options --
	--------------------

	-- RAIL allowed to attack monster?
	Actor.IsAttackAllowed = function(self)
		-- Determine if we are allowed to attack the monster
		return self:IsEnemy() and self.BattleOpts.AttackAllowed
	end

	-- RAIL allowed to cast against monster?
	Actor.IsSkillAllowed = function(self,level)
		-- Check if skills are allowed
		if not self:IsEnemy() or not self.BattleOpts.SkillsAllowed then
			return false
		end

		-- Check that the skill level is high enough
		if level < self.BattleOpts.MinSkillLevel then
			return false
		end

		-- Check if we've reached max cast count
		if
			(self.BattleOpts.CastsAgainst or 0) >= self.BattleOpts.MaxCastsAgainst and
			self.BattleOpts.MaxCastsAgainst >= 0
		then
			return false
		end

		-- Check if we should wait before casting against this actor
		if RAIL.Self.SkillState:CompletedTime() + self.BattleOpts.TicksBetweenSkills > GetTick() then
			return false
		end

		-- Skills are allowed (and hint at the max skill level)
		return true,math.min(self.BattleOpts.MaxSkillLevel,level)
	end

	-- Determine if attacking this actor would be kill-stealing
	Actor.WouldKillSteal = function(self)
		-- Free-for-all monsters are never kill-stealed
		if self.BattleOpts.FreeForAll then
			return false
		end

		-- Check if it's an enemy
		if not self:IsEnemy() then
			return false
		end

		-- Check if this actor is targeting anything
		local targ = self.Target[0]
		if targ ~= -1 then
			-- Owner and self don't count
			if targ == RAIL.Self.ID or targ == RAIL.Owner.ID then
				return false
			end

			local targ = Actors[targ]

			-- Can't kill steal friends
			if targ:IsFriend() then
				return false
			end

			-- Determine if it's not targeting another enemy
			if not targ:IsEnemy() then

				-- Determine if the target has been updated recently
				if targ.Active then
					-- It would be kill stealing
					return true
				end

			end
		end

		-- Check if this actor is the target of anything
		-- Note: TargetOf table will always be fresh by the time this is called
		for i=1,self.TargetOf:Size(),1 do
			targ = self.TargetOf[i]

			-- Determine if the targeter is...
			if
				targ ~= RAIL.Owner and				-- not the owner
				targ ~= RAIL.Self and				-- not ourself
				not targ:IsEnemy() and				-- not an enemy
				not targ:IsFriend() and				-- not a friend
				true
			then
				-- Likely kill-stealing
				return true
			end
		end

		-- Check if the monster is probably part of a mob-train
		-- TODO: Check for monster chasing another

		-- Default is not kill-steal
		return false
	end



	-- Kite / Attack**
	--	**- based partially on shared table, based partially on homu's current HP?

	--------------------
	-- Utils Wrappers --
	--------------------

	-- The following wrappers are fairly complex, so here are some examples:
	--
	--	RAIL.Owner:DistanceTo(x,y)
	--		Returns the pythagorean distance between owner and (x,y)
	--
	--	RAIL.Owner:DistanceTo(-500)(x,y)
	--		Returns the pythagorean distance between (x,y) and the owner's
	--		estimated position at 500 milliseconds into the future
	--
	--	RAIL.Owner:DistanceTo(RAIL.Self)
	--		Returns the pythagorean distance between owner and homu/merc
	--
	--	RAIL.Owner:DistanceTo(500)(RAIL.Self)
	--		Returns the pythagorean distance between owner's position
	--		500 milliseconds ago, and the homu/merc's position 500 milliseconds ago
	--
	--	RAIL.Owner:DistanceTo(RAIL.Self.X[500],RAIL.Self.Y[500])
	--		Returns the pythagorean distance between owner's current position
	--		and the homu/merc's position 500 milliseconds ago
	--
	--	RAIL.Owner:DistanceTo(-500)(RAIL.Self.X[0],RAIL.Self.Y[0])
	--		Returns the pythagorean distance between owner's estimated position
	--		(500ms into future), and homu/merc's current position.
	--
	-- Remember:
	--	- negative values represent future (estimated)
	--	- positive values represent past (recorded)
	--
	--

	-- Closures will timeout and be removed after 10 seconds of non-use
	local closure_timeout = 10000

	-- Pythagorean Distance
	Actor.DistanceTo = function(self,a,b)
		-- Check if a specific closure is requested
		if type(a) == "number" and b == nil then

			-- Check if a closure already exists
			if not self[closures].DistanceTo[a] then

				-- Create table to hold the closure
				local table = {}
				self[closures].DistanceTo[a] = table

				-- Create closure
				table.func = function(x,y)
					-- Main function logic follows

					-- Check if "x" is an actor table
					if RAIL.IsActor(x) then
						y = x.Y[a]
						x = x.X[a]
					end

					return PythagDistance(self.X(a),self.Y(a),x,y)

				end -- function(x,y)

				-- Add a timeout to remove the table
				table.timeout = RAIL.Timeouts:New(closure_timeout,false,function()
					self[closures].DistanceTo[a] = nil
				end)

			end -- not self[closures].DistanceTo[a]

			-- Update the timeout
			self[closures].DistanceTo[a].timeout[2] = GetTick()

			-- Return the requested closure
			return self[closures].DistanceTo[a].func
		end

		-- Not requesting specific closure, so use 0
		return Actor.DistanceTo(self,0)(a,b)
	end

	-- Straight-line Block Distance
	Actor.BlocksTo = function(self,a,b)
		-- Check if a specific closure is requested
		if type(a) == "number" and b == nil then

			-- Check if a closure already exists
			if not self[closures].BlocksTo[a] then

				-- Create table to hold the closure
				local table = {}
				self[closures].BlocksTo[a] = table

				-- Create closure
				table.func = function(x,y)
					-- Main function logic follows

					-- Check if "x" is an actor table
					if RAIL.IsActor(x) then
						y = x.Y[a]
						x = x.X[a]
					end

					return BlockDistance(self.X[a],self.Y[a],x,y)

				end -- function(x,y)

				-- Add a timeout to remove the table
				table.timeout = RAIL.Timeouts:New(closure_timeout,false,function()
					self[closures].BlocksTo[a] = nil
				end)

			end -- not self[closures].BlocksTo[a]

			-- Update the timeout
			self[closures].BlocksTo[a].timeout[2] = GetTick()

			-- Return the requested closure
			return self[closures].BlocksTo[a].func
		end

		-- Not requesting specific closure, so use 0
		return Actor.BlocksTo(self,0)(a,b)
	end

	-- Angle from actor to point
	Actor.AngleTo = function(self,a,b)
		-- Check if a specific closure is requested
		if type(a) == "number" and b == nil then

			-- Check if a closure already exists
			if not self[closures].AngleTo[a] then

				-- Create table to hold the closure
				local table = {}
				self[closures].AngleTo[a] = table

				-- Create closure
				table.func = function(x,y)
					-- Main function logic follows

					-- Check if "x" is an actor table
					if RAIL.IsActor(x) then
						y = x.Y[a]
						x = x.X[a]
					end

					return GetAngle(self.X[a],self.Y[a],x,y)
				end -- function(x,y)

				-- Add a timeout to remove the table
				table.timeout = RAIL.Timeouts:New(closure_timeout,false,function()
					self[closures].AngleTo[a] = nil
				end)

			end -- not self[closures].AngleTo[a]

			-- Update the timeout
			self[closures].AngleTo[a].timeout[2] = GetTick()

			-- Return the requested closure
			return self[closures].AngleTo[a].func
		end

		-- Not requesting specific closure, so use 0
		return Actor.AngleTo(self,0)(a,b)
	end

	-- Angle from point to actor
	Actor.AngleFrom = function(self,a,b)
		-- Check if a specific closure is requested
		if type(a) == "number" and b == nil then

			-- Check if a closure already exists
			if not self[closures].AngleFrom[a] then

				-- Create table to hold the closure
				local table = {}
				self[closures].AngleFrom[a] = table

				-- Create closure
				table.func = function(x,y)
					-- Main function logic follows

					-- Check if "x" is an actor table
					if RAIL.IsActor(x) then
						y = x.Y[a]
						x = x.X[a]
					end

					return GetAngle(x,y,self.X[a],self.Y[a])
				end -- function(x,y)

				-- Add a timeout to remove the table
				table.timeout = RAIL.Timeouts:New(closure_timeout,false,function()
					self[closures].AngleFrom[a] = nil
				end)

			end -- not self[closures].AngleFrom[a]

			-- Update the timeout
			self[closures].AngleFrom[a].timeout[2] = GetTick()

			-- Return the requested closure
			return self[closures].AngleFrom[a].func
		end

		-- Not requesting specific closure, so use 0
		return Actor.AngleFrom(self,0)(a,b)
	end

	-- Plot a point on a circle around this actor
	Actor.AnglePlot = function(self,a,b)
		-- Check if a specific closure is requested
		if type(a) == "number" and b == nil then

			-- Check if a closure already exists
			if not self[closures].AnglePlot[a] then

				-- Create table to hold the closure
				local table = {}
				self[closures].AnglePlot[a] = table

				-- Create closure
				table.func = function(angle,radius)
					-- Main function logic follows

					return PlotCircle(self.X[a],self.Y[a],angle,radius)
				end -- function(angle,radius)

				-- Add a timeout to remove the table
				table.timeout = RAIL.Timeouts:New(closure_timeout,false,function()
					self[closures].AnglePlot[a] = nil
				end)

			end -- not self[closures].AnglePlot[a]

			-- Update the timeout
			self[closures].AnglePlot[a].timeout[2] = GetTick()

			-- Return the requested closure
			return self[closures].AnglePlot[a].func
		end

		-- Not requesting specific closure, so use 0
		return Actor.AnglePlot(self,0)(a,b)
	end

	------------------
	-- API Wrappers --
	------------------

	-- These are mainly to allow attacks/skills vs. specific monsters to be
	--	hooked in a more efficient manner than hooking Attack() base API

	Actor.Attack = function(self)
		-- Send the attack
		Attack(RAIL.Self.ID,self.ID)

		-- After sending an attack, this actor can never be kill-stealed (until Actor.Expire)
		self.BattleOpts.FreeForAll = true
	end

	Actor.SkillObject = function(self,skill)
		-- Send the skill
		skill:Cast(self.ID)

		-- And never see this actor as kill-stealing
		self.BattleOpts.FreeForAll = true
	end

	-----------------------
	-- Actors Collection --
	-----------------------

	Actors = {}
	setmetatable(Actors,{
		__index = function(self,idx)
			if type(idx) ~= "number" then
				return self[-1]
			end

			-- Make sure the actor ID is positive
			--	(but -1 is a special value)
			if idx < -1 then
				return self[-idx]
			end

			-- Ensure the actor is sane
			if GetV(V_MOTION,idx) == -1 then
				return self[-1]
			end

			-- Generate a new actor class
			rawset(self,idx,Actor:New(idx))
			return self[idx]
		end
	})

	-- Create Actors[-1], and disable certain features
	rawset(Actors,-1,Actor:New(-1))

	Actors[-1].ExpireTimeout[1] = false

	Actors[-1].Update    = function(self) return self end
	Actors[-1].IsEnemy   = function() return false end
	Actors[-1].IsFriend  = function() return false end
	Actors[-1].IsIgnored = function() return true end
	Actors[-1].IsAllowed = function() return false end

	-- After setting up the Actor class and Actors table,
	--	rework the ragnarok API to allow Actor inputs
	-- TODO? Don't think I even want this...
end