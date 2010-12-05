-- Various Table Classes


-- Table
do
  Table = { }

  -- Private key to track the number of entries in the table
  local key_n = {}

  -- Metatable to make tables inherit from Table
  local metatable = {
    __index = Table,
  }

  -- Create a new table
  function Table.New(self)
    local ret = {
      [key_n] = 0,
    }
    setmetatable(ret,metatable)

    return ret
  end
  
  -- Get table size
  function Table.GetN(t)
    -- See if the table has an "n" element
    if t[key_n] == nil then
      -- If it doesn't, count until we find nil
      local i = 0
      while t[i+1] ~= nil do i=i+1 end
      t[key_n] = i
    end

    return t[key_n]
  end
  Table.Size = Table.GetN
  
  -- Set the table size
  function Table.SetN(t,size)
    -- Get the table size
    local len = Table.GetN(t)
    
    -- Check if we're reducing the size
    if size < len then
      -- Remove all elements after size
      for i=len,size+1,-1 do
        t[i]=nil
      end
    end
  
    -- Set n
    t[key_n]=size

    return t
  end
  
  -- Add an element to a table
  function Table.Insert(t,pos,item)
    -- Check if we were given 3 arguments
    if item == nil then
      -- Nope, only 2, 2nd one is the item
      item = pos
      pos = nil
    end
  
    -- Get the number of items we're adding
    local num = 1
    if type(item) == "table" and item[key_n] ~= nil then
      num = Table.GetN(item)
    end

    -- Save the number of items in t
    local tEnd = Table.GetN(t)
  
    -- Increase number of items
    t[key_n] = Table.GetN(t) + num
  
    -- Check if we have a position
    if pos == nil then
      -- Set pos to the end
      pos = tEnd + 1
    end
  
    -- Shift everything forward
    local i
    for i=t[key_n],pos+num,-1 do
      t[i]=t[i-num]
    end
  
    -- Insert the item(s)
    if type(item) == "table" and item[key_n] ~= nil then
      -- Loop through the table to be merged
      for i=1,Table.GetN(item) do
        -- Merge them in
        t[pos+i-1]=item[i]
      end
    else
      t[pos]=item
    end

    return t
  end

  -- Add an element to the end of a table
  function Table.Append(t,item)
    -- Just the same as insert without specifying position
    return Table.Insert(t,item,nil)
  end
  
  -- Remove an element from a table
  function Table.Remove(t,pos,num)
    -- Check if we have num
    if num == nil or num < 0 then
      num = 1
    elseif num == 0 then
      return
    end
  
    -- Check if the item exists
    if Table.GetN(t) < pos then
      return
    end

    -- Shift everything forward
    for i=pos,t[key_n]-num do
      t[i]=t[i+num]
      t[i+num]=nil
    end
  
    -- Remove the previous elements
    t[key_n]=t[key_n]-num

    return t
  end
  
--[[
  -- Remove elements from the table, based on a function evaluating their values
  function Table.sieveValues(t,f,reversed)
    -- Make sure we have a sieving function
    if type(f) ~= "function" then
      return t
    end

    -- Make sure reversed is a boolean
    if type(reversed) ~= "boolean" then
      reversed = false
    end

    -- Loop through each element in the table
    local i,max = 1,Table.getn(t)
    while i <= max do
      -- Check if the element should be ignored
      local ret = f(t[i])
      if type(ret) ~= "boolean" then
        ret = false
      end
      if ret ~= reversed then
        -- Element should be removed
        Table.remove(t,i)

        -- Reduce the max
        max = Table.getn(t)
      else
        -- Element should stay
        i = i + 1
      end
    end

    return t
  end
--]]

  -- Shallow copy a table (just create a new one)
  function Table.ShallowCopy(t,into,overwrite)
    local copy = into or {}

    -- Loop through all elements of the table
    for k,v in t do
      if copy[k] == nil or overwrite then
        copy[k] = v
      end
    end

    -- Set the same metatable
    local mt = getmetatable(t)
    if type(mt) == "table" then
      setmetatable(copy,mt)
    end

    return copy
  end

  -- Deep copy a table (subtables are also copied to new ones)
  do
    local function do_deep_copy(v,saved)
      if not saved[v] then
        local t = type(v)
        if t == "table" then
          -- Deep copy the table
          saved[v] = Table.DeepCopy(v,nil,nil,saved)
        else
          -- Everything else
          saved[v] = v
        end
      end
      return saved[v]
    end

    function Table.DeepCopy(t,copy,overwrite,saved)
      -- Create a saved table
      saved = saved or setmetatable({},{__mode="k",})

      -- Check if this table has already been copied
      if saved[t] then
        return saved[t]
      end

      -- Create a copy table
      local copy = copy or {}

      -- Add this table to the saved list
      saved[t] = copy

      -- Loop through all elements of the table
      for k,v in pairs(t) do
        local new_k = do_deep_copy(k,saved)

        if copy[new_k] == nil or overwrite then
          copy[new_k] = do_deep_copy(v,saved)
        end
      end

      -- Check for a metatable
      local mt = getmetatable(t)
      if type(mt) == "table" then
        local deep_mt = getmetatable(copy)
        setmetatable(copy,Table.DeepCopy(mt,deep_mt,overwrite,saved))
      end

      -- Return the copy
      return copy
    end
  end
end

-- List
do
  -- List based on code from http://www.lua.org/pil/11.4.html

  List = {}

  local metatable = {
    __index = List
  }

  function List.New()
    local ret = { first = 0, last = -1 }
    setmetatable(ret,metatable)

    return ret
  end

  function List.PushLeft (list, value)
    list.first = list.first - 1
    list[list.first] = value;
  end

  function List.PushRight (list, value)
    list.last = list.last + 1
    list[list.last] = value
  end

  function List.PopLeft (list)
    if list.first > list.last then
      return nil
    end
    local value = list[list.first]
    list[list.first] = nil         -- to allow garbage collection
    list.first = list.first + 1
    return value
  end

  function List.PopRight (list)
    if list.first > list.last then
      return nil
    end
    local value = list[list.last]
    list[list.last] = nil
    list.last = list.last - 1
    return value
  end

  function List.Clear (list)
    for i=list.first,list.last do
      list[i] = nil
    end

    list.first = 0
    list.last = -1
  end

  function List.Size (list)
    return list.last - list.first + 1
  end
end

-- Function to selectively return values from pairs based on index name
function FindPairs(t,pattern,init,plain)
  -- Get the results from pairs
  local iter,t,first = pairs(t)

  -- Return a custom function with the table and first item from pairs()
  return function(t,idx)
    -- Loop through the values from iter()
    local value
    repeat
      -- Get the next index and skill from pairs()'s iterator
      idx,value = iter(t,idx)
    -- Loop until no pairs left or an index matches the pattern
    until idx == nil or string.find(tostring(idx),pattern,init,plain) ~= nil

    -- Return the next index and value
    return idx,value
  end,t,first
end
