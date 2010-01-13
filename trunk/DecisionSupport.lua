-- Validation options
RAIL.Validate.InterceptAlgorithm = {"string","normal"}
RAIL.Validate.Aggressive = {"boolean", true}
RAIL.Validate.AssistOwner = {"boolean", false}

-- Interception Routines
do
	RAIL.CalculateIntercept = {
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

	setmetatable(RAIL.CalculateIntercept,{
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
	RAIL.SelectTarget = { }

	-- The metatable to run subtables
	local st_metatable = {
		__call = function(self,potentials)
			-- Count the number of potential targets
			local n=0
			for i in potentials do
				n=n+1
			end

			-- Sieve the potential list through each of the targeting functions, until 1 or fewer targets are left
			for i,f in ipairs(self) do
				-- Call the function
				if type(f) == "function" then
					potentials,n = f(potentials,n)
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
	RAIL.SelectTarget.Attack = {
		-- Assist owner as top priority
		[1] = function(potentials,n)
			-- Check if we can assist our owner
			if RAIL.State.AssistOwner and potentials[RAIL.Owner.Target[0]] ~= nil then
				return { RAIL.Owner.Target[0] },1
			end

			-- Don't modify the potential targets
			return potentials,n
		end,

		-- Defend owner
		[2] = function(potentials,n)
			-- TODO: this
			return potentials,n
		end,

		-- Assist owner's merc/homu
		[3] = function(potentials,n)
			-- Check if we can assist the other (merc or homun)
			if RAIL.Other ~= RAIL.Self and RAIL.State.AssistOther and potenitals[RAIL.Other.Target[0]] ~= nil then
				return { RAIL.Other.Target[0] },1
			end

			-- Don't modify the potential targets
			return potentials,n
		end,

		-- Defend friends and other
		[4] = function(potentials,n)
			-- Check if we should defend friends

			-- TODO: this
			return potentials,n
		end,

		-- Sieve out monsters that would be Kill Stolen
		[5] = function(potentials,n)
			local ret,ret_n = {},0
			for id,actor in potentials do
				if not actor:WouldKillSteal() then
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end
			return ret,ret_n
		end,

		-- If not aggressive, sieve out monsters that aren't targeting self, other, or owner
		[6] = function(potentials,n)
			-- If aggressive, don't modify the list
			if RAIL.State.Aggressive then
				return potentials,n
			end

			local ret,ret_n = {},0
			for id,actor in potentials do
				local target = actor.Target[0]
				if target == RAIL.Owner or target == RAIL.Self or target == RAIL.Other then
					ret[id] = actor
					ret_n = ret_n + 1
				end
			end
			return ret,ret_n
		end,

		-- Select the highest priority set of monsters
		[7] = function(potentials,n)
			local ret,ret_n,ret_priority = {},0,0

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
		end,
	}
	setmetatable(RAIL.SelectTarget.Attack,st_metatable)

	-- Chase targeting
	RAIL.SelectTarget.Chase = {
		-- Chase targeting is mostly the same as attack targeting
		[2] = RAIL.SelectTarget.Attack[1],
		[3] = RAIL.SelectTarget.Attack[2],
		[4] = RAIL.SelectTarget.Attack[3],
		[5] = RAIL.SelectTarget.Attack[4],
		[6] = RAIL.SelectTarget.Attack[5],
		[7] = RAIL.SelectTarget.Attack[6],
		[8] = RAIL.SelectTarget.Attack[7],

		-- But won't move outside of RAIL.State.MaxDistance
		[1] = function(potentials,n)
			-- TODO: this
			return potentials,n
		end,

		-- Add one more routine to remove monsters that are already in range
		[9] = function(potentials,n)
			-- TODO: this
			return potentials,n
		end,
	}
	setmetatable(RAIL.SelectTarget.Chase,st_metatable)
end