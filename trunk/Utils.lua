-- Distance functions
do
	-- Pythagorean Distance
	function PythagDistance(x1,y1,x2,y2)
		return math.sqrt((x2-x1)^2 + (y2-y1)^2)
	end

	-- Block Distance
	function BlockDistance (x1,y1,x2,y2)
		local x_delta = math.abs(x2-x1)
		local y_delta = math.abs(y2-y1)
	
		if x_delta > y_delta then
			return x_delta
		end

		return y_delta
	end
end

-- Number functions
do
	-- Round a number up or down based on the decimal
	function RoundNumber(n)
		local floor = math.floor(n)
		n = n - floor

		if n >= 0.5 then
			return floor + 1
		else
			return floor
		end
	end
end

-- Angle functions
do
	function GetAngle(x1,y1,x2,y2)
		-- Get the radius first
		local radius = PythagDistance(x1,y1,x2,y2)

		-- Radius of 0 has no angle
		if radius == 0 then
			return -1,0
		end

		-- Get the deltas
		local x_delta = x2-x1
		local y_delta = y2-y1

		-- Get degrees from X
		local angle = math.deg(math.acos(x_delta / radius))

		-- Get modification from Y
		if math.deg(math.asin(y_delta / radius)) < 0 then
			angle = 360 - angle
		end

		-- Return angle and radius
		return angle,radius
	end

	function PlotCircle(x,y,angle,radius)
		-- Convert the angle to radians
		angle = math.rad(angle)

		-- Calculate the deltas
		local x_delta = radius * math.cos(angle)
		local y_delta = radius * math.sin(angle)

		-- Apply the deltas to the position, then return
		return x+x_delta, y+y_delta
	end

	-- Check to see if an angle is within X degrees of a second
	function CompareAngle(angle1,angle2,degrees)
		local bottom,top

		-- Get the modulus remainder of both angles
		angle1 = math.mod(angle1,360)
		angle2 = math.mod(angle2,360)
	
		-- Check if degrees is positive or negative
		if degrees > 0 then
			-- Check if adding degrees to angle1 would throw it past 359
			if angle1 + degrees >= 360 then
				-- Make a second check
				if CompareAngle(0,angle2,math.mod(angle1 + degrees,360)) then
					-- Found it already
					return true
				end
	
				-- Reduce degrees below 360
				degrees = degrees - math.mod(angle1 + degrees,360) - 1
			end
	
			-- Set the bottom and the top
			bottom = angle1
			top = angle1 + degrees
	
		elseif degrees < 0 then
			-- Invert the degrees, to make later stuff easier to read
			degrees = -degrees
	
			-- Check if subtracting degrees would throw it under 0
			if angle1 - degrees < 0 then
				-- Make a second check
				if CompareAngle(360 + angle1 - degrees,angle2,math.abs(angle1 - degrees) - 1) then
					-- Found it already
					return true
				end
	
				-- Increase the degrees above -1
				degrees = degrees + math.abs(angle1 - degrees)
			end
	
			-- Set the bottom
			bottom = angle1 - degrees
			top = angle1
	
		else
			-- If degrees is 0, then check if the angles are the same
			if angle1 == angle2 then
				-- They check out as the same
				return true
			end
	
			-- They're not the same
			return false
		end
	
		-- Check if its above the bottom but below the top, inclusively
		if bottom <= angle2 and angle2 <= top then
			-- Its inside
			return true
		end
	
		-- Its not inside
		return false
	end
end

-- Check for sanity of Ragnarok API environment
do
	local function CheckAPI()
		local sane = true

		-- Check TraceAI logging
		if not TraceAI then
			TraceAI = function(str)
				-- Output to the console
				print(str);
			end
		end

		-- Check user-input
		if not GetMsg then
			GetMsg = function()
				return { 0 }	-- NONE_CMD
			end
			TraceAI("GetMsg() not supplied, in-game command may be impossible.")
		end
		if not GetResMsg then
			GetResMsg = function()
				return { 0 }	-- NONE_CMD
			end
			TraceAI("GetResMsg() not supplied, in-game command may be impossible.")
		end

		-- Check actor-tracking
		if not GetV then
			GetV = function(v,id)
				if id == -1 then
					return -1,-1
				else
					return 0,0
				end
			end
			TraceAI("GetV() not supplied, undefined behavior may occur.")
			sane = false
		end
		if not GetActors then
			GetActors = function()
				return {
					0,
					1,
					--id,		-- self
					--GetV(0,id),	-- owner: GetV(V_OWNER,id)
				}
			end
			TraceAI("GetActors() not supplied, undefined behavior may occur.")
			sane = false
		end
		if not IsMonster then
			IsMonster = function(actor_id)
				-- Check a few conditions for non-monsters
				if
					actor_id < 0 or
					--actor_id == id or
					--actor_id == GetV(0,id) or	-- GetV(V_OWNER,id)
					false		-- (no other conditions)

					-- Note: Don't check for ID ranges of NPCs, Players, etc,
					--	IsMonster isn't supplied, so the environment isn't sane anyway...
				then
					return 0
				end

				-- Default all but self and owner to monsters
				return 1
			end
			TraceAI("IsMonster() not supplied, undefined behavior may occur.")
			sane = false
		end

		-- Check tick count
		if not GetTick then
			GetTick = function()
				return -1
			end
			TraceAI("GetTick() not supplied, undefined behavior may occur.")
			sane = false
		end

		-- Is the environment sane?
		return sane
	end

	CheckAPI()
end
