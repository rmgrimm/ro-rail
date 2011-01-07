-- Loadfile protection
do
  RAIL.pcall = RAIL._G.pcall
  if type(RAIL.pcall) ~= "function" then
    if type(RAIL._G.xpcall) ~= "function" then
      -- No protection possible
      RAIL.pcall = function(f,...)
        return true,f(unpack(arg))
      end
    else
      -- Protect using xpcall
      RAIL.pcall = function(f,...)
        local f_closure = function()
          return f(unpack(arg))
        end

        local err_f = function(obj)
          return obj
        end

        return xpcall(f_closure, err_f)
      end
    end
  end

  -- Protected loadfile
  RAIL.ploadfile = function(file)
    -- Run a protected call for loadfile
    local ret1,ret2,ret3 = RAIL.pcall(RAIL._G.loadfile,file)
  
    -- Check for success
    if ret1 then
      -- Succeeded
      return ret2,ret3
    else
      -- Failed
      return nil,ret2
    end
  end

  -- Protected loadstring
  RAIL.ploadstring = function(string)
    -- Run a protected call for loadstring
    local ret1,ret2,ret3 = RAIL.pcall(RAIL._G.loadstring,string)

    -- Check for success
    if ret1 then
      -- Succeeded
      return ret2,ret3
    else
      -- Failed
      return nil,ret2
    end
  end
end

-- State protection
do
  ProtectedEnvironment = function()
    -- Create a table for the environment
    local env = {
      -- Environment
      _VERSION = RAIL._G._VERSION,
      getfenv = RAIL._G.getfenv,
      setfenv = RAIL._G.setfenv,

      -- Memory
      collectgarbage = RAIL._G.collectgarbage,
      gcinfo = RAIL._G.gcinfo,
      newproxy = RAIL._G.newproxy,

      -- Misc Lua API
      tostring = RAIL._G.tostring,
      type = RAIL._G.type,
      unpack = RAIL._G.unpack,

      pcall = RAIL._G.pcall,
      xpcall = RAIL._G.xpcall,

      -- The ^ operator function
      __pow = RAIL._G.__pow,

      -- Lua loading
      _LOADED = {},
      loadfile = RAIL.ploadfile,
      loadstring = RAIL.ploadstring,
      require = nil,  -- function created later

      -- Lua modules
      os = {},  -- proxy metatable set later
      string = {},  -- proxy metatable set later

      -- Ragnarok API
      TraceAI = RAIL._G.TraceAI,
      MoveToOwner = RAIL._G.MoveToOwner,
      Move = RAIL._G.Move,
      Attack = RAIL._G.Attack,
      GetV = RAIL._G.GetV,
      GetActors = RAIL._G.GetActors,
      GetTick = RAIL._G.GetTick,
      GetMsg = RAIL._G.GetMsg,
      GetResMsg = RAIL._G.GetResMsg,
      SkillObject = RAIL._G.SkillObject,
      SkillGround = RAIL._G.SkillGround,
      IsMonster = RAIL._G.IsMonster,
    }

    -- Create a new require function so setfenv on the original function won't result in strange behavior
    env.require = function(virt_file)
      -- Check if the file has been required before
      if _LOADED[virt_file] then
        return _LOADED[virt_file]
      end

      -- Get LUA_PATH
      local path
      if type(LUA_PATH) == "string" then
        path = LUA_PATH
      elseif type(os.getenv("LUA_PATH")) == "string" then
        path = os.getenv("LUA_PATH")
      else
        path = "?;?.lua"
      end

      -- Search each path, separated by ";"
      local f
      do
        local start = 1
        local pos
        repeat
          pos = string.find(path,";",start,true)

          -- Get the pattern used for finding the file
          local pattern
          if pos then
            pattern = string.sub(path,start,pos-1)
            start = pos+1
          else
            pattern = string.sub(path,start)
          end

          -- Replace "?" with virt_file
          local file = string.gsub(pattern,"%?",virt_file)

          -- Attempt to load the file
          local new_f,err = loadfile(file)

          if new_f ~= nil then
            f = new_f
            break
          end
        until pos == nil
      end

      if type(f) == "function" then
        -- Copy the previous value of _REQUIREDNAME
        local prev_name = _REQUIREDNAME

        -- Set _REQUIREDNAME
        _REQUIREDNAME = virt_file

        -- Set the function environment
        setfenv(f,getfenv(1))

        -- Run a protected call
        local pret = { pcall(f) }

        -- Check the return
        if pret[1] then
          _LOADED[virt_file] = pret[2]
          if _LOADED[virt_file] == nil then
            _LOADED[virt_file] = true
          end
        else
          return nil, string.format("could not load package `%s': %s", virt_file, pret[2])
        end

        -- Reset _REQUIREDNAME
        _REQUIREDNAME = prev_name

        -- Return the result of running the file
        return _LOADED[virt_file]
      end

      -- Fail safely
      return nil, string.format("could not load package `%s' from path `%s'", virt_file, path)
    end
    setfenv(env.require,env)

    -- Proxy the Lua standard library
    setmetatable(env.os,{
      __index = RAIL._G.os
    })
    setmetatable(env.string,{
      __index = RAIL._G.string
    })

    -- return the environment
    return env
  end
