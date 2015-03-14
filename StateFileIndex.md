

# Introduction #

The Rampage AI Lite state-file contains all configuration relating to behavior of the AI. In addition, it also contains information regarding the current-state of the AI (for example, the ID number of the homunculus/mercenary).

The state-file options are verified as they are used, so it is impossible to cause a Lua error when changing options. Further, corrected values are saved back into the state-file.

Because of the way the state-file is saved, it is impractical to maintain user-comments or values outside of the rail\_state table. The order of options may also change. Please avoid storing important information inside of the RAIL state file.

# Finding Your State-File #

By default, your state-file is located in the base Ragnarok Online directory. (See [Before You Begin: Locate your Ragnarok Online directory](http://code.google.com/p/ro-rail/wiki/FirstTimeInstall#Before_You_Begin:_Locate_your_Ragnarok_Online_directory) for more information on finding your Ragnarok Online directory.) The [RAIL.StateFile](http://code.google.com/p/ro-rail/wiki/ConfigLuaFile#RAIL._StateFile) option in the Config.lua file will specify the filename.

With default filename, the image below shows the state-file for a Rampage AI Lite-controlled mercenary. Notice that the default of `"RAIL_State.{2}.lua"` was automatically expanded to `"RAIL_State.merc.lua"` for the mercenary AI.

![http://ro-rail.googlecode.com/svn/wiki/img/find-state-file.png](http://ro-rail.googlecode.com/svn/wiki/img/find-state-file.png)

Once you've located the state-file, it is safe to open it in Microsoft Notepad or any other text-editor.

_Note: Vista users will have problems editing the state-file if it is inside the_Program Files_directory. Please make sure your copy of Ragnarok Online is installed outside of this folder._

# An Important Note #

All options shown on this page will appear in the state-file similar to the following:
```
rail_state["Aggressive"] = false
```
In this example, the option is [Aggressive](StateFileIndex#Aggressive.md), and the option is set to `false`.

The names of the options in the state-file (eg, "[Aggressive](StateFileIndex#Aggressive.md)") are all case-sensitive. In other words, the option "aggRESsive" will not have any relation to the option "[Aggressive](StateFileIndex#Aggressive.md)". When adding new options, be careful to note that the capitalization matches what is shown on this page.

# Options Index #

## Base Options Table ##

### AcquireWhileLocked ###

_This option was removed in [revision 191](http://code.google.com/p/ro-rail/source/detail?r=191). Please refer to [AutoPassive Sub-table](StateFileIndex#AutoPassive_Sub-table.md)._

<a href='Hidden comment: 
*Type:* Boolean

*Default:* false

When set to true, !AcquireWhileLocked will cause the AI to actively seek targets that are outside of its attack range, even while attacking. Because this causes melee-range mercenaries/homunculi to run away from their attack target, it is recommended to enable only for long-range mercenaries.

*See also:* [StateFileIndex#AttackWhileChasing AttackWhileChasing]
'></a>

### Aggressive ###

**Type:** Boolean

**Default:** `false`

When set to `true`, Aggressive will cause the AI to actively search for new targets.

_Note: This option can be changed from inside the Ragnarok Online client by pressing `<ALT+T>` for a homunculus, or `<CTRL+T>` for a mercenary. Changes made by this key-press will be saved._

### AttackWhileChasing ###

**Type:** Boolean

**Default:** `false`

AttackWhileChasing allows Rampage AI Lite to attack a target that is within range even if it is moving toward a higher priority monster that is outside range. When set to `true`, this allows Rampage AI Lite to maximize the number of attacks it makes. When set to `false`, Rampage AI Lite will be able to move more quickly to the highest priority target.

_Note: This is only recommended for long-range attacks such as archer mercenaries._

### ~~AutoPassiveHP~~ ###

_This option was removed in [revision 191](http://code.google.com/p/ro-rail/source/detail?r=191). Please refer to [AutoPassive Sub-table](StateFileIndex#AutoPassive_Sub-table.md)._

<a href='Hidden comment: 
*Type:* Number

*Default:* 0

*Minimum Value:* 0

*Maximum Value:* no maximum value if [StateFileIndex#AutoPassiveHPisPercent AutoPassiveHPisPercent] is false; otherwise, 99

When Rampage AI Lite determines that its HP value has dropped below the setting of AutoPassiveHP, it will enter a temporary passive mode. This temporary passive mode has the same effect as setting [StateFileIndex#Aggressive Aggressive] to false, but does not make any change to the state-file. This mode will automatically be disabled when the HP value rises to the value specified in the [StateFileIndex#AutoUnPassiveHP AutoUnPassiveHP] option.

_Note: If the [StateFileIndex#DefendOptions_Sub-table DefendOptions Sub-table] options [StateFileIndex#DefendWhilePassive DefendWhilePassive] is set to false, it is likely that this will cause Rampage AI Lite to stop attacking any monster that reduced its HP below the level set by this option._

*See also:* [StateFileIndex#AutoPassiveHPisPercent AutoPassiveHPisPercent]; [StateFileIndex#AutoUnPassiveHP AutoUnPassiveHP]
'></a>

### ~~AutoPassiveHPisPercent~~ ###

_This option was removed in [revision 191](http://code.google.com/p/ro-rail/source/detail?r=191). Please refer to [AutoPassive Sub-table](StateFileIndex#AutoPassive_Sub-table.md)._

<a href='Hidden comment: 
*Type:* Boolean

*Default:* false

AutoPassiveHPisPercent specifies whether the values in [StateFileIndex#AutoPassiveHP AutoPassiveHP] and [StateFileIndex#AutoUnPassiveHP AutoUnPassiveHP] should be interpreted as percentages.

*See also:* [StateFileIndex#AutoPassiveHP AutoPassiveHP]; [StateFileIndex#AutoUnPassiveHP AutoUnPassiveHP]
'></a>

### ~~AutoUnPassiveHP~~ ###

_This option was removed in [revision 191](http://code.google.com/p/ro-rail/source/detail?r=191). Please refer to [AutoPassive Sub-table](StateFileIndex#AutoPassive_Sub-table.md)._

<a href='Hidden comment: 
*Type:* Number

*Default:* [StateFileIndex#AutoPassiveHP AutoPassiveHP] + 1

*Minimum Value:* [StateFileIndex#AutoPassiveHP AutoPassiveHP] + 1

*Maximum Value:* unlimited if [StateFileIndex#AutoPassiveHPisPercent AutoPassiveHPisPercent] is false; otherwise, 100

_Please see the description under [StateFileIndex#AutoPassiveHP AutoPassiveHP].

*See also:* [StateFileIndex#AutoPassiveHP AutoPassiveHP]; [StateFileIndex#AutoPassiveHPisPercent AutoPassiveHPisPercent]
'></a>

### BeginFollowDistance ###

**Type:** Number

**Default:** -1

**Minimum Value:** _The value of [FollowDistance](StateFileIndex#FollowDistance.md)_

**Maximum Value:** _The value of [MaxDistance](StateFileIndex#MaxDistance.md)_

This option specifies the number of tiles away from the owner before Rampage AI Lite begins chasing after its owner. If Rampage AI Lite detects your character begins movement that will place it outside of this range, it will spend all resources in attempt to move within the the range specified by [FollowDistance](StateFileIndex#FollowDistance.md).

If the value of BeginFollowDistance is set to `-1`, then it will be automatically calculated based on [MaxDistance](StateFileIndex#MaxDistance.md).

**See also:** [FollowDistance](StateFileIndex#FollowDistance.md); [MaxDistance](StateFileIndex#MaxDistance.md)

### DanceAttackTiles ###

**Type:** Number

**Default:** -1

**Minimum Value:** -1

**Maximum Value:** 1

This option specifies the number of tiles that the AI should attempt to move away from itself after every attack or skill. This allows homunculi to ignore sprite-delay in attacks and mercenaries to ignore sprite-delay in skills.

_Note: Rampage AI Lite will stay within [MaxDistance](StateFileIndex#MaxDistance.md) while "dancing"._

**See also:** [MaxDistance](StateFileIndex#MaxDistance.md)

### DebugFile ###

**Type:** String

**Default:** `"RAIL_Log.{2}.lua"`

The DebugFile option specifies where RAIL's logs should be output to. It allows pattern expansion in a similar manner as the [Config.lua StateFile option](ConfigLuaFile#RAIL._StateFile.md). Multiple instances of RAIL can simultaneously use the same log file without problem.

_Note: If the [Config.lua UseTraceAI option](ConfigLuaFile#RAIL.UseTraceAI.md) is set to `true`, then this option will have no effect._

**See also:** [DebugLevel](StateFileIndex#DebugLevel.md); [ProfileMark](StateFileIndex#ProfileMark.md)

### DebugLevel ###

**Type:** Number

**Default:** `50`

**Maximum Value:** `99`

This option sets the verbosity of RAIL logging, with higher numbers being more verbose. Unless troubleshooting or learning about RAIL, this option should be ignored.

_Note: Debug levels for various log messages can be found at the top of http://ro-rail.googlecode.com/svn/trunk/Debug.lua._

**See also:** [DebugFile](StateFileIndex#DebugFile.md); [ProfileMark](StateFileIndex#ProfileMark.md)

### DelayFirstAction ###

**Type:** Number

**Default:** `0`

**Minimum Value:** `0`

This option prevents Rampage AI Lite from taking action for the specified number of milliseconds. This will cancel automatically if the owner moves, or manually issues a command to the AI.

_Note: This may be desirable in order to maintain the invulnerability time of the player. If the AI moves the homunculus before the invulnerability time has worn off, then the **player** becomes vulnerable to attacks. Due to the way homunculus and mercenaries are treated, they will **never** have invulnerable time._

### ~~DisableChase~~ ###

_This option was removed in [revision 175](http://code.google.com/p/ro-rail/source/detail?r=175). Please refer to [ActorOptions Sub-table](StateFileIndex#ActorOptions_Sub-table.md)._

### FollowDistance ###

**Type:** Number

**Default:** `4`

**Minimum Value:** `0`

**Maximum Value:** _The value of [MaxDistance](StateFileIndex#MaxDistance.md)_

Once Rampage AI Lite begins following the owner (your character) due to [MaxDistance](StateFileIndex#MaxDistance.md), it will only stop under two conditions:
  1. Your character stops moving; or
  1. Rampage AI Lite manages to get close enough to its owner.
FollowDistance indicates how close RAIL needs to be before it decides it is "close enough" and resumes normal operation.

**See also:** [BeginFollowDistance](StateFileIndex#BeginFollowDistance.md); [MaxDistance](StateFileIndex#MaxDistance.md)

### MaxDistance ###

**Type:** Number

**Default:** `13`

**Minimum Value:** `0`

This option specifies the maximum distance (in tiles) that Rampage AI Lite should stray. RAIL will still move to attack enemies outside of this area, provided it has a long enough attack or skill range (eg, archer mercenaries).

**See also:** [BeginFollowDistance](StateFileIndex#BeginFollowDistance.md); [FollowDistance](StateFileIndex#FollowDistance.md);

### MobIDFile ###

**Type:** String

**Default:** `"./AI/USER_AI/Mob_ID.lua"`

MobIDFile specifies the file to communicate monster types with. It is recommended to leave this setting at default, except under special circumstances.

**Warning:** MobIDFile does _not_ support `{n}` pattern expansion. (For more information on pattern expansion, refer to the [Config.lua StateFile option](ConfigLuaFile#RAIL._StateFile.md).)

_Note: The default setting is compatible with Azzy AI's Mob ID feature._

**See also:** [MobIDMode](StateFileIndex#MobIDMode.md)

### MobIDMode ###

**Type:** String

**Default:** `"automatic"`

MobIDMode is the main switch for Rampage AI Lite's Mob-ID communication support. When active, this feature allows Mercenary-type AIs to determine monster type with help from a Homunculus-type AI. The accepted values vary by the type of AI.

For AIs that are able to distinguish monster-type (eg, Homunculus):
  * `"disabled"` will not use Mob-ID communication. This will prevent Rampage AI Lite from creating or changing the file specified in [MobIDFile](StateFileIndex#MobIDFile.md).
  * `"automatic"` will automatically enable use of Mob-ID communication when Rampage AI Lite is paired (eg, Homunculus and Mercenary are both active simultaneously). This is the recommended value for standard use.
  * `"overwrite"` will recreate the [MobIDFile](StateFileIndex#MobIDFile.md) each time Rampage AI Lite is loaded. Changing maps will clear all previous ID-to-type entries.
  * `"update"` will only update the [MobIDFile](StateFileIndex#MobIDFile.md) as new monsters (or changed-types) are found. Old values will remain unchanged. This is recommended only when generating a MobID file while teleporting within the same map.

For AIs that are _not_ able to distinguish monster-type (eg, Mercenary):
  * `"disabled"` never loads the [MobIDFile](StateFileIndex#MobIDFile.md). Rampage AI Lite will be unable to distinguish monster types.
  * `"automatic"` will automatically enable use of Mob-ID communication when Rampage AI Lite is paired (eg, Homunculus and Mercenary are both active simultaneously). This is the recommended value for standard use.
  * `"once"` will only read the [MobIDFile](StateFileIndex#MobIDFile.md) when Rampage AI Lite starts. This provides compatibility for pre-generated tables (for example, generated by `"update"` or `"overwrite"` above).
  * `"active"` rereads the [MobIDFile](StateFileIndex#MobIDFile.md) whenever Rampage AI Lite encounters an actor that is not in the loaded Mob-ID table. This should not be used unless the [MobIDFile](StateFileIndex#MobIDFile.md) is being actively updated. (_Note: This mode is unable to detect monster-type changes._)

**See also:** [MobIDFile](StateFileIndex#MobIDFile.md)

### ProfileMark ###

**Type:** Number

**Default:** `20000`

**Minimum Value:** `2000`

The ProfileMark option specifies how often Rampage AI Lite should log profiling information. This information includes average cycle time, memory usage, etc. If you are unsure what this means, it is safe to ignore this option.

**See also:** [DebugFile](StateFileIndex#DebugFile.md); [DebugLevel](StateFileIndex#DebugLevel.md)

### TempFriendRange ###

**Type:** Number

**Default:** `-1`

**Minimum Value:** `-1`

TempFriendRange sets the distance at which players will be temporarily considered "friends" for the purpose of defending, assisting, and disabling kill-steal protection. Players are considered friends only for the duration that they are within this range, and no permanent record is kept.

This range is counted by tiles from your character, from `0` to `5`. A value of `-1` indicates that no players should ever be counted as temporary friends.

**See also:** [AssistOptions Sub-table](StateFileIndex#AssistOptions_Sub-table.md); [DefendOptions Sub-table](StateFileIndex#DefendOptions_Sub-table.md)

### update ###

**Type:** Boolean

**Default:** `false`

The update option is a hidden option that causes a running RAIL instance to reload its state-file configuration. To change state-file options without resetting the AI completely, set this option to `true`.

_Note: Because this is a hidden option, it will only appear in the state-file after being manually added. If you wish to enable it, please manually type it into the bottom of the state-file. Afterward, you may simply change `false` to `true`._

**Warning:** Please notice that the first letter is not capitalized. This option must be entered completely lowercase to take effect.


## ActorOptions Sub-table ##

The ActorOptions Sub-table contains what is sometimes referred to as "monster tactics". In order to determine the appropriate course of action, Rampage AI Lite separates options into three categories: `"Default"`, `"ByType"`, and `"ByID"`. Each category accepts identical options and can refer to both players and monsters. The categories are described in more detail below:

  * `"ByID"` is the most specific category, and differentiates actors by their specific ID in Ragnarok. At most, ByID will refer to only one actor at a time. Because character IDs remain the same across all maps, this option is most useful when defining options for a specific player.
  * `"ByType"` refers to actors by their type, which can be found in various online databases. For example, all non-rebirthed alchemists are of type `18` while a poring has type `1002`. It is important to remember that while many monsters may share the same name, they may have different types. A prominent example of this is with summoned mobs. As an example: [Ghostring](http://ro.amesani.org/db/monster-info/1120/) spawns with a different type of Giant Whisper than he later summons.
    * When using [Amesani RO - Monster Info](http://ro.amesani.org/db/monster-info/), the monster ID will appear in the URL. With the example of Abysmal Knight, `http://ro.amesani.org/db/monster-info/`**1219**`/` shows the type as `1219`.
    * _Note: Without help from a [Mob-ID File](StateFileIndex#MobIDFile.md), Mercenaries are unable to distinguish monsters by type. Please refer to [MobIDMode](StateFileIndex#MobIDMode.md) for information on creating and using Mob-ID files._
  * `"Default"` contains the base options, used as defaults for all actors.

When a specific option is not found under a `"ByID"` table, Rampage AI Lite will then check `"ByType"`. If the option is not found in `"ByType"`, then the `"Default"` option will used. In this way, `"ByID"` options override `"ByType"`, which override `"Default"`.

For example:
```
rail_state["ActorOptions"]["Default"] = {}
rail_state["ActorOptions"]["Default"]["Priority"] = 0
rail_state["ActorOptions"]["ByType"][123] = {}
rail_state["ActorOptions"]["ByType"][123]["Priority"] = 15
rail_state["ActorOptions"]["ByID"][1234] = {}
rail_state["ActorOptions"]["ByID"][1234]["Priority"] = 50
```
In this example, a monster with ID `1234` would have a [Priority](StateFileIndex#Priority.md) value of 50, regardless of type. All monsters of type `123` would have a [Priority](StateFileIndex#Priority.md) of 15. All _other_ monsters would have a [Priority](StateFileIndex#Priority.md) of 0.

**Warning:** Note that the first line for any `"ByType"` or `"ByID"` value must set the ID/type to `{}`. **This is very important** because it is required for proper [Lua](http://www.lua.org/)-file interpretation. Failure to include this will prevent Rampage AI Lite from loading any state-file settings, and RAIL will subsequently generate a new state-file from scratch. Please see the [ActorOptions Example State-file](ActorOptionsExample.md) for more examples.

### AttackAllowed ###

**Type:** Boolean

**Default:** `true`

AttackAllowed specifies whether Rampage AI Lite should use physical attacks against a target. When both AttackAllowed and [SkillsAllowed](StateFileIndex#SkillsAllowed.md) are set to `false`, Rampage AI Lite will never target the specified monster or monsters.

_Note: When actor type can be distinguished (eg, on a homunculus), monsters of type `1555`, `1575`, `1579`, `1589`, and `1590` automatically use default setting of `false`. These are the 5 alchemist-summoned support monsters._

**See also:** [SkillsAllowed](StateFileIndex#SkillsAllowed.md)

### DefendOnly ###

**Type:** Boolean

**Default:** `false`

This option indicates that an actor should only be considered a target if it is attacking any of the following:
  * The homunculus or mercenary that Rampage AI Lite is controlling,
  * The owner of this homunculus or mercenary,
  * The owner's other AI (if any),
    * For a homunculus, this is the owner's mercenary.
    * For a mercenary, this is the owner's homunculus.
  * Any player that is marked as a [Friend](StateFileIndex#Friend.md) by the [ActorOptions Sub-table](StateFileIndex#ActorOptions_Sub-table.md)'s `"ByID"`, `"ByType"`, or `"Default"` categories, or
  * Any player that is within a range specified by [TempFriendRange](StateFileIndex#TempFriendRange.md).

**See also:** [AttackAllowed](StateFileIndex#AttackAllowed.md); [SkillsAllowed](StateFileIndex#SkillsAllowed.md)

### DisableChase ###

**Type:** Boolean

**Default:** `false`

When DisableChase is set to `true`, Rampage AI Lite will not attempt to move toward an enemy. The AI will only target the enemy if it is already in range of attacks or skills.

### FreeForAll ###

**Type:** Boolean

**Default:** `false`

FreeForAll indicates that specified target(s) should have kill-steal prevention code disabled. This is not recommended against non-MVP monsters, as players are often held accountable for their AI's behavior.

### Friend ###

**Type:** Boolean

**Default:** `false`

The Friend option indicates that a player should be considered a friend. This option has no effect for monsters or other non-player actors.

_Note: It is not advised to set this for the `"Default"` category of [ActorOptions](StateFileIndex#ActorOptions_Sub-table.md) because it will circumvent kill-steal prevention for all monsters._

### KiteDistance ###

**Type:** Number

**Default:** `-1`

**Minimum Value:** `1`

**Exceptional Values:** `-1` to disable

KiteDistance specifies the number of tiles that Rampage AI Lite should stay away from actor. The priority of the kiting will be the same as the actor's [Priority](StateFileIndex#Priority.md). Rampage AI Lite is designed in a way that will kite specified enemies at all times, even if they are not the primary target.

_Note: This only takes effect if the actor is an enemy. In non-PVP maps, for example, specified players will not be "kited" away from._

**See also:** [KiteMode](StateFileIndex#KiteMode.md)

### KiteMode ###

**Type:** String

**Default:** `"always"`

KiteMode specifies when Rampage AI Lite should begin keeping distance away from an enemy. The possible values are as follows:
  * `"always"` specifies that the AI should always maneuver away from the specified enemy.
  * `"tank"` will only cause the AI to move away from the specified enemy when the homunculus or mercenary is the target. Note that this will require the enemy to attack the homunculus or mercenary at least once before kiting is enabled

**See also:** [KiteDistance](StateFileIndex#KiteDistance.md)

### MaxCastsAgainst ###

**Type:** Number

**Default:** `-1`

**Minimum Value:** `-1`

MaxCastsAgainst sets the maximum number of times that Rampage AI Lite should cast an attack skill (eg, Caprice or Pierce) against the specified target(s). A value of `-1` indicates "infinity"; in other words, `-1` means that there is no limit to the number of times it should cast against the target(s).

_Note: If the target dies or moves off-screen, Rampage AI Lite will reset its count of casts against that target. Under certain circumstances, this may result in more casts against one target than MaxCastsAgainst allows._

**See also:** [MaxSkillLevel](StateFileIndex#MaxSkillLevel.md); [MinSkillLevel](StateFileIndex#MinSkillLevel.md); [SkillsAllowed](StateFileIndex#SkillsAllowed.md); [TicksBetweenSkills](StateFileIndex#TicksBetweenSkills.md)

### MaxSkillLevel ###

**Type:** Number

**Default:** `5` for homunculi; `10` for mercenaries

**Minimum Value:** `1`

**Maximum Value:** `5` for homunculi; `10` for mercenaries

MaxSkillLevel determines the maximum level of skill to be used against the specified target(s).

**See also:** [MaxCastsAgainst](StateFileIndex#MaxCastsAgainst.md); [MinSkillLevel](StateFileIndex#MinSkillLevel.md); [SkillsAllowed](StateFileIndex#SkillsAllowed.md); [TicksBetweenSkills](StateFileIndex#TicksBetweenSkills.md)

### MinSkillLevel ###

**Type:** Number

**Default:** `1`

**Minimum Value:** `1`

**Maximum Value:** `5` for homunculi; `10` for mercenaries

MinSkillLevel determines the minimum level of skill to be used against the specified target(s).

**See also:** [MaxCastsAgainst](StateFileIndex#MaxCastsAgainst.md); [MaxSkillLevel](StateFileIndex#MaxSkillLevel.md); [SkillsAllowed](StateFileIndex#SkillsAllowed.md); [TicksBetweenSkills](StateFileIndex#TicksBetweenSkills.md)

### Name ###

**Type:** String

**Default:** `"unknown"`

This is the name of the actor as it will show up in the TraceAI.txt or [DebugFile](StateFileIndex#DebugFile.md) files.

_Note: If the value is equal to the specified default name, then no name will be written to the log._

### Priority ###

**Type:** Number

**Default:** `1`

**Minimum Value:** `1`

Priority specifies a numerical value assigned to each target. After evaluating each potential target, Rampage AI Lite selects the target with the highest value. If multiple targets share the same value, Rampage AI Lite will select the closest among them. This follows the idea that "highest number is highest priority" instead of the opposing idea that "number one is first priority".

_Note: Certain options (such as the [AssistOptions Sub-table](StateFileIndex#AssistOptions_Sub-table.md) options) will reduce the list of potential targets before Rampage AI Lite evaluates each target's Priority value._

### SkillsAllowed ###

**Type:** Boolean

**Default:** `true`

SkillsAllowed specifies whether Rampage AI Lite should use skills against a target. When both SkillsAllowed and [AttackAllowed](StateFileIndex#AttackAllowed.md) are set to `false`, Rampage AI Lite will never target the specified monster(s).

_Note: When actor type can be distinguished (eg, on a homunculus), monsters of type `1078`-`1085`, `1555`, `1575`, `1579`, `1589`, and `1590` automatically use default setting of `false`. These include the 5 alchemist-summoned support monsters and inactive plant monsters (eg, "Red Plant" or "Black Mushroom")._

**See also:** [AttackAllowed](StateFileIndex#AttackAllowed.md); [MaxCastsAgainst](StateFileIndex#MaxCastsAgainst.md); [MaxSkillLevel](StateFileIndex#MaxSkillLevel.md); [MinSkillLevel](StateFileIndex#MinSkillLevel.md); [SkillOptions Sub-table](StateFileIndex#SkillOptions_Sub-table.md); [TicksBetweenSkills](StateFileIndex#TicksBetweenSkills.md)

### TicksBetweenSkills ###

**Type:** Number

**Default:** `0`

**Minimum Value:** `0`

This option specifies the number of ticks (or milliseconds) that Rampage AI Lite will wait between using skills against the specified actor.

**See also:** [MaxCastsAgainst](StateFileIndex#MaxCastsAgainst.md); [MaxSkillLevel](StateFileIndex#MaxSkillLevel.md); [MinSkillLevel](StateFileIndex#MinSkillLevel.md); [SkillsAllowed](StateFileIndex#SkillsAllowed.md)

## AssistOptions Sub-table ##

The AssistOptions Sub-table contains three settings related to the way Rampage AI Lite assists other players. Each settings is identical and works to classify the player into one of three groups:
  * `"Owner"` refers _only_ to Rampage AI Lite's owner; also known as your character.
  * `"Other"` refers _only_ to a paired homunculus or mercenary. For example, an alchemist's homunculus would refer to the same alchemist's mercenary as `"Other"`, and vice versa.
    * _Note: This only takes effect when both homunculus and mercenary are running Rampage AI Lite._
  * `"Friend"` refers to any player that is either:
    * explicitly marked as a [Friend](StateFileIndex#Friend.md), or
    * is within a certain number of tiles from your character (decided by [TempFriendRange](StateFileIndex#TempFriendRange.md)).

For clarity and simplicity, the following settings are described in terms of the above `"Owner"` category; however, each may be used for any category setting. The possible settings include:
  * `"assist"` indicates that Rampage AI Lite should prioritize attacking your target. If multiple categories are set to `"assist"`, Rampage AI Lite will select targets in this order: `"Owner"`, `"Other"`, and `"Friend"`. In other words, the `"Owner"`'s target will take precedence over all others.
  * `"avoid"` causes Rampage AI Lite to attack your target _only_ when no other enemies are available. If multiple categories are set to `"avoid"`, Rampage AI Lite will group the targets together. In this way, it will avoid all `"avoid"`ed targets together, or none at all.
  * `"indifferent"` has no effect on the normal targeting routines of Rampage AI Lite. This option is default.

Both `"assist"` and `"avoid"` take precedence over the [ActorOptions Sub-table](StateFileIndex#ActorOptions_Sub-table.md)'s [Priority](StateFileIndex#Priority.md) option and all [DefendOptions Sub-table](StateFileIndex#DefendOptions_Sub-table.md) options.

As an example, to optimize killing with a high-level pair of homunculus and mercenary:
Set the following in **both** `homu` and `merc` state-files:
```
rail_state["AssistOptions"]["Other"] = "avoid"
```

**Warning:** Setting **both** `homu` and `merc` state-file settings of `"Other"` to `"assist"` (as opposed to the above example of `"avoid"`) may result in low-priority targeting or other undesirable behavior.

## AutoPassive Sub-table ##

_Not written yet. Check back soon!_

## DefendOptions Sub-table ##

_Not written yet. Check back soon!_

## IdleMovement Sub-table ##

The IdleMovement sub-table contains options specific to how Rampage AI Lite should act when it is idle. RAIL is considered idle when it has not selected an attack target, a skill to use, or a desired position to move to.

### MoveType ###

**Type:** String

**Default:** `"none"`

This option specifies the form of movement that Rampage AI Lite should take after it has been idle for the time specified in [BeginAfterIdleTime](StateFileIndex#BeginAfterIdleTime.md).

The possible values are:
  * `"none"` - No action will be taken while idle.
  * `"return"` - If the homunculus/mercenary is outside of [FollowDistance](StateFileIndex#FollowDistance.md), then it will return to its owner while idle.

### BeginAfterIdleTime ###

**Type:** Number

**Default:** `3000`

**Minimum Value:** `0`

This specifies the number of milliseconds to wait before taking action while idle.

## Information Sub-table ##

The Information sub-table contains only settings used for diagnostic purposes. None of the values contained in the Information sub-table affect the way in which Rampage AI Lite operates.

## SkillOptions Sub-table ##

_Not written yet. Check back soon!_