RAIL.Validate.DanceAttackTiles = {"number",-1,-1,1}
-- removed: RAIL.Validate.DisableChase = {"boolean",false}
RAIL.Validate.RunAhead = {"boolean",false}
RAIL.Validate.IdleMovement = {is_subtable = true,
  MoveType = {"string","none",
    { ["none"] = true, ["return"] = true, }
  },
  BeginAfterIdleTime = {"number",3000,0},
}

-- Hidden option; this probably shouldn't be changed
RAIL.Validate.KitePriorityMultiplier = {"number",1,1,
  unsaved = true,
}


RAIL.Validate.MaxDistance = {"number", 13, 0}
RAIL.Validate.FollowDistance = {"number", 4, 0, nil}  -- maximum value will be MaxDistance
setmetatable(RAIL.Validate.FollowDistance,{
  __index = function(self,idx)
    if idx == 4 then
      return RAIL.State.MaxDistance
    end

    return nil
  end,
})

RAIL.Event["AI CYCLE"]:Register(50,                 -- Priority
                                "Chase Map Begin",  -- Handler name
                                -1,                 -- Max runs (negative means infinite)
                                function()          -- Handler function
  local MaxDistance = RAIL.State.MaxDistance
  local range = {
    x = {-MaxDistance,MaxDistance},
    y = {-MaxDistance,MaxDistance},
  }

  -- Create a submap of the entire 1024x1024 map
  RAIL.ChaseMap = TileMap:SubMap({x=RAIL.Owner.X[0],y=RAIL.Owner.Y[0]},     -- Center
                            range)                                          -- Submap Range
end)

RAIL.Event["TARGET SELECT/PRE"]:Register(0,               -- Priority
                                         "Chase Owner",   -- Handler name
                                         -1,              -- Max runs (negative means infinite)
                                         function()       -- Handler function
  if RAIL.State.RunAhead and false then
    return RAIL.Event["CHASE CHECK/AHEAD"]:Fire()
  else
    return RAIL.Event["CHASE CHECK/BEHIND"]:Fire()
  end
end)

RAIL.Event["CHASE CHECK/AHEAD"]:Register(0,               -- Priority
                                          "Check Chase",  -- Handler name
                                          -1,             -- Max runs (negative means infinite)
                                          function()      -- Handler function
  -- TODO: Write this
end)

do
  local chasing = false

  RAIL.Event["CHASE CHECK/BEHIND"]:Register(0,              -- Priority
                                            "Check Chase",  -- Handler name
                                            -1,             -- Max runs (negative means infinite)
                                            function()      -- Handler function

    -- Reset the chasing flag, but retain the previous state
    local last = chasing
    chasing = false
    
    local max = RAIL.State.MaxDistance
    local moving = false

    -- Check if we were already chasing our owner
    if last then
      if
        RAIL.Owner.Motion[0] == MOTION_MOVE or
        History.FindMostRecent(RAIL.Owner.Motion,MOTION_MOVE,nil,500)
      then
        -- Set the moving flag
        moving = true
      end

      -- Also chase to a closer distance
      max = RAIL.State.FollowDistance
    else
      if
        RAIL.Owner.Motion[0] == MOTION_MOVE and
        RAIL.Self:DistanceTo(0)(RAIL.Owner.X[-500],RAIL.Owner.Y[-500])
          > RAIL.Self:DistanceTo(0)(RAIL.Owner)
      then
        moving = true
      end
    end
    
    -- Check if blocks to owner is too great
    if RAIL.Self:BlocksTo(RAIL.Owner) > max then
      -- Chase
      return true
    end
    
    -- Check if owner is moving
    if moving then
      -- Estimate the movement speed of the owner
      local speed = RAIL.Owner:EstimateMove()
      
      -- Determine a fraction of the distance to estimate ahead
      local tiles = math.ceil(max / 4)
      
      -- Estimate if the homu/merc will be off-screen after moving for the
      --    time it would take to move this number of tiles
      -- Note: Negative values project into the future
      if RAIL.Self:BlocksTo(-1 * tiles * speed)(RAIL.Owner) > max then
        -- Chase
        return true
      end
    end

    -- Don't chase
    return false
  end)

  RAIL.Event["CHASE CHECK/BEHIND"]:Register(5,              -- Priority
                                            "Do Chase",     -- Handler name
                                            -1,             -- Max runs (negative means infinite)
                                            function()      -- Handler function
    chasing = true

    -- Boost priority on the tiles that are within FollowDistance of the owner
    for tile in RAIL.ChaseMap:TilesAround(0,0,RAIL.State.FollowDistance) do
      tile.priority = tile.priority + 1000
    end
    
    -- Reduce priority on tiles that are within a tile around ourself
    --local s_x,s_y = RAIL.ChaseMap:TranslateFromParent(RAIL.Self.X[0],RAIL.Self.Y[0])
    --for tile in RAIL.ChaseMap:TilesAround(s_x,s_y,1) do
    --  tile.priority = tile.priority - 1
    --end
  end)
