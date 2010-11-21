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
    X = {-MaxDistance,MaxDistance},
    Y = {-MaxDistance,MaxDistance},
  }

  -- Create a submap of the entire 1024x1024 map
  RAIL.ChaseMap = TileMap:SubMap({X=RAIL.Owner.X[0],Y=RAIL.Owner.Y[0]},     -- Center
                                 range,                                     -- Submap Range
                                 { Priority = 0, },                         -- Defaults
                                 { Priority = 0, },                         -- Invalid table
                                 nil)                                       -- Passthrough
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
      tile.Priority = tile.Priority + 1000
    end
    
    -- Reduce priority on tiles that are within a tile around ourself
    --local s_x,s_y = RAIL.ChaseMap:TranslateFromParent(RAIL.Self.X[0],RAIL.Self.Y[0])
    --for tile in RAIL.ChaseMap:TilesAround(s_x,s_y,1) do
    --  tile.Priority = tile.Priority - 1
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
      tile.Priority = tile.Priority - priority * RAIL.State.KitePriorityMultiplier
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
          tile.Priority = tile.Priority + delta
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
        tile.Priority = tile.Priority - 1000
      end
    end
  end)
end

RAIL.Event["TARGET SELECT/POST"]:Register(0,                  -- Priority
                                          "Move Targeting",   -- Handler name
                                          -1,                 -- Max runs (negative means infinite)
                                          function()          -- Handler function
  -- Get current position relative to the owner
  local s_x,s_y = RAIL.ChaseMap:TranslateFromParent(RAIL.Self.X[0],RAIL.Self.Y[0])
  
  -- Get the maximum distance
  local MaxDistance = RAIL.State.MaxDistance
  
  -- A table to use for tiles that haven't been accessed
  local nil_tile = {
    Priority = 0,
    X = nil,
    Y = nil,
  }
  
  -- A table to use as place holder in case a nil_tile is best
  local nil_best = Table.ShallowCopy(nil_tile)

  -- Loop through all the tiles around our owner
  -- NOTE: Do not use TileAround because it will generate tables for each tile,
  --       even if it hasn't been accessed this cycle. Using rawget will yield
  --       only tiles that have been accessed (and as such, probably have move
  --       priorities
  local best
  for y=-MaxDistance,MaxDistance do
    -- Get the row from the ChaseMap
    local row = rawget(RAIL.ChaseMap,y)
    -- Loop through each tile within this row
    for x=-MaxDistance,MaxDistance do
      -- Get the tile at (x,y)
      local tile
      if row ~= nil then
        tile = rawget(row,x) or nil_tile
      else
        tile = nil_tile
      end
      
      -- Check that the tile isn't known to be unpassable
      if tile.Passable ~= false then
        -- Check if a tile has been selected yet
        if not best then
          best = tile
        else
          -- Check this tile's priority against the current selection
          if tile.Priority > best.Priority then
            best = tile
          elseif tile.Priority == best.Priority then
            -- Check if the tile is closer to the AI
            local tile_dist = PythagDistance(s_x,s_y,x,y)
            local best_dist = PythagDistance(s_x,s_y,best.X,best.Y)
            if tile_dist < best_dist then
              best = tile
            elseif tile_dist == best_dist then
              -- Check if the tile is closer to the owner
              if PythagDistance(0,0,x,y) < PythagDistance(0,0,best.X,best.Y) then
                best = tile
              end
            end
          end -- tile.Priority > best.Priority
        end -- not best
        
        -- Check if the best tile is the nil_tile
        if best == nil_tile then
          -- Change best to the nil_best
          best = nil_best
          
          -- Set the coordinates of it
          nil_best.X = x
          nil_best.Y = y
        end
      end -- tile.Passable ~= nil
    end -- x=-MaxDistance,MaxDistance
  end -- y=-MaxDistance,MaxDistance

  -- Check to see if we've found a tile better than the one we're on
  if best then
    -- Transform the X,Y to map-wide coordinates
    local x,y
    if best ~= nil_best then
      x,y = TileMap:GetCoordsFromTile(best)
    else
      x,y = RAIL.ChaseMap:TranslateToParent(best.X,best.Y)
    end

    -- If we're not already at that position, set it as the chase target
    if x ~= RAIL.Self.X[0] or y ~= RAIL.Self.Y[0] then
      RAIL.Target.Chase = { x, y }
    end
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
