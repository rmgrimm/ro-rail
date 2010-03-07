-- Save the global environment that RAIL is loaded from
RAIL._G = getfenv(0)

-- Load the configuration options
require "Config.lua"

-- Load State.lua before all other code, to allow others to add state
--	validation options
require "State.lua"

-- Alphabetical
require "ActorOpts.lua"
require "Const.lua"
require "Debug.lua"
require "History.lua"
require "SkillAIs.lua"
require "Table.lua"
require "Timeout.lua"
require "Utils.lua"

-- Load-time Dependency
require "Actor.lua"		-- depends on History.lua
require "Commands.lua"		-- depends on Table.lua
require "DecisionSupport.lua"	-- depends on Table.lua
require "Skills.lua"		-- depends on Table.lua
require "SkillSupport.lua"	-- depends on Actor.lua

-- State validation options
RAIL.Validate.Information = {is_subtable = true,
	InitTime = {"number", 0},
	OwnerID = {"number", 0},
	OwnerName = {"string", "unknown"},
	SelfID = {"number", 0},
}

RAIL.Validate.AcquireWhileLocked = {"boolean",false}
RAIL.Validate.AttackWhileChasing = {"boolean",false}

RAIL.Validate.RunAhead = {"boolean",false}
RAIL.Validate.MaxDistance = {"number", 13, 3, 14}
RAIL.Validate.FollowDistance = {"number", 7, 3, 14}

function AI(id)
	-- Load persistent state data
	RAIL.State:SetOwnerID(GetV(V_OWNER,id))
	RAIL.State:Load(true)

	-- Store the initialization time
	RAIL.State.Information.InitTime = GetTick()
	RAIL.State.Information.OwnerID = GetV(V_OWNER,id)
	RAIL.State.Information.SelfID = id

	-- Get Owner and Self
	RAIL.Owner = Actors[GetV(V_OWNER,id)]
	RAIL.LogT(40," --> Owner; Name = {1}",RAIL.State.Information.OwnerName)
	RAIL.Self  = Actors[id]

	-- Get AI type
	if RAIL.Mercenary then
		RAIL.Self.AI_Type = GetV(V_MERTYPE,id)
	else
		RAIL.Self.AI_Type = GetV(V_HOMUNTYPE,id)
	end
	RAIL.Self.Skills = GetSkillList(RAIL.Self.AI_Type)

	-- Get our attack range
	RAIL.Self.AttackRange = GetV(V_ATTACKRANGE,id)

	-- AttackRange seems to be misreported for melee
	if RAIL.Self.AttackRange <= 2 then
		RAIL.Self.AttackRange = 1.5
	end

	-- Log extra information about self
	RAIL.LogT(40," --> Self; AI_Type = {2}; Attack Range = {3}",RAIL.Self,RAIL.Self.AI_Type,RAIL.Self.AttackRange)

	-- Extra info about skills
	do
		local buf = StringBuffer.New()
		for skill_type,skill in pairs(RAIL.Self.Skills) do
			buf:Append(skill.Name)
			if type(skill_type) == "string" then
				buf:Append(" as AI's \""):Append(skill_type):Append("\"")
			end
			buf:Append("; ")
		end
		RAIL.LogT(40," --> Skills: {1}",buf:Append(" "):Get())
	end

	-- Create a bogus Other until homu<->merc communication is established
	RAIL.Other = RAIL.Self

	-- Track HP and SP
	do
		local update = RAIL.Owner.Update
		-- An extended variant of Update(), to track HP and SP values
		RAIL.Owner.Update = function(self,...)
			-- First, call the regular update
			update(self,unpack(arg))

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

	-- Track skill state for self
	--	Note: This will hook Update(), so it has to be after SP check hook
	RAIL.Self:InitSkillState()

	-- Initialize Skill decision making
	SelectSkill:Init(RAIL.Self.Skills)

	-- Never show up as either enemies or friends
	RAIL.Owner.IsEnemy  = function() return false end
	RAIL.Owner.IsFriend = function() return false end
	RAIL.Self.IsEnemy   = function() return false end
	RAIL.Self.IsFriend  = function() return false end

	-- Save some processing power on later cycles
	RAIL.Owner.ExpireTimeout[1] = false
	RAIL.Self.ExpireTimeout[1] = false

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
	Attack = -1, -- History.New(-1,false),
	Chase = History.New(-1,false),
	Move = {
		DanceTarget = -1,
		X = -1,
		Y = -1,
	},
}

