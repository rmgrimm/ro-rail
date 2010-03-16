-- Find highest available skill level costing less than X sp
do
	function FindSkillLevel(sp,skill)
		-- Check if there is enough SP for the skill
		if sp >= skill.SPCost then
			-- Non-selectable will return their level; selectable will return highest level
			return skill.Level
		end

		-- Check if the skill is level selectable
		if skill[1] == nil then
			-- Not selectable, and didn't match earlier...
			return 0
		end

		-- Loop through each level to find the highest that matches
		for i=skill.Level,1,-1 do
			if skill[i] and sp >= skill[i].SPCost then
				-- Use this level
				return i
			end
		end

		-- None matched, not even level 1
		return 0
	end
end

-- Skill state
do
	-- Possible skill states
	local state_enum = {
		READY = 0,		-- Can use a skill
		CASTING_ACK = 1,	-- Waiting for cast time to start
		CASTING = 2,		-- Waiting for cast time to finish
		DELAY_ACK = 3,		-- Waiting for server to acknolwedge skill
		DELAY = 4,		-- Waiting for cast delay to finish
		CASTING_UNK = 5,	-- Waiting for cast time of unknown skill
	}
	setmetatable(state_enum,{
		__newindex = function(self,idx,value)
			-- Don't allow values to be added to the state enumeration table
			return nil
		end,
	})

	-- Private key to hold a table of state-checking variables
	local key = {}

	-- Helper functions for History.FindMostRecent
	local casting_f = function(v) return v == MOTION_CASTING end
	local not_casting_f = function(v) return v ~= MOTION_CASTING end
	local skill_f = function(v) return v == MOTION_SKILL end

	-- SkillState class is private; instantiated by Actor class objects
	local SkillState = {
		Enum = state_enum,

		-- Wait for a skill to cast
		WaitFor = function(self,skill,target,timeout)
			-- Ensure we're ready for a skill
			if self[key].state ~= state_enum.READY then
				return false
			end

			-- Decide if the skill has a casting time
			local state = state_enum.DELAY_ACK
			if skill.CastTime ~= 0 then
				state = state_enum.CASTING_ACK
			end

			-- Set the state, skill, and the beginning time
			self[key].state = state
			self[key].skill = skill
			self[key].target = target
			self[key].ticks[state] = GetTick()
			self[key].ticks.begin = self[key].ticks[state]

			-- Set the timeout
			if not timeout then
				-- TODO: make state option for this
				timeout = 1000
			end
			self[key].timeout = timeout

			return true
		end,

		-- Get the skill state
		Get = function(self)
			local state = self[key].state

			-- Simplify the state to one of three possibilities
			--	READY, CASTING, DELAY
			if state == state_enum.CASTING_ACK then
				return state_enum.CASTING
			elseif state == state_enum.DELAY_ACK then
				return state_enum.DELAY
			elseif state == state_enum.CASTING_UNK then
				return state_enum.CASTING
			else
				return state
			end
		end,

		CompletedTime = function(self)
			return self[key].ticks[state_enum.READY]
		end,

		-- Setup the update table
		Update = {
			[state_enum.READY] = function(self,ticks_in_state)
				-- Ready; nothing to update

				-- Check for casting motion, and properly handle it
				--		(timed out cast started? user casted non-targeted?)
				if self[key].actor.Motion[0] == MOTION_CASTING then
					return state_enum.CASTING_UNK,0
				end


				-- Don't change state
				return
			end,
			[state_enum.CASTING_ACK] = function(self,ticks_in_state)
				-- Check for server acknowledgement

				-- Find the most recent casting time
				local most_recent = History.FindMostRecent(self[key].actor.Motion,casting_f,nil,ticks_in_state)

				-- Check if a most recent skill casting action was found
				if most_recent ~= nil then
					-- Change to casting state
					return state_enum.CASTING,most_recent
				else
					-- Check if the skill timed out
					if ticks_in_state >= self[key].timeout then
						-- Failed, return to ready state
						return state_enum.READY,ticks_in_state,"timeout"
					end
				end

				-- Wait longer; don't change state
				return
			end,
			[state_enum.CASTING] = function(self,ticks_in_state)
				-- Ensure we're still casting

				-- Get the actor we're watching
				local actor = self[key].actor

				-- Find the most recent non-casting item
				local most_recent = History.FindMostRecent(actor.Motion,not_casting_f,nil,ticks_in_state)

				-- If we're still casting, nothing should match
				if most_recent == nil then
					-- Don't change state
					return
				end

				-- Check the motion
				local motion = actor.Motion[most_recent]

				-- Check if the skill completed
				if motion == MOTION_SKILL then
					-- Change state to delay
					return state_enum.DELAY,most_recent
				end

				-- Check for SP usage; homunculi don't show MOTION_SKILL
				local sp_delta = actor.SP[0] - actor.SP[ticks_in_state]

				if sp_delta < 0 then
					-- Set state to DELAY_ACK, to reuse code for SP check
					return state_enum.DELAY_ACK,ticks_in_state
				end

				-- TODO: Check for uninterruptable skills

				-- Set the state to ready, the skill was interrupted (or failed)
				return state_enum.READY,ticks_in_state,"cast interrupted or failed"
			end,
			[state_enum.DELAY_ACK] = function(self,ticks_in_state)
				-- Check for SP usage or MOTION_SKILL (as server acknowledgement)

				-- Get the actor we're watching
				local actor = self[key].actor

				-- Find the most recent MOTION_SKILL
				local most_recent = History.FindMostRecent(actor.Motion,skill_f,nil,ticks_in_state)

				-- Check if a most recent skill usage was found
				if most_recent ~= nil then
					-- Skill seems to have worked, wait for delay
					return state_enum.DELAY,most_recent
				end

				-- Check if SP was used since we've been waiting
				local sp_delta = actor.SP[0] - actor.SP[ticks_in_state]

				if sp_delta < 0 then
					-- Make sp_delta positive now, for easier comparison to SP costs
					sp_delta = -sp_delta

					-- Get the skill
					local skill = self[key].skill

					-- Check if a different level has possibly been used
					if skill.SPCost ~= sp_delta then
						-- Find the skill level that was probably used
						local new_level = FindSkillLevel(sp_delta, AllSkills[skill.ID])

						-- Check if the new level is less than current
						if 0 < new_level and new_level < skill.Level then
							RAIL.LogT(60,"Cast of {1} seems to have used level {2}; SP used = {3}.",
								skill,new_level,sp_delta)

							-- Replace it, so delay time will be more accurate
							self[key].skill = AllSkills[skill.ID][new_level]
						end
					end

					-- Set state to delay (use half ticks_in_state as an estimation of when the skill was used)
					return state_enum.DELAY,RoundNumber(ticks_in_state / 2)
				end

				-- Check for timeout
				if ticks_in_state >= self[key].timeout then
					return state_enum.READY,ticks_in_state,"timeout"
				end

				-- Don't change state
				return
			end,
			[state_enum.DELAY] = function(self,ticks_in_state)
				-- Waiting for cast delay

				-- Check if enough time has passed
				if ticks_in_state >= self[key].skill.CastDelay then
					-- Change to ready state
					return state_enum.READY,ticks_in_state - self[key].skill.CastDelay
				end

				-- Don't change state
				return
			end,
			[state_enum.CASTING_UNK] = function(self,ticks_in_state)
				-- Wait until we aren't casting anymore

				if self[key].actor.Motion[0] ~= MOTION_CASTING then
					return state_enum.READY,0
				end
			end,
		},

		-- Callback functions
		Callbacks = {
			-- Add functions to the callback list
			Add = function(self,skill,success,failure,persistent)
				-- Get the parent table's hidden callbacks table
				local cb = self[key][key].callbacks

				-- If tables don't exist, create them
				if not cb.success[skill.ID] then
					cb.success[skill.ID] = {}
				end
				if not cb.failure[skill.ID] then
					cb.failure[skill.ID] = {}
				end

				-- Ensure we have have a persistent option
				if persistent == nil then
					persistent = false
				end

				-- Add callbacks to the table
				if success ~= nil then
					cb.success[skill.ID][success] = persistent
				end
				if failure ~= nil then
					cb.failure[skill.ID][failure] = persistent
				end
			end,

			-- Fire the callbacks that are registered for a skill
			Fire = function(self,skill,succeeded,...)
				-- Get the parent table's hidden callback set
				local cb = self[key][key].callbacks

				-- Decide whether to use success callbacks or failure callbacks
				local t
				if succeeded then
					t = cb.success[skill.ID]
				else
					t = cb.failure[skill.ID]
				end

				-- Check if there are any callbacks
				if t ~= nil and type(t) == "table" then
					-- Loop through the functions
					for f in t do
						-- Call the function
						f(skill,unpack(arg))
					end
				end
			end,

			-- Clear some or all callbacks
			Clear = function(self,skill)
				-- Get the parent table's hidden callback table
				local cb = self[key][key].callbacks

				-- Check if we're clearing all callbacks
				if not skill then
					-- Loop through each skill and clear it
					for id,table in cb.success do
						-- Note: Use a fake skill that only holds ID
						self:Clear({ID = id})
					end
				else
					-- Check if there are tables for this skill
					if not cb.success[skill.ID] then
						return
					end

					-- Loop through the success callbacks, and add them to a replacement table
					local success = {}
					for f,persist in cb.success[skill.ID] do
						if persist then
							success[f] = persist
						end
					end
					cb.success[skill.ID] = success

					-- Loop through the failure callbacks, and add them to a replacement table
					local failure = {}
					for f,persist in cb.failure[skill.ID] do
						if persist then
							failure[f] = persist
						end
					end
					cb.failure[skill.ID] = failure
				end
			end,
		},
	}

	-- Metatable for SkillState-class objects
	local mt = {
		__index = SkillState,
	}

	-- Metatable for generated Update tables
	local update_mt = {
		__newindex = function(self,idx,value)
			-- Only allow overwriting of functions that already exist
			if SkillState.Update[idx] ~= nil then
				-- Save the value
				self[idx] = value

				-- Return as well
				return value
			end

			-- Otherwise do nothing
			return nil
		end,

		-- Inherit from the base Update table
		__index = SkillState.Update,

		-- Allow this table to be called like a function
		__call = function(self)
			-- Get the parent object
			local parent = self[key]

			-- Get the state
			local state = parent[key].state

			-- Loop until a function returns nil
			while state ~= nil do
				-- Get the function
				local f = self[state]

				-- Call the function, and check for state change
				local ticks = GetTick() - parent[key].ticks[state]
				local reason
				state,ticks,reason = f(parent,ticks)

				-- Check for a state change
				if state ~= nil then
					-- Log it
					RAIL.LogT(65,"Skill state changed from {1} to {2} after {3}ms.",
						parent[key].state, state, GetTick()-parent[key].ticks.begin)

					-- Check for success/failure
					if
						state == state_enum.READY and
						parent[key].state ~= state_enum.DELAY and
						parent[key].state ~= state_enum.CASTING_UNK
					then
						-- Failure!

						-- Get the skill
						local skill = parent[key].skill

						-- Log it
						RAIL.LogT(60,"Cast of {1} failed after {2}ms; reason = {3}.",
							skill,GetTick()-parent[key].ticks.begin,reason)

						-- Fire any failure callback for this skill
						parent.Callbacks:Fire(skill,false,parent[key].target,ticks)

						-- Clear callbacks for this skill
						parent.Callbacks:Clear(skill)

						-- Set ticks to GetTick(), so CompletedTime() will return close to 0
						ticks = GetTick()

					elseif state == state_enum.DELAY then
						-- Success!

						-- Get the skill
						local skill = parent[key].skill

						-- Log it
						RAIL.LogT(60,"Cast of {1} succeeded after {2}ms.",
							skill,GetTick()-parent[key].ticks.begin)

						-- Fire any success callbacks for this skill
						parent.Callbacks:Fire(skill,true,parent[key].target,ticks)

						-- Clear callbacks for this skill
						parent.Callbacks:Clear(skill)

					elseif state == state_enum.CASTING_UNK then
						-- Casting unknown skill started

						-- Log it
						RAIL.LogT(60,"Cast of unknown skill started.")
					end

					-- Set the state and ticks
					parent[key].state = state
					parent[key].ticks[state] = GetTick() - ticks
				end
			end
		end,
	}

	-- Metatable for generated Callbacks tables
	local callbacks_mt = {
		__index = SkillState.Callbacks,
	}

	-- Get the private Actor class table
	local Actor = getmetatable(Actors[-1]).__index

	-- A function for later
	local function blank_f(self)
		return self.SkillState
	end

	-- Insert a function to instantiate SkillState object
	Actor.InitSkillState = function(self)
		-- Generate a new table for the actor
		self.SkillState = {
			[key] = {
				["actor"] = self,
				state = state_enum.READY,
				ticks = {
					[state_enum.READY] = 0,
				},
				callbacks = {
					success = {},
					failure = {},
				},
			},
			Update = {},
			Callbacks = {},
		}

		-- Set the Update and Callbacks parent table to self.SkillState
		self.SkillState.Update[key] = self.SkillState
		self.SkillState.Callbacks[key] = self.SkillState

		-- Set metatables
		setmetatable(self.SkillState,mt)
		setmetatable(self.SkillState.Update,update_mt)
		setmetatable(self.SkillState.Callbacks,callbacks_mt)

		-- Override the InitSkillState function with a blank function
		self.InitSkillState = blank_f

		-- Hook the actor Update() function to also update skill state
		local update = self.Update
		self.Update = function(self,...)
			-- First call the hooked function
			local ret = update(self,unpack(arg))

			-- Then update the skill state
			self.SkillState:Update(self)

			return ret
		end

		-- Return the new skill state table
		return self.SkillState
	end
end

