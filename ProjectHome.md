# Introduction #

Rampage AI Lite (RAIL) is a complete rewrite of Rampage AI from the ground up. It is written with the intent of being faster and more efficient. In addition, this rewrite takes into account the changes in Ragnarok since the last release of Rampage AI (eg, Mercenaries, Alchemist-skill removal, etc).

Visit the [Wiki](MainPage.md) for more information on installation and configuration of Rampage AI Lite!

# Feature Comparison #

| _**Features**_ | **Rampage AI Lite** | **Rampage AI Original** | **Other AIs** | **Description** |
|:---------------|:--------------------|:------------------------|:--------------|:----------------|
| _AI Code-Base_ | Custom-built (fast) | Sequencer (medium) | Default AI (slow) | RAIL features a custom-built code-base to ensure optimal performance in target selection and execution. |
| _Actor Tracking_ | Comprehensive | Limited | None | RAIL monitors information about all monsters, players, and even NPCs. Because of this, it is able to estimate movement speed, projected location, optimal intercept paths, and activity. This tracking also includes HP and SP trends of the owner, as well as skill success/failure and cast delay time. |
| _Actor Evasion_ | Active Multi-target | Experimental Single-target | Limited Single-target | RAIL actively monitors evasion distance settings and determines the optimal location to _kite_ monsters. |
| _Targeting Model_ | Separate Attack, Skill, and Chase Targets | Dual-target | Single-target | RAIL is able to target multiple actors simultaneously, selecting only the best for each action. |
| _Configuration System_ | Dynamic; Validated | Static; Checked | Static; Error-prone | RAIL verifies and corrects all state-file configuration as used. Even an improperly formatted state-file will not cause Ragnarok Online to display a Lua error. Further, RAIL updates the state-file with modified settings (such as aggressive/passive mode), so that they will continue even after map-change or teleport. |
| _Separate Configuration_ | Multiple; Configurable | One configuration | One or fewer available configurations | By default, RAIL separates configuration of homunculus and mercenary, and allows per-account configuration as well. Using different settings for different characters is easy. |
| _Mercenary Support_ | Identical Features | None | Limited Support | RAIL uses the exact same code for both homunculi and mercenaries, when available. _(Without use of a MobID file, mercenaries are unable to distinguish monster types.)_ |
| _Mercenary MobID Support_ | Active | N/A | Limited | RAIL borrows the idea behind AzzyAI's Mob\_ID.lua feature and brings it to the next level: RAIL actively updates the MobID file in real time. Mercenaries are able to perform along-side homunculi, even before the map has been pre-scouted! |
| _Skill Support_ | Extensive | Mixed | Mixed | RAIL provides extensive support for both homunculus and mercenary skills. Intelligent default settings emulate a real-player style, and full customization is available to fit specific needs. |

# GUI Configuration #

The current known GUI configuration utilities are:
  * [pyRAIL](http://code.google.com/p/pyrail/) by landsteiner - A GUI written in Python for any platform using wxGlade. **(recommended)**
  * [RAIL-GUI](http://code.google.com/p/ro-rail-gui) by Faithful - A GUI written in C#.NET for Windows platforms.
  * [RAIL Web-GUI](http://code.google.com/p/rail-web-gui/) by Kusanagi2k - A GUI written in HTML and JavaScript for any web browser.
Please visit the links for more information on each individual GUI project. Use of a GUI to configure RAIL is recommended but not required.

# Special Thanks #

  * _Jared_ - Inspiration and support through the development of Rampage AI original.
  * _Fallen~Angel_ - Helped to provide support for Rampage AI original.
  * _Blueness_ - Hosting Rampage AI original.
  * _Cody_ - Testing in early and mid stages of development.
  * _Abraham_ - Testing in early stages of development.
  * _Dr. Azzy_ - Idea for MobID files as a work-around for mercenaries.


_**Remember:** Rampage AI Lite is still in active development! More features and optimizations are coming soon!_