end

-- Config validation
do
  RAIL.Validate = {
    -- Name = {type, default, numerical min, numerical max }
    -- Subtable = {is_subtable = true}
  }

  local types = {
    ["function"] = function(data,validate)
      local t = type(data)
      local pregenerated = false

      -- If it's a function return it
      if t == "function" then
        return data
      end

      -- If it's not a string, return the default
      if t ~= "string" then
        return validate[2]
      end

      -- Check if the function is base64 encoded
      if string.sub(data,1,7) == "base64:" then
        -- Decode it
        data = RAIL.Base64:Decode(string.sub(data,8))
        pregenerated = true
      end

      -- Attempt to convert it to a function
      data = RAIL.ploadstring(data)

      -- Check if its nil
      if data == nil then
        -- Return default
        return validate[2]
      end

      -- Check if we need to generate a function
      if not pregenerated then
        data = data()

        -- And again check sanity
        if type(data) ~= "function" then
          return validate[2]
        end
      end

      return data
    end,
    number = function(data,validate)
      -- Check that the data is a number
      if type(data) ~= "number" then
        -- Not a number, so use default instead
        return validate[2]
      end

      -- Check if there's an exceptions table, and this value is in it
      if type(validate[5]) == "table" and validate[5][data] then
        -- It's acceptable
        return data
      end

      -- Validate that the number is greater or equal to the minimum
      if validate[3] and data < validate[3] then
        -- Below the minimum, so return minimum instead
        return validate[3]
      end

      -- Validate that the number is less or equal to the maximum
      if validate[4] and data > validate[4] then
        -- Above the maximum, so return maximum instead
        return validate[4]
      end

      -- Return the number, it's in range
      return data
    end,
    table = function(data,validate)
      if type(data) ~= "table" then
        return {}
      end

      return data
    end,
    string = function(data,validate)
      -- Check that it's a string
      if type(data) ~= "string" then
        return validate[2]
      end

      -- Check if there's a table of possible values
      if type(validate[3]) == "table" then
        -- Convert the string to lower case
        data = string.lower(data)

        -- Check if the string (in lower case) is in the accepted values table
        if validate[3][data] == nil then
          -- Return default
          return validate[2]
        end
      end

      -- Data is fine
      return data
    end,
    default = function(data,validate)
      if type(data) ~= validate[1] then
        return validate[2]
      end

      return data
    end,
  }
  setmetatable(types,{
    __index = function(t,key)
      return t.default
    end,
  })

  setmetatable(RAIL.Validate,{
    __call = function(self,data,validate)
      -- Verify the validation info
      if type(validate) ~= "table" or (validate[1] == nil and validate.is_subtable == nil) then
        -- Validation impossible
        return data
      end

      -- Use specialized functions to verify data
      if validate.is_subtable then
        return types.table(data,validate)
      else
        return types[validate[1]](data,validate)
      end
    end,
  })
end

