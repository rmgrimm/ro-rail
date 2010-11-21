-- String Buffer
do
  StringBuffer = {}

  local metatable = {
    __index = StringBuffer,
    __tostring = function(self)
      return tostring(self:Get())
    end,
  }

  local key = {}

  StringBuffer.New = function()
    -- Create a new table, which "inherits" from StringBuffer
    local ret = {}
    setmetatable(ret,metatable)

    -- Set the number of string items to 0
    ret[key] = 0

    return ret
  end

  StringBuffer.Append = function(buf,str)
    -- Make sure we have a valid StringBuffer
    if type(buf) ~= "table" or buf[key] == nil then return nil end

    -- Append only strings
    str = tostring(str)

    -- Only concatenate now if the string is larger... Tower of Hanoi
    while buf[key] > 0 and string.len(buf[buf[key]-1]) < string.len(str) do
      str = buf[buf[key]-1] .. str
      buf[buf[key]-1] = nil
      buf[key] = buf[key] - 1
    end

    -- Drop it on the end
    buf[buf[key]] = str
    buf[key] = buf[key] + 1

    -- Return the buffer
    return buf
  end

  -- Collapse the list down to a single string
  StringBuffer.Get = function(buf)
    while buf[key] > 1 do
      buf[key] = buf[key] - 1
      buf[buf[key]-1] = buf[buf[key]-1] .. buf[buf[key]]
      buf[buf[key]] = nil
    end

    return tostring(buf[0])
  end

  StringBuffer.Clear = function(buf)
    -- Remove strings from the buffer
    while buf[key] > 0 do
      buf[buf[key]] = nil
      buf[key] = buf[key] - 1
    end

    -- Return the buffer
    return buf
  end
end

-- Base64 Functions
do
  -- Bitwise shift functions
  local function lsh(v,shift)
    return math.mod((v*(2^shift)),256)
  end
  local function rsh(v,shift)
    return math.floor(v/2^shift)
  end
  
  Base64 = {
    -- The 64 characters that will be used for Base64 encoding/decoding,
    --  plus one more for placeholding
    --  Note: Base64 encoding is NOT encryption.
    Table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=",

    -- The function to encode a set of data
    Encode = function(self,input)
      -- Sets of 3 characters get converted to sets of 4 character output
  
      local t = self.Table
      local output = StringBuffer.New()
  
      local len = string.len(input)
      local bytes = {}
  
      -- Encode three bytes at a time
      for i=0,len-1,3 do
        bytes[1] = 0
        for j=1,3 do
          local working = string.byte(input,i+j) or 0
  
          bytes[j] = string.byte(t,
            bytes[j] + rsh(working,j*2)
          +1)
          bytes[j+1] = math.mod(lsh(working,6-j*2),64)
        end
        bytes[4] = string.byte(t,math.mod(bytes[4],64)+1)
  
        -- Fix placeholders
        if len-i < 3 then bytes[4] = string.byte(t,65) end
        if len-i < 2 then bytes[3] = string.byte(t,65) end
  
        -- Add 4 bytes to the output buffer
        output:Append(string.char(unpack(bytes)))
      end
  
      return output:Get()
    end,
    Decode = function(self,input)
      -- Sets of 4 characters get converted back to sets of 3 ASCII characters
  
      local t = self.Table
      local output = StringBuffer.New()
  
      local len = string.len(input)
      for i=0,len-1,4 do
        for j=1,3 do
          -- Get the two bytes that make up the character
          local byte1 = string.find(t,string.sub(input,i+j,i+j),1,true) - 1
          local byte2 = string.find(t,string.sub(input,i+j+1,i+j+1),1,true) - 1
  
          -- Check for placeholders
          if byte1 == 64 or byte2 == 64 then break end
  
          -- Add the character
          output:Append(string.char(
            lsh(byte1,j*2) + rsh(byte2,6-j*2)
          ))
        end
      end

      return output:Get()
    end,
  }
end

