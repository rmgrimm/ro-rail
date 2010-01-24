-- Validation options
RAIL.Validate.Aggressive = {"boolean",false}
RAIL.Validate.AssistOwner = {"boolean",false}
RAIL.Validate.AssistOther = {"boolean",false}
RAIL.Validate.DefendWhilePassive = {"boolean",true}
RAIL.Validate.DefendWhileAggro = {"boolean",true}
RAIL.Validate.InterceptAlgorithm = {"string","normal"}

-- Interception Routines
do
	CalculateIntercept = {
		-- Routine with no interception algorithm
		none = function(target)
			return target.X[0],target.Y[0]
		end,

		-- Sloppy, but processor unintensive
		sloppy = function(target)
			return target.X[-500],target.Y[-500]
		end,

		-- Regular
		normal = function(target)
			-- Get movement speed
			local speed = RAIL.Self:EstimateMove()

			-- Estimate time it'd take to reach the target (if it were standing still)
			local dist = RAIL.Self:DistanceTo(target)
			local ticks = dist/speed

			-- Return the actor's projected position in <ticks> time
			return target.X[-ticks],target.Y[-ticks]
		end,

		-- Should be accurate, but more processor intensive
		advanced = function(target)
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
	
			local t_angle_in_triangle = math.abs(t_to_s_angle - t_move_angle)
			if t_angle_in_triangle > 180 then
				t_angle_in_triangle = 360 - t_angle_in_triangle
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
	
			-- Determine the distance to move
			local radius = t_dist * (s_speed / x_speed)
	
			-- Plot the point
			return PlotCircle(s_x,s_y,s_move_angle,radius)
		end,
	}

	setmetatable(CalculateIntercept,{
		__call = function(t,target)
			-- Verify input
			if not RAIL.IsActor(target) then
				return nil
			end

			-- Check for the default intercept algorithm
			local algo = t[string.lower(RAIL.State.InterceptAlgorithm)] or
				t.none
			if type(algo) ~= "function" then
				return nil
			end

			-- Check if the target is moving
			if target.Motion[0] == MOTION_MOVE or type(t.none) ~= "function" then
				return algo(target)
			end

			-- Use none, since it doesn't need to be intercepted
			return t.none(target)
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

			-- Sieve the potential list through each of the targeting functions, until 1 or fewer targets are left
			for i,f in ipairs(self) do
				-- Check to see if any potentials are left
				if n < 1 then
					return nil
				end

				-- Call the function
				if type(f) == "function" then
					local sieveType = "Unknown"
					if self == SelectTarget.Attack then
						sieveType = "Attack"
					elseif self == SelectTarget.Chase then
						sieveType = "Chase"
					end
					RAIL.Log(95,"Before Sieve #%d: sieve=%q; n=%d",i,sieveType,n)
					potentials,n = f(potentials,n,friends)
					RAIL.Log(95,"After  Sieve #%d: sieve=%q; n=%d",i,sieveType,n)
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
	
		-- Assist owner as first priority
		SelectTarget.Attack:Append(function(potentials,n)
			-- Check if we can assist our owner
			--	(check if owner has attacked in the last second or so)
			if History.FindMostRecent(RAIL.Owner.Motion,MOTION_ATTACK, 1250) <= 1000 then
				local owner_target = RAIL.Owner.Target[0]
				if RAIL.State.AssistOwner and potentials[owner_target] ~= nil then
					return { [owner_target] = Actors[owner_target] },1
				end
			end

			-- Don't modify the potential targets
			return potentials,n
		end)
	
		-- Assist owner's merc/homu
		SelectTarget.Attack:Append(function(potentials,n)
			-- Check if we can assist the other (merc or homun)
			if
				RAIL.Other ~= RAIL.Self and
				-- TODO: Setup a mechanism to communicate target and attack status
				RAIL.Other.Motion[0] == MOTION_ATTACK
			then
				local other_target = RAIL.Other.Target[0]
				if RAIL.State.AssistOther and potentials[other_target] ~= nil then
					return { [other_target] = Actors[other_target] },1
				end
			end

			-- Don't modify the potential targets
			return potentials,n
		end)

		-- Defend owner, other, and friends
		do
			local prioritization = function(defend_actors,defend_n,defend_prio,actors,n,prio)
				-- Make sure something is attacking this actor
				if n < 1 then
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

			SelectTarget.Attack:Append(function(potentials,n,friends)
				if not RAIL.State.Aggressive then
					-- If not aggressive, and not defending while passive, don't modify the list
					if not RAIL.State.DefendWhilePassive then
						return potentials,n
					end
				else
					-- If aggressive, and not prioritizing defense, don't modify the list
					if not RAIL.State.DefendWhileAggro then
						return potentials,n
					end
				end
	
				local owner_n = RAIL.Owner.TargetOf:GetN()
				local self_n = RAIL.Self.TargetOf:GetN()
	
				-- Check for the highest number of actors attacking friends/other
				local friends_n,friends_actors = 0,Table.New()
				do
					-- First, set other as the actor
					if RAIL.Self ~= RAIL.Other then
						friends_n = RAIL.Other.TargetOf:GetN()
						friends_actors:Append(RAIL.Other)
					end
	
					for id,actor in friends do
						local n = actor.TargetOf:GetN()
	
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
					return potentials,n
				end

				-- Keep a list of the actors that will be defended
				local defend_actors = Table.New()
				local defend_n = 0
				local defend_prio = 0

				-- Check to see if we should defend ourself
				-- TODO: make a state option for priority (PrioritizeSelfDefense,PrioritizeOwnerDefense,PrioritizeFriendDefense)
				defend_actors,defend_n,defend_prio =
					prioritization(defend_actors,defend_n,defend_prio,RAIL.Self,self_n,5)

				-- Check to see if we should defend our owner
				defend_actors,defend_n,defend_prio =
					prioritization(defend_actors,defend_n,defend_prio,RAIL.Owner,owner_n,1)

				-- Check to see if we should defend our friends
				defend_actors,defend_n,defend_prio =
					prioritization(defend_actors,defend_n,defend_prio,friends_actors,friends_n,4)

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

				return ret,ret_n
			end)
		end

		-- Sieve out monsters that would be Kill Stolen
		SelectTarget.Attack:Append(function(potentials,n)
			local ret,ret_n = {},0
			for id,actor in potentials do
				if not actor:WouldKillSteal() then
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end
			return ret,ret_n
		end)
	
		-- If not aggressive, sieve out monsters that aren't targeting self, other, owner, or a friend
		SelectTarget.Attack:Append(function(potentials,n,friends)
			-- If aggressive, don't modify the list
			if RAIL.State.Aggressive then
				return potentials,n
			end

			for id,actor in potentials do
				local target = actor.Target[0]
				if
					target ~= RAIL.Owner.ID and
					target ~= RAIL.Self.ID and
					target ~= RAIL.Other.ID and
					friends[target] == nil
				then
					potentials[id] = nil
					n = n - 1
				end
			end
			return potentials,n
		end)
	
		-- Select the highest priority set of monsters
		SelectTarget.Attack:Append(function(potentials,n)
			local ret,ret_n,ret_priority = {},0,-10000
	
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
	
			return ret,ret_n
		end)
	
		-- Check to see if the previous target is still in this list
		SelectTarget.Attack:Append(function(potentials,n)
			local id = RAIL.TargetHistory.Attack

			-- Check if a target was acquired, and is in the list
			if id ~= -1 and potentials[id] ~= nil then
				-- Use the previous target
				return { [id] = potentials[id] },1
			end

			-- It's not, so don't modify the potential list
			return potentials,n
		end)

		-- Find the closest actors
		SelectTarget.Attack:Append(function(potentials,n)
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

			return ret,ret_n
		end)
	end

	-- Chase targeting
	do
		SelectTarget.Chase = Table.New()
		setmetatable(SelectTarget.Chase,st_metatable)

		-- First, ensure we won't move outside of RAIL.State.MaxDistance
		SelectTarget.Chase:Append(function(potentials,n)
			-- MaxDistance is in block tiles, but attack range is in pythagorean distance...
			local max_dist = RAIL.State.MaxDistance

			-- Process each actor
			for id,actor in potentials do
				-- If the actor is within MaxDistance block tiles, this is easy
				if RAIL.Owner:BlocksTo(actor) < max_dist then
					-- Leave the actor in the list
				else
					-- Get the angle from our owner to the actor
					local angle,dist = RAIL.Owner:AngleTo(actor)

					-- If the distance is less than our attack range, we'll be fine
					if dist < RAIL.Self.AttackRange then
						-- Leave the actor in the list
					else
						-- Plot a point that will be closer to the owner
						local x,y = RAIL.Owner:AnglePlot(angle,dist - RAIL.Self.AttackRange + 1)

						-- Check if this point would be inside MaxDistance
						if RAIL.Owner:BlocksTo(x,y) < max_dist then
							-- Leave the actor in the list
						else
							-- Take the actor out of the list, it's outside of range
							potentials[id] = nil
							n = n - 1
						end
					end
				end
			end

			return potentials,n
		end)

		-- Then, chase targeting is mostly the same as attack targeting
		--	Note: Don't copy the attack-target locking
		do
			local max = SelectTarget.Attack:GetN()
			for i=1,max do
				if i ~= max-1 then
					SelectTarget.Chase:Append(SelectTarget.Attack[i])
				end
			end
		end

		-- Check to see if the previous target is still in this list
		SelectTarget.Chase:Append(function(potentials,n)
			local id = RAIL.TargetHistory.Chase

			-- Check if a target was acquired, and is in the list
			if id ~= -1 and potentials[id] ~= nil then
				-- Use the previous target
				return { [id] = potentials[id] },1
			end

			-- If not in the list, don't modify the list
			return potentials,n
		end)
	end

	-- Attack Skill targeting
	do
		SelectTarget.Skill = {}
		SelectTarget.Skill.Attack = Table.New()
		setmetatable(SelectTarget.Skill.Attack,st_metatable)

		-- Copy everything from attack
		for i=1,SelectTarget.Attack:GetN() do
			SelectTarget.Skill.Attack:Append(SelectTarget.Attack[i])
		end

		-- But remove the target locking
		SelectTarget.Skill.Attack:Remove(SelectTarget.Skill.Attack:GetN()-1)
	end
end