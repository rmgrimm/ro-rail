-- GetMsg command processing
do
  RAIL.Cmd = {}
  RAIL.Cmd.Queue = List.New()

  -- Function to command the AI to move to a specific spot
  local function ChaseTo(x,y)
    -- Get the tile located at (x,y)
    x,y = RAIL.ChaseMap:TranslateFromParent(x,y)
    local tile = RAIL.ChaseMap(x,y)

    -- Increase the chase priority
    tile.priority = tile.priority + 1000
  end

  -- Function to log the information about an unknown message
  local function UnknownMessage(shift,msg,cmd)
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

    RAIL.LogT(0,"Unknown {1} command: shift={2}; msg={3}.",cmd,shift,str:Append(")"):Get())
  end

  -- Functions to process input from the user
  RAIL.Cmd.ProcessInput = {
    -- Nothing
    [NONE_CMD] = function(shift,msg)
      -- Do nothing
    end,

    -- "alt+right click" on ground
    --  ("alt+left click" for mercenaries)
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
    --  ("alt+left click" twice for mercenaries)
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
      --  Note: Redo msg to use the skill object instead of skill ID + level
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
      --  Note: Redo msg to use the skill object instead of skill ID + level
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
  }

  RAIL.Event["AI CYCLE"]:Register(125,                  -- Priority
                                  "Process Commands",   -- Handler name
                                  -1,                   -- Max runs (negative means infinite)
                                  function(self,id)
    do
      -- Check for a regular command
      local shift = false
      local msg = GetMsg(id)

      if msg[1] == NONE_CMD then
        -- Check for a shift+command
        shift = true
        msg = GetResMsg(id)
      end

      -- Process any input command
      local f = RAIL.Cmd.ProcessInput[msg[1]]
      if type(f) == "function" then
        f(shift,msg)
      else
        -- Unknown input command, log it
        UnknownMessage(shift,msg,"GetMsg()")
      end
    end
  end)
  
  -- False CMD to place hold until a skill goes off
  local SKILL_WAIT_CMD = {}

  -- Helper function to remove SKILL_WAIT_CMD from the queue
  local function RemoveSkillWait(skill_target)
    local queue = RAIL.Cmd.Queue

    -- Ensure there are commands on the queue
    if queue:Size() < 1 then
      return
    end

    -- Get the first item
    local first_item = queue[queue.first]

    -- Ensure the first item is SKILL_WAIT_CMD
    if first_item[1] ~= SKILL_WAIT_CMD then
      return
    end

    -- Check that the skill_target matches
    if first_item[2] ~= skill_target then
      return
    end

    -- Pop the SKILL_WAIT_CMD off the command processing queue
    RAIL.Cmd.Queue:PopLeft()

    -- Check if the target skill has already been set
    if RAIL.Target.Skill == skill_target then
      RAIL.Target.Skill = nil
    end
  end

  -- Helper function to select a skill and set the callbacks on it
  local function SetSkill(skill_target)
    -- Mark it as a manually requested skill
    skill_target.Manual = true

    -- Set the skill
    RAIL.Target.Skill = skill_target
    
    -- Replace the skill use command with SKILL_WAIT_CMD
    RAIL.Cmd.Queue:PopLeft()
    RAIL.Cmd.Queue:PushLeft{ SKILL_WAIT_CMD, skill_target }

    -- Generate closures for callbacks on the skill
    local failures = 0
    local function SuccessCallback(self,skill,ticks)
      -- Call the helper function
      RemoveSkillWait(skill_target)
    end
    local function FailureCallback(self,skill,ticks)
      -- If we failed more than 3 times, just forget the skill
      if failures > 3 then
        RemoveSkillWait(skill_target)
        return
      end

      -- Increment the number of failures
      failures = failures + 1
    end
    
    -- Set the callbacks for the skill
    RAIL.Self.SkillState.Callbacks:Add(skill_target[1],   -- The skill
                                       SuccessCallback,
                                       FailureCallback,
                                       false)             -- Do not persist
  end

  -- Process commands that have been queued up
  RAIL.Cmd.Evaluate = {
      [MOVE_CMD] = function(msg)
        -- Get the (x,y) coordinates
        local x,y = msg[2],msg[3]

        -- Check if we've already arrived
        if RAIL.Self:DistanceTo(x,y) < 1 then
          -- Remove the command and don't modify any targets
          return false
        end

        -- Check if the location is out of max range
        if RAIL.Owner:BlocksTo(x,y) > RAIL.State.MaxDistance then
          -- TODO: Move to the closest spot that is in range

          -- Don't interrupt processing
          return false
        end

        -- Chase to that location
        ChaseTo(x,y)

        return true
      end,
      [ATTACK_OBJECT_CMD] = function(msg)
        -- Check for valid, active actor
        local actor = Actors[msg[2]]
        if not actor.Active then
          -- Invalid actor; don't continue this one
          return false
        end

        local range = RAIL.Self.AttackRange
        if RAIL.Self:DistanceTo(actor) <= range then
          -- If close enough, attack the monster
          RAIL.Target.Attack = actor
        else
          -- Otherwise, chase the monster
          ChaseTo(actor.X[0],actor.Y[0],range)
        end

        -- Interrupt processing for now
        return true
      end,
      [SKILL_OBJECT_CMD] = function(msg)
        -- Check if a skill is usable now
        if RAIL.Self.SkillState:Get() == RAIL.Self.SkillState.Enum.READY then
          -- Get the skill and actor from msg
          local skill_obj = msg[2]
          local actor = Actors[msg[3]]

          -- Ensure the actor hasn't timed out or died
          if not actor.Active then
            return false
          end

          -- Check if we're in range to use the skill
          local srange = skill_obj:GetRange()
          if RAIL.Self:DistanceTo(actor) <= srange then
            -- Set the skill target
            -- Note: Even without enough SP, we want this to block the skill
            --       targeting AI
            SetSkill{ skill_obj, actor }
          else
            -- Chase the target
            ChaseTo(actor.X[0],actor.Y[0],srange)
          end
        end

        -- Don't continue processing
        return true
      end,
      [SKILL_AREA_CMD] = function(msg)
        -- Check if a skill is usable now
        if RAIL.Self.SkillState:Get() == RAIL.Self.SkillState.Enum.READY then
          -- Gather information about the skill command
          local x,y = msg[3],msg[4]
          local skill_obj = msg[2]
          local srange = skill_obj:GetRange()

          -- Check if the target is within range
          if RAIL.Self:DistanceTo(x,y) < srange then
            -- Set the skill target
            -- Note: Even without enough SP, we want this to block the skill
            --       targeting AI
            SetSkill{ msg[2], msg[3], msg[4] }
          else
            -- Move closer
            ChaseTo(x,y,srange)
          end
        end

        -- Stop processing commands
        return true
      end,
      [SKILL_WAIT_CMD] = function(msg)
        -- Set the skill target
        RAIL.Target.Skill = msg[2]

        -- Stop command processing until the skill callbacks remove this
        return true
      end,
  }

  RAIL.Event["AI CYCLE"]:Register(910,                -- Priority
                                  "Execute commands", -- Handler name
                                  -1,                 -- Max runs (negative means infinite)
                                  function()          -- Handler function
    -- Loop as long as there are commands to process (or a command
    -- signals to break)
    while RAIL.Cmd.Queue:Size() > 0 do
      -- Get the first command
      local msg = RAIL.Cmd.Queue[RAIL.Cmd.Queue.first]

      -- Get a function to process it
      local f = RAIL.Cmd.Evaluate[msg[1]]

      -- Process the command
      if type(f) == "function" then
        -- Call the function and determine if we should stop processing
        -- queued commands
        if f(msg) then
          -- Stop processing queued commands
          break
        end
      else
        -- Log the unknown message
        UnknownMessage(false,msg,"evaluate")
      end

      -- Remove the message and continue processing
      RAIL.Cmd.Queue:PopLeft()
    end
  end)
