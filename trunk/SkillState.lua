------------------------
-- Validation Options --
------------------------

if not RAIL.Validate.SkillOptions then
  RAIL.Validate.SkillOptions = {is_subtable = true}
end

RAIL.Validate.SkillOptions.RampageMode = {"boolean",false}
RAIL.Validate.SkillOptions.Timeout = {"number",1000,0,nil,
  unsaved = true,
}

-- Skill state tracking
do
  ----------------
  -- State Base --
  ----------------

  -- Private key
  local key = {}

  -- Equality function, to compare skill states
  local function GetValue(obj)
    if obj[key].Value ~= nil then
      return obj[key].Value
    end
    
    return obj[key].State[key].Value
  end
  local function __eq(left,right)
    -- Check if the values are the same
    return GetValue(left) == GetValue(right)
  end

  -- Metatable for values
  local value_mt = {
    __eq = function(left,right) return GetValue(left) == GetValue(right) end,
    __lt = function(left,right) return GetValue(left) <  GetValue(right) end,
    __le = function(left,right) return GetValue(left) <= GetValue(right) end,
    __tostring = function(self)
      return self[key].Name .. " (" .. self[key].Value .. ")"
    end,
  }

  -- Build skill state values
  local enum = setmetatable({},{
    __newindex = function(self,idx,val)
      -- Create the object
      rawset(self,idx,{ [key] = { Value = val, Name = idx, }, })

      -- Set the value metatable
      setmetatable(self[idx],value_mt)
    end,
  })

  -- Skill states
  -- NOTE: Equal numbers will evaluate as equal (due to metatable), but will
  --       be separate objects which allows us to split logic while
  --       maintaining a simplified API
  enum.READY        = 0   -- Ready to use a skill
  enum.CASTING_ACK  = 1   -- Waiting for cast time to start
  enum.CASTING      = 1   -- Waiting for cast time to finish
  enum.CASTING_UNK  = 1   -- Waiting for cast time of unknown skill
  enum.DELAY_ACK    = 2   -- Waiting for server to acknowledge skill
  enum.DELAY        = 2   -- Waiting for cast delay to finish

  -- Skill state object
  local SkillState = {}
  
  -- Set the metatable
  setmetatable(SkillState,{
    -- Values not found in this table should check the enumeration
    __index = enum,

    -- Use the exact same comparison functions as the enum values; otherwise
    -- Lua will ignore these metatable events
    __eq = value_mt.__eq,
    __lt = value_mt.__lt,
    __le = value_mt.__le,
  })

  -- Setup the base private table
  SkillState[key] = {
    Actor = nil,                      -- set later
    State = enum.READY,               -- default to ready
    Ticks = { [enum.READY] = 0, },    -- start times of each state
    Callbacks = {},
  }
  
  -- Return the time of last successful cast
  SkillState.CompletedTime = function(self)
    return self[key].Ticks[enum.READY]
  end
  
  -- Get function is simple
  SkillState.Get = function(self)
    return self[key].State
  end
  
  -- Set function contains a table of functions to call when state changes
  SkillState.Set = {}
  setmetatable(SkillState.Set,{
    __call = function(self,state_obj,new_state,ticks,...)
      -- Get the previous state (before calling Set())
      local old_state = state_obj[key].State

      -- If they're the same, do nothing
      if rawequal(old_state,new_state) then
        return
      end
      
      -- Ticks is the amount of time spent in this state before
      -- Set() was called
      ticks = ticks or 0

      -- Set the skill state
      state_obj[key].State = new_state

      -- Set the time that this state began
      state_obj[key].Ticks[new_state] = GetTick() - ticks

      -- Check if there is a handler for shifting into a new state
      if self[new_state] then
        -- Call the handler and pass the parent and previous state
        self[new_state](state_obj,old_state,ticks,unpack(arg))
      end
    end,
  })
  
  -- Update function base
  SkillState.Update = {}
  setmetatable(SkillState.Update,{
    __call = function(self,state_obj)
      -- Loop until a function tells not to
      local continue
      repeat
        local state = state_obj[key].State
        local ticks = GetTick() - state_obj[key].Ticks[state]
        continue = self[state](state_obj,ticks)
      until not continue
    end,
  })

  -- WaitFor function
  SkillState.WaitFor = function(self,skill,...)
    -- Check if we're overwriting a skill
    -- NOTE: This should only happen in Rampage mode
    if self ~= enum.READY then
      -- If not in DELAY state, fire the failure callbacks
      if self ~= enum.DELAY then
        -- Fire failure callbacks
        self.Callbacks:Fire(false,                                          -- Failure
                            GetTick() - self[key].Ticks[self[key].State],   -- Time since failure
                            self[key].Skill,                                -- Used skill
                            unpack(self[key].Target))                       -- Skill target
      end

      -- Reset any callbacks on the old skill
      self.Callbacks:Reset(skill)
    end

    -- Determine which state to transition into
    local state
    if skill.CastTime ~= 0 then
      -- Casting time, transition to CASTING_ACK
      state = enum.CASTING_ACK
    else
      -- Check if "Rampage Mode" is enabled
      if RAIL.State.SkillOptions.RampageMode then
        -- Assume the skill is successful and transition to DELAY
        state = enum.DELAY
      else
        -- Transition to DELAY_ACK and wait for server acknowledgement
        state = enum.DELAY_ACK
      end
    end
    
    -- Set the skill and target that's being tracked
    self[key].Skill = skill
    self[key].Target = arg
    
    -- Set the time when this skill cast began
    self[key].Ticks.Begin = GetTick()
    
    -- Set the timeout
    self[key].Timeout = RAIL.State.SkillOptions.Timeout

    -- Transition to the state
    self:Set(state,0)
  end
  
  -------------------
  -- Callback Base --
  -------------------
  
  SkillState.Callbacks = {
    -- When destroying SkillState, unset [key] so that it can be garbage
    -- collected.
    [key] = SkillState,
    Add = function(self,skill,success,failure,persistent)
      -- Get the table of callbacks
      local cb = self[key][key].Callbacks
      
      -- Ensure there's a table for this skill
      if not cb[skill.ID] then
        cb[skill.ID] = {
          [true]  = Table.New(),    -- success
          [false] = Table.New(),    -- failure
        }
      end

      -- Get the table for this skill
      cb = cb[skill.ID]

      -- Add the callbacks
      if success then
        cb[true]:Append{success,persistent}
      end
      if failure then
        cb[false]:Append{failure,persistent}
      end
    end,
    Fire = function(self,succeeded,ticks,skill,...)
      -- Get the table of callbacks
      local cb = self[key][key].Callbacks[skill.ID]

      -- Ensure there are callbacks for this skill
      if not cb then return end
      
      -- Get the success/failure group
      cb = cb[succeeded]

      -- Loop through and call each function
      for i=1,cb:GetN() do
        cb[i][1](ticks,skill,unpack(arg))
      end
    end,
  }
  
  -- Reset function
  do
    -- Helper function to remove non-persistent callbacks
    local function RemoveNonPersistent(t)
      local i=1
      while i < t:GetN() do
        -- Check if the item is persistent
        if t[i][2] then
          -- Increment i because the item is persistent
          i = i + 1
        else
          -- Remove the item
          t:Remove(i)
        end
      end
    end

    SkillState.Callbacks.Reset = function(self,skill)
      -- If no skill is supplied, loop through all skills
      if not skill then
        for id,t in pairs(self[key][key].Callbacks) do
          -- Call reset with a pseudo skill table that only contains ID
          self:Reset{ID = id,}
        end
        return
      end

      -- Get the table of callbacks
      local cb = self[key][key].Callbacks[skill.ID]

      -- Ensure there are callbacks for this skill
      if not cb then return end

      -- Remove from both success callbacks and failure callbacks
      RemoveNonPersistent(cb[true])
      RemoveNonPersistent(cb[false])
    end
  end

  ------------------
  -- State: READY --
  ------------------

  -- Transition to READY
  SkillState.Set[enum.READY] = function(state_obj,old_state,ticks,reason)
    -- If transitioning from a known success, do nothing
    if rawequal(old_state,enum.DELAY) then return end

    -- If transitioning from an unknown cast, we can't know... do nothing
    if rawequal(old_state,enum.CASTING_UNK) then return end

    -- Get the skill
    local skill = state_obj[key].Skill

    -- Log
    RAIL.LogT(60,
              "Cast of {1} failed after {2}ms; reason = {3}.",
              skill,
              GetTick() - state_obj[key].Ticks.Begin,
              reason)

    -- Fire failure callbacks
    state_obj.Callbacks:Fire(false,                           -- Failure
                             ticks,                           -- Time since failure
                             skill,                           -- Used skill
                             unpack(state_obj[key].Target))   -- Skill target

    -- Reset non-persistent callbacks on this skill
    state_obj.Callbacks:Reset(skill)
    
    -- Reset the completed time
    state_obj[key].Ticks[enum.READY] = 0
  end

  -- Check for skill start
  SkillState.Update[enum.READY] = function(parent_obj,ticks_in_state)
    -- Check for casting motion and properly handle it
    --  (timed-out cast started after lag? user casted a non-targeted skill?)
    if parent_obj[key].Actor.Motion[0] == MOTION_CASTING then
      -- Set the state to CASTING_UNK
      parent_obj:Set(enum.CASTING_UNK)

      -- Continue evaluating update functions
      return true
    end
  end

  ------------------------
  -- State: CASTING_ACK --
  ------------------------

  do
    -- Helper function to check for casting motion
    local function casting_f(v) return v == MOTION_CASTING end

    -- Check for server acknowledgement
    SkillState.Update[enum.CASTING_ACK] = function(state_obj,ticks_in_state)
      -- Find the most recent casting time
      local most_recent = History.FindMostRecent(state_obj[key].Actor.Motion,   -- History table
                                                 casting_f,                     -- Match function
                                                 nil,                           -- Latest (closest to present; in this case any)
                                                 ticks_in_state)                -- Earliest (farthest from present)

      -- Check if a recent casting action was found
      if most_recent ~= nil then
        -- Change state to CASTING
        state_obj:Set(enum.CASTING,most_recent)

        -- Continue processing update functions
        return true
      end

      -- Check if the skill timed out
      if ticks_in_state >= state_obj[key].Timeout then
        -- Failed, return to ready state
        state_obj:Set(enum.READY,ticks_in_state,"timeout")
      end
    end
  end

  --------------------
  -- State: CASTING --
  --------------------

  do
    -- Helper function to check for casting motion
    local function not_casting_f(v) return v ~= MOTION_CASTING end

    -- Check that we're still casting
    SkillState.Update[enum.CASTING] = function(state_obj,ticks_in_state)
      -- Get the actor
      local actor = state_obj[key].Actor

      -- Find the most recent non-casting item
      local most_recent = History.FindMostRecent(actor.Motion,      -- History table
                                                 not_casting_f,     -- Match function
                                                 nil,               -- Anything recent works, no latest cap
                                                 ticks_in_state)    -- Anything newer than ticks_in_state; earliest cap
      
      -- If we're still casting, keep waiting
      if most_recent == nil then return end
      
      -- Check the motion when casting stopped
      local motion = actor.Motion[most_recent]
      
      -- Check if the skill completed
      if motion == MOTION_SKILL then
        -- Transition to skill delay
        state_obj:Set(enum.DELAY,most_recent)
        
        -- Continue processing skill state update functions
        return true
      end
      
      -- Check for SP usage; homunculi don't show MOTION_SKILL
      local sp_delta = actor.SP[0] - actor.SP[ticks_in_state]
      if sp_delta < 0 then
        -- Transition to DELAY_ACK, and reuse code for SP check
        state_obj:Set(enum.DELAY_ACK,ticks_in_state)

        -- Continue processing skill state update functions
        return true
      end
      
      -- TODO: Check for uninterruptable skills

      -- Set state to READY since the skill was interrupted or failed
      state_obj:Set(enum.READY,ticks_in_state,"cast interrupted or failed")
    end
  end

  ------------------------
  -- State: CASTING_UNK --
  ------------------------

  -- When skill state gets set to CASTING_UNK, log it
  SkillState.Set[enum.CASTING_UNK] = function(state_obj)
    -- Log
    RAIL.LogT(60,"Cast of unknown skill started.")
  end

  -- Check for the unknown skill to finish
  SkillState.Update[enum.CASTING_UNK] = function(state_obj,ticks_in_state)
    -- Check if the motion isn't CASTING anymore
    if state_obj[key].Actor.Motion[0] ~= MOTION_CASTING then
      -- Transition to READY
      state_obj:Set(enum.READY,0)
    end
  end

  ----------------------
  -- State: DELAY_ACK --
  ----------------------

  do
    local function skill_f(v) return v == MOTION_SKILL end

    -- Check for server acknowledgement of skill without cast time
    SkillState.Update[enum.DELAY_ACK] = function(state_obj,ticks_in_state)
      local actor = state_obj[key].Actor

      -- Find the most recent MOTION_SKILL
      local most_recent = History.FindMostRecent(actor.Motion,
                                                 skill_f,
                                                 nil,
                                                 ticks_in_state)

      -- Check if a most-recent skill usage was found
      if most_recent ~= nil then
        -- Transition to DELAY
        state_obj:Set(enum.DELAY,most_recent)

        -- Continue processing state updates
        return true
      end

      -- Check if SP has been used
      local sp_delta = actor.SP[0] - actor.SP[ticks_in_state]
      if sp_delta < 0 then
        -- Make sp_delta positive for easier comparison of SP costs
        sp_delta = -sp_delta

        -- Get the original skill
        local orig_skill = state_obj[key].Skill

        -- Check if a different level has possibly been used
        if orig_skill.SPCost ~= sp_delta then
          -- Get the skill object from AllSkills (so level is selectable)
          local skill = AllSkills[orig_skill.ID]

          -- Look for another level
          local level = skill.Level
          while level > 1 do
            if skill[level] and sp_delta >= skill[level].SPCost then
              break
            end

            level = level - 1
          end
          
          -- Check if the level is different
          if level ~= orig_skill.Level then
            RAIL.LogT(60,
                      "Cast of {1} seems to have used level {2}; SP used = {3}.",
                      orig_skill,
                      level,
                      sp_delta)
            
            -- Replace the skill, so delay/duration time will be more accurate
            state_obj[key].Skill = skill[level]
          end
        end
        
        -- Transition to DELAY
        -- NOTE: Use half of ticks_in_state as an estimation of when the skill
        --       was used
        state_obj:Set(enum.DELAY,RoundNumber(ticks_in_state / 2))
      end

      -- Check for timeout
      if ticks_in_state >= state_obj[key].Timeout then
        -- Transition to READY
        state_obj:Set(enum.READY,ticks_in_state,"timeout")
      end
    end
  end

  ------------------
  -- State: DELAY --
  ------------------

  -- When skill state gets set to DELAY, skill cast succeeded
  SkillState.Set[enum.DELAY] = function(state_obj,old_state,ticks)
    -- Get the skill
    local skill = state_obj[key].Skill

    -- Log
    RAIL.LogT(60,
              "Cast of {1} succeeded after {2}ms.",
              skill,
              GetTick() - state_obj[key].Ticks.Begin)

    -- Fire success callbacks
    state_obj.Callbacks:Fire(true,                          -- Success
                             ticks,                         -- Time since success
                             skill,                         -- Used skill
                             unpack(state_obj[key].Target)) -- Skill target

    -- Reset non-persistent callbacks on this skill
    state_obj.Callbacks:Reset(skill)
  end
  
  -- Wait for cast delay
  SkillState.Update[enum.DELAY] = function(state_obj,ticks_in_state)
    -- Get the after-cast delay of the skill
    local delay = state_obj[key].Skill.CastDelay
    -- Check if enough time has passed
    if ticks_in_state >= delay then
      -- Transition to ready state
      state_obj:Set(enum.READY,ticks_in_state - delay)
    end
  end

  ------------
  -- Events --
  ------------

  -- Insert a function to instantiate SkillState object
  RAIL.Event["AI CYCLE"]:Register(-40,                  -- Priority
                                  "Skill State Init",   -- Handler name
                                  1,                    -- Max runs
                                  function(self,id)     -- Handler function
    -- Set the actor
    SkillState[key].Actor = RAIL.Self

    -- Make the object public at RAIL.SkillState
    RAIL.SkillState = SkillState
  end)

  RAIL.Event["AI CYCLE"]:Register(10,                   -- Priority
                                  "Skill State Update", -- Handler name
                                  -1,                   -- Max runs (infinite)
                                  function(self,id)     -- Handler function
    RAIL.SkillState:Update()
  end)
end