-- State persistence
do
  -- Is data "dirty" ?
  local dirty = false

  -- Filename to load/save from
  local filename

  -- Alternate filename to load from
  local alt_filename

  -- Private keys to data and validation tables
  local data_t = {}
  local unsaved_t = {}
  local vali_t = {}
  local unsaved_tree = {}

  -- Metatable (built after ProxyTable)
  local metatable = {}

  -- Proxy tables to track "dirty"ness
  local ProxyTable = function(d,v)
    local ret = {
      [data_t] = d,
      [unsaved_t] = {},
      [vali_t] = v,
    }

    setmetatable(ret,metatable)

    return ret
  end

  -- Metatable
  metatable.__index = function(t,key)
    -- Get the data from proxied table
    local data_table = rawget(t,data_t)
    local unsaved_table = rawget(t,unsaved_t)

    local data = unsaved_table[key]
    if data == nil then
      data = data_table[key]
    end

    -- Get the validation information
    local valid = rawget(t,vali_t)
    if type(valid) == "table" and type(valid[key]) == "table" then
      valid = valid[key]
    else
      -- No validating for this
      return data
    end

    -- Check if it's optional
    if data == nil and valid.optional then
      return nil
    end

    -- Validate the data
    local v = RAIL.Validate(data,valid)

    -- Check if the validated data is different
    if v ~= data then
      -- Check if the data was nil and unsaved flag is set
      if data_table[key] == nil and valid.unsaved then
        t[unsaved_t][key] = v
      else
        -- Save new data, and set dirty
        t[data_t][key] = v
        dirty = true
      end
    end

    -- Check if it's a table
    if type(v) == "table" then
      -- Proxy it
      rawset(t,key,ProxyTable(v,valid))

      -- Check if it's an unsaved table
      if t[unsaved_t][key] == v or rawget(t,unsaved_tree) then
        -- Set the unsaved tree information
        rawset(t[key],unsaved_tree,{t,key})
      end

      return t[key]
    end

    -- Return validated data
    return v
  end
  metatable.__newindex = function(t,key,value)
    -- Don't do anything if the value stays the same
    if t[key] == value then
      return
    end

    -- Set dirty
    dirty = true

    -- Set the value
    t[data_t][key] = value

    -- Check if we have unsaved tree information to convert to saved
    while true do
      -- Get tree info for the current table
      local tree_info = rawget(t,unsaved_tree)

      -- Check if it doesn't exist (aka, it's not unsaved)
      if not tree_info then
        -- Stop looping
        break
      end

      -- Remove tree info from table
      rawset(t,unsaved_tree,nil)

      -- Go up a step
      t = tree_info[1]

      -- Convert to saved
      if t[unsaved_t][tree_info[2]] then
        t[data_t][tree_info[2]] = t[unsaved_t][tree_info[2]]
        t[unsaved_t][tree_info[2]] = nil
      end
    end
  end

  -- Setup RAIL.State
  RAIL.State = ProxyTable({},RAIL.Validate)

  -- Save function
  rawset(RAIL.State,"Save",function(self,forced)
    -- Only save the state if it's changed
    if not forced and not dirty then
      return
    end

    -- Unset dirty state
    dirty = false

    -- Save the state to a file
    local file = io.open(filename,"w")
    if file ~= nil then
      file:write(SerializeFull("rail_state",self[data_t]).."\n")
      file:close()
    end

    RAIL.Log(3,"Saved state to %q",filename)
  end)

  local KeepInState = { SetOwnerID = true, Load = true, Save = true, [data_t] = true, [unsaved_t] = true, [vali_t] = true }

  -- Set OwnerID function
  rawset(RAIL.State,"SetOwnerID",function(self,id)
    --local base = StringBuffer.New():Append("RAIL_State.")
    --if not RAIL.SingleStateFile then
    --  base:Append("%d.")
    --end
    --base = string.format(base:Get(),id)

    --local homu = base .. "homu.lua"
    --local merc = base .. "merc.lua"

    local base = RAIL.StateFile
    if type(base) ~= "string" then
      base = "RAIL_State.{2}.lua"
    end

    local homu = RAIL.formatT(base,id,"homu",RAIL.Version)
    local merc = RAIL.formatT(base,id,"merc",RAIL.Version)

    if RAIL.Mercenary then
      filename = merc
      alt_filename = homu
    else
      filename = homu
      alt_filename = merc
    end
  end)
  
  -- Function to copy specific parts of one state file to another
  local function CopyState(to,from)
    -- TODO: Make this automatic based on flags in RAIL.Validate subtables
    if not from.rail_state or type(from.rail_state) ~= "table" then
      return
    end

    local f_rs = from.rail_state
    to.rail_state = {}
    local t_rs = to.rail_state

    t_rs.DefendOptions = f_rs.DefendOptions     -- table
    t_rs.DebugFile = f_rs.DebugFile
    t_rs.DebugLevel = f_rs.DebugLevel
    t_rs.FollowDistance = f_rs.FollowDistance
    t_rs.IdleMovement = f_rs.IdleMovement       -- table
    t_rs.MaxDistance = f_rs.MaxDistance
    t_rs.MobIDMode = f_rs.MobIDMode
    t_rs.MobIDFile = f_rs.MobIDFile
    t_rs.ProfileMark = f_rs.ProfileMark
    t_rs.TempFriendRange = f_rs.TempFriendRange
    
    if f_rs.ActorOptions and type(f_rs.ActorOptions) == "table" then
      t_rs.ActorOptions = {
        ByID = f_rs.ActorOptions.ByID,
        ByType = f_rs.ActorOptions.ByType,
      }
    end
    
    if f_rs.AssistOptions and type(f_rs.AssistOptions) == "table" then
      t_rs.AssistOptions = {
        Owner = f_rs.AssistOptions.Owner,
        Friend = f_rs.AssistOptions.Friend,
      }
    end
  end

  -- Load function
  rawset(RAIL.State,"Load",function(self,forced)
    -- Setup an environment for homu state-file and merc state-file
    local self_env = ProtectedEnvironment()
    local alt_env = ProtectedEnvironment()

    -- Load the files into both
    local self_ret,self_err = self_env.require(filename)
    local alt_ret,alt_err = alt_env.require(alt_filename)

    -- Use self-filename as default "from_file" (for logging)
    local from_file = filename

    -- Get the other's name for logging purposes
    local alt_name = "mercenary"
    if RAIL.Mercenary then
      alt_name = "homunculus"
    end

    -- Check if self is nil, but we're forcing a load
    if not self_ret and forced then
      -- Log it
      RAIL.LogT(3,"Failed to load state from \"{1}\": {2}",filename,self_err)
      RAIL.LogT(3," --> Trying from {1}'s state file.",alt_name)

      -- Check if alt is also nil
      if not alt_ret then
        -- Log it
        RAIL.LogT(3,"Failed to load state from \"{1}\": {2}",alt_filename,alt_err)

        -- Can't load, just return
        return
      end

      -- Load from the alternate state file
      self_env = {}
      CopyState(self_env,alt_env)

      self_ret = alt_ret
      from_file = alt_filename
    end

    -- First, load alternate state, to see if we can find RAIL.Other's ID
    -- Note: No reason to search for RAIL.Other if we don't have RAIL.Owner yet
    if alt_ret and alt_env ~= self_env and RAIL.Owner then
      local f_G = alt_env

      -- Try to find the other's ID
      local id
      if
        type(f_G.rail_state) == "table" and
        type(f_G.rail_state.Information) == "table" and
        type(f_G.rail_state.Information.OwnerID) == "number" and
        f_G.rail_state.Information.OwnerID == RAIL.Owner.ID and
        type(f_G.rail_state.Information.SelfID) == "number"
      then
        id = f_G.rail_state.Information.SelfID
      end

      -- Check if we found the other's ID
      if id then
        -- Try to get it from the Actors table
        local other = rawget(Actors,id)

        -- Check if it exists, and isn't already set
        if other and other ~= RAIL.Other then
          -- Log it
          RAIL.LogT(40,"Found owner's {1} ({2}).",alt_name,other)

          -- Set it to RAIL.Other
          RAIL.Other = other

          -- Hook the expire function
          local expire = RAIL.Other.Expire
          RAIL.Other.Expire = function(self,...)
            -- Check if we're still the owner's other
            if RAIL.Other == self then
              -- Log it
              RAIL.LogT(40,"Owner's {1} expired; removing from friends.",alt_name)

              -- Unset (set to RAIL.Self)
              RAIL.Other = RAIL.Self
            end

            -- Return the expire function
            self.Expire = expire

            -- Forward the function call
            return self:Expire(unpack(arg))
          end
        end
      end
    end

    -- Load our state
    if self_ret then
      local f_G = self_env

      -- See if it left us with a workable rail_state object
      local rail_state = f_G.rail_state
      if type(rail_state) ~= "table" then
        -- Log an invalid file
        RAIL.LogT(0,"Error loading state; invalid rail_state object.")
        return
      end
  
      -- Decide if we should load this state
      if rail_state.update or forced then
        self[data_t] = rail_state
        dirty = false

        -- Log it
        RAIL.LogT(3,"Loaded state from \"{1}\".",from_file)

        -- Resave with the update flag off if we need to
        if self[data_t].update then
          self[data_t].update = false
  
          -- Save the state to a file
          local file = io.open(filename,"w")
          if file ~= nil then
            file:write(SerializeFull("rail_state",self[data_t]))
            file:close()
          end
        end
  
        -- Clear any proxied tables in RAIL.State
        local k,v
        for k,v in pairs(RAIL.State) do
          if not KeepInState[k] then
            RAIL.State[k] = nil
          end
        end

        -- Remove all unsaved values
        RAIL.State[unsaved_t] = {}
      end

    end
  end)
end

RAIL.Event["AI CYCLE"]:Register(-50,                    -- Priority
                                "Pre-init Load State",  -- Handler name
                                1,                      -- Max runs
                                function(self,id)            -- Handler function
  -- Create temporary fake actors
  RAIL.Owner = { ID = GetV(V_OWNER,id) }
  RAIL.Self = { ID = id }

  -- Prevent logging
  RAIL.Log.Disabled = true

  -- Load persistent state data
  RAIL.State:SetOwnerID(RAIL.Owner.ID)
  RAIL.State:Load(true)
  
  -- Reenable logging
  RAIL.Log.Disabled = false
end)

