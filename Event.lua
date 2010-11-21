--------------------
-- Event Handling --
--------------------
do
  -- Private key for performance monitoring
  local performance = {}

  local event_base = {
    Register = function(self,priority,name,runs,f)
      -- Generate a new node
      local new_handler = {
        -- Basic information
        ["name"] = name,
        ["priority"] = priority,
        func = f,
        runs_left = runs,
        next = nil,
        event = self,
      }

      -- Check if the new node should be inserted at the beginning
      if not self.begin or self.begin.priority > priority then
        new_handler.next = self.begin
        self.begin = new_handler
        return
      end

      -- Loop through the linked list
      local cur_handler = self.begin
      while cur_handler.next and cur_handler.next.priority <= priority do
        cur_handler = cur_handler.next
      end
      
      -- Insert the new node
      new_handler.next = cur_handler.next
      cur_handler.next = new_handler
    end,
    Fire = function(self,...)
      -- Get the ticks at the beginning of the event
      local ticks = GetTick()
      
      -- Increment the event depth
      RAIL.Event[performance].Depth = RAIL.Event[performance].Depth + 1
      
      -- If this is the first call, reset the log
      if RAIL.Event[performance].Depth == 1 then
        RAIL.Event[performance].Log:Clear()
      end
      
      -- Add a line to the event log to indicate entering an event
      local log_depth = string.rep(" ",RAIL.Event[performance].Depth - 1)
      RAIL.Event[performance].Log:Append(string.format("%s+%s\r\n",
                                                       log_depth,
                                                       self.Name))

      -- Log the firing of the event
      RAIL.LogT(95,"+Event \"{1}\" fired...",self.Name)

      -- Reset the event return
      self.ret_val = nil

      -- Loop through the event list until one returns false
      local prev = nil
      local cur = self.begin
      local continue,skip_from,skip_to = true,0,0
      while continue do
        -- Ensure the node has runs left
        while cur and cur.runs_left == 0 do
          -- Skip to the next handler
          cur = cur.next
        end

        -- Set the previous node's next
        if not prev then
          self.begin = cur
        else
          prev.next = cur
        end

        -- Ensure there's a node to use
        if not cur then
          break
        end

        -- Check that the current node is outside the threshold of
        --    skipped nodes.
        local prev_from,prev_to = skip_from,skip_to
        if cur.priority < skip_from or skip_to <= cur.priority then
          -- Log it
          RAIL.LogT(97,"..running event handler \"{1}\" (priority {2})",cur.name,cur.priority)

          -- Add a line to the event log
          RAIL.Event[performance].Log:Append(string.format("%s *%s\r\n",
                                                           log_depth,
                                                           cur.name))

          -- Increment the event depth
          RAIL.Event[performance].Depth = RAIL.Event[performance].Depth + 1

          -- Get the time before starting the function
          local func_ticks = GetTick()

          -- Run the function
          continue,skip_from,skip_to = cur:func(unpack(arg))
          
          -- Measure the time taken
          func_ticks = GetTick() - func_ticks

          -- Require an explicit "false" to break continue
          if continue ~= false then continue = true end

          -- Ensure the skip_from and skip_to returns are numbers
          if type(skip_from) ~= "number" then skip_from = prev_from end
          if type(skip_to) ~= "number" then skip_to = prev_to end

          -- Subtract the runs_left if applicable
          if cur.runs_left > 0 then
            cur.runs_left = cur.runs_left - 1
          end
          
          -- Decrement the event depth
          RAIL.Event[performance].Depth = RAIL.Event[performance].Depth - 1

          -- Add a line to the event log
          RAIL.Event[performance].Log:Append(string.format("%s *%s (%dms)\r\n",
                                                           log_depth,
                                                           cur.name,
                                                           func_ticks))
        end

        -- Go to the next
        prev = cur
        cur = cur.next
      end
      
      -- Get the ticks at the end of the event
      local event_end = GetTick()

      -- Record performance data
      local perf = self[performance]
      ticks = GetTick() - ticks

      perf.runs = perf.runs + 1
      perf.ticks = perf.ticks + ticks
      if ticks > perf.longest then
        perf.longest = ticks
      end
      -- TODO: sub events
      
      -- Log it
      RAIL.LogT(96,"-Event \"{1}\" finished; time spent = {2}ms",self.Name,ticks)
      
      -- Add a line to the event log
      RAIL.Event[performance].Log:Append(string.format("%s-%s (%dms)\r\n",
                                                       log_depth,
                                                       self.Name,
                                                       ticks))
                                                       
      -- Decrement event log depth
      RAIL.Event[performance].Depth = RAIL.Event[performance].Depth - 1
      
      -- Check if we're at depth 0 now, and hit a relatively long cycle
      if RAIL.Event[performance].Depth == 0 and ticks > 400 then
        -- Log it to TraceAI
        TraceAI(string.format("EXCEPTIONALLY LONG CYCLE (%dms):\r\n%s",
                              ticks,
                              RAIL.Event[performance].Log:Get()))
      end

      -- Return any return value set by the event handlers
      return self.ret_val
    end,
    ResetPerformanceData = function(self)
      local perf = self[performance]
      perf.runs = 0
      perf.ticks = 0
      perf.longest = 0
      perf.subevents = 0
    end,
    GetPerformanceData = function(self)
      local perf = self[performance]
      
      -- If the event was never called, return 0ms average and longest
      if perf.runs == 0 then
        return 0,0
      end
      
      -- Otherwise return the calculated average and longest
      return math.ceil(perf.ticks / perf.runs), perf.longest
    end,
  }

  local event_mt = {
    __index = event_base,
    __call = function(self,...)
      return self:Fire(unpack(arg))
    end,
  }

  RAIL.Event = setmetatable({
    [performance] = {
      Log = StringBuffer.New(),
      Depth = 0,
    },
    ResetAllPerformanceData = function(self)
      for name,event in pairs(self) do
        if type(event) == "table" and name ~= performance then
          event:ResetPerformanceData()
        end
      end
    end,
  },{
    __index = function(self,idx)
      self[idx] = setmetatable({
        Name = idx,
        [performance] = {
          runs = 0,
          ticks = 0,
          longest = 0,
          subevents = 0,
        },
      },event_mt)
      return self[idx]
    end,
  })
