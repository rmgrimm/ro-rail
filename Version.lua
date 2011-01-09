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

-- 2011-01-09 -- Fix actor-targeted AoE skills. Revamp the simulation in Utils.lua
-- 2011-01-08 -- Add obstacle detection.
-- 2011-01-07 -- Fix State.lua loading functions from the state-file.
-- 2011-01-06 -- Fix a few minor logical errors; Fix MaxSkillLevel; Add TargetCondition option for actors; Amistr will fix incorrect position after castling
-- 2010-12-15 -- Minor tweaks
-- 2010-12-14 -- Revision 200: Implement AoE skills
-- 2010-12-13 -- Move KiteMode options to ActorOpts.lua; implement better idle-return; implemented screen-wide actor friending/unfriending.
-- 2010-12-05 -- Reimplement HealOwner and HealSelf skill AIs
-- 2010-12-04 -- Implemented logging for first occurrence of actor types not in state-file; Changed Provoke skill AI type to Debuff and PartySupport.
-- 2010-12-03 -- Implementation of some TODOs; rewrite of AutoPassive; Implement MaintainTargetsWhilePassive
-- 2010-11-26 -- Implement PartySupport skills; Fix accidental naming error
-- 2010-11-25 -- Added new state-file option BeginChaseDistance; Added early-cancelation conditions to DelayFirstAction
-- 2010-11-23 -- Fix a bugs for AI types without attack skills
-- 2010-11-22 -- Fix commands to work with new SkillState
-- 2010-11-22 -- Chasing to get into skill/attack range now chases into pythagorean distance range (as opposed to block range); kiting priority decreases as range from monster increaes
-- 2010-11-22 -- Various bug fixes; Refactoring of SkillSupport into SkillState, now supports ground-skill targeting; New state-file options: SkillOptions.RampageMode and SkillOptions.Timeout
-- 2010-11-21 -- Fix Chase selection so that it assumes non-generated ChaseMap locations have priority 0; this fixes kiting mode.
-- 2010-11-21 -- Reimplement AttackWhileChasing, code clean ups, fix out-of-range targeting
-- 2010-11-21 -- Rewrite TileMap.lua, optimize Chase selection to not generate tile tables.
-- 2010-11-21 -- Fix for unimplemented skills, fix numbering of homunculi.
-- 2010-11-21 -- Massive restructuring of code into event-based system. Most user options stayed the same, but performance should be better.
-- 2010-09-17 -- Fix IsEnemy's metatable (was preventing the friend system from working)
-- 2010-09-16 -- Chase targeting will now check skill ranges as well; MaxDistance cap removed
-- 2010-06-19 -- Add AutoPassiveHP, AutoPassiveHPisPercent, AutoUnPassiveHP options
-- 2010-06-19 -- Add ReservedSP and ReservedSPisPercent for each skill. Set Filir's Moonlight condition to "attacking"
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

