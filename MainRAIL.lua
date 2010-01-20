-- Save the global environment that RAIL is loaded from
RAIL._G = getfenv(0)

-- Load State.lua before all others, to allow others to add state validation options
require "State.lua"

-- Alphabetical
require "Const.lua"
require "Debug.lua"
require "History.lua"
require "Table.lua"
require "Timeout.lua"
require "Utils.lua"

-- Load-time Dependency
require "Actor.lua"		-- depends on History.lua
require "Commands.lua"		-- depends on Table.lua
require "DecisionSupport.lua"	-- depends on Table.lua
require "Skills.lua"		-- depends on Table.lua

-- State validation options
RAIL.Validate.AcquireWhileLocked = {"boolean",false}
RAIL.Validate.DefendFriends = {"boolean",false}
RAIL.Validate.FollowDistance = {"number", 7, 3, 14}
RAIL.Validate.MaxDistance = {"number", 13, 3, 14}

function AI(id)
	-- Get Owner and Self
	RAIL.Owner = Actors[GetV(V_OWNER,id)]
	RAIL.Self  = Actors[id]

	-- Store the initialization time
	RAIL.Self.InitTime = GetTick()

	-- Create a bogus Other until homu<->merc communication is established
	RAIL.Other = RAIL.Self

	-- Get our attack range
	RAIL.Self.AttackRange = GetV(V_ATTACKRANGE,id)

	-- Track HP and SP
	do
		local update = RAIL.Self.Update
		-- An extended variant of Update(), to track HP and SP values
		RAIL.Owner.Update = function(self)
			-- First, call the regular update
			update(self)

			-- The extended tracking information will be useless against other actors
			if self.ID ~= RAIL.Owner and self.ID ~= RAIL.Self then
				return self
			end
	
			-- Update the HP and SP tables
			History.Update(self.HP,GetV(V_HP,self.ID))
			History.Update(self.SP,GetV(V_SP,self.ID))

			return self
		end
		RAIL.Self.Update = RAIL.Owner.Update

		-- Use the maximum values as default, but don't calculate sub-update values
		RAIL.Owner.HP = History.New(GetV(V_MAXHP,RAIL.Owner.ID),false)
		RAIL.Owner.SP = History.New(GetV(V_MAXSP,RAIL.Owner.ID),false)
		RAIL.Self.HP = History.New(GetV(V_MAXHP,RAIL.Self.ID),false)
		RAIL.Self.SP = History.New(GetV(V_MAXSP,RAIL.Self.ID),false)
	end

	-- Never show up as either enemies or friends
	RAIL.Owner.IsEnemy  = function() return false end
	RAIL.Owner.IsFriend = function() return false end
	RAIL.Self.IsEnemy   = function() return false end
	RAIL.Self.IsFriend  = function() return false end

	-- Save some processing power on later cycles
	RAIL.Owner.ExpireTimeout[1] = false
	RAIL.Self.ExpireTimeout[1] = false

	if RAIL.Mercenary then
		RAIL.Self.AI_Type = GetV(V_MERTYPE,id)
	else
		RAIL.Self.AI_Type = GetV(V_HOMUNTYPE,id)
	end
	RAIL.Self.Skills = GetSkillList(RAIL.Self.AI_Type)

	-- Load persistent state data
	RAIL.State:Load(true)

	-- Periodically save state data
	RAIL.Timeouts:New(2500,true,function()
		-- Only load data if the "update" flag is on in the file
		RAIL.State:Load(false)

		-- Save data (if any data was loaded, it won't be dirty and won't save)
		RAIL.State:Save()
	end)

	AI = ProfilingHook("RAIL.AI",RAIL.AI,50)
	AI(id)
end

-- Targeting histories
RAIL.TargetHistory = {
	Skill = {
		UseTime = 0,
		ReadyTime = 0,
		Target = -1,
	},
	Attack = -1,
	Chase = -1,
	Move = {
		DanceTarget = -1,
		X = -1,
		Y = -1,
	},
}

