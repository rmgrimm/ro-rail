-- Validation options
RAIL.Validate.AcquireWhileLocked = {"boolean",false}
RAIL.Validate.Aggressive = {"boolean",false}
RAIL.Validate.AssistOptions = {is_subtable = true,
	Owner = {"string","indifferent",nil},
	Other = {"string","indifferent",nil},	-- allowed options are set further down this file
	Friend = {"string","indifferent",nil},	--	(search "RAIL.Validate.AssistOptions.Owner")
}
RAIL.Validate.AutoPassiveHP = {"number",0,0}
setmetatable(RAIL.Validate.AutoPassiveHP,{
	__index = function(self,idx)
		-- If percentages, then maximum should be 99
		if idx == 4 and RAIL.State.AutoPassiveHPisPercent then
			return 99
		end
	end,
})
RAIL.Validate.AutoPassiveHPisPercent = {"boolean",false}
RAIL.Validate.AutoUnPassiveHP = {"number"}
setmetatable(RAIL.Validate.AutoUnPassiveHP,{
	__index = function(self,idx)
		-- AutoUnPassiveHP should have a default and minimum of AutoPassiveHP
		if idx == 2 or idx == 3 then
			return RAIL.State.AutoPassiveHP + 1
		end
		
		-- And maximum should be 100 if using percents
		if idx == 4 and RAIL.State.AutoPassiveHPisPercent then
			return 100
		end

		return nil
	end,
})
RAIL.Validate.DisableChase = {"boolean",false}
RAIL.Validate.DefendOptions = {is_subtable = true,
	DefendWhilePassive = {"boolean",true},
	DefendWhileAggro = {"boolean",true},
	OwnerThreshold = {"number",1,0},
	SelfThreshold = {"number",5,0},
	FriendThreshold = {"number",4,0},
}

-- Minimum priority (not an option)
local min_priority = -10000

do
	-- Aggressive Support
	RAIL.IsAggressive = function(actor)
		-- TODO: Add support for checking RAIL.Other's aggressive state

		-- Non-aggressive means always non-aggressive
		if not RAIL.State.Aggressive then
			return false
		end
		
		-- Check for HP changes updating auto-passive mode
		do
			local hp = actor.HP[0]
			local log_percent = ""
			if RAIL.State.AutoPassiveHPisPercent then
				hp = math.floor(hp / actor:GetMaxHP() * 100)
				log_percent = "%"
			end
			
			if not actor.AutoPassive then
				if hp < RAIL.State.AutoPassiveHP then
					RAIL.LogT(10,"Temporarily entering passive mode due to HP below threshold; hp={1}{3}, threshold={2}{3}.",
						hp, RAIL.State.AutoPassiveHP, log_percent)
					actor.AutoPassive = true
				end
			else
				if hp >= RAIL.State.AutoUnPassiveHP then
					RAIL.LogT(10,"Disabling temporary passive mode due to HP above threshold; hp={1}{3}, threshold={2}{3}.",
						hp, RAIL.State.AutoUnPassiveHP, log_percent)
					actor.AutoPassive = nil
				end
			end
		end
		
		-- If auto-passive, don't return aggressive mode
		if actor.AutoPassive then
			return false
		end

		return true
	end
end