end

-- Advanced movement commands
do
  RAIL.AdvMove = {}

  local function false_ret()
    return false
  end
  local default_ret = { false_ret, false_ret }
  local x_mt = {
    __index = function(self,idx)
      -- Ensure the idx is a number
      if type(idx) ~= "number" then
        return nil
      end

      -- Return the default command table
      return default_ret
    end,
  }

  setmetatable(RAIL.AdvMove,{
    __index = function(self,idx)
      -- Ensure the idx is a number
      if type(idx) ~= "number" then
        return nil
      end

      -- Generate a new item for the X index
      rawset(self,idx,{})
      setmetatable(self[idx],x_mt)

      return self[idx]
    end,
    __newindex = function(self,idx,val)
      -- Don't allow new indexes to be created
    end,
    __call = function(self,shift,x,y)
      -- Find the closest actor to the location
      local closest,x_delt,y_delt,blocks
      do
        for id,actor in RAIL.ActorLists.All do
          local b = actor:BlocksTo(x,y)
          local x_d = x - actor.X[0]
          local y_d = y - actor.Y[0]

          if
            (not blocks or b < blocks) and
            self[x_d][y_d][2](shift,actor)
          then
            closest = actor
            x_delt = x_d
            y_delt = y_d
            blocks = b
          end
        end
      end

      -- If there are no actors at all, do nothing
      if not closest then
        return false
      end

      -- Call the relevant function
      return self[x_delt][y_delt][1](shift,closest)
    end,
  })


  -- Under-target attack
  RAIL.AdvMove[0][0] = {
    -- First function is the command to use
    function(shift,target)
      -- Process the attack object command
      RAIL.Cmd.ProcessInput(shift,{ATTACK_OBJECT_CMD,target.ID})

      -- Return true, because we've used an advanced command
      return true
    end,

    -- Second function is a check to see if a target actor is eligible
    function(shift,target)
      -- This command is only usable against enemies
      if target:IsEnemy() then
        return true
      end

      return false
    end,
  }

  -- 1-tile left of a target: delete friend
  RAIL.AdvMove[-1][0] = {
    function(shift,target)
      -- Check if the target is our owner
      if target == RAIL.Owner then
        -- TODO: Remove all players on screen from friend list.
        return true
      end

      -- Log it
      RAIL.LogT(1,"{1} removed from friend list.",target)

      -- Remove it from friend list
      target:SetFriend(false)

      -- Intercept movement command; advanced command accepted
      return true
    end,
    function(shift,target)
      -- Non-players aren't allowed
      if target.ActorType ~= "Player" then
        return false
      end

      -- Non-friends can't be removed
      if not target:IsFriend(true) then
        return false
      end

      return true
    end,
  }

  -- 1-tile right of a target: add friend
  RAIL.AdvMove[1][0] = {
    function(shift,target)
      -- Check if the target is our owner
      if target == RAIL.Owner then
        -- TODO: Set all players on screen as friend.
        return true
      end

      -- Log it
      RAIL.LogT(1,"{1} marked as friend.",target)

      -- Set the target as a friend
      target:SetFriend(true)

      -- Return true, to indicate that we used an advanced movement command
      return true
    end,
    function(shift,target)
      -- Non-players aren't allowed
      if target.ActorType ~= "Player" then
        return false
      end

      -- Friends can't be added again
      if target:IsFriend(true) then
        return false
      end

      return true
    end,
  }
end
