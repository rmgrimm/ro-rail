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

-- Add callback functions to a skill
do
	function SetSkillCallbacks(skill,success,failure)
		local skill_base = AllSkills[skill.ID]

		-- Loop through each level and set success/failure callback
		for i=1,skill_base.Level do
			-- Set the success and failure callback
			skill_base[i].Success = success
			skill_base[i].Failure = failure
		end
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
		WaitFor = function(self,skill,timeout)
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

				-- TODO: Check for casting motion, and properly handle it
				--		(timed out cast started?)

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
					if tick_delta >= self[key].timeout then
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

				-- TODO: Check for SP usage; homunculi don't show MOTION_SKILL

				-- TODO: Check for uninterruptable skills

				-- Set the state to ready, the skill was interrupted
				return state_enum.READY,ticks_in_state,"cast interrupted"
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
					-- Make sp_delta positive now, for easier comparison between SP costs
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
								skill.Name,new_level,sp_delta)

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
					-- Check for success/failure
					if state == state_enum.READY and parent[key].state ~= state_enum.DELAY then
						-- Failure!

						-- Get the skill
						local skill = parent[key].skill

						-- Log it
						RAIL.LogT(60,"Cast of {1} failed after {2}ms; reason = {3}.",
							skill.Name,GetTick()-parent[key].ticks.begin,reason)

						-- If the skill has a failure callback, fire it
						if type(skill.Failure) == "function" then
							skill:Failure(ticks)
						end

						-- Set ticks to GetTick(), so CompletedTime() will return close to 0
						ticks = GetTick()

					elseif state == state_enum.DELAY then
						-- Success!

						-- Get the skill
						local skill = parent[key].skill

						-- Log it
						RAIL.LogT(60,"Cast of {1} succeeded after {2}ms.",
							skill.Name,GetTick()-parent[key].ticks.begin)

						-- If the skill has a success callback, fire it
						if type(skill.Success) == "function" then
							skill:Success(ticks)
						end
					end

					-- Set the state and ticks
					parent[key].state = state
					parent[key].ticks[state] = GetTick() - ticks
				end
			end
		end,
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
			},
			Update = {},
		}

		-- Set the Update parent table to self.SkillState
		self.SkillState.Update[key] = self.SkillState

		-- Set metatables
		setmetatable(self.SkillState,mt)
		setmetatable(self.SkillState.Update,update_mt)

		-- Override the InitSkillState function with a blank function
		self.InitSkillState = blank_f

		-- Hook the actor Update() function to also update skill state
		local update = self.Update
		self.Update = function(self)
			-- First call the hooked function
			local ret = update(self)

			-- Then update the skill state
			self.SkillState:Update(self)

			return ret
		end

		-- Return the new skill state table
		return self.SkillState
	end
end

