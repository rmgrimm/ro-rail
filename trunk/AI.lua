-- Create a RAIL object (to be populated later)
if not RAIL then
	RAIL = {}
end

-- Now auto-detect where RAIL is located
do
	local req = require

	function FileExists(filename)
		-- Try to open the file
		local file = io.open(filename)
		if file then
			file:close()
			return true
		end
		return false
	end

	local function CheckVersion(path,prev_ver,prev_path,prev_env)
		-- Check for MainRAIL.lua, to ensure Version.lua doesn't come from another script
		if not FileExists(path .. "MainRAIL.lua") then
			-- Can't read RAIL from here
			return -1
		end

		-- Load version file
		local success,f = pcall(loadfile,path .. "Version.lua")

		-- Check that it loaded okay
		if not success or not f then return -1 end

		-- Set environment
		local env = { ["RAIL"] = {}, ["string"] = string }
		setfenv(f,env)

		-- Call the function
		local ver
		success = pcall(f)

		-- Check if the protected call succeeded
		if not success then return -1 end

		-- Check for the RAIL object's Version property
		if not env.RAIL or not env.RAIL.Version then return -1 end

		-- Check against previous version
		if env.RAIL.Version > prev_ver then
			return env.RAIL.Version, path, env
		else
			return prev_ver, prev_path, prev_env
		end
	end

	-- Find the highest version of RAIL
	local ScriptVersion,ScriptLocation,penv = CheckVersion("./")
	ScriptVersion,ScriptLocation,penv = CheckVersion("./AI/",ScriptVersion,ScriptLocation,penv)
	ScriptVersion,ScriptLocation,penv = CheckVersion("./AI/USER_AI/",ScriptVersion,ScriptLocation,penv)

	-- If all else failed, make sure the RO client doesn't crash
	if ScriptVersion < 0 then
		TraceAI("RAIL failed to locate script directory.")
		RAIL.CantRun = true
		AI = function() end
	end

	-- Copy version information from the protected environment (created in CheckVersion)
	RAIL.Version = penv.RAIL.Version
	RAIL.FullVersion = penv.RAIL.FullVersion

	-- Replace the require function with one that uses RAIL's autodetected location
	require = function(filename)
		if FileExists(filename) then
			return req(filename)
		end

		return req(ScriptLocation .. filename)
	end
end

-- Only continue if autodetection worked
if not RAIL.CantRun then
	-- The only difference between AI_M.lua and AI.lua is this following line
	RAIL.Mercenary = false
	require "MainRAIL.lua"
end