end

--------------
-- Timeouts --
--------------
do
  RAIL.Timeouts = Table:New()

  local Timeout = { }

  local metatable = {
    __index = Timeout
  }

  Timeout.Update = function(self)
    if not self[1] then
      -- Not active; do nothing
      return self
    end

    -- Check if the timeout should fire
    local delta = GetTick() - (self[2]+self[3])
    if delta >= 0 then
      -- Add delta as the last argument to the callback
      if not self[6].delta then
        self[6].delta = Table.GetN(self[6]) + 1
      end
      self[6][self[6].delta] = delta

      -- Fire the callback
      self[5](unpack(self[6]))

      if not self[4] then
        -- Not repeating, so set the active element to false
        self[1] = false
      else
        -- Repeating, so reset the base time
        self[2] = GetTick()
      end
    end

    return self
  end

  RAIL.Timeouts.New = function(self,duration,repeating,callback,...)
    local ret = { true, GetTick(), duration, repeating, callback, arg }
    setmetatable(ret,metatable)

    self:Insert(ret)

    return ret
  end

  RAIL.Event["AI CYCLE"]:Register(200,            -- Priority
                                  "Timeouts",     -- Handler name
                                  -1,             -- Max runs (negative means infinite)
                                  function()      -- Handler function
    local k = 0
    for i=1,RAIL.Timeouts:GetN() do
      -- Update the timeout, then check if it's still active
      if RAIL.Timeouts[i]:Update()[1] == true then
        -- Since it's still active, keep it in the table
        k = k + 1
        RAIL.Timeouts[k] = RAIL.Timeouts[i]
      end
    end

    RAIL.Timeouts:SetN(k)
  end)
end