-- Target Selection Routines
do
	-- Base table
	SelectTarget = { }

	-- The metatable to run subtables
	local st_metatable = {
		__index = Table,
		__call = function(self,potentials,...)
			-- Count the number of potential targets
			local n=0
			for i in potentials do
				n=n+1
			end

			-- Get the name of the sieve table
			local sieveType = "Unknown"
			if self.SieveType ~= nil then
				sieveType = tostring(self.SieveType)
			end

			-- List of actors that should be protected from non-aggro removal
			local protected = { }

			-- Sieve the potential list through each of the targeting functions, until 1 or fewer targets are left
			for i,t in ipairs(self) do
				-- Check to see if any potentials are left
				if n < 1 then
					return nil
				end

				-- Get the function
				local f = t[2]

				-- Call the function
				if type(f) == "function" then
					local n_before = n

					potentials,n,protected = f(potentials,n,protected,unpack(arg))

					-- Log it
					if n ~= n_before then
						RAIL.LogT(95,"\"{1}\" sieve table's \"{2}\" removed {3} actors; before={4}, after={5}.",
							sieveType,t[1],n_before-n,n_before,n)
					end
				end
			end

			-- Check the number of potentials left
			if n > 0 then
				-- Select a target at random from the remaining potentials
				--	(the first returned by the pairs iterator will be used)
				--	Note: if only 1 is left, only 1 can be selected
				local i,k = pairs(potentials)(potentials)
				return k
			else
				-- Return nothing, since we shouldn't target anything
				return nil
			end
		end,
	}

	-- Physical attack targeting
	do
		SelectTarget.Attack = Table.New()
		SelectTarget.Attack.SieveType = "Attack"
		setmetatable(SelectTarget.Attack,st_metatable)

		-- Make sure targets are within range
		SelectTarget.Attack:Append{"AttackAllowedAndRange",function(potentials,n,protected)
			local ret,ret_n = {},0

			for id,actor in potentials do
				if
					actor:IsAttackAllowed() and
					RAIL.Self:DistanceTo(actor) < RAIL.Self.AttackRange
				then
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end

			return ret,ret_n,protected
		end}

		-- Assist/avoid owner or other's target
		do
			-- A helper function for most recent offensive motion
			local function offensive_motion(v) return
				v == MOTION_ATTACK or
				v == MOTION_ATTACK2 or
				v == MOTION_SKILL or
				v == MOTION_CASTING or
				false
			end

			-- A helper function to find the target of an actor's offensive motion
			local function offensive_target(actor)
				-- Find most recent offensive motion
				local most_recent = History.FindMostRecent(actor.Motion,offensive_motion,nil,3000)

				-- If no offensive motion, no target
				if most_recent == nil then return nil end

				-- Return the target
				return Actors[actor.Target[most_recent]]
			end

			-- Functions to sort into categories
			local sorters = {
				["indifferent"] = function(assist,avoid,actor)
					-- Do nothing; indifferent to their target
				end,
				["assist"] = function(assist,avoid,actor)
					local target = offensive_target(actor)

					if target ~= nil then
						assist:Append(target)
					end
				end,
				["avoid"] = function(assist,avoid,actor)
					local target = offensive_target(actor)

					if target ~= nil then
						avoid:Append(target)
					end
				end,
			}

			-- Set the valid options for AssistOptions
			RAIL.Validate.AssistOptions.Owner[3] = sorters
			RAIL.Validate.AssistOptions.Other[3] = sorters
			RAIL.Validate.AssistOptions.Friend[3] = sorters

			SelectTarget.Attack:Append{"AssistAndAvoid",function(potentials,n,protected)
				local ret,ret_n

				-- First, build tables of assist/avoid (and drop indifferent)
				local assist = Table.New()
				local avoid = Table.New()

				do
					sorters[RAIL.State.AssistOptions.Owner](assist,avoid,RAIL.Owner)
					sorters[RAIL.State.AssistOptions.Other](assist,avoid,RAIL.Other)

					local f = sorters[RAIL.State.AssistOptions.Friend]
					for id,actor in RAIL.ActorLists.Friends do
						f(assist,avoid,actor)
					end
				end

				-- Loop through each assist
				for i=1,assist:GetN() do
					local target = assist[i]
					-- Check if the target is a potential
					if potentials[target.ID] then
						-- Assist against this target
						ret = { [target.ID] = target }
						return ret,1,ret
					end
				end

				-- Make a copy of the potentials
				ret,ret_n = Table.ShallowCopy(potentials),n

				-- Loop through each avoid and remove the target
				for i=1,avoid:GetN() do
					local target = avoid[i]

					-- Check if the target is a potential
					if ret[target.ID] then
						-- Remove it
						ret[target.ID] = nil
						ret_n = ret_n - 1
					end
				end

				-- If none are left, don't replace the table
				if ret_n < 1 then
					return potentials,n,protected
				end

				-- Otherwise, return what's left-over
				return ret,ret_n,protected
			end}
		end

		-- Defend owner, other, and friends
		do
			-- Prioritization support function
			local prioritization = function(defend_actors,defend_n,defend_prio,actors,n,prio)
				-- Make sure something is attacking this actor, and the priority threshold is above 0
				if n < 1 or prio < 1 then
					return defend_actors,defend_n,defend_prio
				end

				-- Check if this actor reaches the prioritization threshold
				if n >= prio then
					-- Check the priority against the existing defense priority
					if
						prio > defend_prio or
						(prio == defend_prio and n > defend_n)
					then
						-- Reset the defense list
						defend_actors = Table.New():Append(actors)
						defend_prio = prio
						defend_n = n
					elseif prio == defend_priority and n == defend_n then
						-- Add to the defense list
						defend_actors:Append(actors)
					end
				else
					-- Check if anything else was prioritized
					if defend_prio == 0 then
						-- Nothing was, add actor to the list
						defend_actors:Append(actors)
					end
				end

				return defend_actors,defend_n,defend_prio
			end

			-- Target counting support function
			local getN = function(actor,potentials)
				-- Get the number of targets attacking actor
				local n = actor.TargetOf:GetN()

				-- Ensure that at least one is in the potentials list
				for i=1,n do
					if potentials[actor.TargetOf[i].ID] then
						-- One of actor's attackers is in the potentials list, return N
						return n
					end
				end

				-- Nothing in actor's TargetOf list is attackable, return 0
				return 0
			end

			SelectTarget.Attack:Append{"Defend",function(potentials,n,protected)
				if not RAIL.IsAggressive(RAIL.Self) then
					-- If not aggressive, and not defending while passive, don't modify the list
					if not RAIL.State.DefendOptions.DefendWhilePassive then
						return potentials,n,protected
					end
				else
					-- If aggressive, and not prioritizing defense, don't modify the list
					if not RAIL.State.DefendOptions.DefendWhileAggro then
						return potentials,n,protected
					end
				end
	
				local owner_n = getN(RAIL.Owner,potentials)
				local self_n = getN(RAIL.Self,potentials)
	
				-- Check for the highest number of actors attacking friends/other
				local friends_n,friends_actors = 0,Table.New()
				if RAIL.State.DefendOptions.FriendThreshold > 0 then
					-- First, set other as the actor
					if RAIL.Self ~= RAIL.Other then
						friends_n = getN(RAIL.Other,potentials)
						friends_actors:Append(RAIL.Other)
					end
	
					for id,actor in RAIL.ActorLists.Friends do
						local n = getN(actor,potentials)
	
						if n > friends_n then
							friends_actors = Table.New()
							friends_actors:Append(actor)
							friends_n = n
						elseif n == friends_n then
							friends_actors:Append(actor)
						end
					end
				end
	
				-- Check if any actor is being attacked
				if owner_n == 0 and self_n == 0 and friends_n == 0 then
					-- Don't modify the list if defense isn't needed
					return potentials,n,protected
				end

				-- Keep a list of the actors that will be defended
				local defend_actors = Table.New()
				local defend_n = 0
				local defend_prio = 0

				-- Check to see if we should defend ourself
				defend_actors,defend_n,defend_prio =
					prioritization(
						defend_actors,defend_n,defend_prio,
						RAIL.Self,self_n,RAIL.State.DefendOptions.SelfThreshold
					)

				-- Check to see if we should defend our owner
				defend_actors,defend_n,defend_prio =
					prioritization(
						defend_actors,defend_n,defend_prio,
						RAIL.Owner,owner_n,RAIL.State.DefendOptions.OwnerThreshold
					)

				-- Check to see if we should defend our friends
				defend_actors,defend_n,defend_prio =
					prioritization(
						defend_actors,defend_n,defend_prio,
						friends_actors,friends_n,RAIL.State.DefendOptions.FriendThreshold
					)

				-- Modify the return list
				local ret,ret_n = {},0
				for id,defend_actor in ipairs(defend_actors) do
					for id,actor in ipairs(defend_actor.TargetOf) do
						if potentials[actor.ID] ~= nil then
							ret[actor.ID] = actor
							ret_n = ret_n + 1
						end
					end
				end

				-- Return potential defend targets, the number of potentials,
				--	and use the same target table as protected, so none are removed
				--	due to non-aggro
				return ret,ret_n,ret
			end}
		end

		-- Sieve out monsters that would be Kill Stolen
		SelectTarget.Attack:Append{"KillSteal",function(potentials,n,protected)
			local ret,ret_n = {},0
			for id,actor in potentials do
				if not actor:WouldKillSteal() or protected[id] then
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end
			return ret,ret_n,protected
		end}

		-- If not aggressive, sieve out monsters that aren't protected
		SelectTarget.Attack:Append{"Aggressive",function(potentials,n,protected)
			-- If aggressive, don't modify the list
			if RAIL.IsAggressive(RAIL.Self) then
				return potentials,n,protected
			end

			-- Count the number of protected
			local ret,ret_n = {},0
			for id,actor in protected do
				if potentials[id] then
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end

			-- Return only monsters that have been protected by previous functions
			return ret,ret_n,ret
		end}

		-- Select the highest priority set of monsters
		SelectTarget.Attack:Append{"Priority",function(potentials,n,protected)
			local ret,ret_n,ret_priority = {},0,min_priority
	
			for id,actor in potentials do
				-- Check this actors priority against the existing list
				local priority = actor.BattleOpts.Priority

				-- If priority matches, add this actor to the list
				if priority == ret_priority then
					ret[id] = actor
					ret_n = ret_n + 1
	
				-- If priority is greater, start the list over
				elseif priority > ret_priority then
					ret = { [id] = actor }
					ret_n = 1
					ret_priority = priority
				end
	
			end

			return ret,ret_n,ret
		end}
	
		-- Check to see if the previous target is still in this list
		SelectTarget.Attack:Append{"Retarget",function(potentials,n,protected)
			local id = RAIL.TargetHistory.Attack

			-- Check if a target was acquired, and is in the list
			if id ~= -1 and potentials[id] ~= nil then
				-- Use the previous target
				local ret = { [id] = potentials[id] }
				return ret,1,ret
			end

			-- It's not, so don't modify the potential list
			return potentials,n,protected
		end}

		-- Find the closest actors
		SelectTarget.Attack:Append{"Closest",function(potentials,n,protected)
			local ret,ret_n,ret_dist = {},0,1000

			for id,actor in potentials do
				-- Calculate the distance to the actor
				local dist = RAIL.Self:DistanceTo(actor)

				-- Check if the actor is closer than previously checked ones
				if dist < ret_dist then
					-- Create a new return list
					ret = { [id] = actor }
					ret_n = 1
					ret_dist = dist

				-- Check if the actor is just as close
				elseif dist == ret_dist then
					-- Add the actor to the list
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end

			return ret,ret_n,ret
		end}
	end

	-- Target sieve generator
	SelectTarget.GenerateSieve = function(sieveType)
		local ret = Table.New()
		ret.SieveType = sieveType
		setmetatable(ret,st_metatable)

		-- Copy all the sieves from Attack sieve, except AttackRange and Retarget
		for i=1,SelectTarget.Attack:GetN() do
			local sieve = SelectTarget.Attack[i]

			if sieve[1] == "AttackAllowedAndRange" then
				-- Don't add
			elseif sieve[1] == "Retarget" then
				-- Don't add
			else
				-- Add it
				ret:Append(sieve)
			end
		end

		return ret
	end

	-- Chase targeting
	do
		SelectTarget.Chase = SelectTarget.GenerateSieve("Chase")

		-- Remove all targets if chase targeting is disabled
		SelectTarget.Chase:Insert(1,{"DisableChase",function(potentials,n,protected)
			if RAIL.State.DisableChase then
				return {},0,{}
			end

			return potentials,n,protected
		end})

		-- Sieve out targets that are not attack-allowed or skill-allowed
		SelectTarget.Chase:Insert(2,{"NotAllowed",function(potentials,n,protected)
			local ret,ret_n = {},0
			for id,actor in potentials do
				if actor:IsAttackAllowed() or actor:IsSkillAllowed(1) then
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end

			return ret,ret_n,protected
		end})

		-- Sieve out targets that are already within range
		SelectTarget.Chase:Insert(3,{"TooClose",function(potentials,n,protected)
			-- Get attack range
			local range = RAIL.Self.AttackRange

			-- Sieve out actors that are too close
			local ret,ret_n = {},0
			for id,actor in potentials do
				if
					RAIL.Self:DistanceTo(actor) > range or
					-- Don't sieve current target if not acquiring while locked
					(not RAIL.State.AcquireWhileLocked and RAIL.Target.Attack == actor)
				then
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end

			return ret,ret_n,protected
		end})

		-- Ensure we won't move outside of RAIL.State.MaxDistance
		SelectTarget.Chase:Insert(4,{"MaxDistance",function(potentials,n,protected)
			-- MaxDistance is in block tiles, but attack range is in pythagorean distance...
			local max_dist = RAIL.State.MaxDistance

			-- Process each actor
			local ret,ret_n = {},0
			for id,actor in potentials do
				-- If the actor is within MaxDistance block tiles, this is easy
				local blocks = RAIL.Owner:BlocksTo(actor)
				if blocks <= max_dist then
					-- Leave the actor in the list
					ret[id] = actor
					ret_n = ret_n + 1
				else
					-- Get the angle from our owner to the actor
					local angle,dist = RAIL.Owner:AngleTo(actor)

					-- If the distance is less than our attack range, we'll be fine
					if dist < RAIL.Self.AttackRange then
						-- Leave the actor in the list
						ret[id] = actor
						ret_n = ret_n + 1
					else
						-- Plot a point that will be closer to the owner
						local x,y = RoundNumber(RAIL.Owner:AnglePlot(angle,dist - RAIL.Self.AttackRange))

						-- Check if this point would be inside MaxDistance
						local closest_blocks = RAIL.Owner:BlocksTo(x,y)
						if closest_blocks <= max_dist then
							-- Leave the actor in the list
							ret[id] = actor
							ret_n = ret_n + 1
						else
							-- Take the actor out of the list, it's outside of range
							dist = RoundNumber(dist)
							RAIL.LogT(95,"Chase sieve removed {1}; dist s->a = {2}; blocks o->a = {3}, closer o->a = {4}.",actor,dist,blocks,closest_blocks)
						end
					end
				end
			end

			return ret,ret_n,protected
		end})

		-- As last part of sieve, don't chase attack target
		SelectTarget.Chase:Append{"UnduplicateAttack",function(potentials,n,protected)
			if
				RAIL.Target.Attack ~= nil and
				potentials[RAIL.Target.Attack.ID] ~= nil
			then
				-- Remove from the potential table
				potentials[RAIL.Target.Attack.ID] = nil
				n = n - 1
			end

			return potentials,n,protected
		end}

		-- Check to see if the previous target is still in this list
		SelectTarget.Chase:Append{"Retarget",function(potentials,n,protected)
			local id = RAIL.TargetHistory.Chase[0]

			-- Check if a target was acquired, and is in the list
			if id ~= -1 and potentials[id] ~= nil then
				-- Use the previous target
				local ret = { [id] = potentials[id] }
				return ret,1,ret
			end

			-- If not in the list, don't modify the list
			return potentials,n,protected
		end}
	end
end