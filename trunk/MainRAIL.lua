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
require "Actor.lua"	-- depends on History.lua
require "Commands.lua"	-- depends on Table.lua

-- State validation options
RAIL.Validate.MaxDistance = {"number", 14, 3, 14}
RAIL.Validate.Aggressive = {"boolean", false}

function AI(id)
	-- Get Owner and Self
	RAIL.Owner = Actors[GetV(V_OWNER,id)]
	RAIL.Self  = Actors[id]

	-- Get our attack range
	RAIL.Self.AttackRange = GetV(V_ATTACKRANGE,id)

	-- Get our longest skill range
	-- TODO
	RAIL.Self.SkillRange = 0

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

	AI = RAIL.AI
	AI(id)
end

function RAIL.AI(id)
	-- Potential targets
	local Potential = {
		Attack = {},
		Skill = {},
		Chase = {},
	}

	-- Decided targets
	local Target = {
		Skill = nil,
		Attack = nil,
		Chase = nil,
	}

	local Friends = {}

	-- Flag to terminate after data collection
	local terminate = false

	-- Update actor information
	do
		-- Update both owner and self before every other actor
		RAIL.Owner:Update()
		RAIL.Self:Update()

		-- Determine if we need to chase our owner
		if RAIL.Self:BlocksTo(0)(
			-- 3 tiles ahead, to start moving before off screen
			RAIL.Owner.X[-3*RAIL.Owner:EstimateMoveSpeed()],
			RAIL.Owner.Y[-3*RAIL.Owner:EstimateMoveSpeed()]
		) >= RAIL.State.MaxDistance then
			Target.Chase = RAIL.Owner
		end

		-- Update all the on-screen actors
		local i,actor
		for i,actor in ipairs(GetActors()) do
			-- Don't double-update the owner or self
			if RAIL.Owner.ID ~= actor and RAIL.Self.ID ~= actor then
				-- Indexing non-existant actors will auto-create them
				local actor = Actors[actor]

				-- Update the information about it
				actor:Update()

				-- If the actor that was just updated is a portal
				if actor.Type == 45 and not terminate then
					-- Get the block distances between the portal and the owner
						-- roughly 2.5 tiles from now
					local inFuture = RAIL.Owner:BlocksTo(-2.5*RAIL.Owner:EstimateMoveSpeed())(actor)
						-- and now
					local now = RAIL.Owner:BlocksTo(actor)

					if inFuture < 3 and inFuture < now then
						RAIL.Log(0,"Owner approaching portal; cycle terminating after data collection.")
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

		-- Process any command
		RAIL.Cmd.Process[msg[1]](shift,msg)

	end

	-- Check if the cycle should terminate early
	if terminate then
		-- Save state data before terminating
		RAIL.State:Save()

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
					-- Chase it
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
		end

		-- Attack
		if Target.Attack == nil and Target.Chase ~= RAIL.Owner then
		end

		-- Move
		if Target.Chase == nil then
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
		if Target.Chase ~= nil then
			local x,y

			if RAIL.IsActor(Target.Chase) then
				-- Move to actor
				-- TODO: Predict location
				x,y = Target.Chase.X[0],Target.Chase.Y[0]
			else
				-- Move to ground
				x,y = Target.Chase[2],Target.Chase[3]
			end

			-- TODO: Alter move such that repeated moves to same location
			--		aren't ignored

			Move(RAIL.Self.ID,x,y)
		end
	end
end

-- Script is loaded...
RAIL.Log(0,"\r\n\r\n\r\nRAIL loaded...")
