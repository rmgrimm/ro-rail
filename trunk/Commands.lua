-- GetMsg command processing
do
	RAIL.Cmd = {
		Queue = List:New(),
		ProcessInput = {
			-- Nothing
			[NONE_CMD] = function(shift,msg)
				-- Do nothing
			end,

			-- "alt+right click" on ground
			--	("alt+left click" for mercenaries)
			[MOVE_CMD] = function(shift,msg)
				-- Clear queue if shift isn't depressed
				if not shift then
					RAIL.Cmd.Queue:Clear()
				end

				-- Check for under-target attack command / advanced movement commands
				if not RAIL.AdvMove(shift,msg[2],msg[3]) then
					-- If it didn't turn out to be an advanced command,
					-- add movement to the queue
					RAIL.Cmd.Queue:PushRight(msg)
				end
			end,

			-- "alt+right click" on enemy, twice
			--	("alt+left click" twice for mercenaries)
			[ATTACK_OBJECT_CMD] = function(shift,msg)
				-- Clear queue if shift isn't depressed
				if not shift then
					RAIL.Cmd.Queue:Clear()
				end

				-- Add to queue
				RAIL.Cmd.Queue:PushRight(msg)
			end,

			-- Actor-targeted skill
			[SKILL_OBJECT_CMD] = function(shift,msg)
				-- Clear queue if shift isn't depressed
				if not shift then
					RAIL.Cmd.Queue:Clear()
				end

				-- Get the skill and level to be used
				local skill = AllSkills[msg[3]][msg[2]]

				-- Add to queue
				--	Note: Redo msg to use the skill object instead of skill ID + level
				RAIL.Cmd.Queue:PushRight({ SKILL_OBJECT_CMD, skill, msg[4] })
			end,

			-- Ground-targeted skill
			[SKILL_AREA_CMD] = function(shift,msg)
				-- Clear queue if shift isn't depressed
				if not shift then
					RAIL.Cmd.Queue:Clear()
				end

				-- Get the skill and level to be used
				local skill = AllSkills[msg[3]][msg[2]]

				-- Add to queue
				--	Note: Redo msg to use the skill object instead of skill ID + level
				RAIL.Cmd.Queue:PushRight({ SKILL_AREA_CMD, skill, msg[4], msg[5] })
			end,

			-- "alt+t" ("ctrl+t" for mercenaries)
			[FOLLOW_CMD] = function(shift,msg)
				-- Toggle aggressive mode
				RAIL.State.Aggressive = not RAIL.State.Aggressive

				-- Log it
				local key = "ALT+T"
				if RAIL.Mercenary then key = "CTRL+T" end
				RAIL.LogT(1,"<{1}> RAIL.State.Agressive set to \"{2}\", due to {1} press.",key,RAIL.State.Aggressive)
			end,
		},
		Evaluate = {
			[MOVE_CMD] = function(msg,skill,atk,chase)
				-- Check if we've already arrived
				if RAIL.Self:DistanceTo(msg[2],msg[3]) < 1 then
					-- Remove the command and don't modify any targets
					return false,skill,atk,chase
				end

				-- Check if the move would be out of range
				if RAIL.Owner:BlocksTo(msg[2],msg[3]) > RAIL.State.MaxDistance then
					-- TODO: Move to the closest spot that is in range

					-- Set no targets, and don't interrupt processing
					return false,skill,atk,chase
				end

				-- Set the chase target and stop processing
				return true,skill,atk,msg
			end,
			[ATTACK_OBJECT_CMD] = function(msg,skill,atk,chase)
				-- Check for valid, active actor
				local actor = Actors[msg[2]]
				if not actor.Active then
					-- Invalid actor; don't interrupt processing; don't set targets
					return false,skill,atk,chase
				end

				if RAIL.Self:DistanceTo(actor) <= RAIL.Self.AttackRange then
					-- If close enough, attack the monster
					atk = actor
				else
					-- Otherwise, chase the monster
					chase = actor
				end

				-- Interrupt processing after changing one of the targets
				return true,skill,atk,chase
			end,
			[SKILL_OBJECT_CMD] = function(msg,skill,atk,chase)
				-- Check if a skill is usable now
				if RAIL.Self.SkillState:Get() == RAIL.Self.SkillState.Enum.READY then
					-- Check if we've already used this command
					if msg.CmdUsed then
						-- Remove the command and don't modify targets
						return false,skill,atk,chase
					end

					-- Get the skill and actor from msg
					local skill_obj = msg[2]
					local actor = Actors[msg[3]]

					-- Ensure the actor hasn't timed out or died
					if not actor.Active then
						return false,skill,atk,chase
					end

					-- Check if the target is out of range
					if RAIL.Self:DistanceTo(actor) > skill_obj:GetRange() then
						-- Chase the target
						return true,skill,atk,actor
					else
						-- Set a flag that the skill is used now
						msg.CmdUsed = true

						-- Stop processing, and set the skill target
						return true,{ skill_obj, actor },atk,chase
					end
				end

				-- Don't continue processing, but don't modify targets
				return true,skill,atk,chase
			end,
			[SKILL_AREA_CMD] = function(msg,skill,atk,chase)
				-- Check if a skill is usable now
				if RAIL.Self.SkillState:Get() == RAIL.Self.SkillState.Enum.READY then
					-- Check if we've already used this command
					if msg.CmdUsed then
						-- Remove the command and don't modify targets
						return false,skill,atk,chase
					end

					-- Check if the target is out of range
					if RAIL.Self:DistanceTo(msg[3],msg[4]) < msg[2]:GetRange() then
						-- Remove the command and don't modify targets
						return false,skill,atk,chase
					else
						-- Set a flag that the skill is used now
						msg.CmdUsed = true

						-- Stop processing, and set the skill target
						return true,{ msg[2], msg[3], msg[4] },atk,chase
					end
				end

				-- Don't continue processing, but don't modify targets
				return true,skill,atk,chase
			end,
		},
	}

	local UnknownProcessInput = function(shift,msg,cmd)
		-- Initialize a string buffer
		local str = StringBuffer:New():Append(msg[1]):Append("(")

		-- Add each message argument to the string buffer
		local msg_i=2
		while msg[msg_i] ~= nil do
			-- Keep arguments comma-separated
			if msg_i ~= 2 then str:Append(", ") end

			-- Format arguments to strings, and quote existing strings
			local t = type(msg[msg_i])
			if t == "string" then
				t = "%q"
			else
				t = "%s"
				msg[msg_i] = tostring(msg[msg_i])
			end

			str:Append(string.format(t,msg[msg_i]))
		end

		if not cmd then cmd = "GetMsg()" end
		RAIL.LogT(0,"Unknown {1} command: shift={2}; msg={3}.",cmd,shift,str:Append(")"):Get())
	end

	setmetatable(RAIL.Cmd.ProcessInput,{
		__index = function(self,cmd_id)
			-- Any command that wasn't recognized will be logged
			return UnknownProcessInput
		end,
		__call = function(self,shift,msg)
			-- Call the relevant subfunction
			self[msg[1]](shift,msg)
		end,
	})

	local function UnknownProcessEvaluate(msg,skill,atk,chase)
		-- For simplicity, send it to UnknownProcessInput for logging
		UnknownProcessInput(false,msg,"evaluate")

		-- Remove it from the queue
		RAIL.Cmd.Queue:PopLeft()

		-- Continue processing
		return true,skill,atk,chase
	end

	setmetatable(RAIL.Cmd.Evaluate,{
		__call = function(self,skill,atk,chase)
			-- Loop as long as there are commands to process (or a command signals to break
			local break_sig = false
			while RAIL.Cmd.Queue:Size() > 0 and not break_sig do
				-- Get the command
				local msg = RAIL.Cmd.Queue[RAIL.Cmd.Queue.first]

				-- Get a function to process it
				local f = self[msg[1]]

				-- Process the command
				break_sig,skill,atk,chase = f(msg,skill,atk,chase)

				if not break_sig then
					-- Remove the command
					RAIL.Cmd.Queue:PopLeft()
				end
			end

			return skill,atk,chase
		end,
		__index = function(self,cmd_id)
			-- Any command that wasn't recognized will be logged
			return UnknownProcessEvaluate
		end,
	})
end

-- Advanced movement commands
do
	RAIL.AdvMove = {}

	local function false_ret()
		return false
	end
	local x_mt = {
		__index = function(self,idx)
			-- Ensure the idx is a number
			if type(idx) ~= "number" then
				return nil
			end

			-- Return a blank function
			return false_ret
		end,
	}

	setmetatable(RAIL.AdvMove,{
		__index = function(self,idx)
			-- Ensure the idx is a number
			if type(idx) ~= "number" then
				return nil
			end

			-- Ensure that the subtable for the X-idx exists
			if rawget(self,idx) == nil then
				rawset(self,idx,{})
				setmetatable(self[idx],x_mt)
			end

			return self[idx]
		end,
		__newindex = function(self,idx,val)
			-- Don't allow new indexes to be created
		end,
		__call = function(self,shift,x,y)
			-- Find the closest actor to the location
			local closest,x_delt,y_delt,blocks
			do
				local actors = GetActors()
				for i,a in actors do
					local actor = Actors[a]
					local b = actor:BlocksTo(x,y)
	
					if not blocks or b < blocks then
						closest = actor
						x_delt = x - actor.X[0]
						y_delt = y - actor.Y[0]
						blocks = b
					end
				end
			end

			-- If there are no actors at all, do nothing
			if not closest then
				return false
			end

			-- Call the relevant function
			return self[x_delt][y_delt](shift,closest)
		end,
	})


	-- Under-target attack
	RAIL.AdvMove[0][0] = function(shift,target)
		-- Process the attack object command
		RAIL.Cmd.ProcessInput(shift,{ATTACK_OBJECT_CMD,target.ID})

		-- Return true, because we've used an advanced command
		return true
	end

	-- 1-tile left of a target: delete friend
	RAIL.AdvMove[-1][0] = function(shift,target)
		-- Ensure the target is a player
		if target.ActorType ~= "Player" then
			return false
		end

		-- Check if the target is our owner
		if target == RAIL.Owner then
			-- TODO: Remove all players on screen from friend list.
			return true
		end

		-- Check if the target is a friend
		if target:IsFriend(true) then
			-- Log it
			RAIL.LogT(1,"{1} removed from friend list.",target)

			-- Remove it from friend list
			target:SetFriend(false)

			-- Intercept movement command; advanced command accepted
			return true
		end

		-- Log it
		RAIL.LogT(1,"{1} not marked as friend; can't remove friend status.",target)

		-- Don't intercept movement command
		return false
	end

	-- 1-tile right of a target: add friend
	RAIL.AdvMove[1][0] = function(shift,target)
		-- Check for a player
		if target.ActorType ~= "Player" then
			-- Can't set non-players as friend, don't use as advanced command
			return false
		end

		-- Check if the target is our owner
		if target == RAIL.Owner then
			-- TODO: Set all players on screen as friend.
			return true
		end

		-- Check if the target is already a friend (not including temporary friends)
		if not target:IsFriend(true) then
			-- Log it
			RAIL.LogT(1,"{1} marked as friend.",target)

			-- Set the target as a friend
			target:SetFriend(true)

			-- Return true, to indicate that we used an advanced movement command
			return true
		end

		-- Log it
		RAIL.LogT(1,"{1} is already marked as a friend.",target)

		-- Didn't actually do anything, don't interrupt command
		return false
	end
end
