------------------------
-- Environment Backup --
------------------------

-- Load table first
require "Table"

-- And use it to make a backup of _G before loading the rest of RAIL
do
  -- Make a deep copy of the global table
  local RAIL__G = Table.DeepCopy(getfenv(0))
  
  -- Remove copies of parts that RAIL added
  RAIL__G.RAIL = nil
  RAIL__G.Table = nil
  
  -- Set a metatable for the copy and set it as RAIL._G
  RAIL._G = setmetatable(RAIL__G,{ __index = _G, })
end

---------------
-- Constants --
---------------

-- GetV() constants
V_OWNER             = 0   -- Homunculus owner's ID
V_POSITION          = 1   -- Current (X,Y) coordinates
V_TYPE              = 2   -- Defines an object (Not Implemented)
V_MOTION            = 3   -- Returns current action
V_ATTACKRANGE       = 4   -- Attack range
V_TARGET            = 5   -- Target of an attack or skill
V_SKILLATTACKRANGE  = 6   -- Skill attack range
V_HOMUNTYPE         = 7   -- Returns the type of Homunculus
V_HP                = 8   -- Current HP amount
V_SP                = 9   -- Current SP amount
V_MAXHP             = 10  -- Maximum HP amount
V_MAXSP             = 11  -- Maximum SP amount
V_MERTYPE           = 12  -- Mercenary Type

-- Return values for GetV(V_HOMUNTYPE,id)
do
  local names = {"LIF","AMISTR","FILIR","VANILMIRTH"}
  local function GenerateConst(suffix,base)
    for i=1,4 do
      _G[names[i] .. suffix] = base + i
    end
  end
  GenerateConst("",    0)
  GenerateConst("2",   4)
  GenerateConst("_H",  8)
  GenerateConst("_H2",12)
end

-- Return values for GetV(V_MERTYPE,id)
do
  local function GenerateConst(name,base)
    for i=1,10 do
      _G[string.format("%s%.2d",name,i)] = base + i
    end
  end
  GenerateConst("ARCHER",   0)
  GenerateConst("LANCER",  10)
  GenerateConst("SWORDMAN",20)
end

-- Return values for GetV(V_MOTION,id)
do
  MOTION = {}
  local function GenerateConst(t)
    for i,name in t do
      _G["MOTION_" .. name] = i
      MOTION[name] = i
      MOTION[i] = name
    end
  end
  -- Standard motions
  GenerateConst{[ 0] = "STAND",
                       "MOVE",
                       "ATTACK",
                       "DEAD",
                       "DAMAGE",                -- Flinching (taking damage)
                       "BENDDOWN",              -- Bending over (pick up item, set trap)
                       "SIT",
                       "SKILL",                 -- Used a skill
                       "CASTING",               -- Casting a skill
                       "ATTACK2",               -- Attacking (double dagger?)

  -- Knight motions
                [13] = "COUNTER",               -- Counter-attack

  -- Hunter motions
                [18] = "FOCUSED_ARROW",

  -- Alchemist motions
                [12] = "TOSS",                  -- Toss something (spear boomerang, aid potion)
                [28] = "BIGTOSS",               -- A heavier toss (slim potions / acid demonstration)

  -- Bard/Dancer motions
                [16] = "DANCE",
                [17] = "SING",

  -- Taekwon Kid motions
                [19] = "TK_LEAP_UP",
                [20] = "TK_LEAP_DOWN",
                [25] = "TK_LEAP_LAND",

                [21] = "TK_STANCE_TORNADO",
                [22] = "TK_STANCE_HEELDROP",
                [23] = "TK_STANCE_ROUNDHOUSE",
                [24] = "TK_STANCE_COUNTER",
                [25] = "TK_TUMBLING",           -- Same as MOTION_TK_LEAP_LAND

                [26] = "TK_COUNTER",
                [27] = "TK_FLYINGKICK",
                [30] = "TK_TORNADO",
                [31] = "TK_HEELDROP",
                [32] = "TK_ROUNDHOUSE",

  -- Taekwon Master motions
                [33] = "TKM_PROTECTION",
                [34] = "TKM_HEAT",

  -- Soul Linker motions
                [23] = "SL_LINK",               -- Casting Link skill

  -- Ninja motions
                [35] = "NJ_BENDING",            -- ???
                [36] = "NJ_SKILL",              -- Used a skill
                [37] = "NJ_CASTING",            -- Casting a skill

  -- Gunslinger motions
                [38] = "GS_DESPERADO",
                [39] = "GS_COIN",
                [40] = "GS_GATLING",
                [41] = "GS_CASTING",            -- Casting a skill
                [42] = "GS_FULLBLAST",}
