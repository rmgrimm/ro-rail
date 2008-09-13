require "Actor.lua"
require "Const.lua"
require "Log.lua"
require "Table.lua"
require "Timeout.lua"
require "Utils.lua"

RAIL.CmdQueue = List:New()

function AI(id)
	-- Get Owner and Self
	RAIL.Owner = Actors[GetV(V_OWNER,id)]
	RAIL.Self  = Actors[id]

	-- Get our attack range
	RAIL.Self.AttackRange = GetV(V_ATTACKRANGE,id)

	-- Never show up as either monsters or friends
	RAIL.Owner.IsMonster = function() return false end
	RAIL.Owner.IsFriend  = function() return false end
	RAIL.Self.IsMonster  = function() return false end
	RAIL.Self.IsFriend   = function() return false end

	if RAIL.Mercenary then
		RAIL.Self.AI_Type = GetV(V_MERTYPE,id)
	else
		RAIL.Self.AI_Type = GetV(V_HOMUNTYPE,id)
	end

	AI = RAIL.AI
	AI(id)
end

function RAIL.AI(id)
	-- Update actor information
	local Monsters = {}
	local Friends = {}
	local terminate = false
	do
		-- Update the owner before every other actor
		RAIL.Owner:Update()

		-- Update all the on-screen actors
		local i,actor
		for i,actor in ipairs(GetActors()) do
			-- Don't double-update the owner
			if RAIL.Owner.ID ~= actor then
				-- Indexing non-existant actors will auto-create them
				local actor = Actors[actor]

				-- Update the information about it
				actor:Update()

				-- If the actor that was just updated is a portal
				if actor.Type == 45 then
					-- Get the block distances between the portal and the owner
						-- 500ms from now
					local inFuture = actor:BlocksTo(RAIL.Owner.X[-500],RAIL.Owner.Y[-500])
						-- and now
					local now = actor:BlocksTo(RAIL.Owner)

					if inFuture < 3 and inFuture < now then
						TraceAI("x")
						TraceAI("Owner approaching portal; cycle terminating after data collection.")
						terminate = true
					end
				end

				if actor.IsMonster() then
					Monsters[actor.ID] = actor
				end

				if actor.IsFriend() then
					Friends[actor.ID] = actor
				end

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
		if msg[1] ~= NONE_CMD then
			-- If shift is not depressed, clear the command queue
			if msg[1] ~= FOLLOW_CMD and not shift then
				CmdQueue:Clear()
			end

			-- TODO: Process commands

			-- Add the command to the queue
			CmdQueue:PushRight(msg)
		end
	end

	-- Check if the cycle should terminate early
	if terminate then return end

	-- Strip out completed/invalid commands from the CmdQueue

	-- Skill

	-- Attack

	-- Move

	if RAIL.Self:BlocksTo(RAIL.Owner) > 4 then
		MoveToOwner(RAIL.Self.ID)
	end
end

