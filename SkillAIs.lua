-- The option "Condition" is included in the following default option sets.
-- This option allows custom use-conditions to be programmed with functions
--	in the form of "function(_G,target)", where the global environment is
--	accessed through _G.
-- Note: Be careful to never use upvalues, as they cannot be serialized and will
--	cause an error.
-- Example: "return function(_G,target) return target:IsEnemy() end"
--	The above example will return true if the proposed target is an enemy
-- Note: Due to the way loadstring works, you must return the condition function, otherwise
--	it will not be loaded properly.

-- Options
RAIL.Validate.SkillOptions = {is_subtable = true,
	BuffBasePriority = {"number",40},

	-- Default options that all skills will have
	all_default = {is_subtable = true,
		Enabled = {"boolean",true},
		Name = {"string",nil},				-- (default set by init function)
		Condition = {"function",nil,unsaved=true},	-- (default set by init function)
		ReservedSP = {"number",0,0},
		ReservedSPisPercent = {"boolean",false},
	},

	-- Options that all attack skills will have
	atks_default = {is_subtable = true,
		PriorityOffset = {"number",0},
	},

	-- Options that all buff skills will have
	buff_default = {is_subtable = true,
		MaxFailures = {"number",10,1},
		PriorityOffset = {"number",0},
		LastCastSelfID = {"number",0},
		NextCastTime = {"number",0},
	},

	-- Options that all debuff skills will have
	debuff_default = {is_subtable = true,
		MaxFailures = {"number",10,1},
		PriorityOffset = {"number",0.5},
	},

	-- Options that all heal skills will have
	heal_default = {is_subtable = true,
		Priority = {"number",50},
		EstimateFutureTicks = {"number",0,0},

		-- Will only show up if the skill can cast on owner
		OwnerHP = {"number",50,0},
		OwnerHPisPercent = {"boolean",true},

		-- Will only show up if the skill can cast on self
		SelfHP = {"number",0,0},
		SelfHPisPercent = {"boolean",false},
		OnlyAfterIdleFor = {"number",3000,0},
	},

	-- Mental Charge
	--	(inherits from debuff_default and all_default)
	[8004] = {
		MaxFailures = {"number",4},
		PriorityOffset = {"number",15},
	},
	-- Provoke
	--	(inherits from debuff_default and all_default)
	[8232] = {
		ProvokeOwner = {"boolean",true},
	},
}

-- Minimum priority (not an option)
local min_priority = -10000