end

-- Return values for GetMsg(id), GetResMsg(id)
NONE_CMD            = 0   -- (Cmd)
MOVE_CMD            = 1   -- (Cmd, X, Y)
ATTACK_OBJECT_CMD   = 3   -- (Cmd, ID)
SKILL_OBJECT_CMD    = 7   -- (Cmd, Level, Type, ID)
SKILL_AREA_CMD      = 8   -- (Cmd, Level, Type, X, Y)
FOLLOW_CMD          = 9   -- (Cmd)

-- Unused:
--STOP_CMD            = 2   -- (Cmd)
--ATTACK_AREA_CMD     = 4   -- (Cmd, X, Y)
--PATROL_CMD          = 5   -- (Cmd, X, Y)
--HOLD_CMD            = 6   -- (Cmd)

-----------------------
-- Require() Imports --
-----------------------

-- Load the configuration options and constants
require "Config"

-- Setup a foundation API
require "Serialize"
require "Utils"
require "Event"
require "State"
require "Log"
require "TileMap"

require "History"
require "ActorGetType"
require "ActorOpts"
require "Actor"

require "Skills"
require "SkillState"
--require "SkillSupport"

-- AI modules
require "TargetBasic"
require "TargetChase"
--require "TargetChaseSimple"
require "TargetSkill"
--require "TargetSkillAoE"
require "Commands"

------------------------------
-- State Validation Options --
------------------------------
RAIL.Validate.DelayFirstAction = {"number",0,0}
RAIL.Validate.Information = {is_subtable = true,
  InitTime = {"number", 0},
  OwnerID = {"number", 0},
  OwnerName = {"string", "unknown"},
  SelfID = {"number", 0},
  RAILVersion = {"string", "unknown"},
}
RAIL.Validate.ProfileMark = {"number",20000,2000,nil}

----------------
-- Main Logic --
----------------

-- The main logic is broken up into events; an example is as follows
RAIL.Event["LOAD"]:Register(0,                -- Priority
                            "Loaded Log",     -- Handler name
                            1,                -- Max runs
                            function()        -- Handler function
  if RAIL.UseTraceAI then
    RAIL.LogT(0,"RAIL loaded...")
  end
end)

-- Function to fire the AI cycle event
do
  local last_perf = GetTick()
  
  local function ErrorHandler(error)
    -- Log the error
    TraceAI("LUA ERROR: " .. tostring(error))

    -- Wipe out the _LOADED table, so we can reset
    _LOADED = {}
    
    -- Require either AI.lua or AI_M.lua
    if not RAIL.Mercenary then
      require "AI"
    else
      require "AI_M"
    end
  end

  local AI_id
  local function FireEvent()
    -- Since "AI CYCLE" is a massive event chain, handler priority levels are
    --    broken down as follows:
    --    -50 to  -1  - Initialization
    --      0 to 799  - Data collection
    --    800 to 899  - Termination conditionals
    --    900 to 999  - Decision making
    --          1000  - Action
    RAIL.Event["AI CYCLE"]:Fire(AI_id)
  end

  function AI(id)
    -- Call the main AI CYCLE event with a custom error handler
    AI_id = id
    if not xpcall(FireEvent,ErrorHandler) then
      -- Don't process performance logging
      return
    end
    
    -- Do performance logging outside of all events
    do
      -- Get the current ticks
      local now = GetTick()

      -- Check if its time to spit out more performance data
      local ticks_since_last = now - last_perf
      if ticks_since_last < RAIL.State.ProfileMark then
        return
      end

      -- Get the performance data
      local average,longest = RAIL.Event["AI CYCLE"]:GetPerformanceData()
      
      -- Log it
      RAIL.LogT(40,
                " -- mark (avg: {1}ms; longest: {2}ms; mem: {3}kb; gc threshold: {4}kb) --",
                average,
                longest,
                gcinfo())
                
      -- Reset performance data
      RAIL.Event:ResetAllPerformanceData()
      
      -- And set the time of last log
      last_perf = GetTick()
    end
  end
end

