-- Mob ID Support
do
  -- Mob ID State-Options
  RAIL.Validate.MobIDFile = {"string","./AI/USER_AI/Mob_ID.lua"}

  --  Note: Possible MobIDMode values are set in the RAIL.MobID.Init function
  RAIL.Validate.MobIDMode = {"string","automatic"}

  -- Private data key
  local key = {}

  GetType = {
    -- Modes take the form of:
    --  [1] -> boolean; load MobID table at start
    --  [2] -> function to get monster type from ID
    [true] = {
      ["disabled"] = {
        false,
        function(self,id)
          -- Just return the type
          return GetV(self[key].SaneGetType,id)
        end,
      },
      ["automatic"] = {
        false,
        function(self,id)
          if RAIL.Other == RAIL.Self or RAIL.Other == nil then
            -- If not paired with another RAIL, don't use Mob ID
            return GetType[true].disabled[2](self,id)
          end

          -- Otherwise, use "overwrite"
          return GetType[true].overwrite[2](self,id)
        end,
      },
      ["update"] = {
        true,
        function(self,id)
          -- After the first init, works exactly like "overwrite"
          return GetType[true].overwrite[2](self,id)
        end,
      },
      ["overwrite"] = {
        false,
        function(self,id)
          -- Get the type from disabled
          local type = GetType[true].disabled[2](self,id)

          -- Check for change
          if type ~= self[key].Map[id] then
            -- Force an update
            self[key].ForceUpdate = true
          end

          -- Store it in the MobID table
          self[key].Map[id] = type

          -- Return the type
          return type
        end,
      },
    },
    [false] = {
      ["disabled"] = {
        false,
        function(self,id)
          return -2
        end,
      },
      ["automatic"] = {
        false,
        function(self,id)
          if RAIL.Other == RAIL.Self or RAIL.Other == nil then
            -- If not paired with another RAIL, don't use Mob ID
            return GetType[false].disabled[2](self,id)
          end

          -- Otherwise, use "active"
          return GetType[false].active[2](self,id)
        end,
      },
      ["once"] = {
        true,
        function(self,id)
          -- Return the Type ID if known, or disabled value
          return self[key].Map[id] or GetType[false].disabled[2](self,id)
        end,
      },
      ["active"] = {
        false,
        function(self,id)
          local type = self[key].Map[id]

          if type == nil then
            -- Force an update
            self[key].ForceUpdate = true

            -- Get from disabled
            type = GetType[false].disabled[2](self,id)
          end

          return type
        end,
      },
    },
  }
  local GetType_mt = {
    __call = function(self,self2,id)
      return self[RAIL.State.MobIDMode][2](self2,id)
    end,
  }
  setmetatable(GetType[true],GetType_mt)
  setmetatable(GetType[false],GetType_mt)

  local Update = {
    -- Valid; save types
    [true] = function(self)
      -- Create a simply serialized string (no need for full serialization)
      local buf = StringBuffer.New()
        :Append("MobID = {}\n")
      for key,value in self[key].Map do
        buf:Append("MobID["):Append(key):Append("] = "):Append(value):Append("\n")
      end

      -- Save the state to a file
      local file = io.open(RAIL.State.MobIDFile,"w")
      if file ~= nil then
        file:write(buf:Get())
        file:close()

        RAIL.LogT(55,"MobID table saved to \"{1}\".",RAIL.State.MobIDFile)
      end
    end,
    -- Invalid; load types
    [false] = function(self)
      -- Try to load the MobID file into a function
      local f,err = RAIL.ploadfile(RAIL.State.MobIDFile)
  
      if not f then
        RAIL.LogT(55,"Failed to load MobID file \"{1}\": {2}",RAIL.State.MobIDFile,err)
        return
      end
  
      -- Protect RAIL from any unwanted code
      local env = ProtectedEnvironment()
      setfenv(f,env)
  
      -- Run the MobID function
      f()
  
      -- Check for the creation of a MobID table
      if type(env.MobID) ~= "table" then
        RAIL.LogT(55,"File \"{1}\" failed to load MobID table.",RAIL.State.MobIDFile)
        return
      end
  
      -- Log it
      RAIL.LogT(55,"MobID table loaded from \"{1}\".",RAIL.State.MobIDFile)

      -- Set it to our Map table
      self[key].Map = env.MobID
    end,
  }

  -- Setup RAIL's Mob ID table
  RAIL.MobID = {
    [key] = {
      Update = nil,   -- function; set later
      GetType = nil,    -- function; set later
      SaneGetType = nil,  -- number; set later
      ForceUpdate = false,
      Map = {}    -- table; map of ID->type
    },
  }
  setmetatable(RAIL.MobID,{
    __index = function(self,id)
      -- Make sure we're initialized
      if not self[key].GetType then
        return -1
      end

      -- Return the type
      return self[key].GetType(self,id)
    end,
  })

  local TypeNums = {
    V_HOMUNTYPE,
    -- never sane: V_MERTYPE,
  }

  RAIL.Event["AI CYCLE"]:Register(-46,              -- Priority
                                  "MobID Init",   -- Handler name
                                  1,              -- Max runs
                                  function()      -- Function handler
    local self = RAIL.MobID
  
    -- Check for a sane GetType
    for i,V_ in TypeNums do
      if GetV(V_,RAIL.Owner.ID) ~= nil then
        self[key].SaneGetType = V_
        break
      end
    end
  
    -- Set valid options (and handlers) for MobIDMode
    local types = GetType[self[key].SaneGetType ~= nil]
    RAIL.Validate.MobIDMode[3] = types
    self[key].GetType = types
  
    -- Set the update function
    self[key].Update = Update[self[key].SaneGetType ~= nil]
  
    -- Check if the mode is set to load table on startup
    if types[RAIL.State.MobIDMode][1] then
      self[key].Update(self)
    end
  
    -- Setup a timeout to load/save the MobID file at regular intervals
    -- Note: RAIL._G.debug only appears in lua.exe, not in ragexe.exe
    if not RAIL._G.debug then
      self[key].Timeout = RAIL.Timeouts:New(250,true,function(self)
        -- Check if an update is forced
        if not self[key].ForceUpdate then
          return
        end
  
        -- Unset ForceUpdate
        self[key].ForceUpdate = false

        -- Run the update function
        return self[key].Update(self)
      end,self)
    end
  end)
  
end
