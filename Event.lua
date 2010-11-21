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
        Name = name,
        Priority = priority,
        Func = f,
        RunsLeft = runs,
        Next = nil,
        Event = self,
      }

      -- Check if the new node should be inserted at the beginning
      if not self.Begin or self.Begin.Priority > priority then
        new_handler.Next = self.Begin
        self.Begin = new_handler
        return
      end

      -- Loop through the linked list
      local cur_handler = self.Begin
      while cur_handler.Next and cur_handler.Next.Priority <= priority do
        cur_handler = cur_handler.Next
      end

      -- Insert the new node
      new_handler.Next = cur_handler.Next
      cur_handler.Next = new_handler
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
      self.RetVal = {}

      -- Loop through the event list until one returns false
      local prev = nil
      local cur = self.Begin
      local continue,skip_from,skip_to = true,0,0
      while continue do
        -- Ensure the node has runs left
        while cur and cur.RunsLeft == 0 do
          -- Skip to the next handler
          cur = cur.Next
        end

        -- Set the previous node's next
        if not prev then
          self.Begin = cur
        else
          prev.Next = cur
        end

        -- Ensure there's a node to use
        if not cur then
          break
        end

        -- Check that the current node is outside the threshold of
        --    skipped nodes.
        local prev_from,prev_to = skip_from,skip_to
        if cur.Priority < skip_from or skip_to <= cur.Priority then
          -- Log it
          RAIL.LogT(97,"..running event handler \"{1}\" (priority {2})",cur.Name,cur.Priority)

          -- Add a line to the event log
          RAIL.Event[performance].Log:Append(string.format("%s *%s\r\n",
                                                           log_depth,
                                                           cur.Name))

          -- Increment the event depth
          RAIL.Event[performance].Depth = RAIL.Event[performance].Depth + 1

          -- Get the time before starting the function
          local func_ticks = GetTick()

          -- Run the function
          continue,skip_from,skip_to = cur:Func(unpack(arg))

          -- Measure the time taken
          func_ticks = GetTick() - func_ticks

          -- Require an explicit "false" to break continue
          if continue ~= false then continue = true end

          -- Ensure the skip_from and skip_to returns are numbers
          if type(skip_from) ~= "number" then skip_from = prev_from end
          if type(skip_to) ~= "number" then skip_to = prev_to end

          -- Subtract the runs_left if applicable
          if cur.RunsLeft > 0 then
            cur.RunsLeft = cur.RunsLeft - 1
          end

          -- Decrement the event depth
          RAIL.Event[performance].Depth = RAIL.Event[performance].Depth - 1

          -- Add a line to the event log
          RAIL.Event[performance].Log:Append(string.format("%s *%s (%dms)\r\n",
                                                           log_depth,
                                                           cur.Name,
                                                           func_ticks))
        end

        -- Go to the next
        prev = cur
        cur = cur.Next
      end

      -- Get the ticks at the end of the event
      local event_end = GetTick()

      -- Record performance data
      local perf = self[performance]
      ticks = GetTick() - ticks

      perf.Runs = perf.Runs + 1
      perf.Ticks = perf.Ticks + ticks
      if ticks > perf.Longest then
        perf.Longest = ticks
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
      return unpack(self.RetVal)
    end,
    ResetPerformanceData = function(self)
      local perf = self[performance]
      perf.Runs = 0
      perf.Ticks = 0
      perf.Longest = 0
      perf.Subevents = 0
    end,
    GetPerformanceData = function(self)
      local perf = self[performance]

      -- If the event was never called, return 0ms average and longest
      if perf.Runs == 0 then
        return 0,0
      end

      -- Otherwise return the calculated average and longest
      return math.ceil(perf.Ticks / perf.Runs), perf.Longest
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
          Runs = 0,
          Ticks = 0,
          Longest = 0,
          Subevents = 0,
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