end

do
  -- Make a table of kite mode functions
  local kite_modes = setmetatable({
    ["always"] = function() return true end,
    ["tank"] = function(actor) return actor.Target[0] == RAIL.Self.ID end,
  },{
    __index = function() return false end,
  })


  local function GetKiteRange(actor)
    -- Check if the KiteMode allows kiting right now
    if kite_modes[actor.BattleOpts.KiteMode](actor) then
      -- Get the kite range
      return actor.BattleOpts.KiteDistance
    end

    -- Return negative (disabled) if the kite mode doesn't allow kiting yet
    return -1
  end

  RAIL.Event["ACTOR UPDATE/ENEMY"]:Register(0,                -- Priority
                                            "Kite/allowed",   -- Handler name
                                            -1,               -- Max runs (negative means infinite)
                                            function(self,actor)
    -- Get the kite range
    local kite_range = GetKiteRange(actor)

    -- Get the actor's priority
    local priority = actor.BattleOpts.Priority

    -- Subtract the monster's priority level from the area it should be kited
    local actor_x,actor_y = RAIL.ChaseMap:TranslateFromParent(actor.X[0],actor.Y[0])
    for tile,x,y in RAIL.ChaseMap:TilesAround(actor_x,actor_y,kite_range) do
      -- Subtract the monster's priority to the tile's priority
      tile.priority = tile.priority - priority * RAIL.State.KitePriorityMultiplier
    end -- tile,x,y in RAIL.ChaseMap:TilesAround(actor_x,actor_y,kite_range)
  end)
  
  RAIL.Event["TARGET SELECT/ENEMY/CHASE"]:Register(0,                 -- Priority
                                                   "Disable Chase",   -- Handler name
                                                   -1,                -- Max runs (negative means infinite)
                                                   function(self,actor,range,priority)
    -- Check if we shouldn't chase after this monster
    if actor.BattleOpts.DisableChase then
      -- Don't continue this event
      return false
    end
  end)

  RAIL.Event["TARGET SELECT/ENEMY/CHASE"]:Register(100,                 -- Priority
                                                   "Add to ChaseMap",   -- Handler name
                                                   -1,                  -- Max runs (infinite)
                                                   function(self,actor,range,priority)
    -- Get the kite distance of this monster
    local kite_range = GetKiteRange(actor)
    
    -- Check if kite_range is greater than range
    if kite_range > range then
      -- Don't do anything
      return
    end

    -- Loop through all tiles that are within "range" blocks
    local actor_x,actor_y = RAIL.ChaseMap:TranslateFromParent(actor.X[0],actor.Y[0])
    for tile,x,y in RAIL.ChaseMap:TilesAround(actor_x,actor_y,range) do
      -- Only modify tile priority when outside of kite range
      if BlockDistance(actor_x,actor_y,x,y) > kite_range then
        -- Get the change over any previous priority applied to this tile
        -- from this actor
        local delta = priority - (tile[actor] or 0)

        -- If the change is positive, apply it
        if delta > 0 then
          tile[actor] = priority
          tile.priority = tile.priority + delta
        end
      end
    end -- tile,x,y in RAIL.ChaseMap:TilesAround(actor_x,actor_y,range)
  end)

  RAIL.Event["TARGET SELECT/POST"]:Register(-10,              -- Priority
                                            "Dance attack",   -- Handler name
                                            -1,               -- Max runs (negative means infinite)
                                            function()
    -- Check if an attack target was selected
    if RAIL.IsActor(RAIL.Target.Attack) then
      -- Set the area around the self to have a lower priority
      local x,y = RAIL.ChaseMap:TranslateFromParent(RAIL.Self.X[0],RAIL.Self.Y[0])
      for tile in RAIL.ChaseMap:TilesAround(x,y,RAIL.State.DanceAttackTiles) do
        tile.priority = tile.priority - 1000
      end
    end
  end)
end

