-- TileMap logic
do
  -- Y out of range
  local y_oor = setmetatable({},{
    __index = function(self,idx)
      return {
        walkable = false,
        priority = 0,
      }
    end,
    __newindex = function() end,
  })

  -- X in range (generates value table)
  local key = {}
  local proxy_mt
  local function GenerateValue(x,y,base,offset)
    if not base then
      return {
        walkable = nil,   -- unknown
        priority = 0,
      }
    end

    return setmetatable({
      [key] = {
        base = base(x+offset.x, y+offset.y),
        passthrough = {
          walkable = true
        },
      },
      priority = 0,
    },proxy_mt)
  end

  proxy_mt = {
    __index = function(self,idx)
      return self[key][idx]
    end,
    __newindex = function(self,idx,val)
      -- Get the table of options for this cell
      local opts = self[key]
      
      -- Check if index is a value that should be written to the base
      if opts.passthrough[idx] then
        -- Write to the base cell
        self[key][idx] = val
      else
        -- Only write to the proxied cell
        rawset(self,idx,val)
      end
    end,
  }

  -- Y in range (generates X table)
  local x_mt = {
    __index = function(self,x)
      local range = self.options.range
      if range.x[1] <= x and x <= range.x[2] then
        rawset(self,x,GenerateValue(x,self.options.y,self.options.base,self.options.offset))
        return self[x]
      else
        return y_oor[0]
      end
    end,
    __newindex = function(self,x,val) end,
  }

  -- Base table
  local tilemap_mt = {
    __index = function(self,y)
      if type(y) ~= "number" then
        if self[key].base then
          return self[key].base[y]
        end
        return
      end

      local range = self[key].range
      if range.y[1] <= y and y <= range.y[2] then
        rawset(self,y,setmetatable({
          options = {
            range = self[key].range,
            base = self[key].base,
            offset = self[key].offset,
            y = y,
          },
        },x_mt))
        return self[y]
      else
        return y_oor
      end
    end,
    __newindex = function(self,y,val)
      if type(y) ~= "number" then
        rawset(self,y,val)
      end
    end,
    __call = function(self,x,y)
      return self[y][x]
    end,
  }

  TileMap = setmetatable({
    [key] = {
      range = {
        x = {0,1023},
        y = {0,1023},
      },
      base = nil,
      offset = {
        x = 0,
        y = 0,
      },
    },
    Get = function(self,x,y)
      return self[y][x]
    end,
    SubMap = function(self,center,range)
      return setmetatable({
        [key] = {
          range = range,
          base = self,
          offset = center,
        },
      },tilemap_mt)
    end,
    TranslateFromParent = function(self,x,y)
      return x - self[key].offset.x,y - self[key].offset.y
    end,
    TranslateToParent = function(self,x,y)
      return x + self[key].offset.x,y + self[key].offset.y
    end,
    TilesAround = function(self,center_x,center_y,range)
      -- Ensure that at least one tile will be on the TileMap
      if
        range < 0 or
        math.ceil(center_x + range)  < self[key].range.x[1] or
        math.floor(center_x - range) > self[key].range.x[2] or
        math.ceil(center_y + range)  < self[key].range.y[1] or
        math.floor(center_y - range) > self[key].range.y[2]
      then
        return function() return nil end
      end

      -- Calculate the beginning and end of X and Y
      local x_min = math.max(math.ceil(center_x - range),self[key].range.x[1])
      local x = x_min - 1
      local x_max = math.min(math.floor(center_x + range),self[key].range.x[2])
      local y = math.max(math.ceil(center_y - range),self[key].range.y[1])
      local y_max = math.min(math.floor(center_y + range),self[key].range.y[2])
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
                                    "Tile Movable",   -- Handler name
                                    -1,               -- Max runs (negative means infinite)
                                    function(self,actor)
  -- The location the actor is on is definitely movable
  TileMap(actor.X[0],actor.Y[0]).movable = true
end)

