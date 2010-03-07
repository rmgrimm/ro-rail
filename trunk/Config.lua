-- This configuration file holds only a very basic foundation of options for
--	Rampage AI Lite. More options will be held in your Ragnarok directory
--	after RAIL has been run at least once.



-- If SingleStateFile is set to false, configuration files will be specific
--	to the character ID. This will keep settings separate between all
--	characters that use the script (even on the same account).
--
--	When set to false, configuration files will be named
--	RAIL_State.xxxx.homu.lua and RAIL_State.xxxx.merc.lua, where xxxx
--	is the ID number of your character.
--
--	When set to true, configuration files will be named RAIL_State.homu.lua
--	and RAIL_State.merc.lua.
--
--	All files will be in your base Ragnarok Online directory (in other words,
--	the files will not be in your AI or AI\USER_AI directories).
RAIL.SingleStateFile = true

-- If UseTraceAI is set to false, logging will be redirected to a file specified
--	in the state file under the option "DebugFile".
RAIL.UseTraceAI = true

-- If uncommented, the following line would specify the translation file to use
--	for logging purposes. Messages not translated by the follow file will
--	default to en-US.
-- Note: This is not implemented yet.

-- RAIL.TranslationFile = "./AI/USER_AI/zh-cn.lua"

