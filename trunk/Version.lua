-- Version information
do
	if not RAIL then
		RAIL = {}
	end

	RAIL.FullVersion = "$Id$"
	RAIL.Version = "$Rev$"

	-- Fix version into a number
	if string and string.len and string.sub then
		-- We can pull out the number from "$Rev$"

		if string.len(RAIL.Version) < 6 then
			-- Keyword wasn't updated by SVN; don't know version
			RAIL.Version = 0
		else
			RAIL.Version = tonumber(string.sub(RAIL.Version,7,-3))
		end
	else
		RAIL.Version = 0
	end
end

-- 2010-03-13 -- Fixed ignore actor triggering while close enough to attack
--	-- First commit of Version.lua

