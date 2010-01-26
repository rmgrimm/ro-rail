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
	}
	setmetatable(state_enum,{
		__newindex = function(self,idx,value)
			-- Don't allow values to be added to the state enumeration table
			return nil
		end,
	})

	-- Skill state helpers
	local state = state_enum.READY	-- default to ready
	local skill = nil		-- skill from AllSkills db
	local skill_sp = 0		-- RAIL.Self.SP[0] when the last skill was cast
	local skill_ticks = 0		-- GetTick() when the last skill was cast
	local casting_ticks = 0		-- GetTick() of the first MOTION_CASTING
	local delay_ticks = 0		-- GetTick() of when the skill was used
	local finish_ticks = 0		-- GetTick() of when the skill delay finished

	-- Skill timeout time
	-- TODO: Make state option for this? Do I want that?
	local timeout = 600

	-- Helper functions for History.FindMostRecent
	local casting_f = function(v) return v == MOTION_CASTING end
	local not_casting_f = function(v) return v ~= MOTION_CASTING end
	local skill_f = function(v) return v == MOTION_SKILL end

	-- Skill State object
	RAIL.SkillState = {
		Enum = state_enum,
		WaitFor = function(self,skill_)
			-- If the current state is not READY, don't do anything
			if state ~= state_enum.READY then
				return false
			end

			-- Check if the skill has a casting time, and set the state accordingly
			if skill_.CastTime > 0 then
				state = state_enum.CASTING_ACK
			else
				state = state_enum.DELAY_ACK
			end
			skill = skill_
			skill_sp = RAIL.Self.SP[0]
			skill_ticks = GetTick()
			casting_ticks = 0
			delay_ticks = 0
			finish_ticks = 0

			return true
		end,
		Update = function(self)
			-- Check what state we're in
			if state == state_enum.READY then
				-- Ready; nothing to update

				-- TODO: Check for casting motion, and properly handle it
				--		(timed out cast started?)

			elseif state == state_enum.CASTING_ACK then
				-- Check for server acknowledgement

				-- Get the time that has passed since cast command was sent
				local tick_delta = GetTick() - skill_ticks

				-- Find the most recent casting time
				local most_recent = History.FindMostRecent(RAIL.Self.Motion,casting_f,tick_delta)

				-- Check if the skill timed out
				if most_recent == nil and tick_delta >= timeout then
					RAIL.LogT(60,"Use of {1} seems to have failed; timeout after {2}ms.",skill.Name,tick_delta)

					state = state_enum.READY
					return
				end

				-- Set state to casting
				state = state_enum.CASTING
				casting_ticks = GetTick() - most_recent

			elseif state == state_enum.CASTING then
				-- Ensure we're still casting

				-- Get the time that has passed since we started casting
				local tick_delta = GetTick() - casting_ticks

				-- Find the most recent non-casting item
				local most_recent = History.FindMostRecent(RAIL.Self.Motion,not_casting_f,tick_delta)

				-- If we're still casting, nothing should match
				if most_recent == nil then
					return
				end

				-- Check the motion
				local motion = RAIL.Self.Motion[most_recent]

				-- Check if the skill completed
				if motion == MOTION_SKILL then
					-- Wait for delay
					state = state_enum.DELAY
					delay_ticks = GetTick() - most_recent

					-- Also check if delay time has also already passed
					return self:Update()
				end

				-- TODO: uninteruptible skill handling (eg, arrow repel)
				--		(set to DELAY_ACK when skill is estimated to go off)

				RAIL.LogT(60,"Use of {1} seems to have failed; casting state interrupted after {2}ms.",skill.Name,tick_delta)

				-- Set the state to ready, the skill was interrupted
				state = state_enum.READY

			elseif state == state_enum.DELAY_ACK then
				-- Check for SP usage or MOTION_SKILL (as server acknowledgement)

				-- Get the number of ticks since the skill was used
				local tick_delta = GetTick() - skill_ticks

				-- Find the most recent MOTION_SKILL
				local most_recent = History.FindMostRecent(RAIL.Self.Motion,skill_f,tick_delta)

				-- Check if a most recent skill usage was found
				if most_recent ~= nil then
					-- Wait for delay
					state = state_enum.DELAY
					delay_ticks = GetTick() - most_recent

					-- Check if delay time has also already passed
					return self:Update()
				end

				-- Check if SP was used since we've been waiting
				local sp_delta = RAIL.Self.SP[0] - skill_sp

				if sp_delta < 0 then
					-- Make sp_delta positive now, for easier comparison between SP costs
					sp_delta = -sp_delta

					-- Check if a different level has possibly been used
					if skill.SPCost ~= sp_delta then
						-- Find the skill level that was probably used
						local new_level = FindSkillLevel(sp_delta, AllSkills[skill.ID])

						-- Check if the new level is less than current
						if 0 < new_level and new_level < skill.Level then
							RAIL.LogT(60,"Cast of {1} seems to have used level {2}; SP used = {3}.",
								skill.Name,new_level,sp_delta)

							-- Replace it, so delay time will be more accurate
							skill = AllSkills[skill.ID][new_level]
						end
					end

					-- Set state to delay
					state = state_enum.DELAY
					delay_ticks = skill_ticks

					-- Also check if delay time has already passed
					return self:Update()
				end

				-- Check for timeout
				if tick_delta >= timeout then
					RAIL.LogT(60,"Use of {1} seems to have failed; timeout after {2}ms.",skill.Name,tick_delta)

					state = state_enum.READY
					return
				end

			elseif state == state_enum.DELAY then
				-- Waiting for cast delay

				-- Check if enough time has passed
				if GetTick() >= delay_ticks + skill.CastDelay then
					RAIL.LogT(60,"Use of {1} seems to have succeeded; finished after {2}ms.",skill.Name,GetTick()-skill_ticks)

					-- Set ready state
					state = state_enum.READY
					finish_ticks = GetTick()
				end
			end
		end,
		Get = function(self)
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
			return finish_ticks
		end,
	}
end

