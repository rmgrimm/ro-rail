--
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
		end
	})
end