function RAIL.AI(id)
	-- Potential targets
	local Potential = {
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

	-- Update actor information
	do
		-- Update owner and self before every other actor
		RAIL.Owner:Update()
		RAIL.Self:Update()

		-- Check if action is impossible due to casting time
		if RAIL.Self.SkillState:Get() == RAIL.Self.SkillState.Enum.CASTING then
			-- Terminate due to skill state
			terminate = RAIL.Self.SkillState
		end

		-- Check if we're terminating this round
		if not terminate then
			-- Determine if we need to chase our owner
			do
				-- Check that chasing would be worthwhile
				if terminate == nil then
					-- Check if we're following normally
					if not RAIL.State.RunAhead then
						-- Owner-chase estimation is based on max distance
						local max_estim = (-1 * math.ceil(RAIL.State.MaxDistance / 4))
							* RAIL.Owner:EstimateMove()

						if
							RAIL.Self:BlocksTo(0)(
								-- Guess some tiles ahead, so homu/merc isn't off screen when finally decides to move
								RAIL.Owner.X[max_estim],
								RAIL.Owner.Y[max_estim]
							) > RAIL.State.MaxDistance or

							-- Continue following
							(RAIL.TargetHistory.Chase[0] == RAIL.Owner.ID and
							RAIL.Owner.Motion[0] == MOTION_MOVE and
							RAIL.Self:BlocksTo(0)(
								-- Guess some tiles ahead when already following
								RAIL.Owner.X[0],
								RAIL.Owner.Y[0]
							) > RAIL.State.FollowDistance)
						then
							Target.Chase = RAIL.Owner
						end
					else
						-- Or if we're running ahead
						if
							RAIL.Owner.Motion[0] == MOTION_MOVE or
							(RAIL.TargetHistory.Chase[0] == RAIL.Owner.ID and
							math.abs(RAIL.Self:DistanceTo(RAIL.Owner) - RAIL.State.FollowDistance) > 1)
						then
							Target.Chase = RAIL.Owner
						end
					end
				end
			end

			-- Begin determining the best skill to use
			do
				local skill = SelectSkill:CycleBegin()

				if skill ~= nil then
					-- An emergency skill, use it and terminate
					terminate = skill
				end
			end
		end -- not terminate

		-- Update all the on-screen actors
		local i,actor
		for i,actor in ipairs(GetActors()) do
			-- Don't double-update the owner or self
			if RAIL.Owner.ID ~= actor and RAIL.Self.ID ~= actor then
				-- Indexing non-existant actors will auto-create them
				local actor = Actors[actor]

				-- Update the information about it
				actor:Update()

				-- Make sure we aren't just collecting data this round
				if not terminate then
					-- If the actor that was just updated is a portal
					if actor.Type == 45 then
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
							end

							-- Check the actor against potential skills
							SelectSkill:ActorCheck(actor)

							-- Keep track of friends
							if actor:IsFriend() then
								Friends[actor.ID] = actor
							end
	
						end -- not actor:IsIgnored()
					end -- Target.Chase ~= RAIL.Owner
				end -- not terminate
			end -- RAIL.Owner.ID ~= actor
		end -- i,actor in ipairs(GetActor())
	end

	-- After update of actors is done, check if we need to save the MobID file
	if not RAIL.Mercenary and RAIL.State.UseMobID then
		MobID:Update()
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
		-- Check if it's due to a portal
		if RAIL.IsActor(terminate) then
			RAIL.LogT(7,"Owner approaching {1}; cycle terminating after data collection.",terminate)
	
			-- Save state data before terminating
			RAIL.State:Save()

		-- Check if its due to skill state
		elseif terminate == RAIL.Self.SkillState then
			RAIL.LogT(7,"Casting motion prevents action; cycle terminating after data collection.")

		-- Check if its due to an emergency skill
		elseif type(terminate) == "table" and type(terminate[1]) == "table" and terminate[1].Cast then
			RAIL.LogT(7, "Urgently casting {1}; cycle terminating after data collection.",terminate[1].Name)

			terminate[1]:Cast(terminate[2],terminate[3])

		end

		-- Terminate this cycle early
		return
	end

	-- Pre-decision cmd queue evaluation
	do
		-- Don't process commands if we're chasing owner
		if Target.Chase ~= RAIL.Owner then
			-- Process commands to find skill target, attack target, and move target
			Target.Skill,Target.Attack,Target.Chase =
				RAIL.Cmd.Evaluate(Target.Skill,Target.Attack,Target.Chase)
		end -- Target.Chase ~= RAIL.Owner
	end -- do

	-- Decision Making
	do
		-- Skill
		if Target.Skill == nil and Target.Chase ~= RAIL.Owner then
			-- Select a skill to use
			Target.Skill = SelectSkill:Run()
		end

		-- Attack
		if Target.Attack == nil and Target.Chase ~= RAIL.Owner then
			-- Use routines from DecisionSupport.lua to determine the best actor
			Target.Attack = SelectTarget.Attack(Potential.Attack,Friends)
		end

		-- Move
		if Target.Chase == nil then
			-- Check chase target history
			-- TODO: test further
			if
				-- Debug toggle
				true and


				RAIL.TargetHistory.Chase[0] ~= -1 and
				RAIL.TargetHistory.Chase[0] ~= RAIL.TargetHistory.Attack and
				RAIL.TargetHistory.Chase[0] ~= RAIL.Owner.ID
			then
				local list = History.GetConstList(RAIL.TargetHistory.Chase)
				local tick_delta = GetTick() - list[list.last][2]

				-- TODO: Make state option for this
				local ignore_after = 5000

				-- Check if we've been chasing this actor for a while
				if tick_delta >= ignore_after then
					-- Decide if we've been able to get closer

					-- Get our current position
					local actor = Actors[list[list.last][1]]
					local x,y = actor.X[0],actor.Y[0]

					-- Check if X coordinate has changed recently
					local x_changed_f = function(v) return v ~= x end
					local most_recent_x = History.FindMostRecent(actor.X,x_changed_f,nil,tick_delta)

					-- If it hasn't, then check Y
					if not most_recent_x or most_recent_x > 2000 then
						local y_changed_f = function(v) return v ~= y end
						local most_recent_y = History.FindMostRecent(actor.Y,y_changed_f,nil,tick_delta)

						-- If it hasn't, ignore the actor
						if not most_recent_y or most_recent_y > 2000 then
							-- Log it
							RAIL.LogT(20,"Failed to get closer to {1} (closest = {2}); ignoring.",
								actor,RAIL.Self:DistanceTo(actor))

							-- Ignore the actor
							actor:Ignore()

							-- Also remove from the potential chase
							Potential.Chase[actor.ID] = nil
						end
					end
				end
			end

			-- Check to see if we should add our attack target to the chase list as well
			if not RAIL.State.AcquireWhileLocked and Target.Attack then
				Potential.Chase[Target.Attack.ID] = Target.Attack
			end

			-- Find highest priority monster to move toward
			Target.Chase = SelectTarget.Chase(Potential.Chase,Friends)
		end

		-- Check if we should attack while chasing
		if
			Target.Attack and
			Target.Chase and
			Target.Attack ~= Target.Chase and
			not RAIL.State.AttackWhileChasing
		then
			Target.Attack = nil
		end
	end

	-- Record the targets
	do
		-- Attack
		if Target.Attack then
			RAIL.TargetHistory.Attack = Target.Attack.ID
		else
			RAIL.TargetHistory.Attack = -1
		end

		-- Chase
		if Target.Chase then
			History.Update(RAIL.TargetHistory.Chase,Target.Chase.ID)
		else
			History.Update(RAIL.TargetHistory.Chase,-1)
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
				-- Default range is attack range
				--	Note: Underestimate just to be safe
				local range = RAIL.Self.AttackRange - 1

				-- Check if we're chasing owner
				if Target.Chase == RAIL.Owner then
					-- Set range to follow distance
					range = RAIL.State.FollowDistance

					-- Check if we're supposed to run ahead
					if RAIL.State.RunAhead then
						-- Estimate the owner's walking speed
						local owner_speed,angle = RAIL.Owner:EstimateMove()

						-- Plot a point ahead of them
						x,y = RAIL.Owner:AnglePlot(angle,RAIL.State.FollowDistance)
					end
				end

				-- TODO: Check if we're chasing for a skill (to update range)

				-- If a target destination hasn't been plotted yet, calculate one now
				if not x then
					x,y = CalculateIntercept(Target.Chase,range)
				end

				-- Check if the distance between this and last move is about the same
				if x and y then
					local last_x,last_y = RAIL.TargetHistory.Move.Y,RAIL.TargetHistory.Move.Y
					if PythagDistance(x,y,last_x,last_y) <= 1 then
						-- Use the old move
						x,y = last_x,last_y
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
			local owner_estim = (-1 * math.ceil(RAIL.State.MaxDistance / 4))
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