-- Skill type AIs and selector
do
	-- Private key to hold information on a skill
	local priv_key = {
		Sieves = {},
	}

	local function next_key(s) return RAIL.formatT("NextSkill{1}Time",s.ID) end
	local function failures_key(s) return RAIL.formatT("Skill{1}Failures",s.ID) end
	
	local function usable_sp(actor,skill)
		local options = RAIL.State.SkillOptions[skill.ID]

		local reserved_sp = options.ReservedSP
		if options.ReservedSPisPercent then
			reserved_sp = math.ceil(reserved_sp / 100 * actor:GetMaxSP())
		end
		
		return math.max(0,actor.SP[0] - reserved_sp)
	end

	-- Private key to hold skills
	local skills_key
	skills_key = {
		-- Reuse this table to hold skill AIs

		generic_offensive = {
			range_sieve = {"SkillRangeAndLevel",function(potentials,n,protected,skill,level)
				local ret,ret_n = {},0
		
				if not level then
					level = skill.Level
				end

				local max_failures = RAIL.State.SkillOptions[skill.ID].MaxFailures or 10

				for id,actor in potentials do
					if
						RAIL.Self:DistanceTo(actor) <= skill:GetRange() and
						actor:IsSkillAllowed(level) and

						-- Also check failures and duration
						(actor.BattleOpts[failures_key(skill)] or 0) < max_failures and
						(skill.Duration < 1 or (actor.BattleOpts[next_key(skill)] or 0) <= GetTick()) and

						-- No more things to check
						true
					then
						ret[id] = actor
						ret_n = ret_n + 1
					end
				end
		
				return ret,ret_n,protected
			end},
			condition_sieve = {"SkillCondition",function(potentials,n,protected,skill)
				local ret,ret_n = {},0
		
				for id,actor in potentials do
					if RAIL.State.SkillOptions[skill.ID].Condition(RAIL._G,actor) then
						ret[id] = actor
						ret_n = ret_n + 1
					end
				end
		
				return ret,ret_n,protected
			end},

			callbacks = {
				Success = function(s,target,ticks)
					-- Set failures to 0
					target.BattleOpts[failures_key(s)] = 0

					-- Set the next time that we should cast the skill
					if s.Duration > 0 then
						target.BattleOpts[next_key(s)] = GetTick() - ticks + s.Duration
					end
				end,
				Failure = function(s,target,ticks)
					-- Increment the failures key
					local failures = failures_key(s)
					target.BattleOpts[failures] = (target.BattleOpts[failures] or 0) + 1
				end,
			},

			Init = function(skill,validate_default)
				if validate_default then
					-- Generate a validation table based on the default
					-- Note: If the table exists, it will copy into it
					RAIL.Validate.SkillOptions[skill.ID] = Table.DeepCopy(validate_default,RAIL.Validate.SkillOptions[skill.ID],false)
				end

				-- Generate a sieve
				priv_key.Sieves[skill.ID] = SelectTarget.GenerateSieve(RAIL.formatT("Skill({1})",skill.ID))
				local sieve = priv_key.Sieves[skill.ID]

				-- Add a range sieve
				sieve:Insert(1,skills_key.generic_offensive.range_sieve)

				-- Add condition sieve
				for i=2,sieve:GetN() do
					if sieve[i][1] == "Priority" then
						-- Add the condition sieve
						sieve:Insert(i,skills_key.generic_offensive.condition_sieve)

						break
					end
				end
			end,
			Select = function(skill,callbacks,level_ignore)
				-- Find the level of skill usable this round
				local level = FindSkillLevel(usable_sp(RAIL.Self,skill),skill)

				-- Get the level to indicate to the sieve functions
				local level_override = level
				if level_ignore then
					level_override = 10
				end

				-- Run the sieve and find a target
				local target = priv_key.Sieves[skill.ID](RAIL.ActorLists.Targets,skill,level_override)

				-- Check if a target was found
				if target ~= nil then
					-- Check if the skill level is selectable
					if skill[1] then
						-- Get the level we should use against the monster
						local dummy,level = target:IsSkillAllowed(level)

						-- Set the skill to use
						skill = skill[level]
					end

					-- Get the target priority
					local prio = target.BattleOpts.Priority

					-- And offset it based on options
					prio = prio + RAIL.State.SkillOptions[skill.ID].PriorityOffset

					-- Set the callbacks for the skill
					if type(callbacks) ~= "table" then
						callbacks = skills_key.generic_offensive.callbacks
					end

					RAIL.Self.SkillState.Callbacks:Add(
						skill,
						callbacks.Success,
						callbacks.Failure,
						false
					)

					return prio,skill,target
				end

				-- Otherwise, target nothing
				return
			end,
		},

		Attack = {
			callbacks = {
				Success = function(s,target,ticks)
					-- Increment skill counter
					-- Note: This is checked in Actor.lua's IsSkillAllowed()
					target.BattleOpts.CastsAgainst = (target.BattleOpts.CastsAgainst or 0) + 1
				end,
			},
			Init = function(skill)
				-- Use generic initialization
				return skills_key.generic_offensive.Init(skill,RAIL.Validate.SkillOptions.atks_default)
			end,
			Select = function(skill)
				-- Use generic selection
				local ret = { skills_key.generic_offensive.Select(skill,skills_key.Attack.callbacks) }

				-- Check if a skill was selected
				if ret[2] ~= nil then
					-- Add another callback to count the number of successful casts
					RAIL.Self.SkillState.Callbacks:Add(
						skill,
						skills_key.Attack.callbacks.Success,
						nil,
						false
					)
				end

				-- Return the generic results
				return unpack(ret)
			end,
		},
		Buff = {
			Init = function(skill)
				-- Add to the state validation options
				do
					-- Generate the table, based off of default options
					local validate_byID = RAIL.Validate.SkillOptions
					-- Note: If the table exists, it will copy into it
					validate_byID[skill.ID] = Table.DeepCopy(validate_byID.buff_default,validate_byID[skill.ID],false)
				end

				-- Ensure that the NextCastTime is sane
				if
					RAIL.State.SkillOptions[skill.ID].LastCastSelfID ~= RAIL.Self.ID or
					RAIL.State.Information.InitTime + skill.Duration <
						RAIL.State.SkillOptions[skill.ID].NextCastTime
				then
					RAIL.State.SkillOptions[skill.ID].LastCastSelfID = RAIL.Self.ID
					RAIL.State.SkillOptions[skill.ID].NextCastTime = 0
				end

				-- Set the private key to hold the failure count
				skill[priv_key] = 0

				-- Add callbacks to the skill
				RAIL.Self.SkillState.Callbacks:Add(
					skill,
					function(self,target,ticks)
						-- Reset the failure count
						skill[priv_key] = 0

						-- Set the next time we can use the buff
						RAIL.State.SkillOptions[skill.ID].NextCastTime =
							GetTick() + skill.Duration - ticks
					end,
					function(self,target,ticks)
						-- Increment the failure count
						skill[priv_key] = skill[priv_key] + 1
					end,
					-- Persistent
					true
				)
			end,
			Select = function(skill)
				-- Get the state table
				local state = RAIL.State.SkillOptions[skill.ID]

				-- Check to see if the skill has failed 10 times in a row
				if skill[priv_key] >= state.MaxFailures then
					-- We probably don't actually have this skill; stop trying
					return
				end

				-- Don't use the buff if we don't have enough SP
				-- Note: Disabled; will not use until we have enough SP,
				--	but will prevent lower priority skills from being used
				--if RAIL.Self.SP[0] < skill.SPCost then
				--	return
				--end

				-- Don't use the buff if it's still active
				if GetTick() < state.NextCastTime then
					return
				end

				-- Check the custom condition of the buff
				if state.Condition(RAIL._G,nil) then
					-- Return the skill priority and the skill
					return RAIL.State.SkillOptions.BuffBasePriority + state.PriorityOffset
						,skill,RAIL.Self
				end

				-- Otherwise, return nothing
				return
			end,
		},

		generic_heal = {
			Init = function(skill)
				-- Add to the state validation options
				do
					-- Generate the table, based off of default options
					local byID = RAIL.Validate.SkillOptions
					-- Note: If the table exists, it will copy into it
					byID[skill.ID] = Table.DeepCopy(byID.heal_default,byID[skill.ID],false)
				end
			end,
			Select = function(skill,idletime,owner_skill,self_skill)
				-- Get state skill options table
				local state = RAIL.State.SkillOptions[skill.ID]

				-- Check if we've been idle long enough
				if (idletime or 0) < state.OnlyAfterIdleFor then
					return
				end

				-- Get some skill options for use later
				local priority = state.Priority
				local advance_heal = -state.EstimateFutureTicks

				-- Check owner's HP level
				if owner_skill ~= nil then
					local hp = RAIL.Owner.HP[advance_heal]
					local target = state.OwnerHP
					if state.OwnerHPisPercent then
						hp = math.floor(hp * 100 / RAIL.Owner:GetMaxHP())
						target = math.min(99,target)
					end

					if hp <= target then
						return priority,owner_skill,RAIL.Owner
					end
				end

				-- Check self HP level
				if self_skill ~= nil then
					local hp = RAIL.Self.HP[advance_heal]
					local target = state.SelfHP
					if state.SelfHPisPercent then
						hp = math.min(99,math.floor(hp * 100 / RAIL.Self:GetMaxHP()))
						target = math.min(99,target)
					end

					if hp <= target then
						return priority,self_skill,RAIL.Self
					end
				end

				return
			end,
		},
		HealChaos = {
			Init = function(skill)
				return skills_key.generic_heal.Init(skill)
			end,
			Select = function(skill)
				-- Level 3 has best chance for healing owner, 4 has best chance for healing self
				return skills_key.generic_heal.Select(skill,nil,skill[3],skill[4])
			end,
			IdleSelect = function(skill,idletime)
				return skills_key.generic_heal.Select(skill,idletime,skill[3],skill[4])
			end,
		},
		HealHands = {
			Init = function(skill)
				return skills_key.generic_heal.Init(skill)
			end,
			Select = function(skill)
				return skills_key.generic_heal.Select(skill,nil,skill)
			end,
			IdleSelect = function(skill,idletime)
				return skills_key.generic_heal.Select(skill,idletime,skill)
			end,
		},
		Debuff = {
			Init = function(skill)
				-- Use generic initialization
				local ret = skills_key.generic_offensive.Init(skill,RAIL.Validate.SkillOptions.debuff_default)
			end,
			Select = function(skill,friends)
				-- Use generic selection
				return skills_key.generic_offensive.Select(skill,skills_key.Debuff.callbacks)
			end,
		},
		Emergency = {
			CycleBegin = function(skill)
				-- TODO: Check if RAIL.Owner is in emergency state
				--		and return the skill if it's urgent

				return nil
			end,
		},
		Provoke = {
			Init = function(skill)
				local ret = skills_key.generic_offensive.Init(skill,RAIL.Validate.SkillOptions.debuff_default)

				-- TODO: Add sieve for provokes failed
					-- if the actor hasn't had 10 provoke casts in a row fail against it
					--(actor.BattleOpts.ProvokesFailed or 0) < 10 and


				return ret
			end,
			Select = function(skill)
				-- Get the state file options table
				local state = RAIL.State.SkillOptions[8232]

				-- Run the generic offensive select
				local offensive = { skills_key.generic_offensive.Select(skill,nil,true) }

				-- TODO: Check for provoke against friendly targets
				--	(mercenary provokes can be used friendly, right?)

				-- Otherwise, return the offensive result
				return unpack(offensive)
			end,
		},
	}

	-- Add support for Buff2, Attack2, etc
	--	TODO: clean this up, so they don't count targets twice, etc
	skills_key.Attack2 = skills_key.Attack
	skills_key.Buff2 = skills_key.Buff
	
	SelectSkill = {
		-- Private table of skills that will be checked
		[skills_key] = {},
		Init = function(self,skills)
			-- Types that we have
			local cyclebegin,actorcheck,select,idle = false,false,false,false

			-- Validate options table base
			local byID = RAIL.Validate.SkillOptions

			for ai_type,skill in skills do
				-- Check if we can handle this AI type
				if skills_key[ai_type] then
					-- Add a key-value pair to our private table
					self[skills_key][skill] = skills_key[ai_type]

					-- Init the skill
					if skills_key[ai_type].Init then
						skills_key[ai_type].Init(skill)
					end

					-- Check which functions this skill AI type uses
					if skills_key[ai_type].CycleBegin then cyclebegin = true end
					if skills_key[ai_type].ActorCheck then actorcheck = true end
					if skills_key[ai_type].Select then select = true end
					if skills_key[ai_type].IdleSelect then idle = true end

					-- Set validation options
					do
						-- Copy from all_default, but don't overwrite
						byID[skill.ID] = Table.DeepCopy(byID.all_default,byID[skill.ID],false)

						-- Skill Name
						do
							-- Set the default name
							byID[skill.ID].Name[2] = AllSkills[skill.ID]:GetName()

							-- And rework the skill to now use the name from state file
							AllSkills[skill.ID].GetName = function(self)
								return RAIL.State.SkillOptions[self.ID].Name
							end
						end

						-- Set the default condition
						byID[skill.ID].Condition[2] = AllSkills[skill.ID].Condition
					end
				end
			end

			-- Remove functions that aren't used
			if not cyclebegin then
				self.CycleBegin = function() return nil end
			end
			if not actorcheck then
				self.ActorCheck = function() end
			end
			if not select then
				self.Run = function() return nil end
			end
			if not idle then
				self.RunIdle = function() return nil end
			end
		end,
		CycleBegin = function(self)
			-- If skills aren't usable, do nothing
			if RAIL.Self.SkillState:Get() ~= RAIL.Self.SkillState.Enum.READY then
				return
			end

			-- Loop through each skill
			for skill,ai_obj in self[skills_key] do
				-- Call the skill AI's cycle-begin function
				local urgent
				if RAIL.State.SkillOptions[skill.ID].Enabled then
					if ai_obj.CycleBegin then
						urgent = ai_obj.CycleBegin(skill)
					end
				else
					-- To prevent Select functions from giving an error if they
					--	depend on something from CycleBegin
					ai_obj.wait_for_next_cycle = true
				end

				-- Check if an urgent skill was selected
				if urgent then
					-- Return the skill
					return urgent
				end
			end
		end,
		ActorCheck = function(self,actor)
			-- If skills aren't usable, do nothing
			if RAIL.Self.SkillState:Get() ~= RAIL.Self.SkillState.Enum.READY then
				return
			end

			-- Loop through each skill
			for skill,ai_obj in self[skills_key] do
				if
					ai_obj.ActorCheck and
					RAIL.State.SkillOptions[skill.ID].Enabled and
					not ai_obj.wait_for_next_cycle
				then
					ai_obj.ActorCheck(skill,actor)
				end
			end
		end,
		generic_Run = function(self,func_name,...)
			-- If skills aren't usable, do nothing
			if RAIL.Self.SkillState:Get() ~= RAIL.Self.SkillState.Enum.READY then
				return
			end
			
			-- Loop through each skill
			local best = { min_priority }
			for skill_obj,ai_obj in self[skills_key] do
				local current = { best[1] }
				if
					ai_obj[func_name] and
					RAIL.State.SkillOptions[skill_obj.ID].Enabled and
					not ai_obj.wait_for_next_cycle
				then
					current = { ai_obj[func_name](skill_obj,unpack(arg)) }

					if current[1] == nil then
						current[1] = min_priority
					end
				end

				if current[1] > best[1] then
					best = current
				end

				-- Take off the wait for next cycle flag (if it's off, nothing happens)
				ai_obj.wait_for_next_cycle = nil
			end

			-- Ensure a skill was selected
			if best[1] == min_priority then
				return nil
			end

			-- Check if we don't have enough SP for the skill
			-- Note: Skills don't seem to actually work unless they'll leave
			--	the homunculus/mercenary at above 0 sp.
			if usable_sp(RAIL.Self,best[2]) < best[2].SPCost + 1 then
				RAIL.LogT(65,"Not enough SP to cast highest priority skill; skill={1}, usable sp={2}.",
					best[2],usable_sp(RAIL.Self,best[2]))
				-- Don't use a skill yet
				return nil
			end

			-- Return the skill and target that were selected (if target_x is an actor, target_y will be nil)
			return { best[2], best[3], best[4] }
		end,
		Run = function(self)
			return self:generic_Run("Select")
		end,
		RunIdle = function(self,idletime)
			return self:generic_Run("IdleSelect",idletime)
		end,
	}
end
