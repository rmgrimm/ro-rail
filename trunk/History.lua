do
	-- History tracking
	History = {}


	-- Some 'private' keys for our history table
	local default_key = {}
	local list_key = {}
	local subtimes_key = {}
	local different_key = {}

	-- A helper funvtion to calculate values
	History.SubValue = function(a,b,target)
		-- Calculate the time difference ratio of A->B to A->Target
		local dest_ratio = (b[2] - a[2]) / (target - a[2])

		-- Divide the A->B value difference by the ratio,
		--	then apply it back to A to get the target value
		return a[1] + (b[1] - a[1]) / dest_ratio
	end

	local BinarySearch = function(list,target)
		-- left is older, right is newer
		local l,r = list.first,list.last
		local probe
		while true do
			probe = math.floor((l + r) / 2)

			if probe <= l then
				-- This must be the best one
				break
			end

			-- Check the time of the current probe position
			if target < list[probe][2] then
				-- Too new
				r = probe
			elseif target > list[probe][2] then
				-- New enough, search for a better one
				l = probe
			else
				-- If it's exact, go ahead and use it
				return probe,true
			end
		end

		return probe,false
	end

	local History_mt = {
		__index = function(self,key)
			local list = self[list_key]

			-- Check if we have any history
			if list:Size() < 1 then
				-- No history, return the default
				return self[default_key]
			end

			-- Check if we want the most recent
			if key == 0 then
				-- Return the most recent
				return list[list.last][1]
			end

			-- How many milliseconds into the past?
			--	negative indexes will "predict" future values
			local target = GetTick() - key

			-- If time older than history is requested, use default
			if target < list[list.first][2] then
				return self[default_key]
			end

			-- If time more recent than latest history, use it
			if target >= list[list.last][2] then
				if list:Size() < 2 or not self[subtimes_key] then
					-- Since size is only 1, we can't calculate
					return list[list.last][1]
				end

				return History.SubValue(list[list.last-1],list[list.last],target)
			end

			-- Otherwise, binary search for the closest item that isn't newer
			do
				local probe,exact = BinarySearch(list,target)

				if exact or not self[subtimes_key] then
					return list[probe][1]
				end

				return History.SubValue(list[probe],list[probe+1],target)
			end
		end,
		__newindex = function(self,key,val)
			-- Don't allow new entries to be created directly
		end,

		-- For consistency with Util wrappers in Actor.lua
		__call = function(self,key)
			return self[key]
		end,
	}

	local default_Different = function(a,b) return a[1] ~= b[1] end

	History.New = function(default_value,calc_sub_vals,diff_func)
		local ret = {
			[default_key] = default_value,
			[list_key] = List.New(),
			[subtimes_key] = calc_sub_vals,
			[different_key] = default_Different
		}
		setmetatable(ret,History_mt)

		if type(diff_func) == "function" then
			ret[different_key] = diff_func
		end

		return ret
	end

	History.Update = function(table,value)
		local list = table[list_key]
		local diff = table[different_key]

		-- New value
		value = {value,GetTick()}

		-- Make sure it's not a duplicate
		if list:Size() < 1 or diff(list[list.last],value) then
			list:PushRight(value)
			return
		end

		-- If we don't calculate sub-values, it won't matter
		if not table[subtimes_key] then return end

		-- Since sub-values are calculated, keep the beginning and end times
		if list:Size() < 2 or diff(list[list.last-1],list[list.last]) then
			list:PushRight(value)
			return
		end

		-- If there's already beginning and end, update the end
		list[list.last] = value
	end

	History.Clear = function(table)
		table[list_key]:Clear()
	end

	-- Find the most recent entry in a history that will return true from value
	History.FindMostRecent = function(table,value,search_after,search_before)
		-- TODO: Double-check logic of this function

		local list = table[list_key]

		-- If the list is empty, nothing can be found
		if list:Size() < 1 then
			return nil
		end

		-- Generate (or use) a function while searching
		local v_func
		if type(value) ~= "function" then
			-- Generate a function to check against value
			v_func = function(v)
				return v == value
			end
		else
			-- Use the function provided in value
			v_func = value
		end

		-- Validate search_after
		do
			if type(search_after) ~= "number" or search_after < 0 then
				-- Default at the current time
				search_after = 0
			end
	
			-- Determine the target tick count to begin searching after
			local target_after = GetTick() - search_after

			-- If the target tick count is smaller than the first entry, nothing will match
			if target_after < list[list.first][2] then
				return nil

			-- If the target tick count is greater than the most recent entry, begin searching at the most recent entry
			elseif target_after >= list[list.last][2] then
				search_after = list.last

			-- Otherwise, find the most appropriate list entry to begin searching from
			else
				local exact
				search_after,exact = BinarySearch(list,target_after)
			end
		end

		-- Validate search_before
		do
			if type(search_before) ~= "number" then
				search_before = GetTick()
			end

			-- Determine the target tick count to begin searching before
			local target_before = GetTick() - search_before

			-- If the target tick count is smaller than the first entry, use the first entry
			if target_before < list[list.first][2] then
				search_before = list.first

			-- If the target tick count is greater than the most recent entry, nothing will match
			elseif target_before >= list[list.last][2] then
				return nil

			-- Otherwise, find the most appropriate list entry to search until
			else
				local exact
				search_before,exact = BinarySearch(list,target_before)

				-- Ensure the time won't be after the target time
				search_before = search_before + 1
			end
		end

		-- Check that search_before references an older entry than search_after
		if search_before > search_after then
			return nil
		end

		-- Start from the determined search-after entry, and iterate until the oldest entry in the list
		local i
		for i=search_after,search_before,-1 do
			-- Check if the entry in the list matches
			if v_func(list[i][1]) then
				-- Return the number of ticks since the most-recent, matching entry
				return GetTick() - list[i][2]
			end
		end

		-- Nothing was found
		return nil
	end

	-- Return the list of values stored for this history (read-only)
	History.GetConstList = function(table)
		local ret = { }
		setmetatable(ret,{__index = table[list_key]})
		return ret
	end
end
