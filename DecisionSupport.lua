-- Validation options
RAIL.Validate.AcquireWhileLocked = {"boolean",false}
RAIL.Validate.Aggressive = {"boolean",false}
RAIL.Validate.AssistOwner = {"boolean",false}
RAIL.Validate.AssistOther = {"boolean",false}
RAIL.Validate.DisableChase = {"boolean",false}
RAIL.Validate.DefendOptions = {is_subtable = true,
	DefendWhilePassive = {"boolean",true},
	DefendWhileAggro = {"boolean",true},
	OwnerThreshold = {"number",1,0},
	SelfThreshold = {"number",5,0},
	FriendThreshold = {"number",4,0},
}
RAIL.Validate.InterceptAlgorithm = {"string","normal",
	-- Note: Don't allow advanced until it's written
	{ ["none"] = true, ["sloppy"] = true, ["normal"] = true, ["advanced"] = nil, }
}
RAIL.Validate.RunAhead = {"boolean",false}

RAIL.Validate.MaxDistance = {"number", 13, 0, 14}
RAIL.Validate.FollowDistance = {"number", 4, 0, nil}	-- maximum value will be MaxDistance
setmetatable(RAIL.Validate.FollowDistance,{
	__index = function(self,idx)
		if idx == 4 then
			return RAIL.State.MaxDistance
		end

		return nil
	end,
})


-- Minimum priority (not an option)
local min_priority = -10000

-- Interception Routines
do
	local none_algo

	CalculateIntercept = {
		-- Routine with no interception algorithm
		none = function(target,range,ticks)
			local x,y

			-- Use a projected time of 0 if none is specified
			--	(or it references a time in the past)
			if not ticks or ticks > 0 then
				ticks = 0
			end

			-- Calculate the distance and angle from it (now)
			local angle,dist = RAIL.Self:AngleFrom(ticks)(target)

			-- Check if the target is within range
			if dist > range then
				-- Plot a point that's within range of the target
				x,y = RoundNumber(target:AnglePlot(ticks)(angle,range))

				-- Double-check that the point is closer than current
				if target:DistanceTo(ticks)(x,y) > dist then
					x,y = nil,nil
				end
			else
				-- Don't move
				x,y = nil,nil
			end

			return x,y
		end,

		-- Sloppy, but processor unintensive
		sloppy = function(target,range)
			-- Calculate the distance and angle from the target's projected position 500ms in the future
			--	(reuse the "none" algorithm, but at 500ms into the future)
			return none_algo(target,range,-500)
		end,

		-- Regular
		normal = function(target,range)
			-- Get movement speed of ourself and our target
			local s_speed = RAIL.Self:EstimateMove()
			local t_speed,t_angle = target:EstimateMove()

			-- Estimate time it'd take to reach the target (if it were standing still)
			local s_dist = RAIL.Self:DistanceTo(target)
			local ticks = s_dist * s_speed

			-- See how far the target will go in that time
			local t_dist = math.floor(ticks / t_speed)

			-- Bring distance down a bit
			if t_dist >= 4 then t_dist = 4 end

			-- Project where the actor will be after moving that distance
			local x,y = target:AnglePlot(t_angle,t_dist)

			-- Calculate the distance and angle from that position
			local angle,dist = RAIL.Self:AngleFrom(0)(RoundNumber(x,y))

			-- Check if the position is within range
			if dist > range then
				-- Save the projected location of the monster
				--	(future_x, future_y)
				local f_x,f_y = x,y

				-- Plot a point that's closer to it
				x,y = RoundNumber(PlotCircle(f_x,f_y,angle,range))

				-- Double-check that the point is closer than current
				if PythagDistance(RoundNumber(f_x),RoundNumber(f_y),x,y) > dist then
					x,y = nil,nil
				end
			else
				-- Don't move
				x,y = nil,nil
			end

			return x,y
		end,

		-- Should be accurate, but more processor intensive
		advanced = function(target,range)
			-- Use normal until advanced is written
			return CalculateIntercept.normal(target,range)
		end,
	}

	none_algo = CalculateIntercept.none

	setmetatable(CalculateIntercept,{
		__call = function(t,target,range)
			-- Verify input
			if not RAIL.IsActor(target) then
				return nil
			end

			-- Check if the target isn't moving
			if
				target.Motion[0] ~= MOTION_MOVE and

				-- debug switch: false = test intercept algorithm
				true
			then
				-- Return the actor's current position since it's standing still
				return none_algo(target,range)
			end

			-- Get the intercept algorithm
			local algo = t[string.lower(RAIL.State.InterceptAlgorithm)] or t.none

			-- Verify the algorithm is a function
			if type(algo) ~= "function" then
				-- Return the target's current position
				return none_algo(target,range)
			end

			-- Run the intercept algorithm
			return algo(target,range)
		end,
	})
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

		-- Assist owner or other
		do
			-- A helper function for most recent offensive motion
			local function offensive_motion(v) return
				v == MOTION_ATTACK or
				v == MOTION_ATTACK2 or
				v == MOTION_SKILL or
				v == MOTION_CASTING or
				false
			end

			-- A helper function to generate sieve to assist a target
			local function generate_assist(assist,allowed)
				return function(potentials,n,protected)
						-- Get the target to assist
						local assist = assist()

						-- Check assist target and the allowed function
						if not assist or not allowed() then
							return potentials,n,protected
						end

						-- Get the most recent offensive move
						local most_recent = History.FindMostRecent(assist.Motion,offensive_motion,nil,3000)

						-- Ensure most_recent isn't nil
						if most_recent ~= nil then
							-- Check the target of that offensive motion
							local target = assist.Target[most_recent]

							-- Check if that target is an option
							if RAIL.IsActor(potentials[target]) then
								-- Return only that actor
								local ret = { [target] = potentials[target] }

								-- Note: return this table twice, to protect from being removed by non-aggro sieve
								return ret,1,ret
							end
						end

						-- Don't modify potential targets
						return potentials,n,protected
				end
			end

			SelectTarget.Attack
				:Append{"AssistOwner",generate_assist(
					function() return RAIL.Owner end,
					function() return RAIL.State.AssistOwner end
				)}
				:Append{"AssistOther",generate_assist(
					function()
						if RAIL.Other == RAIL.Self then return nil end
						return RAIL.Other
					end,
					function() return RAIL.State.AssistOther end
				)}
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
				if not RAIL.State.Aggressive then
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
			if RAIL.State.Aggressive then
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