-- Serialization Functions
--  (original version based loosely on http://www.lua.org/pil/12.1.2.html)
do
  local function SerializePart(self,name,val,format,args,saved)
    if name then
      format:Append(name):Append(" = ")
    end

    local t = self[type(val)]
    if type(t) == "table" then
      format:Append(t.format)
      args.n = args.n + 1
      if t.prepare then
        args[args.n] = t.prepare(val)
      else
        args[args.n] = val
      end

      -- Check if args is getting unusually large
      if args.n > 100 then
        args[1] = string.format(format:Get(),unpack(args))
        format:Clear():Append("%s")
        args.n = 1
      end
    else
      -- No actual value, but this signals a tail-call
      return t(self,name,val,format,args,saved)
    end
  end

  Serialize = setmetatable({
    ["string"] = {
      format = "%q",
    },
    ["function"] = {
      format = "\"base64:%s\"",
      prepare = function(val)
        local success,ret = pcall(string.dump,val)
        if success then
          return Base64:Encode(ret)
        else
          return "string.dump error"
        end
      end,
    },
    ["table"] = function(self,name,val,format,args)
      -- Note: No concept of "saved" because there is no way to
      --    reference earlier parts of the table until the whole
      --    table has been closed.
      local ret
      if format and args then
        ret = false
      else
        ret = true
        format = StringBuffer:New()
        if name then
          format:Append(name):Append(" = ")
        end
        args = {n=0,}
      end
  
      -- Begin the table
      format:Append("{")
  
      -- Serialize each key and value
      for k,v in pairs(val) do
        -- Serialize the key first
        format:Append("[")
        SerializePart(self,nil,k,format,args)
        format:Append("]=")

        -- Then serialize the value
        SerializePart(self,nil,v,format,args)
        format:Append(",")
      end
  
      format:Append("}")
  
      if ret then
        args.n = nil
        return string.format(format:Get(),unpack(args))
      end
    end,
  },{
    __index = function(self,idx)
      return {
        format = "%s",
        prepare = tostring,
      }
    end,
    __call = function(self,name,val)
      -- Check if a name was specified
      if not val then
        val = name
        name = nil
      end

      -- Determine the type of value to serialize
      local t = self[type(val)]
  
      if type(t) == "table" then
        -- Prepare the data and then format it
        if t.prepare then val = t.prepare(val) end
        if name then
          return name .. " = " .. string.format(t.format,val)
        else
          return string.format(t.format,val)
        end
      else
        return t(self,name,val)
      end
    end,
  })
  
  SerializeFull = setmetatable({
    ["table"] = function(self,name,val,format,args,saved)
      local ret
      if format and args then
        ret = false
      else
        ret = true
        format = StringBuffer:New():Append(name):Append(" = ")
        args = {n=0,}
      end
      saved = saved or setmetatable({},{__mode="k",})
      
      -- Check if this value already has a name
      if saved[val] then
        if ret then
          return format:Append(saved[val]):Get()
        else
          format:Append(saved[val])
          return
        end
      else
        saved[val] = name
      end

      -- Serialize each element
      format:Append("{}")

      for k,v in pairs(val) do
        format:Append("\n")

        -- Serialize the key
        local field
        if saved[k] then
          field = saved[k]
        else
          local t = type(k)
          if t ~= "table" then
            t = self[t]
            if t.prepare then
              field = string.format(t.format,t.prepare(k))
            else
              field = string.format(t.format,k)
            end
          else
            args.private = (args.private or 0) + 1
            field = "private_key_" .. args.private
            saved[k] = field
            format:Append(self:table(field,k)):Append("\n")
          end
        end
        field = string.format("%s[%s]",name,field)

        -- Serialize the value
        SerializePart(self,field,v,format,args,saved)
      end

      -- Check if this is the function that will ultimately return
      if ret then
        -- Format the string and return it
        return string.format(format:Get(),unpack(args))
      end
    end,
  },{
    __index = Serialize,
    __call = function(self,name,val)
      -- Determine the type of value to serialize
      local t = self[type(val)]

      if type(t) == "table" then
        -- Prepare the data and then format it
        if t.prepare then val = t.prepare(val) end
        return name .. " = " .. string.format(t.format,val)
      else
        return t(self,name,val)
      end
    end,
  })
end
