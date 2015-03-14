

# Configuration Basics #

Rampage AI Lite configuration is split between two files: Config.lua, and the state-file. The Config.lua file holds only the most basic options for operation of Rampage AI Lite. By contrast, the state-file holds most settings and information related to the current state of the AI.

# The Config.lua File #

The options in the Config.lua file will affect all users of RAIL, regardless of character ID, or homunculus/mercenary. It is recommended to change settings in this file before the first-run of RAIL. Further information can be found on the [The Config.lua File](ConfigLuaFile.md) wiki page.

# The State File #

The second file, called the state-file, is generated and verified by Rampage AI Lite. This file will be created in the Ragnarok Online directory _(**not** in the_USER`_`AI_directory)_. It is separate from the rest of the RAIL files to discourage accidental modification of core RAIL files. The Rampage AI Lite state-files will be named _RAIL`_`State._xyz_.lua_, where _xyz_ indicates the type of AI: "merc" for mercenary, or "homu" for homunculus. Additionally, RAIL can be set (in the Config.lua file) to include the character ID in the state-file filename, which allows separate settings between characters.

In addition to settings for the AI, the state-file also contains information such as the owner's ID, the homunculus/mercenary's ID, the time that buffs will wear off, etc. This file is both read-from and written-to regularly, which allows interaction with GUI programs and mercenary-homunculus interaction for alchemists. Further, it allows updates to the settings without resetting the entire AI (via teleport, map-change, etc).

_Note: Changes to the settings must be indicated by use of a special option (described in [the state-file index](StateFileIndex.md)) inside the state-file._

It is recommended to modify the state-file only after using RAIL for a short period of time. Settings are written to the file only after the first use. For example, no battle options will appear inside the state-file until after RAIL has encountered a monster. Advanced users may skip this step, and add settings that RAIL has not written yet.

If Rampage AI Lite cannot read the settings _(for example, if the syntax would cause a Lua error)_, then it will rewrite the state-file from scratch. Once the state-file has been loaded successfully, all settings are verified as used. If, for example, the setting `MaxDistance` is set to `"Hello"`, then RAIL will convert `MaxDistance` back to default. In this way, it is impossible for an invalid state-file to cause an error in the Ragnarok Online client.

For further information on configuring the state-file, please view [a default state-file](DefaultStateFile.md) and [the state-file index](StateFileIndex.md).