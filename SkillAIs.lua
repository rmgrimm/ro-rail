-- Options
RAIL.Validate.SkillOptions = {is_subtable = true,
	ProvokePriorityOffset = {"number",0.5},
	Attacks = {is_subtable = true,
		BySkillID = {is_subtable = true,
			default = {is_subtable = true,
				PriorityOffset = {"number",0},
			},
		},
	},
	Buffs = {is_subtable = true,
		BasePriority = {"number",40},
		BySkillID = {is_subtable = true,
			default = {is_subtable = true,
				PriorityOffset = {"number",0},
				NextCastTime = {"number",0},

				-- Condition takes a function in the form of "function(_G)",
				--	where the global environment is accessed through _G.
				-- Note: Be careful to never use upvalues, as they cannot be
				--	serialized
				Condition = {"function",nil},	-- (default set by Buff Init function)
			},
		},
	},
	ChaosHeal = {is_subtable = true,
		Priority = {"number",50},
		EstimateFutureTicks = {"number",0,0},
		OwnerHP = {"number",50,0},
		OwnerHPisPercent = {"boolean",true},
		SelfHP = {"number",0,0},
		SelfHPisPercent = {"boolean",false},
	},
}

-- Minimum priority (not an option)
local min_priority = -10000

-- Skill type AIs and selector
do
	-- Private key to hold information on a skill
	local priv_key = {}

	-- Private key to hold skills
	local skills_key
	skills_key = {
		-- Reuse this table to hold skill AIs
		Attack = {
			Init = function(skill)
				-- Generate a validation table based on the default Attacks validation table
				local validate_byID = RAIL.Validate.SkillOptions.Attacks.BySkillID
				validate_byID[skill.ID] = Table.DeepCopy(validate_byID.default)

				priv_key.AttackSieve = Table.New()

				-- Copy the attack target sieve, but drop retargeting
				for i=1,SelectTarget.Attack:GetN() do
					if SelectTarget.Attack[i][1] ~= "Retarget" then
						priv_key.AttackSieve:Append(SelectTarget.Attack[i])
					end
				end

				-- Set the metatable from SelectTarget.Attack's metatable
				setmetatable(priv_key.AttackSieve,getmetatable(SelectTarget.Attack))

				-- Generate the skill success and failure callbacks now
				priv_key.AttackCallbacks = {
					Success = function(s,target,ticks)
						-- Reset skill-failed counter
						target.BattleOpts.CastsFailed = 0

						-- Increment skill counter
						target.BattleOpts.CastsAgainst = (target.BattleOpts.CastsAgainst or 0) + 1
					end,
					Failure = function(s,target,ticks)
						-- Increment skill-failed counter
						target.BattleOpts.CastsFailed = (target.BattleOpts.CastsFailed or 0) + 1

						-- TODO: Ignore completely (attacks and skills) after
						--		a number of consequtive failures
					end
				}
			end,
			CycleBegin = function(skill)
				skill[priv_key] = {}

				-- Create a temporary list of potential skill targets
				skill[priv_key].Targets = {}

				-- Get the level of skill usable this round
				skill[priv_key].Level = FindSkillLevel(RAIL.Self.SP[0],skill)

				-- Create a temporary list of friends
				skill[priv_key].Friends = {}

				-- Don't return anything, since no skill usage is urgent
				return
			end,
			ActorCheck = function(skill,actor)
				-- Check...
				if
					-- if the actor is an enemy
					actor:IsEnemy() and
					-- if skills are allowed against it
					actor:IsSkillAllowed(skill[priv_key].Level) and
					-- and it's in range
					RAIL.Self:DistanceTo(actor) <= skill:GetRange()
				then
					-- Add it to the temporary list
					skill[priv_key].Targets[actor.ID] = actor
				elseif
					actor:IsFriend()
				then
					-- Add it to the temporary friend list
					skill[priv_key].Friends[actor.ID] = actor
				end
			end,
			Select = function(skill,friends)

				-- Run the sieve and find a target
				local target = priv_key.AttackSieve(skill[priv_key].Targets,skill[priv_key].Friends)

				-- Check if a target was found
				if target ~= nil then
					-- Check if the skill level is selectable
					if skill[1] then
						-- Get the level we should use against the monster
						local dummy,level = target:IsSkillAllowed(skill[priv_key].Level)

						-- Set the skill to use
						skill = skill[level]
					end

					-- Get the target priority
					local prio = target.BattleOpts.Priority

					-- And offset it based on options
					prio = prio + RAIL.State.SkillOptions.Attacks.BySkillID[skill.ID].PriorityOffset

					-- Set the callbacks for the skill
					RAIL.Self.SkillState.Callbacks:Add(
						skill,
						priv_key.AttackCallbacks.Success,
						priv_key.AttackCallbacks.Failure,
						false
					)

					return prio,skill,target
				end

				-- Otherwise, target nothing
				return
			end,
		},
		Buff = {
			Init = function(skill)
				-- Add to the state validation options
				do
					-- Generate the table, based off of default options
					local validate_byID = RAIL.Validate.SkillOptions.Buffs.BySkillID
					validate_byID[skill.ID] = Table.DeepCopy(validate_byID.default)

					-- Set the default condition
					validate_byID[skill.ID].Condition[2] = skill.Condition
				end

				-- Ensure that the NextCastTime is sane
				if RAIL.State.Information.InitTime + skill.Duration <
					RAIL.State.SkillOptions.Buffs.BySkillID[skill.ID].NextCastTime
				then
					RAIL.State.SkillOptions.Buffs.BySkillID[skill.ID].NextCastTime = 0
				end

				-- Set the private key to hold the next time the skill should be used
				skill[priv_key] = {
					Failures = 0,
				}

				-- Add callbacks to the skill
				RAIL.Self.SkillState.Callbacks:Add(
					skill,
					function(self,target,ticks)
						-- Reset the failure count
						skill[priv_key].Failures = 0

						-- Set the next time we can use the buff
						RAIL.State.SkillOptions.Buffs.BySkillID[skill.ID].NextCastTime =
							GetTick() + skill.Duration - ticks
					end,
					function(self,target,ticks)
						-- Increment the failure count
						skill[priv_key].Failures = skill[priv_key].Failures + 1
					end,
					-- Persistent
					true
				)
			end,
			Select = function(skill)
				-- Check to see if the skill has failed 10 times in a row
				--	TODO: option for max failures
				if skill[priv_key].Failures >= 10 then
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
				if GetTick() < RAIL.State.SkillOptions.Buffs.BySkillID[skill.ID].NextCastTime then
					return
				end

				-- Check the custom condition of the buff
				if RAIL.State.SkillOptions.Buffs.BySkillID[skill.ID].Condition(RAIL._G) then
					-- Return the skill priority and the skill
					return RAIL.State.SkillOptions.Buffs.BasePriority + RAIL.State.SkillOptions.Buffs.BySkillID[skill.ID].PriorityOffset
					,skill,RAIL.Self
				end

				-- Otherwise, return nothing
				return
			end,
		},
		ChaosHeal = {
			Select = function(skill)
				-- Get some skill options for use later
				local priority = RAIL.State.SkillOptions.ChaosHeal.Priority
				local advance_heal = -RAIL.State.SkillOptions.ChaosHeal.EstimateFutureTicks

				-- Check if we're going for percentages
				local owner_cur_hp = RAIL.Owner.HP[advance_heal]
				if RAIL.State.SkillOptions.ChaosHeal.OwnerHPisPercent then
					owner_cur_hp = math.floor(owner_cur_hp * 100 / RAIL.Owner:GetMaxHP())
				end
				local self_cur_hp = RAIL.Self.HP[advance_heal]
				if RAIL.State.SkillOptions.ChaosHeal.SelfHPisPercent then
					self_cur_hp = math.floor(self_cur_hp * 100 / RAIL.Self:GetMaxHP())
				end

				-- Check to see if we should try healing our owner
				if owner_cur_hp <= RAIL.State.SkillOptions.ChaosHeal.OwnerHP then
					-- Heal our owner
					--	Note: level 3 has 50% chance to heal owner
					return priority,skill[3],RAIL.Owner

				elseif self_cur_hp <= RAIL.State.SkillOptions.ChaosHeal.SelfHP then
					-- Heal our homunculus
					--	Note: level 4 has a 60% chance to heal self
					return priority,skill[4],RAIL.Self

				end

				-- Return nothing
				return
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
				priv_key.ProvokeSieve = Table.New()

				-- Copy the attack targeting sieve, but drop retargeting
				for i=1,SelectTarget.Attack:GetN() do
					if SelectTarget.Attack[i][1] ~= "Retarget" then
						priv_key.ProvokeSieve:Append(SelectTarget.Attack[i])
					end
				end

				-- Set the metatable from SelectTarget.Attack's metatable
				setmetatable(priv_key.ProvokeSieve,getmetatable(SelectTarget.Attack))

				-- Generate the skill success and failure callbacks now
				priv_key.ProvokeCallbacks = {
					Success = function(s,target,ticks)
						-- Reset skill-failed counter
						target.BattleOpts.ProvokesFailed = 0

						-- Set the time of the provoke
						target.BattleOpts.LastProvokeTick = GetTick() - ticks
					end,
					Failure = function(s,target,ticks)
						-- Increment skill-failed counter
						target.BattleOpts.ProvokesFailed = (target.BattleOpts.ProvokesFailed or 0) + 1
					end
				}
			end,
			CycleBegin = function(skill)
				skill[priv_key] = {}

				-- Create a temporary list of potential skill targets
				skill[priv_key].Targets = {}

				-- Create a temporary list of friends
				skill[priv_key].Friends = {}

				-- Don't return anything, since no skill usage is urgent
				return
			end,
			ActorCheck = function(skill,actor)
				-- Check...
				if
					-- if the actor is an enemy
					actor:IsEnemy() and
					-- if skills are allowed against it
					--	(don't let provoke be disqualified because of its level)
					actor:IsSkillAllowed(10) and
					-- if the actor hasn't had 10 provoke casts in a row fail against it
					(actor.BattleOpts.ProvokesFailed or 0) < 10 and
					-- if the actor hasn't been provoked recently
					GetTick() - (actor.BattleOpts.LastProvokeTick or 0) > skill.Duration and
					-- and it's in range
					RAIL.Self:DistanceTo(actor) <= skill:GetRange()
				then
					-- Add it to the temporary list
					skill[priv_key].Targets[actor.ID] = actor
				elseif
					actor:IsFriend()
				then
					-- Add it to the temporary friend list
					skill[priv_key].Friends[actor.ID] = actor
				end
			end,
			Select = function(skill,friends)

				-- Run the sieve and find an enemy target
				local target = priv_key.ProvokeSieve(skill[priv_key].Targets,skill[priv_key].Friends)

				-- Check if a target was found
				local prio
				if target ~= nil then
					-- Get the target priority
					prio = target.BattleOpts.Priority

					-- And offset it based on options
					prio = prio + RAIL.State.SkillOptions.ProvokePriorityOffset
				end

				-- TODO: Check for provoke against friendly targets
				--	(mercenary provokes can be used friendly, right?)

				-- Check if a target was selected
				if prio ~= nil then
					-- Set the callbacks for the skill
					RAIL.Self.SkillState.Callbacks:Add(
						skill,
						priv_key.ProvokeCallbacks.Success,
						priv_key.ProvokeCallbacks.Failure,
						false
					)
	
					return prio,skill,target
				end

				-- Otherwise, target nothing
				return
			end,
		},
	}


	-- TODO: Add support for Buff2, Attack2, etc


	SelectSkill = {
		-- Private table of skills that will be checked
		[skills_key] = {},
		Init = function(self,skills)
			-- Types that we have
			local cyclebegin,actorcheck,select = false,false,false

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
				self.Select = function() return nil end
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
				if ai_obj.CycleBegin then
					urgent = ai_obj.CycleBegin(skill)
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
				if ai_obj.ActorCheck then
					ai_obj.ActorCheck(skill,actor)
				end
			end
		end,
		Run = function(self)
			-- If skills aren't usable, do nothing
			if RAIL.Self.SkillState:Get() ~= RAIL.Self.SkillState.Enum.READY then
				return
			end

			-- Loop through each skill
			local best_prio,best_skill,best_target_x,best_target_y = min_priority
			for skill_obj,ai_obj in self[skills_key] do
				local prio,skill,target_x,target_y = best_prio,nil,nil
				if ai_obj.Select then
					prio,skill,target_x,target_y = ai_obj.Select(skill_obj)

					if prio == nil then
						prio = min_priority
					end
				end

				if prio > best_prio then
					best_prio,best_skill,best_target_x,best_target_y = prio,skill,target_x,target_y
				end
			end

			-- Ensure a skill was selected
			if best_prio == min_priority then
				return nil
			end

			-- Check if we don't have enough SP for the skill
			if RAIL.Self.SP[0] < best_skill.SPCost then
				-- Don't use a skill yet
				return nil
			end

			-- Return the skill and target that were selected (if target_x is an actor, target_y will be nil)
			return { best_skill, best_target_x, best_target_y }
		end
	}
end
