-- TileMap logic
do
  -- Private key to hold data
  local key = {}
  
  local function InvalidProxy(index)
    -- Not in range, generate a proxy for the invalid table
    -- NOTE: true indicates that we want it to have a metatable applied
    local proxy = newproxy(true)

    -- Set metamethods on it
    -- NOTE: setmetatable only works against type "table"
    local mt = getmetatable(proxy)
    mt.__index = index
    mt.__newindex = function() end

    -- Return the proxy
    return proxy
  end

  local proxy_mt = {
    __index = function(self,idx)
      -- An index that doesn't exist on this table should first use the default
      -- value, and then use the base table's value
      if self[key].Defaults[idx] then
        return self[key].Defaults[idx]
      end

      if self[key].Base then
        return self[key].Base[idx]
      end
    end,
    __newindex = function(self,idx,val)
      -- Check if index is a value that should be written to the base
      if self[key].Base and self[key].Passthrough[idx] then
        -- Write to the base tile's value table
        self[key].Base[idx] = val
      else
        -- Only write to the proxied value table
        rawset(self,idx,val)
      end
    end,
  }

  -- X table (populates self with values)
  local x_mt = {
    __index = function(self,x)
      local range = self[key].Range
      if range.X[1] <= x and x <= range.X[2] then
        -- Generate a new value table
        rawset(self,x,{})
        
        -- Populate the X and Y parts of the value table
        self[x].X = x
        self[x].Y = self[key].Y

        -- Generate the private options table, which inherits from the
        -- X-table's private options
        self[x][key] = setmetatable({},{ __index = self[key], })
        
        -- Store the X coordinate
        self[x][key].X = x

        -- If this is from a submap, set the base
        if self[key].Base then
          self[x][key].Base = self[key].Base[x + self[key].Offset.X]
        end
        
        -- Set the proxy metatable onto the new value table
        setmetatable(self[x],proxy_mt)

        -- Return the newly generated value table
        return self[x]
      else
        -- Return a proxy to the invalid table
        return InvalidProxy(self[key].Invalid)
      end
    end,
    -- Don't allow new items to be added manually
    __newindex = function(self,x,val) end,
  }

  -- Base table (Y table; populates self with X tables)
  local tilemap_mt = {
    __index = function(self,y)
      if type(y) ~= "number" then
        if self[key].Base then
          return self[key].Base[y]
        end
        return
      end

      -- Ensure the index is within range
      local range = self[key].Range
      if range.Y[1] <= y and y <= range.Y[2] then
        -- It's within range, generate a new X-table
        rawset(self,y,{})
        
        -- Generate the private options table
        self[y][key] = setmetatable({},{
          __mode = "v",         -- weak values
          __index = self[key],  -- inherit from Y-table's options
        })

        -- Store the base level map (need weak for this to be collected)
        self[y][key].Map = self
        
        -- Store the y position
        self[y][key].Y = y

        -- If this map is a submap, set the base
        if self[key].Base then
          self[y][key].Base = self[key].Base[y + self[key].Offset.Y]
        end

        -- Set the metatable for the new X-table so it will generate values
        setmetatable(self[y],x_mt)

        -- Return the generated X-table
        return self[y]
      else
        -- Return a proxy for a table that just returns invalid proxies
        return InvalidProxy(function() return InvalidProxy(self[key].Invalid) end)
      end
    end,
    __newindex = function(self,y,val)
      -- Don't allow numbers to be set here
      if type(y) ~= "number" then
        rawset(self,y,val)
      end
    end,
    __call = function(self,x,y)
      -- Allow obj(x,y) to be an alias for obj[y][x]
      return self[y][x]
    end,
  }

  TileMap = setmetatable({
    [key] = {
      Range = {
        X = {0,1023},
        Y = {0,1023},
      },
      Base = nil,
      Offset = {
        X = 0,
        Y = 0,
      },
      Defaults = {
        Passable = nil,
      },
      Invalid = {
        Passable = false,
      },
      Passthrough = {
        Passable = true,
      },
    },
    Get = function(self,x,y)
      return self[y][x]
    end,
    GetCoordsFromTile = function(self,tile)
      -- Check that it's not an out-of-range tile
      if type(tile) == "userdata" then
        return nil
      end

      -- Find the tile that matches this map
      while tile[key].Map ~= self do
        -- If there's no base, can't find it on this map
        if tile[key].Base == nil then
          return nil
        end

        tile = tile[key].Base
      end

      return tile[key].X,tile[key].Y
    end,
    SubMap = function(self,offset,range,defaults,invalid,passthrough)
      -- Validate the options
      return setmetatable({
        [key] = setmetatable({
          Range = range,
          Base = self,
          Offset = offset,
          Defaults = defaults,
          Invalid = invalid,
          Passthrough = passthrough,
        },{
          __index = self[key]
        }),
      },tilemap_mt)
    end,
    TranslateFromParent = function(self,x,y)
      return x - self[key].Offset.X,y - self[key].Offset.Y
    end,
    TranslateToParent = function(self,x,y)
      return x + self[key].Offset.X,y + self[key].Offset.Y
    end,
    TilesAround = function(self,center_x,center_y,range)
      -- Ensure that at least one tile will be on the TileMap
      if
        range < 0 or
        math.ceil(center_x + range)  < self[key].Range.X[1] or
        math.floor(center_x - range) > self[key].Range.X[2] or
        math.ceil(center_y + range)  < self[key].Range.Y[1] or
        math.floor(center_y - range) > self[key].Range.Y[2]
      then
        return function() return nil end
      end

      -- Calculate the beginning and end of X and Y
      local x_min = math.max(math.ceil(center_x - range),self[key].Range.X[1])
      local x = x_min - 1
      local x_max = math.min(math.floor(center_x + range),self[key].Range.X[2])
      local y = math.max(math.ceil(center_y - range),self[key].Range.Y[1])
      local y_max = math.min(math.floor(center_y + range),self[key].Range.Y[2])
      local t = self[y]

      -- Return a function that will iterate through tiles that are on the TileMap
      -- Note: Unlike pairs(), this doesn't bother with passing table and index
      --       back and forth. It still works with Lua's for ... in ...().
      return function()
        -- Increment X
        x = x + 1

        -- Check if X is out of the desired range
        if x > x_max then
          -- Increment Y
          y = y + 1

          -- Check if Y is out of the desired range
          if y > y_max then
            -- We're done
            return nil
          end

          -- Get the new Y table
          t = self[y]
          x = x_min
        end

        -- Return the value and its coordinates
        return t[x],x,y
      end
    end,nil,nil
  },tilemap_mt)
end

RAIL.Event["ACTOR UPDATE"]:Register(10,               -- Priority
                                    "Tile Passable",  -- Handler name
                                    -1,               -- Max runs (negative means infinite)
                                    function(self,actor)
  -- The location the actor is on is definitely passable
  TileMap(actor.X[0],actor.Y[0]).Passable = true
end)

