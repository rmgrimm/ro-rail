do
	RAIL.Cmd = {
		Queue = List:New(),
		ProcessInput = {
			-- Nothing
			[NONE_CMD] = function(shift,msg)
				-- Do nothing
			end,

			-- "alt+right click" on ground
			[MOVE_CMD] = function(shift,msg)
				-- Clear queue if shift isn't depressed
				if not shift then
					RAIL.Cmd.Queue:Clear()
				end

				-- TODO: Check for under-target attack command

				-- Add to queue
				RAIL.Cmd.Queue:PushRight(msg)
			end,

			-- "alt+right click" on enemy, twice
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