-- Validation options
RAIL.Validate.Aggressive = {"boolean",false}
RAIL.Validate.AssistOwner = {"boolean",false}
RAIL.Validate.AssistOther = {"boolean",false}
RAIL.Validate.DefendOptions = {is_subtable = true,
	DefendWhilePassive = {"boolean",true},
	DefendWhileAggro = {"boolean",true},
	OwnerThreshold = {"number",1,0},
	SelfThreshold = {"number",5,0},
	FriendThreshold = {"number",4,0},
}
RAIL.Validate.InterceptAlgorithm = {"string","normal"}

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
				x,y = target:AnglePlot(ticks)(angle,range)
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
			if t_dist >= 3 then t_dist = 3 end

			-- Project where the actor will be after moving that distance
			local x,y = target:AnglePlot(t_angle,t_dist)

			-- Calculate the distance and angle from that position
			local angle,dist = RAIL.Self:AngleFrom(0)(x,y)

			-- Check if the position is within range
			if dist > range then
				-- Plot a point that's closer to it
				x,y = PlotCircle(x,y,angle,range)
			else
				-- Don't move
				x,y = nil,nil
			end

			return x,y
		end,

		-- Should be accurate, but more processor intensive
		advanced = function(target,range)
			-- TODO: This is all fuckered up. Unusable in current form.
			--		Fix it.


			-- Gather positions, estimated move speeds, movement angles, etc
			local s_x,s_y = RAIL.Self.X[0],RAIL.Self.Y[0]
			local s_speed = RAIL.Self:EstimateMove()
	
			local t_x,t_y = target.X[0],target.Y[0]
			local t_speed,t_move_angle = target:EstimateMove()
	
			local t_to_s_angle,t_dist = GetAngle(t_x,t_y,s_x,s_y)

			-- In a triangle,
			--
			--	A
			--	 \
			--	  B-------C
			--
			-- Use Law of Sines to find the optimal movement angle
			--	(Side-Side-Angle: s_speed, t_speed, t_angle_in_triangle)
			--	(Result will be s_angle_in_triangle)
			--

			-- Start working in a triangle now
			local t_angle_in_triangle = math.abs(t_move_angle - t_to_s_angle)
			if t_angle_in_triangle > 180 then
				t_angle_in_triangle = t_angle_in_triangle - 180
			end

			-- Invert speeds, such that high numbers are faster
			s_speed = 1 / s_speed
			t_speed = 1 / t_speed

			-- Solve for s_angle_in_triangle
			local law_of_sines_ratio = s_speed / math.sin(t_angle_in_triangle)
			local s_angle_in_triangle = math.asin(1 / (law_of_sines_ratio / t_speed))

			-- Complete the triangle
			local x_angle_in_triangle = 180 - (s_angle_in_triangle + t_angle_in_triangle)
			local x_speed = law_of_sines_ratio * math.sin(x_angle_in_triangle)

			-- Find destination angle on angle side
			local s_to_t_angle = math.mod(t_to_s_angle + 180,360)
			local s_move_angle

			if CompareAngle(t_to_s_angle,t_move_angle,-180) then
				s_move_angle = math.mod(s_to_t_angle + s_angle_in_triangle,360)
			else
				s_move_angle = s_to_t_angle - s_angle_in_triangle
				while s_move_angle < 0 do
					s_move_angle = s_move_angle + 360
				end
			end

			-- Return the speeds to ticks per tile
			s_speed = 1 / s_speed
			x_speed = 1 / x_speed
	
			-- Determine the distance to move
			local radius = t_dist * (s_speed / x_speed)
	
			-- Plot the point
			return PlotCircle(s_x,s_y,s_move_angle,radius)
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
		__call = function(self,potentials,friends)
			-- Count the number of potential targets
			local n=0
			for i in potentials do
				n=n+1
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
					local sieveType = "Unknown"
					if self == SelectTarget.Attack then
						sieveType = "Attack"
					elseif self == SelectTarget.Chase then
						sieveType = "Chase"
					end
					potentials,n,protected = f(potentials,n,friends,protected)
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
		setmetatable(SelectTarget.Attack,st_metatable)

		-- Assist owner or other as first priority
		do
			-- A helper function for most recent offensive motion
			local offensive_motion = function(v) return
				v == MOTION_ATTACK or
				v == MOTION_ATTACK2 or
				v == MOTION_SKILL or
				v == MOTION_CASTING or
				false
			end
			SelectTarget.Attack:Append{"AssistOwner",function(potentials,n,protected)
				-- If we're not supposed to assist the owner, don't modify anything
				if not RAIL.State.AssistOwner then
					return potentials,n,protected
				end

				-- Get the owner's most recent offensive move
				local most_recent = History.FindMostRecent(RAIL.Owner.Motion,offensive_motion,nil,1250)

				-- Ensure most_recent isn't nil
				if most_recent ~= nil then
					-- Check the target of that offensive motion
					local target = RAIL.Owner.Target[most_recent]

					-- Check if that target is an option
					if RAIL.IsActor(potentials[target]) then
						-- Return only that actor
						local ret = { [target] = potentials[target] }
						-- Note: return this table twice, to protect from being removed by non-aggro sieve
						return ret,1,ret
					end
				end

				-- Don't modify the potential targets
				return potentials,n,protected
			end}

			-- Assist owner's merc/homu
			SelectTarget.Attack:Append{"AssistOther",function(potentials,n,friends,protected)
				-- If we're not supposed to assist the other, don't modify anything
				if not RAIL.State.AssistOther or RAIL.Other == RAIL.Self then
					return potentials,n,protected
				end

				-- Get the other's most recent offensive move
				local most_recent = History.FindMostRecent(RAIL.Other.Motion,offensive_motion,nil,1250)

				-- Ensure the motion isn't nil
				if most_recent ~= nil then
					-- Check the target of that offensive motion
					local target = RAIL.Other.Target[most_recent]

					-- Check if that target is an option
					if RAIL.IsActor(potentials[target]) then
						-- Return only that actor
						local ret = { [target] = potentials[target] }
						return ret,1,ret
					end
				end

				-- TODO: Setup a mechanism to communicate target and attack status

				-- Don't modify the potential targets
				return potentials,n,protected
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

			SelectTarget.Attack:Append{"Defend",function(potentials,n,friends,protected)
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
	
					for id,actor in friends do
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
		SelectTarget.Attack:Append{"KillSteal",function(potentials,n,friends,protected)
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
		SelectTarget.Attack:Append{"Aggressive",function(potentials,n,friends,protected)
			-- If aggressive, don't modify the list
			if RAIL.State.Aggressive then
				return potentials,n,protected
			end

			-- Count the number of protected
			local ret_n = 0
			for id,actor in protected do
				ret_n = ret_n + 1
			end

			-- Return only monsters that have been protected by previous functions
			return protected,ret_n,protected
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
		SelectTarget.Attack:Append{"Retarget",function(potentials,n,friends,protected)
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
		SelectTarget.Attack:Append{"Closest",function(potentials,n,friends,protected)
			local ret,ret_n,ret_dist = {},0,RAIL.State.MaxDistance+1

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

	-- Chase targeting
	do
		SelectTarget.Chase = Table.New()
		setmetatable(SelectTarget.Chase,st_metatable)

		-- First, ensure we won't move outside of RAIL.State.MaxDistance
		SelectTarget.Chase:Append{"MaxDistance",function(potentials,n,friends,protected)
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
						local x,y = RAIL.Owner:AnglePlot(angle,dist - RAIL.Self.AttackRange)
						x = RoundNumber(x)
						y = RoundNumber(y)

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
		end}

		-- Then, chase targeting is mostly the same as attack targeting
		--	Note: Don't copy the attack-target locking
		do
			local max = SelectTarget.Attack:GetN()
			for i=1,max do
				if SelectTarget.Attack[i][1] ~= "Retarget" then
					SelectTarget.Chase:Append(SelectTarget.Attack[i])
				end
			end
		end

		-- Check to see if the previous target is still in this list
		SelectTarget.Chase:Append{"Retarget",function(potentials,n,friends,protected)
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
