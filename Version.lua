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

-- Changelog
--	Note: View the subversion commit notes for more full changelog.
--		(This is maintained to regularly bump version number.)

-- 2010-05-12 -- Split DecisionSupport.lua's targeting functions to TargetingSupport.lua; Added idle-handling code; Other small tweaks
-- 2010-05-04 -- Fix for buff-initialization causing error; Added more to fake GetV() function to aid debugging.
-- 2010-04-26 -- Replace AssistOwner and AssistOther with AssistOptions subtable
-- 2010-04-26 -- Change FollowDistance to only take effect when Owner is still moving.
-- 2010-04-26 -- Fixed State.lua not properly protecting RO client from state-file errors; added DisableChase state-file option; Chase fixes
-- 2010-04-23 -- Tweak to new MobID
-- 2010-04-23 -- Completed State.lua's require replacement function, added options for strings; redo MobID code
-- 2010-04-06 -- Made targets public as part of RAIL object; restructured owner chase; reworked skill AIs; see SVN log for more
-- 2010-03-24 -- Reimplement logic to default plants at 1 priority below other default monsters; Small fixes
-- 2010-03-23 -- Rework of actor options setup; Updates to state file handling; Include AMCs; Bug fixes.
-- 2010-03-16 -- Changes to skill state-file options
-- 2010-03-16 -- Minor changes to AI and AI_M files; modification to urgent escape usage
-- 2010-03-15 -- Small fixes to actor ignore and buff skills
-- 2010-03-15 -- Reworked Buff skill AIs; added Base64 and function support to State
-- 2010-03-13 -- Fixed ignore actor triggering while close enough to attack
-- 2010-03-13 -- First commit of Version.lua

