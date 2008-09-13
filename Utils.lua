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

	-- TODO: Angle compare
end
