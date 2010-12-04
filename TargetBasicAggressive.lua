-- Standard aggressive switch; this is toggled by <alt+t> and <ctrl+t>
RAIL.Validate.Aggressive = {"boolean",false}

-- Create the base validation table for AutoPassive options
RAIL.Validate.AutoPassive = {is_subtable = true}

-- Setup the base call structure for IsAggressive
do
  -- Use a table
  RAIL.IsAggressive = Table.New()

  -- Redo the metatable
  setmetatable(RAIL.IsAggressive,{
    -- Maintain the index property
    __index = getmetatable(RAIL.IsAggressive).__index,
    
    -- Add a call method
    __call = function(self)
      -- Loop through each function
      for i=1,self:GetN() do
        -- If the return value is a direct "false", then IsAggressive()
        -- should return false as well.
        if self[i]() == false then
          return false
        end
      end

      -- Otherwise, assume aggressive mode
      return true
    end,
  })
  
  -- Non-aggressive means always non-aggressive
  RAIL.IsAggressive:Append(function()
    if not RAIL.State.Aggressive then
      return false
    end
  end)
end

-- Programmatically generate checks for AutoPassive based on numeric values
do
  local function Generate(name,history,get_max,...)
    -- Generate the keys
    local enabled = name .. "Enabled"
    local enter   = name .. "Enter"
    local exit    = name .. "Exit"
    local percent = name .. "isPercent"

    -- Generate the validation options
    do
      local ap = RAIL.Validate.AutoPassive

      -- Option to enable/disable AutoPassive for this option (hidden)
      ap[enabled] = {"boolean",true,unsaved = true}
  
      -- Option to begin auto-passive mode
      ap[enter] = setmetatable({"number",0,0},{
        __index = function(self,idx)
          -- If using percentages, then maximum should be 99
          if idx == 4 and RAIL.State.AutoPassive[percent] then
            return 99
          end
        end,
      })
      
      -- Option to end auto-passive mode
      ap[exit] = setmetatable({"number"},{
        __index = function(self,idx)
          -- Default and minimum should be 1 above the enter number
          if idx == 2 or idx == 3 then
            return RAIL.State.AutoPassive[enter] + 1
          end
          
          -- Maximum should be 100 if using percents
          if idx == 4 and RAIL.State.AutoPassive[percent] then
            return 100
          end
        end,
      })
      
      -- Option to specify whether using percents
      ap[percent] = {"boolean",false}
    end

    -- The state of this check; true = AutoPassive should be enabled
    local auto_passive = false

    -- Generate a check for this
    RAIL.Event["TARGET SELECT/PRE"]:Register(50,                              -- Priority
                                             "AutoPassive Check: " .. name,   -- Handler name
                                             -1,                              -- Max runs (infinite)
                                             function(self)
      -- Get the value of the history value now
      local value = history[0]
      
      -- Check if the values are in percentages
      local value_suffix = ""
      if RAIL.State.AutoPassive[percent] then
        -- Set the value
        value = math.floor(value / get_max(unpack(arg)) * 100)

        -- Set the value suffix to the percentage sign
        value_suffix = "%"
      end

      -- Determine what to do based on the current state
      if not auto_passive then
        -- Check if it is time to exit AutoPassive mode for this option
        local enter_val = RAIL.State.AutoPassive[enter]
        if value < enter_val then
          RAIL.LogT(10,
                    "Temporarily entering passive mode due to {1} below threshold; value={2}{4}, threshold={3}{4}.",
                    name,
                    value,
                    enter_val,
                    value_suffix)
          auto_passive = true
        end
      else
        -- Check if it is time to exit AutoPassive mode for this option
        local exit_val = RAIL.State.AutoPassive[exit]
        if value >= exit_val then
          RAIL.LogT(10,
                    "Disabling temporary passive mode due to {1} above threshold; value={2}{4}, threshold={3}{4}.",
                    name,
                    value,
                    exit_val,
                    value_suffix)
          auto_passive = false
        end
      end
    end)

    -- Generate a function for the IsAggressive table of functions
    RAIL.IsAggressive:Append(function()
      -- Check enabled
      if not RAIL.State.AutoPassive[enabled] then
        -- Just continue on
        return
      end

      -- Return based on the state of this check
      if auto_passive == true then
        return false
      end
    end)
  end

  RAIL.Event["AI CYCLE"]:Register(-5,
                                  "AutoPassive check generation",
                                  1,
                                  function()
    Generate("HP",RAIL.Self.HP,RAIL.Self.GetMaxHP,RAIL.Self)
    Generate("SP",RAIL.Self.SP,RAIL.Self.GetMaxSP,RAIL.Self)
    Generate("OwnerHP",RAIL.Owner.HP,RAIL.Owner.GetMaxSP,RAIL.Owner)
    Generate("OwnerSP",RAIL.Owner.SP,RAIL.Owner.GetMaxSP,RAIL.Owner)
  end)
end