RAIL.Event["AI CYCLE"]:Register(-100,                         -- Priority
                                "Garbage collect threshold",  -- Handler name
                                0,                            -- Max runs (never)
                                function(self,id)
  -- Check what the garbage collection threshold is
  local kb,threshold = gcinfo()
  
  -- Calculate the target threshold for garbage collection
  local target = 20 * 1024
  
  -- Set it if its lower
  if threshold < target then
    -- Set the garbage collection limit
    collectgarbage(target)
  end
end)

RAIL.Event["AI CYCLE"]:Register(-50,                  -- Priority
                                "Init information",   -- Handler name
                                1,                    -- Max runs
                                function()            -- Handler function
  -- Put some space to signify reload
  if RAIL.UseTraceAI then
    TraceAI("\r\n\r\n\r\n")
  else
    -- Not translatable
    RAIL.Log(0,"\n\n\n")
  end

  -- Log the AI initialization
  RAIL.LogT(0,"Rampage AI Lite r{1} initializing...",RAIL.Version)
  RAIL.LogT(0," --> Full Version ID = {1}",RAIL.FullVersion)
end)

RAIL.Event["AI CYCLE"]:Register(-50,                      -- Priority
                                "State initialization",   -- Handler name
                                0,                        -- Max runs (don't run; already done!)
                                function()                -- Handler function
  -- Load persistent data
  RAIL.State:Load(true)
end)

RAIL.Event["AI CYCLE"]:Register(-45,                -- Priority
                                "Actor info",       -- Handler name
                                1,                  -- Max runs
                                function(self,id)   -- Handler function
  -- Get owner information
  RAIL.Owner = Actors[GetV(V_OWNER,id)]
  RAIL.LogT(40," --> Owner; Name = {2}", RAIL.Owner, RAIL.State.Information.OwnerName)
  if RAIL.State.Information.OwnerName ~= "unknown" then
    RAIL.Owner.BattleOpts.Name = RAIL.State.Information.OwnerName
  end

  -- Get self information
  RAIL.Self = Actors[id]

  -- Get AI type
  if RAIL.Mercenary then
    RAIL.Self.AI_Type = GetV(V_MERTYPE,id)
  else
    RAIL.Self.AI_Type = GetV(V_HOMUNTYPE,id)
  end

  -- Get our attack range
  RAIL.Self.AttackRange = GetV(V_ATTACKRANGE,id)

  -- AttackRange seems to be rounded up for melee
  --if RAIL.Self.AttackRange <= 2 then
  --  RAIL.Self.AttackRange = 1.5
  --end

  -- Log extra information about self
  RAIL.LogT(40," --> Self; AI_Type = {2}; Attack Range = {3}", RAIL.Self, RAIL.Self.AI_Type, RAIL.Self.AttackRange)

  -- Create a bogus "Other" until homu<->merc communication is established
  RAIL.Other = RAIL.Self
end)

RAIL.Event["AI CYCLE"]:Register(-40,              -- Priority
                                "State update",   -- Handler name
                                1,                -- Max runs
                                function()        -- Handler function
  -- Check for the global variable "debug" (should be a table) to determine
  -- if we're running inside lua.exe or ragexe.exe
  if not RAIL._G.debug then
    -- Periodically save state data
    RAIL.Timeouts:New(2500,true,function()
      -- Only load data if the "update" flag in the state file is turned on
      RAIL.State:Load(false)
      
      -- Save data (if any data was loaded, it won't be dirty and won't save)
      RAIL.State:Save()
    end)
  end
end)

RAIL.Event["AI CYCLE"]:Register(-2,               -- Priority
                                "Init complete",  -- Handler name
                                1,                -- Max runs
                                function()        -- Handler function
  -- Store information in the state file
  RAIL.State.Information.InitTime = GetTick()
  RAIL.State.Information.OwnerID = RAIL.Owner.ID
  RAIL.State.Information.SelfID = RAIL.Self.ID
  RAIL.State.Information.RAILVersion = RAIL.FullVersion

  -- Log information
  RAIL.LogT(0,"RAIL initialization complete.")
end)

----------------
-- Main Cycle --
----------------

RAIL.CycleID = 0
RAIL.Event["AI CYCLE"]:Register(0,                    -- Priority
                                "Cycle Begin",        -- Handler name
                                -1,                   -- Max runs (negative means infinite)
                                function()            -- Handler function
  -- Generate a cycle ID
  RAIL.CycleID = math.mod(RAIL.CycleID + 1,5000)

  RAIL.Target = {
    Skill = nil,
    Attack = nil,
    Chase = nil,
  }
  
  RAIL.ActorLists = {
    All = {
      [RAIL.Owner.ID] = RAIL.Owner,
      [RAIL.Self.ID] = RAIL.Self,
    },
    Enemies = {},
    Friends = {},
    Other = {},
  }

  RAIL.Owner:Update()
  RAIL.Self:Update()
end)

RAIL.Event["AI CYCLE"]:Register(100,              -- Priority
                                "Actor Update",   -- Handler name
                                -1,               -- Max runs (negative means infinite)
                                function()        -- Handler function
  local skip_from,skip_to

  for i,actor in ipairs(GetActors()) do
    -- Don't double-update the owner or self
    if RAIL.Owner.ID ~= actor and RAIL.Self.ID ~= actor then
      -- Indexing non-existant actors will auto-create them
      local actor = Actors[actor]

      -- Update the information about it
      actor:Update()

      -- If the actor is a portal...
      if actor.Type == 45 and not skip_from then
        -- Get the block distance between portal and the owner
          -- roughly 1.5 tiles from now
        local inFuture = RAIL.Owner:BlocksTo(-1.5*RAIL.Owner:EstimateMove())(actor)
          -- and now
        local now = RAIL.Owner:BlocksTo(actor)

        if inFuture < 3 and inFuture < now then
          RAIL.LogT(7, "Owner approaching {1}; cycle terminating after data collection.",actor)
          
          -- Save the state data before terminating
          RAIL.State:Save()
          
          skip_from = 900
          skip_to = 1001
        end
      end

      -- Make sure we're not ignoring the actor
      if not actor:IsIgnored() then
        -- Fire an event
        RAIL.Event["ACTOR UPDATE"]:Fire(actor)

        -- Add it to the list of all actors
        RAIL.ActorLists.All[actor.ID] = actor

        -- Check if the actor is a friend
        if actor:IsFriend() then
          RAIL.ActorLists.Friends[actor.ID] = actor

          RAIL.Event["ACTOR UPDATE/FRIEND"]:Fire(actor)

        -- An enemy
        elseif actor:IsEnemy() then
          -- Add it to the enemies list
          RAIL.ActorLists.Enemies[actor.ID] = actor

          RAIL.Event["ACTOR UPDATE/ENEMY"]:Fire(actor)

        -- Or something else
        else
          RAIL.ActorLists.Other[actor.ID] = actor

          RAIL.Event["ACTOR UPDATE/OTHER"]:Fire(actor)
        end
      end -- not actor:IsIgnored
    end -- RAIL.Owner.ID ~= actor
  end -- i,actor in ipairs(GetActor())
  
  return true,skip_from,skip_to
end)

RAIL.Event["AI CYCLE"]:Register(800,                -- Priority
                                "Delay start log",  -- Handler name
                                1,                  -- Max runs
                                function()
  if RAIL.State.DelayFirstAction > 0 then
    RAIL.LogT(10,"Delaying first action for {1}ms",RAIL.State.DelayFirstAction)
  end
end)

RAIL.Event["AI CYCLE"]:Register(800,              -- Priority
                                "Delay action",   -- Handler name
                                -1,               -- Max runs
                                function(self)
  local finished = false

  -- Check if the owner has acted at all, which would cause DelayFirstAction
  -- to be useless.
  if RAIL.Owner.Motion[0] ~= MOTION_STAND then
    -- Owner doesn't have invulnerability any more, start acting
    finished = true
  end
  
  -- Check if the owner requested a motion from the AI, overriding DelayFirstAction
  if RAIL.Cmd.Queue:Size() > 0 then
    -- Delay overridden
    finished = true
  end

  -- Check if the delay for after-init action has expired
  if GetTick() - RAIL.State.Information.InitTime >= RAIL.State.DelayFirstAction then
    -- Expired, the Delay action is finished
    finished = true
  end

  -- Check if the delay is expired or otherwise aborted
  if finished then
    -- The delay has expired, don't run this handler any more
    self.RunsLeft = 0
  end

  -- If the AI is still waiting, don't continue this cycle
  return false
end)

RAIL.Event["AI CYCLE"]:Register(940,                  -- Priority
                                "Pre-selection",      -- Handler name
                                -1,                   -- Max runs (negative means infinite)
                                function()            -- Handler function
  -- Fire the pre-selection event
  return RAIL.Event["TARGET SELECT/PRE"]:Fire()
end)

RAIL.Event["AI CYCLE"]:Register(945,                    -- Priority
                                "Selection - Friends",  -- Handler name
                                -1,                     -- Max runs (negative means infinite)
                                function()              -- Handler function
  -- Fire the selection code based on owner/friends/other
  return RAIL.Event["TARGET SELECT/FRIEND"]:Fire()
end)

RAIL.Event["AI CYCLE"]:Register(950,                    -- Priority
                                "Selection - Enemies",  -- Handler name
                                -1,                     -- Max runs (negative means infinite)
                                function()              -- Handler function
  -- Fire the selection code based on enemies
  return RAIL.Event["TARGET SELECT/ENEMY"]:Fire()
end)

RAIL.Event["AI CYCLE"]:Register(955,                  -- Priority
                                "Post-selection",     -- Handler name
                                -1,                   -- Max runs (negative means infinite)
                                function()            -- Handler function
  -- Fire the post-selection event
  return RAIL.Event["TARGET SELECT/POST"]:Fire()
end)

RAIL.Event["AI CYCLE"]:Register(1000,                 -- Priority
                                "Skill Action",       -- Handler name
                                -1,                   -- Max runs (negative means infinite)
                                function(self,id)     -- Handler function
  if RAIL.Target.Skill ~= nil then
    local skill = RAIL.Target.Skill[1]
    local target_x = RAIL.Target.Skill[2]
    local target_y = RAIL.Target.Skill[3]

    -- Check if the target is an actor
    if RAIL.IsActor(target_x) then
      -- Use the skill
      target_x:SkillObject(skill)
    else
      -- Use the ground skill
      skill:Cast(target_x,target_y)
    end
    
    -- Workaround a strange bug that sometimes causes AI to stop after
    -- only using a skill in a cycle
    if
      true and    -- manual toggle
      not RAIL.Target.Attack and
      not RAIL.Target.Move
    then
      -- Don't let this get prevented by RAIL.Target.Chase action...
      local x,y = GetV(V_POSITION,id)
      if RAIL.Owner.X[0] > x then x = x + 1 else x = x - 1 end
      Move(id,x,y)
    end
  end
end)

RAIL.Event["AI CYCLE"]:Register(1000,             -- Priority
                                "Attack Action",  -- Handler name
                                -1,               -- Max runs (negative means infinite)
                                function()        -- Handler function
  if RAIL.Target.Attack ~= nil then
    -- Log it
    RAIL.LogT(75,"Using physical attack against {1}.",RAIL.Target.Attack)
    
    -- Send the attack
    RAIL.Target.Attack:Attack()
  end
end)

do
  local last_x,last_y
  RAIL.Event["AI CYCLE"]:Register(1000,                 -- Priority
                                  "Move Action",        -- Handler name
                                  -1,                   -- Max runs (negative means infinite)
                                  function(self,id)     -- Handler function
    if not RAIL.Target.Chase then
      return
    end
    
    -- TODO: Remove this after it's unneeded
    if RAIL.IsActor(RAIL.Target.Chase) then
      RAIL.LogT(0,"Error: Old-style chase target specified: {1}",RAIL.Target.Chase)

      return
    elseif
      type(RAIL.Target.Chase) ~= "table" or
      type(RAIL.Target.Chase[1]) ~= "number" or
      type(RAIL.Target.Chase[2]) ~= "number"
    then
      RAIL.LogT(0,"Error: Unknown value in RAIL.Target.Chase: {1}",Serialize(RAIL.Target.Chase))

      return
    end

    local x,y = unpack(RAIL.Target.Chase)

    -- Make sure the target coords are short enough that the server won't ignore them
    do
      local angle,dist = RAIL.Self:AngleTo(x,y)
      local orig_dist = dist
      while dist > 10 do
        dist = dist / 2
      end

      -- Plot a shorter distance in the same direction
      if dist ~= orig_dist then
        x,y = RoundNumber(RAIL.Self:AnglePlot(angle,dist))
      end
    end
    
    -- Check if we tried to move here last cycle
    if x == last_x and y == last_y then
      -- TODO: (Alter move such that repeated moves to same location aren't ignored)
    end

    if
      x ~= last_x or
      y ~= last_y or
      RAIL.Target.Attack ~= nil or
      RAIL.Target.Skill ~= nil
    then
      -- Log it
      RAIL.LogT(85,"Moving to ({1},{2}).",x,y)

      -- Send the move
      Move(id,x,y)

      last_x = x
      last_y = y
    end
  end)
end


RAIL.Event["LOAD"]:Fire()
