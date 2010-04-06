-- This configuration file holds only a very basic foundation of options for
--	Rampage AI Lite. More options will be held in your Ragnarok directory
--	after RAIL has been run at least once.



-- The following option contains the filename and path to the main state-file
--	for Rampage AI Lite. It allows patterns to be used to differentiate
--	state files between character ID, homu/merc, and RAIL revision number.
--
-- The following patterns are allowed in the file specification:
--	{1} - This will expand to the character ID number
--	{2} - This will expand to "merc" for mercenaries, and "homu" for homunculi
--	{3} - This will expand to the numerical revision number
--
-- The recommended values are:
--	"RAIL_State.{2}.lua",
--	"RAIL_State.{1}.{2}.lua"
-- These values will be compatible with older versions of RAIL. The first will differentiate
--	only by homunculi and mercenary; that is, all homunculi--regardless of character--will
--	use the same settings. Similarly, all mercenaries will also use the same settings. However,
--	homunculi and mercenaries will use different settings, even if used simultaneously. The second
--	example will separate all settings between all characters and AI types. This is useful for
--	specialized setups, or when running multiple copies of Rampage AI simultaneously.
RAIL.StateFile = "RAIL_State.{2}.lua"

-- If UseTraceAI is set to false, logging will be redirected to a file specified
--	in the state file under the option "DebugFile".
RAIL.UseTraceAI = true

-- If uncommented, the following line would specify the translation file to use
--	for logging purposes. Messages not translated by the follow file will
--	default to en-US.
-- Note: This is not implemented yet.

-- RAIL.TranslationFile = "./AI/USER_AI/zh-cn.lua"

