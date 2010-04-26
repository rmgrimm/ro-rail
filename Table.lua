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
	
		-- Shift everythign forward
		local i
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
		local function do_deep_copy(v)
			local t = type(v)
			if t == "table" then
				-- Deep copy the table
				return Table.DeepCopy(v)
			elseif t == "function" then
				-- Make a full copy of the function
				return loadstring(string.dump(v))
			else
				-- Everything else
				return v
			end
		end

		function Table.DeepCopy(t,into,overwrite)
			-- Create a copy table
			local copy = into or {}

			-- Loop through all elements of the table
			for k,v in t do
				local new_k = do_deep_copy(k)

				if copy[new_k] == nil or overwrite then
					copy[new_k] = do_deep_copy(v)
				end
			end

			-- Check for a metatable
			local mt = getmetatable(t)
			if type(mt) == "table" then
				local deep_mt = getmetatable(copy)
				setmetatable(copy,Table.DeepCopy(mt,deep_mt,overwrite))
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
		for i,v in ipairs(list) do
			list[i] = nil
		end

		list.first = 0
		list.last = -1
	end

	function List.Size (list)
		return list.last - list.first + 1
	end
end

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

	StringBuffer.Get = function(buf)
		-- Collapse the list down to a single string
		while buf[key] > 1 do
			buf[key] = buf[key] - 1
			buf[buf[key]-1] = buf[buf[key]-1] .. buf[buf[key]]
			buf[buf[key]] = nil
		end

		return tostring(buf[0])
	end
end

