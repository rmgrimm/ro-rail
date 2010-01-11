-- Load State.lua before all others, to allow others to add state validation options
require "State.lua"

-- Alphabetical
require "Const.lua"
require "DecisionSupport.lua"
require "Debug.lua"
require "History.lua"
require "Table.lua"
require "Timeout.lua"
require "Utils.lua"

-- Load-time Dependency
require "Actor.lua"	-- depends on History.lua
require "Commands.lua"	-- depends on Table.lua

-- State validation options
RAIL.Validate.MaxDistance = {"number", 14, 3, 14}
RAIL.Validate.Aggressive = {"boolean", false}

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

	-- Get our longest skill range
	-- TODO
	RAIL.Self.SkillRange = 0

	-- Track HP and SP
	do
		local update = RAIL.Self.Update
		-- An extended variant of Update(), to track HP and SP values
		RAIL.Self.Update = function(self)
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
		RAIL.Owner.Update = RAIL.Self.Update

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

	if RAIL.Mercenary then
		RAIL.Self.AI_Type = GetV(V_MERTYPE,id)
	else
		RAIL.Self.AI_Type = GetV(V_HOMUNTYPE,id)
	end

	-- Load persistent state data
	RAIL.State:Load(true)

	-- Periodically save state data
	RAIL.Timeouts:New(2500,true,function()
		-- Only load data if the "update" flag is on in the file
		RAIL.State:Load(false)

		-- Save data (if any data was loaded, it won't be dirty and won't save)
		RAIL.State:Save()
	end)

	AI = ProfilingHook("RAIL.AI",RAIL.AI,5)
	AI(id)
end

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
	local terminate = false

	-- Update actor information
	do
		-- Update owner, self, and other before every other actor
		RAIL.Owner:Update()
		RAIL.Self:Update()
		if RAIL.Other ~= RAIL.Self then
			RAIL.Other:Update()
		end

		-- Determine if we need to chase our owner
		if
			-- Debug toggle for interception
			(false and RAIL.Owner.Motion[0] == MOTION_MOVE) or
			-- Regular determination
			RAIL.Self:BlocksTo(0)(
				-- Guess ~3 tiles ahead, so homu/merc isn't off screen when finally decides to move
				RAIL.Owner.X[-3*RAIL.Owner:EstimateMove()],
				RAIL.Owner.Y[-3*RAIL.Owner:EstimateMove()]
			) >= RAIL.State.MaxDistance
		then
			Target.Chase = RAIL.Owner
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
						terminate = true
					end
				end

				-- If we're chasing owner, we won't be doing anything else
				if Target.Chase ~= RAIL.Owner then

					if actor:IsEnemy() then
						local dist = RAIL.Self:DistanceTo(actor)

						-- Is the actor in range of attack?
						if dist <= RAIL.Self.AttackRange then
							Potential.Attack[actor.ID] = actor
						end

						-- Is the actor in range of skills?
						if dist <= RAIL.Self.SkillRange then
							Potential.Skill[actor.ID] = actor
						end

						Potential.Chase[actor.ID] = actor
					end

					if actor:IsFriend() then
						Friends[actor.ID] = actor
					end

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
		RAIL.Log(7,"Owner approaching portal; cycle terminating after data collection.")

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
				if math.abs(GetTick() - actor.LastUpdate) > 50 or
					actor.Motion[0] == MOTION_DEAD
				then
					-- Invalid actor
					RAIL.Cmd.Queue:PopLeft()
				else
					-- Chase it (to allow attacks on other actors while heading toward it)
					Target.Chase = actor

					-- And if close enough, attack it
					if RAIL.Self:DistanceTo(actor) <= RAIL.Self.AttackRange then
						Target.Attack = actor
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
			-- TODO
		end

		-- Attack
		if Target.Attack == nil and Target.Chase ~= RAIL.Owner then
			-- TODO: Find highest priority monster that is within attack range
		end

		-- Move
		if Target.Chase == nil then
			-- TODO: Find highest priority monster to move toward
			-- TODO: Make sure to stay outside of range of all kited monsters
		end
	end

	-- Action
	do
		-- Skill
		if Target.Skill ~= nil then
			if Target.Skill[1] == SKILL_OBJECT_CMD then
				-- Actor-targeted skill
				Actors[Target.Skill[4]]:SkillObject(
					Target.Skill[2],	-- level
					Target.Skill[3]		-- skill id
				)
			else
				-- Ground-targeted skill
				SkillGround(
					RAIL.Self.ID,
					Target.Skill[2],	-- level
					Target.Skill[3],	-- skill
					Target.Skill[4],	-- x
					Target.Skill[5]		-- y
				)
			end
		end

		-- Attack
		if Target.Attack ~= nil then
			Target.Attack:Attack()
		end

		-- Move
		local x,y
		if Target.Chase ~= nil then

			if RAIL.IsActor(Target.Chase) then
				-- Move to actor
				x,y = CalculateIntercept(Target.Chase)
			else
				-- Move to ground
				x,y = Target.Chase[2],Target.Chase[3]
			end

			if RAIL.Self:DistanceTo(x,y) > 11 then
				-- TODO: Break down movement command, so server won't ignore it
			end

			-- Make sure the move isn't outside MaxDistance
			local x_d = RAIL.Owner.X[0] - x
			local y_d = RAIL.Owner.Y[0] - y
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
			x = RAIL.Owner.X[0] - x_d
			y = RAIL.Owner.Y[0] - y_d

			-- TODO: Alter move such that repeated moves to same location
			--		aren't ignored

		else
			-- If moving, then stop.
			--if RAIL.Self.Motion[0] == MOTION_MOVE then
			--	x,y = RAIL.Self.X[0], RAIL.Self.Y[0]
			--end

			-- TODO: Idle movement?
		end

		if type(x) == "number" and type(y) == "number" then
			Move(RAIL.Self.ID,x,y)
		end
	end
end

-- Script is loaded...
RAIL.Log(0,"\r\n\r\n\r\nRAIL loaded...")
