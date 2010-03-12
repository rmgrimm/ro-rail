-- Version information
do
	RAIL.FullVersion = "$Id$"
	RAIL.Version = "$Rev$"

	-- Fix version into a number
	if string and string.len and string.sub then
		-- We can pull out the number from "$Rev$"

		if string.len(RAIL.Version) < 6 then
			-- Keyword wasn't updated by SVN; don't know version
			RAIL.Version = 0
		else
			RAIL.Version = tonumber(string.sub(RAIL.Version,5,-2))
		end
	else
		RAIL.Version = 0
	end
end

-- 2010-03-13 -- First commit of Version.lua

