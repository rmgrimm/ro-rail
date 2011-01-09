-- Debugging support hook
function DebugHook(func,arg_type)
  return function(...)
    local i = 1
    while arg_type[i] do
      if type(arg[i]) ~= arg_type[i] then
        return nil
      end
      i = i + 1
    end
    
    return func(unpack(arg))
  end
end

-- Distance functions
do
	-- Pythagorean Distance
	function PythagDistance(x1,y1,x2,y2)
		return math.sqrt((x2-x1)^2 + (y2-y1)^2)
	end
	--PythagDistance = DebugHook(PythagDistance,{"number","number","number","number"})

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
	local function do_round(num,idp)
		local mult = 10^(idp or 0)
		return math.floor(num * mult + 0.5) / mult
	end

	-- Round a number up or down based on the decimal
	function RoundNumber(n,...)
		-- Ensure we have a number to round
		if not n then return nil end

		-- Round the number, and recurse
		return do_round(n),RoundNumber(unpack(arg))
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
	--GetAngle = DebugHook(GetAngle,{"number","number","number","number"})

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
		if
      not GetV or
      not GetActors or
      not IsMonster
    then
      local Owner_id = 1134002
      local AI_id = 5319
      local actors = {
        [Owner_id] = {
          X = 33, Y = 82,
          Type = 18,              -- Alchemist
          IsMonster = 0,
          Motion = MOTION.STAND,
          Target = -1,
          HP = 99, MaxHP = 100,
          SP = 99, MaxSP = 100,
        },
        [AI_id] = {
          X = 33, Y = 82,
          Type = ARCHER10,
          IsMonster = 0,
          Motion = MOTION.STAND,
          Target = -1,
          HP = 98, MaxHP = 100,
          SP = 98, MaxSP = 100,
        },
        [59867] = { X = 31, Y = 81, Type = 1000, IsMonster = 1, Target = Owner_id, Motion = MOTION.ATTACK, },
        [59930] = { X = 34, Y = 81, Type = 1000, IsMonster = 1, Target = Owner_id, Motion = MOTION.MOVE, },
        [59920] = { X = 33, Y = 81, Type = 1000, IsMonster = 1, Target = Owner_id, Motion = MOTION.ATTACK, },
        [59876] = { X = 32, Y = 80, Type = 1000, IsMonster = 1, Target = Owner_id, Motion = MOTION.MOVE, },
        [59838] = { X = 44, Y = 74, Type = 1000, IsMonster = 1, Target = Owner_id, Motion = MOTION.MOVE, },
        [59942] = { X = 45, Y = 70, Type = 1000, IsMonster = 1, Target = Owner_id, Motion = MOTION.STAND, },
      }
      GetActors = function()
        local ret,i = {},1
        for id in pairs(actors) do
          ret[i] = id
          i = i + 1
        end
        
        return ret
      end
      IsMonster = function(id)
        if actors[id] then
          return actors[id].IsMonster
        end
        
        return 0
      end
			GetV = setmetatable({},{
        __call = function(self,v_,...)
          if type(self[v_]) == "function" then
            return self[v_](unpack(arg))
          end
          
          return -1
        end
			})
			GetV[V_OWNER] = function(id) return Owner_id end
			GetV[V_POSITION] = function(id)
			 if actors[id] then
			   return actors[id].X,actors[id].Y
			  end
			  
			  return -1,-1
			end
			GetV[V_TYPE] = function(id) end
			GetV[V_MOTION] = function(id)
        if actors[id] then
			   return actors[id].Motion
			  end

        return -1
		  end
		  GetV[V_ATTACKRANGE] = function(id)
		    local t = actors[AI_id].Type
		    if RAIL.Mercenary and t <= 10 then
		      return 10
		    end
		    
		    return 2
		  end
		  GetV[V_TARGET] = function(id)
		    if actors[id] then
		      return actors[id].Target
		    end
		    
		    return -1
		  end
		  GetV[V_SKILLATTACKRANGE] = GetV[V_ATTACKRANGE]
		  GetV[V_HOMUNTYPE] = function(id)
		    if RAIL.Mercenary then
		      return
		    end
		    
		    if actors[id] then
		      return actors[id].Type
		    end
		    
		    return -1
		  end
		  GetV[V_HP] = function(id)
		    if actors[id] then
		      return actors[id].HP or -1
		    end
		    
		    return -1
		  end
		  GetV[V_SP] = function(id)
		    if actors[id] then
		      return actors[id].SP or -1
		    end

		    return -1
		  end
		  GetV[V_MAXHP] = function(id)
		    if actors[id] then
		      return actors[id].MaxHP or -1
		    end

		    return -1
		  end
		  GetV[V_MAXSP] = function(id)
		    if actors[id] then
		      return actors[id].MaxSP or -1
		    end

		    return -1
		  end
		  GetV[V_MERTYPE] = function(id)
		    if not RAIL.Mercenary then
		      return
		    end
		    
		    return actors[AI_id].Type
		  end
		  
		  RAIL.Event["AI CYCLE"]:Register(-100,
		                                  "Replace AI ID",
		                                  -1,
		                                  function(self,id)
        self.Event.Args[1] = AI_id
		  end)

			TraceAI("GetV(), GetActors(), or IsMonster() not supplied, undefined behavior may occur.")
			sane = false
		end

		-- Check tick count
		if not GetTick then
			GetTick = function()
				return os.clock() * 1000
			end
			TraceAI("GetTick() not supplied, undefined behavior may occur.")
			sane = false
		end

		if not Move then
		  Move = function(id,x,y)
		    TraceAI("Move(" .. id .. "," .. x .. "," .. y .. ")")
		  end
		  TraceAI("Move() not supplied, undefined behavior may occur.")
		  sane = false
		end

		if not SkillObject then
		  SkillObject = function(self_id,level,skill_id,target_id)
		    TraceAI("SkillObject(" .. self_id .. "," .. level .. "," .. skill_id .. "," .. target_id .. ")")
		  end
		  TraceAI("SkillObject() not supplied, undefined behavior may occur.")
		  sane = false
		end

		if not Attack then
		  Attack = function(self_id,target_id)
		    TraceAI("Attack(" .. self_id .. "," .. target_id .. ")")
		  end
		  TraceAI("Attack() not supplied, undefined behavior may occur.")
		  sane = false
		end

		-- Is the environment sane?
		return sane
	end

	CheckAPI()
end
