

# Introduction #

The Config.lua file is the first of two files used to configure Rampage AI Lite. Unlike the state-file, the config.lua file contains only the most basic options to configure RAIL. It is recommended to leave the options in this file at default values, except under special circumstances.

# Config.lua Options #

## RAIL.StateFile ##

This option contains the filename and path to the main state-file for Rampage AI Lite. It allows patterns to be used to differentiate state files between character ID, homu/merc, and RAIL revision number.

The following patterns are allowed in the file specification:
  * `{1}` will expand to the character ID number.
  * `{2}` will expand to "`merc`" for mercenaries, and "`homu`" for homunculi.
  * `{3}` will expand to the numerical revision number.

The recommended values are:
  * `RAIL.StateFile = "RAIL_State.{2}.lua"`, or
  * `RAIL.StateFile = "RAIL_State.{1}.{2}.lua"`
_Note: These values will be compatible with versions of RAIL older than [revision 145](https://code.google.com/p/ro-rail/source/detail?r=145)._

The first will differentiate only by homunculi and mercenary; that is, all homunculi--regardless of character--will use the same settings. Similarly, all mercenaries will also use the same settings. However, homunculi and mercenaries will use different settings, even if used simultaneously. The second example will separate all settings between all characters and AI types. This is useful for specialized setups, or when running multiple copies of Rampage AI simultaneously.

## RAIL.UseTraceAI ##

This option specifies whether Rampage AI Lite should make use of Ragnarok Online's `TraceAI()` function. If set to false, Rampage AI Lite will output logging information to a file specified by the [state-file's DebugFile option](StateFileIndex#DebugFile.md).

Under normal circumstances, the default value is recommended:
```
RAIL.UseTraceAI = true
```

When the TraceAI.txt file becomes too large, the Ragnarok Online client will begin to work very slowly (500ms or longer when using `TraceAI()`). Because of this limitation in Ragnarok Online, it is recommended to set this value to false when debugging or learning about the way RAIL works:
```
RAIL.UseTraceAI = false
```
RAIL's custom logging allows separation between log files. This allows greater separation between log information, and works around the Ragnarok Online limitation specified above.

## RAIL.TranslationFile ##

_This isn't currently implemented in Rampage AI Lite._