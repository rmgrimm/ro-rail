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
				-- Get the skill and level to be used
				local skill = AllSkills[msg[3]][msg[2]]

				-- Add to queue
				--RAIL.Cmd.Queue:PushRight(skill)

				-- Until skills are implemented properly, just pass the skill along to the server
				Actors[msg[4]]:SkillObject(skill)
			end,

			-- Ground-targeted skill
			[SKILL_AREA_CMD] = function(shift,msg)
				-- Get the skill and level to be used
				local skill = AllSkills[msg[3]][msg[2]]

				-- Add to queue
				--RAIL.Cmd.Queue:PushRight(msg)

				-- Until skills are implemented properly, just pass the skill along to the server
				skill:Cast(msg[4],msg[5])
			end,

			-- "alt+t" ("ctrl+t" for mercenaries)
			[FOLLOW_CMD] = function(shift,msg)
				-- Toggle aggressive mode
				RAIL.State.Aggressive = not RAIL.State.Aggressive

				-- Log it
				local key = "ALT+T"
				if RAIL.Mercenary then key = "CTRL+T" end
				RAIL.Log(1,"<%s> RAIL.State.Agressive = %s",key,tostring(RAIL.State.Aggressive))
			end,
		},
		Evaluate = {
		},
	}

	local UnknownProcessInput = function(shift,msg)
		-- Initialize a string buffer
		local str = StringBuffer:New():Append("Unknown GetMsg() command: %d(")

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

		RAIL.Log(0,str:Append(")"):Get())
	end

	setmetatable(RAIL.Cmd.ProcessInput,{
		__index = function(self,cmd_id)
			-- Any command that wasn't recognized will be logged
			return UnknownProcessInput
		end,
	})

	setmetatable(RAIL.Cmd.Evaluate,{
		__index = function(self,cmd_id)

		end
	})
end