RAIL.Event["TARGET SELECT/POST"]:Register(0,                  -- Priority
                                          "Move Targeting",   -- Handler name
                                          -1,                 -- Max runs (negative means infinite)
                                          function()          -- Handler function
                                
  -- The best tile found so far (none yet)
  local best

  -- Get our current position relative to the owner
  local s_x,s_y = RAIL.ChaseMap:TranslateFromParent(RAIL.Self.X[0],RAIL.Self.Y[0])

  -- Loop through all the tiles around our owner
  for tile,x,y in RAIL.ChaseMap:TilesAround(0,0,RAIL.State.MaxDistance) do
    -- Check that the tile hasn't been determined to be unpassable
    if tile.walkable ~= false then
      local better = false
      -- If there is no best, use the first tile returned
      if not best then
        better = true
        
      -- If this tile is higher priority than the last, use it
      elseif tile.priority > best.priority then
        better = true
        
      -- If this tile and the existing best have equal priority, more processing
      --  needs to be done
      elseif tile.priority == best.priority then
        -- Get the distance between the tile and the AI
        tile.s_dist = PythagDistance(s_x,s_y,x,y)

        -- If this tile is equal priority and closer to the AI, it is better
        if tile.s_dist < best.s_dist then
          better = true
          
        -- If the tiles are equidistant, do more processing
        elseif tile.s_dist == best.s_dist then
        
          -- Get the distance between the tile and the owner
          tile.o_dist = PythagDistance(0,0,x,y)
          
          -- Prefer tiles that are closer to the owner
          if tile.o_dist < best.o_dist then
            better = true
          end
        end
      end

      -- Check if the current tile is better than the existing best
      if better then
        -- Copy the tiles information into the "best" variable
        best = tile
        best.s_dist = PythagDistance(s_x,s_y,x,y)
        best.o_dist = PythagDistance(0,0,x,y)
        best.x = x
        best.y = y
      end
    end
  end

  -- Check to see if we've found a tile better than the one we're on
  if best and (best.x ~= s_x or best.y ~= s_y) then
    RAIL.Target.Chase = {RAIL.ChaseMap:TranslateToParent(best.x,best.y)}
  end
end)

-- Idle Handling
RAIL.Event["AI CYCLE"]:Register(900,              -- Priority
                                "Idle begin",     -- Handler name
                                1,                -- Max runs (negative means infinite)
                                function()        -- Handler function
  -- Start the idle time when the first decision-making cycle runs
  RAIL.Self.IdleBegin = GetTick()
end)

RAIL.Event["AI CYCLE"]:Register(980,              -- Priority
                                "Idle Handling",  -- Handler name
                                -1,               -- Max runs (negative means infinite)
                                function()        -- Handler function
  if
    RAIL.Target.Attack ~= nil or
    RAIL.Target.Skill ~= nil or
    RAIL.Target.Chase ~= nil
  then
    -- Not idle; reset idle time
    RAIL.Self.IdleBegin = GetTick()
  else
    -- Call the idle-handler functions
    RAIL.Event["IDLE"]:Fire(GetTick() - RAIL.Self.IdleBegin)
  end
end)

RAIL.Event["IDLE"]:Register(10,                       -- Priority
                            "Idle Return To Owner",   -- Handler name
                            -1,                       -- Max runs (negative means infinite)
                            function(self,idletime)   -- Handler function
    -- Only move if idle movement type is set to "return"
    if RAIL.State.IdleMovement.MoveType ~= "return" then
      return true
    end

    -- Check if we've waited long enough
    if idletime < RAIL.State.IdleMovement.BeginAfterIdleTime then
      -- Continue looping through idle handlers
      return true
    end

    -- Only return if too far away
    if RAIL.Self:BlocksTo(RAIL.Owner) <= RAIL.State.FollowDistance then
      return true
    end

    -- Log it
    RAIL.LogT(0,"Returning to owner; idle for {1}ms",idletime)

    -- Set the chase target to our owner
    --RAIL.Target.Chase = RAIL.Owner
    -- TODO: Since RAIL.Target.Chase now requires (x,y) and this takes place
    --    after the RAIL.ChaseMap parsing, figure out a better way to return
    MoveToOwner(RAIL.Self.ID)
    
    -- Reset idle time
    RAIL.Self.IdleBegin = GetTick()

    -- Don't continue processing idle-handlers
    return false
end)

RAIL.Event["IDLE"]:Register(30,                       -- Priority
                            "Pathed Walk",            -- Handler name
                            -1,                       -- Max runs (negative means infinite)
                            function(self,idletime)   -- Handler function
  -- TODO: Pathed walking while idle
end)

RAIL.Event["IDLE"]:Register(40,             -- Priority
                            "Random Walk",  -- Handler name
                            -1,             -- Max runs
                            function(self,idletime)
  -- TODO: Random walking while idle
end)