function RAIL.AI(id)
	-- Potential targets
	local Potential = {
		Skill = {},
		Attack = {},
		Chase = {},
	}

	-- Decided targets
	local Target = {
		Skill = nil,
		Attack = nil,
		Chase = nil,
	}

	local Friends = {}

	-- Flag to terminate processing after data collection
	local terminate = nil

	-- Max attack skill level that we can use
	local max_skill_level = 0

	-- Update actor information
	do
		-- Update owner, self, and other before every other actor
		RAIL.Owner:Update()
		RAIL.Self:Update()
		if RAIL.Other ~= RAIL.Self then
			RAIL.Other:Update()
		end

		-- Determine if we need to chase our owner
		do
			-- Owner-chase estimation is based on max distance
			local max_estim = (-1 * math.ceil(RAIL.State.MaxDistance / 4) + (-2))
				* RAIL.Owner:EstimateMove()
			local fol_estim = (-1 * math.ceil(RAIL.State.FollowDistance / 4))
				* RAIL.Owner:EstimateMove()

			if
				-- Debug toggle for interception
				(false and RAIL.Owner.Motion[0] == MOTION_MOVE) or

				-- Regular determination
				RAIL.Self:BlocksTo(0)(
					-- Guess some tiles ahead, so homu/merc isn't off screen when finally decides to move
					RAIL.Owner.X[max_estim],
					RAIL.Owner.Y[max_estim]
				) > RAIL.State.MaxDistance or
	
				-- Continue following
				(RAIL.TargetHistory.Chase == RAIL.Owner.ID and
				RAIL.Owner.Motion[0] == MOTION_MOVE and
				RAIL.Self:BlocksTo(0)(
					-- Guess some tiles ahead when already following
					RAIL.Owner.X[fol_estim],
					RAIL.Owner.Y[fol_estim]
				) > RAIL.State.FollowDistance)
			then
				Target.Chase = RAIL.Owner
			end
		end

		-- Determine if we can use an attack skill this cycle
		if RAIL.Self.Skills.Attack and RAIL.TargetHistory.Skill.ReadyTime <= GetTick() then
			-- Check if we have the SP for it
			if RAIL.Self.Skills.Attack.SPCost < RAIL.Self.SP[0] then
				-- Have SP for highest level
				max_skill_level = RAIL.Self.Skills.Attack.Level

			-- Check if the skill level is selectable
			elseif RAIL.Self.Skills.Attack[1] then
				-- Find the highest level that the skill is usable on
				for i=1,10 do
					-- This level doesn't exist
					if RAIL.Self.Skills.Attack[i] == nil then
						break
					end

					-- See if we have SP for this level's cost
					if RAIL.Self.Skills.Attack[i].SPCost < RAIL.Self.SP[0] then
						max_skill_level = i
					end
				end
			end
		end

		-- Update all the on-screen actors
		local i,actor
		for i,actor in ipairs(GetActors()) do
			-- Don't double-update the owner or self
			if RAIL.Owner.ID ~= actor and RAIL.Self.ID ~= actor and RAIL.Other.ID ~= actor then
				-- Indexing non-existant actors will auto-create them
				local actor = Actors[actor]

				-- Update the information about it
				actor:Update()

				-- If the actor that was just updated is a portal
				if actor.Type == 45 and not terminate then
					-- Get the block distances between the portal and the owner
						-- roughly 1.5 tiles from now
					local inFuture = RAIL.Owner:BlocksTo(-1.5*RAIL.Owner:EstimateMove())(actor)
						-- and now
					local now = RAIL.Owner:BlocksTo(actor)

					if inFuture < 3 and inFuture < now then
						terminate = actor
					end
				end

				-- If we're chasing owner, we won't be doing anything else
				if Target.Chase ~= RAIL.Owner then

					-- Make sure we're not ignoring the actor
					if not actor:IsIgnored() then

						-- Check if the actor is an enemy
						if actor:IsEnemy() then
							local dist = RAIL.Self:DistanceTo(actor)

							-- Check if physical attacks are allowed against the enemy
							if actor:IsAttackAllowed() then
								-- If it's in range, add it to the potential attack list
								if dist <= RAIL.Self.AttackRange then
									Potential.Attack[actor.ID] = actor
								else
									-- Otherwise, add it to the potential chase list
									Potential.Chase[actor.ID] = actor
								end
							end

							if
								-- Check if we have magic attacks
								max_skill_level >= actor.BattleOpts.MinSkillLevel and
								-- And skills are allowed
								actor:IsSkillAllowed() and
								-- And a skill would be ready against this monster
								RAIL.TargetHistory.Skill.ReadyTime + actor.BattleOpts.TicksBetweenSkills <= GetTick()
							then
								-- If it's in range, add it to the potential skill list
								if dist <= RAIL.Self.Skills.Attack:GetRange() then
									Potential.Skill[actor.ID] = actor
								else
									-- Otherwise, add it to the potential chase list
									Potential.Chase[actor.ID] = actor
								end
							end
						end

						-- Keep track of friends
						if actor:IsFriend() then
							Friends[actor.ID] = actor
						end

					end -- not actor:IsIgnored()
				end -- Target.Chase ~= RAIL.Owner
			end -- RAIL.Owner.ID ~= actor
		end -- i,actor in ipairs(GetActor())
	end

	-- Iterate through the timeouts
	RAIL.Timeouts:Iterate()

	-- Process commands
	do
		-- Check for a regular command
		local shift = false
		local msg = GetMsg(RAIL.Self.ID)

		if msg[1] == NONE_CMD then
			-- Check for a shift+command
			shift = true
			msg = GetResMsg(RAIL.Self.ID)
		end

		-- Process any input command
		RAIL.Cmd.ProcessInput[msg[1]](shift,msg)

	end

	-- Check if the cycle should terminate early
	if terminate then
		RAIL.LogT(7,"Owner approaching {1}; cycle terminating after data collection.",terminate)

		-- Save state data before terminating
		RAIL.State:Save()

		-- Terminate this cycle early
		return
	end

	-- Pre-decision cmd queue evaluation
	do
		while RAIL.Cmd.Queue:Size() > 0 do
			local msg = RAIL.Cmd.Queue[RAIL.Cmd.Queue.first]

			if msg[1] == MOVE_CMD then
				-- Check for a couple states that would invalidate the move
				if
					-- Move would be out of range
					RAIL.Owner:BlocksTo(msg[2],msg[3]) > RAIL.State.MaxDistance or
					-- Already arrived
					RAIL.Self:DistanceTo(msg[2],msg[3]) < 1
				then
					-- Remove this command
					RAIL.Cmd.Queue:PopLeft()
				else
					-- Set this command, unless chasing owner
					if Target.Chase ~= RAIL.Owner then
						Target.Chase = msg
					end
					break
				end

			elseif msg[1] == ATTACK_OBJECT_CMD then
				-- Check for valid actor
				local actor = Actors[msg[2]]
				if math.abs(GetTick() - actor.LastUpdate) > 100 or
					actor.Motion[0] == MOTION_DEAD
				then
					-- Invalid actor
					RAIL.Cmd.Queue:PopLeft()
				else
					-- If close enough, attack the monster
					if RAIL.Self:DistanceTo(actor) <= RAIL.Self.AttackRange then
						Target.Attack = actor
					else
						-- Otherwise, chase the monster
						Target.Chase = actor
					end

					break
				end
			else
				-- Skill commands are only thing left over
				if Target.Skill == nil then
					Target.Skill = msg
				else
					break
				end
			end
		end
	end

	-- Decision Making
	do
		-- Skill
		if Target.Skill == nil and Target.Chase ~= RAIL.Owner then
			local skill = RAIL.Self.Skills.Attack
			local target = SelectTarget.Skill.Attack(Potential.Skill,Friends)
			if target ~= nil then
				-- Check if the level is selectable
				if skill[1] then
					-- Determine the level of the skill to use
					skill = skill[math.min(target.BattleOpts.MaxSkillLevel,max_skill_level)]
				end

				-- Set the skill target
				Target.Skill = { skill, target }
			end
		end

		-- Attack
		if Target.Attack == nil and Target.Chase ~= RAIL.Owner then
			-- Use routines from DecisionSupport.lua to determine the best actor
			Target.Attack = SelectTarget.Attack(Potential.Attack,Friends)
		end

		-- Move
		if Target.Chase == nil then
			-- Check to see if we should add our attack target to the chase list as well
			if not RAIL.State.AcquireWhileLocked and Target.Attack ~= nil then
				Potential.Chase[Target.Attack.ID] = Target.Attack
			end

			-- Find highest priority monster to move toward
			Target.Chase = SelectTarget.Chase(Potential.Chase,Friends)
		end
	end

	-- Record the targets
	do
		-- TODO: Skill
		-- Skill
		if Target.Skill ~= nil then
			-- TODO: check for interrupted skills
			local skill = Target.Skill[1]
			RAIL.TargetHistory.Skill.UseTime = GetTick()
			RAIL.TargetHistory.Skill.ReadyTime = GetTick() + skill.CastTime + skill.CastDelay
			if RAIL.IsActor(Target.Skill[2]) then
				RAIL.TargetHistory.Skill.Target = Target.Skill[2]
			else
				RAIL.TargetHistory.Skill.Target = -1
			end
		end

		-- Attack
		if Target.Attack ~= nil then
			RAIL.TargetHistory.Attack = Target.Attack.ID
		else
			RAIL.TargetHistory.Attack = -1
		end

		-- Chase
		if Target.Chase ~= nil then
			RAIL.TargetHistory.Chase = Target.Chase.ID
		else
			RAIL.TargetHistory.Chase = -1
		end
	end

	-- Action
	do
		-- Skill
		if Target.Skill ~= nil then
			local skill = Target.Skill[1]
			local target_x = Target.Skill[2]
			local target_y = Target.Skill[3]

			-- Check if the target is an actor
			if RAIL.IsActor(target_x) then
				-- Use the skill
				target_x:SkillObject(skill)
			else
				-- Use the ground skill
				skill:Cast(target_x,target_y)
			end
		end

		-- Attack
		if Target.Attack ~= nil then
			-- Log it
			RAIL.LogT(70,"Using physical attack against {1}.",Target.Attack)

			-- Send the attack
			Target.Attack:Attack()
		end

		-- Move
		local x,y
		if Target.Chase ~= nil and Target.Chase ~= Target.Attack then

			if RAIL.IsActor(Target.Chase) then
				-- Move to actor
				x,y = CalculateIntercept(Target.Chase)

				-- Check if it's an enemy (likely chasing to attack it)
				if Target.Chase:IsEnemy() then
					local angle,dist = RAIL.Self:AngleTo(x,y)

					-- Check if the enemy is outside of attack range
					-- TODO: check skill ranges
					if dist > RAIL.Self.AttackRange then
						-- Replot a new target move
						x,y = RAIL.Self:AnglePlot(angle,dist - RAIL.Self.AttackRange + 1)
					end
				end
			else
				-- Move to ground
				x,y = Target.Chase[2],Target.Chase[3]
			end

		elseif Target.Attack ~= nil then
		--[[ Disabled; not working as intended
			-- Use "dance step" while attacking
			local target = RAIL.Owner
			if
				Target.Attack.ID ~= RAIL.TargetHistory.Move.DanceTarget or
				RAIL.Self:DistanceTo(Target.Attack) + 1 > RAIL.Self.AttackRange
			then
				target = Target.Attack
			end

			-- Get the angle and distance to the target
			local angle,dist = RAIL.Self:AngleTo(target)

			RAIL.LogT(0,"dance step target = {1}; angle = {2}; dist = {3}",target,angle,dist)

			-- Move one tile closer to the target
			x,y = RAIL.Self:AnglePlot(angle, dist - 1)

			-- Save the dance step target
			RAIL.TargetHistory.Move.DanceTarget = target.ID
		--]]
		else

			-- If moving, then stop.
			--if RAIL.Self.Motion[0] == MOTION_MOVE then
			--	x,y = RAIL.Self.X[0], RAIL.Self.Y[0]
			--end

			-- TODO: Idle movement?
		end

		if type(x) == "number" and type(y) == "number" then
			-- Make sure the move isn't outside MaxDistance
			local owner_estim = (-1 * math.ceil(RAIL.State.MaxDistance / 4) + (-2))
				* RAIL.Owner:EstimateMove()
			local x_d = RAIL.Owner.X[owner_estim] - x
			local y_d = RAIL.Owner.Y[owner_estim] - y
			if x_d > RAIL.State.MaxDistance then
				x_d = RAIL.State.MaxDistance
			elseif x_d < -RAIL.State.MaxDistance then
				x_d = -RAIL.State.MaxDistance
			end
			if y_d > RAIL.State.MaxDistance then
				y_d = RAIL.State.MaxDistance
			elseif y_d < -RAIL.State.MaxDistance then
				y_d = -RAIL.State.MaxDistance
			end
			x = RAIL.Owner.X[owner_estim] - x_d
			y = RAIL.Owner.Y[owner_estim] - y_d

			-- Make sure the target coords are short enough that the server won't ignore them
			local angle,dist = RAIL.Self:AngleTo(x,y)
			while dist > 10 do
				dist = dist / 2
			end
			-- Plot a shorter distance in the same direction
			x,y = RAIL.Self:AnglePlot(angle,dist)

			-- Make the numbers nice and round
			x = RoundNumber(x)
			y = RoundNumber(y)

			-- Check if we tried to move here last cycle
			if x == RAIL.TargetHistory.Move.X and y == RAIL.TargetHistory.Move.Y then
				-- TODO: Alter move such that repeated moves to same location
				--		aren't ignored
			end

			-- Check if the move would be a duplicate
			if
				x ~= RAIL.TargetHistory.Move.X or
				y ~= RAIL.TargetHistory.Move.Y or
				Target.Attack ~= nil or
				Target.Skill ~= nil
			then
				-- Log it
				RAIL.LogT(85,"Moving to ({1},{2}).",x,y)
	
				-- Send the move
				Move(RAIL.Self.ID,x,y)

				-- Save the move history
				RAIL.TargetHistory.Move.X = x
				RAIL.TargetHistory.Move.Y = y
			end
		end
	end
end

-- Script is loaded...
RAIL.LogT(0,"\r\n\r\n\r\nRAIL loaded...")