-- Chase Owner
do
	local private = {
		-- TODO: Fix RunAhead, and remove this default override
		Override = false,
	}

	local mt = {
		__index = function(self,idx)
			-- Check if we're overriding the state-file's RunAhead option
			if private.Override ~= nil then
				return rawget(self,private.Override)[idx]
			end

			-- Return an value based on the RunAhead flag
			return rawget(self,RAIL.State.RunAhead)[idx]
		end,
		__newindex = function(self,idx,val)
			-- Check if we're overriding the state-file's RunAhead option
			if private.Override ~= nil then
				return rawget(self,private.Override)[idx]
			end

			-- Save a value based on the RunAhead flag
			rawget(self,private.Override or RAIL.State.RunAhead)[idx] = val
		end,
	}

	ChaseOwner = {
		-- Run ahead
		[true] = {
			Check = function(self)
				-- TODO: Fix this

				if
					RAIL.Owner.Motion[0] == MOTION_MOVE or
					(RAIL.TargetHistory.Chase[0] == RAIL.Owner.ID and
					math.abs(RAIL.Self:DistanceTo(RAIL.Owner) - RAIL.State.FollowDistance) > 1)
				then
					return true
				end
			end,
			Calculate = function(self)
				-- TODO: Fix this

				-- Check if we're chasing owner
				if RAIL.Target.Chase == RAIL.Owner then
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

			end,
		},

		-- Follow behind
		[false] = {
			Check = function(self)
				local max = RAIL.State.MaxDistance
				local moving = false

				-- Check if we were already chasing our owner
				if RAIL.TargetHistory.Chase[0] == RAIL.Owner.ID then
					-- Already chasing owner

					if
						RAIL.Owner.Motion[0] == MOTION_MOVE or
						History.FindMostRecent(RAIL.Owner.Motion,MOTION_MOVE,nil,500)
					then
						-- Set the moving flag
						moving = true

						-- Also chase to a closer distance
						max = RAIL.State.FollowDistance
					end
				else
					-- Not already chasing owner

					if
						RAIL.Owner.Motion[0] == MOTION_MOVE and
						-- Note: Use DistanceTo() instead of BlocksTo() to determine if the owner is
						--	moving away from us. (eg, already X delta of 12, but
						--	moving along Y axis. BlocksTo won't show change, but DistanceTo will)
						RAIL.Self:DistanceTo(0)(RAIL.Owner.X[-500],RAIL.Owner.Y[-500])
							> RAIL.Self:DistanceTo(0)(RAIL.Owner)
					then
						moving = true
					end
				end

				-- Check if blocks to owner is too great
				if RAIL.Self:BlocksTo(RAIL.Owner) > max then
					-- Chase
					return true
				end

				-- Check if owner is moving
				if moving then
					-- Estimate the movement speed of the owner
					local speed = RAIL.Owner:EstimateMove()

					-- Determine a fraction of the distance to estimate ahead
					local tiles = math.ceil(max / 4)

					-- Estimate if the homu/merc will be off-screen after moving for the time
					--	it would take to move this number of tiles
					-- Note: Negative values project into the future
					if RAIL.Self:BlocksTo(-1 * tiles * speed)(RAIL.Owner) > max then
						-- Chase
						return true
					end
				end

				-- Don't chase
				return false
			end,
			Calculate = function(self)
				-- Use calculate intercept algorithm
				return CalculateIntercept(RAIL.Owner,RAIL.State.FollowDistance)
			end,
		},
	}

	setmetatable(ChaseOwner,mt)
end

-- Chase Ignore
do
	-- TODO: Rename and refactor this function
	function CheckChaseTimeAndDistance()
		-- Check chase target history
		if
			-- Debug toggle for chase ignore
			true and
	
	
			RAIL.TargetHistory.Chase[0] ~= -1 and
			RAIL.TargetHistory.Chase[0] ~= RAIL.TargetHistory.Attack and
			RAIL.TargetHistory.Chase[0] ~= RAIL.Owner.ID and
			RAIL.Self:DistanceTo(Actors[RAIL.TargetHistory.Chase[0]]) > 2
		then
			local list = History.GetConstList(RAIL.TargetHistory.Chase)
			local tick_delta = GetTick() - list[list.last][2]
	
			-- Get the state option for this actor
			local actor = Actors[RAIL.TargetHistory.Chase[0]]

			-- Don't repeatedly ignore
			if actor:IsIgnored() then
				return false
			end

			local ignore_after = actor.BattleOpts.IgnoreAfterChaseFail
	
			-- Check if we've been chasing this actor for a while
			if tick_delta >= ignore_after and ignore_after ~= -1 then
				-- Decide if we've been able to get closer
	
				-- Get the actor's current position
				local x,y = actor.X[0],actor.Y[0]

				-- Check if X coordinate has changed recently
				local x_changed_f = function(v) return v ~= x end
				local most_recent_x = History.FindMostRecent(actor.X,x_changed_f,nil,tick_delta)
	
				-- If it hasn't, then check Y
				if not most_recent_x or most_recent_x > ignore_after then
					local y_changed_f = function(v) return v ~= y end
					local most_recent_y = History.FindMostRecent(actor.Y,y_changed_f,nil,tick_delta)
	
					-- If it hasn't, ignore the actor
					if not most_recent_y or most_recent_y > ignore_after then
						-- Log it
						RAIL.LogT(20,"Failed to get closer to {1} (closest = {2}); ignoring.",
							actor,RAIL.Self:DistanceTo(actor))
	
						-- Ignore the actor
						actor:Ignore()
	
						-- Also remove from the potential chase
						return true
					end
				end
			end
		end

		-- Don't remove from potential chase list
		return false
	end
end
