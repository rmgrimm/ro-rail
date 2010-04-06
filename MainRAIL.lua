-- Save the global environment that RAIL is loaded from
RAIL._G = getfenv(0)

-- Load the configuration options
require "Config"

-- Load Utils.lua and State.lua before all other code
require "Utils"			-- run CheckAPI() before others start using Ragnarok API
require "State"			-- allow other files to add state validation options

-- Alphabetical
require "Base64"
require "Const"
require "Debug"
require "History"
require "SkillAIs"
require "Table"
require "Timeout"
require "Version"		-- Note: Version.lua is pre-loaded by AI.lua and AI_M.lua

-- Load-time Dependency
require "Actor"			-- depends on History
require "ActorOpts"		-- depends on Table
require "Commands"		-- depends on Table
require "DecisionSupport"	-- depends on Table
require "Skills"		-- depends on Table
require "SkillSupport"		-- depends on Actor

-- State validation options
RAIL.Validate.Information = {is_subtable = true,
	InitTime = {"number", 0},
	OwnerID = {"number", 0},
	OwnerName = {"string", "unknown"},
	SelfID = {"number", 0},
	RAILVersion = {"string", "unknown"},
}
RAIL.Validate.AttackWhileChasing = {"boolean",false}

function AI(id)
	-- Create temporary fake actors, until properly initialized
	RAIL.Owner = { ID = GetV(V_OWNER,id) }
	RAIL.Self = { ID = id }

	-- Get memory usage before initialization
	local mem_before,thresh_before = gcinfo()

	-- Double the threshold for now
	--	(to prevent a garbage collection while we're initializing)
	collectgarbage(thresh_before * 2)

	-- Prevent logging while loading state file the first time
	RAIL.Log.Disabled = true

	-- Load persistent state data
	RAIL.State:SetOwnerID(RAIL.Owner.ID)
	RAIL.State:Load(true)

	-- Re-enable logging
	RAIL.Log.Disabled = false

	-- Put some space to signify reload
	if RAIL.UseTraceAI then
		TraceAI("\r\n\r\n\r\n")
	else
		-- Not translatable
		RAIL.Log(0,"\n\n\n")
	end

	-- Log the AI initialization
	RAIL.LogT(0,"RampageAI Lite r{1} initializing...",RAIL.Version)
	RAIL.LogT(0," --> Full Version ID = {1}",RAIL.FullVersion)

	-- Check for some features of Lua
	RAIL.LogT(0," --> Lua: _VERSION = {1}; coroutine = {2};",
		RAIL._G._VERSION, RAIL._G.coroutine)

	-- Load persistent state data again
	--	Note: Redundant, but will show up in the log now
	RAIL.State:Load(true)

	-- Check if we're homunculus, tracking MobID, and should update (instead of overwrite)
	if not RAIL.Mercenary and RAIL.State.UseMobID and RAIL.State.MobIDMode == "update" then
		-- Load the MobID file
		-- Note: Since the Load function only maintains Update, this will only work once
		MobID:Load(true)
	else
		-- Remove the Load function, as it's not needed
		MobID.Load = nil
	end

	-- Store the initialization time
	RAIL.State.Information.InitTime = GetTick()
	RAIL.State.Information.OwnerID = RAIL.Owner.ID
	RAIL.State.Information.SelfID = id
	RAIL.State.Information.RAILVersion = RAIL.FullVersion

	-- Get Owner and Self
	RAIL.Owner = Actors[GetV(V_OWNER,id)]
	RAIL.LogT(40," --> Owner; Name = {1}",RAIL.State.Information.OwnerName)
	if RAIL.State.Information.OwnerName ~= "unknown" then
		RAIL.Owner.BattleOpts.Name = RAIL.State.Information.OwnerName
	end
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

		RAIL.Owner.GetMaxHP = function(self) return GetV(V_MAXHP,self.ID) end
		RAIL.Owner.GetMaxSP = function(self) return GetV(V_MAXSP,self.ID) end
		RAIL.Self.GetMaxHP = RAIL.Owner.GetMaxHP
		RAIL.Self.GetMaxSP = RAIL.Owner.GetMaxSP

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

	-- Extra info about skills
	do
		local buf = StringBuffer.New()
		for skill_type,skill in pairs(RAIL.Self.Skills) do
			buf:Append(skill)
			if type(skill_type) == "string" then
				buf:Append(" as AI's \""):Append(skill_type):Append("\"")
			end
			buf:Append("; ")
		end
		RAIL.LogT(40," --> Skills: {1}",buf:Append(" "):Get())
	end

	-- Never show up as either enemies or friends
	RAIL.Owner.IsEnemy  = function() return false end
	RAIL.Owner.IsFriend = function() return false end
	RAIL.Self.IsEnemy   = function() return false end
	RAIL.Self.IsFriend  = function() return false end

	-- Save some processing power on later cycles
	RAIL.Owner.ExpireTimeout[1] = false
	RAIL.Self.ExpireTimeout[1] = false

	-- Check for the global variable "debug" (should be a table), to determine
	--	if we're running inside lua.exe or ragexe.exe
	if not RAIL._G.debug then
		-- Periodically save state data
		RAIL.Timeouts:New(2500,true,function()
			-- Only load data if the "update" flag is on in the file
			RAIL.State:Load(false)
	
			-- Save data (if any data was loaded, it won't be dirty and won't save)
			RAIL.State:Save()
		end)

		-- Homunculi should periodically save MobID file
		if not RAIL.Mercenary then
			RAIL.Timeouts:New(500,true,function()
				if RAIL.State.UseMobID then
					MobID:Update()
				end
			end)
		end
	end

	-- Profile the AI() function (and include memory information)
	AI = ProfilingHook("RAIL.AI",RAIL.AI,50,true)

	-- Get memory usage after initialization
	local mem_after,thresh_after = gcinfo()

	-- Log memory change from initialization
	RAIL.LogT(0,"RAIL initialization complete; memory usage increase of {1}kb.",mem_after - mem_before)
	RAIL.LogT(0," --> Mem before: {1}kb; Mem after: {2}kb; Threshold before: {3}kb; Threshold after: {4}kb",mem_before,mem_after,thresh_before,thresh_after)

	-- Run the first cycle of AI
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
	RAIL.ActorLists = {
		All = {
			[RAIL.Owner.ID] = RAIL.Owner,
			[RAIL.Self.ID] = RAIL.Self,
		},
		Targets = {},
		Friends = {},
		Other = {},
	}

	-- Decided targets
	RAIL.Target = {
		Skill = nil,
		Attack = nil,
		Chase = nil,
	}

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
				if ChaseOwner:Check() then
					RAIL.Target.Chase = RAIL.Owner
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
					if RAIL.Target.Chase ~= RAIL.Owner then

						-- Make sure we're not ignoring the actor
						if not actor:IsIgnored() then

							-- Add it to the all list
							RAIL.ActorLists.All[actor.ID] = actor

							-- Check if the actor is a friend
							if actor:IsFriend() then
								RAIL.ActorLists.Friends[actor.ID] = actor

							-- An enemy
							elseif actor:IsEnemy() then
								RAIL.ActorLists.Targets[actor.ID] = actor

							-- Or something else
							else
								RAIL.ActorLists.Other[actor.ID] = actor
							end

							-- Check the actor against skills
							SelectSkill:ActorCheck(actor)

						end -- not actor:IsIgnored()
					end -- RAIL.Target.Chase ~= RAIL.Owner
				end -- not terminate
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
		RAIL.Cmd.ProcessInput(shift,msg)

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
			RAIL.LogT(7,"Urgently casting {1}; cycle terminating after data collection.",terminate[1])

			terminate[1]:Cast(terminate[2],terminate[3])

		end

		-- Terminate this cycle early
		return
	end

	-- Pre-decision cmd queue evaluation
	do
		-- Don't process commands if we're chasing owner
		if RAIL.Target.Chase ~= RAIL.Owner then
			-- Process commands to find skill target, attack target, and move target
			RAIL.Cmd.Evaluate()
		end -- Target.Chase ~= RAIL.Owner
	end -- do

	-- Decision Making
	do
		-- Skill
		if RAIL.Target.Skill == nil and RAIL.Target.Chase ~= RAIL.Owner then
			-- Select a skill to use
			RAIL.Target.Skill = SelectSkill:Run()
		end

		-- Attack
		if RAIL.Target.Attack == nil and RAIL.Target.Chase ~= RAIL.Owner then
			-- Use routines from DecisionSupport.lua to determine the best actor
			RAIL.Target.Attack = SelectTarget.Attack(RAIL.ActorLists.Targets)
		end

		-- Move
		if RAIL.Target.Chase == nil then
			-- Check if we're chasing, but unable to get closer
			if CheckChaseTimeAndDistance() then
				--Potential.Chase[RAIL.TargetHistory.Chase[0]] = nil
			end

			-- Find highest priority monster to move toward
			RAIL.Target.Chase = SelectTarget.Chase(RAIL.ActorLists.Targets)
		end

		-- Check if we should attack while chasing
		if
			RAIL.Target.Attack and
			RAIL.Target.Chase and
			not RAIL.State.AttackWhileChasing
		then
			RAIL.Target.Attack = nil
		end
	end

	-- Record the targets
	do
		-- Attack
		if RAIL.Target.Attack then
			RAIL.TargetHistory.Attack = RAIL.Target.Attack.ID
		else
			RAIL.TargetHistory.Attack = -1
		end

		-- Chase
		if RAIL.Target.Chase and RAIL.Target.Chase.ID then
			History.Update(RAIL.TargetHistory.Chase,RAIL.Target.Chase.ID)
		else
			History.Update(RAIL.TargetHistory.Chase,-1)
		end
	end

	-- Action
	do
		-- Skill
		if RAIL.Target.Skill ~= nil then
			local skill = RAIL.Target.Skill[1]
			local target_x = RAIL.Target.Skill[2]
			local target_y = RAIL.Target.Skill[3]

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
		if RAIL.Target.Attack ~= nil then
			-- Log it
			RAIL.LogT(75,"Using physical attack against {1}.",RAIL.Target.Attack)

			-- Send the attack
			RAIL.Target.Attack:Attack()
		end

		-- Move
		local x,y
		if RAIL.Target.Chase ~= nil then

			-- Check if we're chasing owner
			if RAIL.Target.Chase == RAIL.Owner then
				-- Calculate the x,y to run to
				x,y = ChaseOwner:Calculate()

			elseif RAIL.IsActor(RAIL.Target.Chase) then
				-- Default range is attack range
				--	Note: Underestimate just to be safe
				local range = RAIL.Self.AttackRange - 1

				-- TODO: Check if we're chasing for a skill (to update range)

				-- Calculate intercept now
				x,y = CalculateIntercept(RAIL.Target.Chase,range)

				-- Check if the distance between this and last move is about the same
				if x and y then
					local last_x,last_y = RAIL.TargetHistory.Move.X,RAIL.TargetHistory.Move.Y
					if PythagDistance(x,y,last_x,last_y) <= 1 then
						-- Use the old move
						x,y = last_x,last_y
					end
				end

			else
				-- Move to ground
				x,y = RAIL.Target.Chase[2],RAIL.Target.Chase[3]
			end

		elseif RAIL.Target.Attack ~= nil then
			-- TODO: Dance step
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
				RAIL.Target.Attack ~= nil or
				RAIL.Target.Skill ~= nil
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
if RAIL.UseTraceAI then
	RAIL.LogT(0,"RAIL loaded...")
end
