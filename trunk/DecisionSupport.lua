-- Validation options
RAIL.Validate.InterceptAlgorithm = {"string","normal",
	-- Note: Don't allow advanced until it's written
	{ ["none"] = true, ["sloppy"] = true, ["normal"] = true, ["advanced"] = nil, }
}
RAIL.Validate.RunAhead = {"boolean",false}

RAIL.Validate.IdleMovement = {is_subtable = true,
	MoveType = {"string","none",
		{ ["none"] = true, ["return"] = true, }
	},
	BeginAfterIdleTime = {"number",3000,0},
}

RAIL.Validate.MaxDistance = {"number", 13, 0}
RAIL.Validate.FollowDistance = {"number", 4, 0, nil}	-- maximum value will be MaxDistance
setmetatable(RAIL.Validate.FollowDistance,{
	__index = function(self,idx)
		if idx == 4 then
			return RAIL.State.MaxDistance
		end

		return nil
	end,
})

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
			local algo = t[RAIL.State.InterceptAlgorithm] or t.none

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

-- Idle handlers
do
	Idle = {
		Handlers = Table.New(),
		Run = function(self,idletime)
			-- Loop through each handler until one doesn't return "true"
			for i,handler in ipairs(self.Handlers) do
				-- Run the function
				local continue = handler[2](idletime)

				if continue ~= true then
					break
				end
			end
		end,
	}

	-- Return before using skills
	Idle.Handlers:Append{"ReturnToOwner",function(idletime)
		-- Only move if idle movement type is set to "return"
		if RAIL.State.IdleMovement.MoveType ~= "return" then
			return true
		end

		-- Check if we've waited long enough
		if idletime < RAIL.State.IdleMovement.BeginAfterIdleTime then
			-- Continue looping through idle handlers
			return true
		end

		-- Only return if too far away
		if RAIL.Self:BlocksTo(RAIL.Owner) <= RAIL.State.FollowDistance then
			return true
		end

		-- TODO: Log it

		-- Set the chase target to our owner
		RAIL.Target.Chase = RAIL.Owner

		-- Don't continue processing idle-handlers
		return false
	end}

	-- Use skills before pathed walk
	Idle.Handlers:Append{"IdleSkills",function(idletime)
		-- Defer processing to SelectSkill's RunIdle function
		RAIL.Target.Skill = SelectSkill:RunIdle(idletime)

		-- TODO: Log it

		-- If a skill target was found, don't continue processing
		return RAIL.Target.Skill == nil
	end}

	-- TODO: Pathed walk
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
