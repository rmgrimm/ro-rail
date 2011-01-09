-- Actor options
RAIL.Validate.ActorOptions = {is_subtable=true}
RAIL.Validate.ActorOptions.Default = {is_subtable=true,
  Name = {"string","unknown"},
  Friend = {"boolean",false},
  FreeForAll = {"boolean",false},

  TargetCondition = {"function",function() return true end,unsaved = true},

  Priority = {"number",1,1},    -- higher number, higher priority; eg, 10 is higher than 1
  AttackAllowed = {"boolean",true},
  DefendOnly = {"boolean",false},
  DisableChase = {"boolean",false},

  SkillsAllowed = {"boolean",true},
  MinSkillLevel = {"number",1,1,10},
  MaxSkillLevel = {"number",10,1,10},
  MaxCastsAgainst = {"number",-1,-1}, -- -1 is unlimited

  TicksBetweenSkills = {"number",0,0},
  TicksBetweenAttack = {"number",0,0},


  -- KiteMode options are:
  --    always    - will always run away from the monster
  --    tanking   - will only run away when the monster is targeting RAIL.Self
  --    custom    - will be determined by custom function specified in KiteCondition
  KiteMode = {"string","always",{
    ["always"] = function() return true end,
    ["tank"] = function(actor) return actor.Target[0] == RAIL.Self.ID end,
    ["custom"] = function(actor)
      -- Get the condition for this actor
      local f = actor.BattleOpts.KiteCondition

      -- Ensure the kite condition is a function
      if type(f) ~= "function" then
        return false
      end

      -- Call the kite condition
      return f(RAIL._G,actor)
    end,
  },},
  KiteDistance = {"number",-1,1,nil,{ [-1] = true, },},
  KiteCondition = {"function",function() return false end,unsaved = true},

  -- amount of time to ignore the actor
  -- removed: DefaultIgnoreTicks = {"number",10000,1000},
  -- When chasing fails, ignore actor after this many ticks
  --  (-1 is never; an exception to the minimum of 2000)
  -- removed: IgnoreAfterChaseFail = {"number",5000,2000,nil,{ [-1] = true, },},
}
RAIL.Validate.ActorOptions.ByType = {is_subtable=true}
RAIL.Validate.ActorOptions.ByID = {is_subtable=true}

-- Max homunculus skill level is 5
if not RAIL.Mercenary then
  RAIL.Validate.ActorOptions.Default.MinSkillLevel[4] = 5
  RAIL.Validate.ActorOptions.Default.MaxSkillLevel[2] = 5
  RAIL.Validate.ActorOptions.Default.MaxSkillLevel[4] = 5
end

-- List of actor names based on type
--  Note: This is created and populated later in this file
local names

-- Set metatables to create validation options for IDs as they're referenced
do
  -- TODO: Optimize Actor Options... (if it becomes a problem)
  --
  --  Actor[id].BattleOpts (metatable; checks ByID, ByType, Default)
  --  ByID checks ByTypes
  --  ByTypes checks Defaults
  --  Defaults/ByID/ByTypes all trigger validation of tables
  --    RAIL.State.ActorOptions
  --    RAIL.State.ActorOptions.[Defaults/ByID/ByType]
  --
  --  Called almost every cycle...
  --

  -- Create the metatables
  local bytype_mt = {
    __index = function(self,idx)
      -- Ensure its a number
      -- Note: Without this, ByType.optional (.unsaved, .is_subtable, etc) will be tables
      if type(idx) ~= "number" then
        return nil
      end

      -- Copy from the default table
      local ret = Table.DeepCopy(RAIL.Validate.ActorOptions.Default)

      -- Loop through, adding optional to all values
      for k,v in ret do
        if type(v) == "table" then
          -- Check for "Name" validation table
          if k == "Name" and names[idx] then
            -- Set the default name based on names table
            v[2] = names[idx]
          else
            -- Set the value as optional, so nil will cause fall through to next table
            --  (first ByID, then ByType, then Default)
            v.optional = true
          end
        end
      end
      ret.unsaved = true

      -- Add the return value to the validate table
      rawset(self,idx,ret)

      -- And return it
      return ret
    end,
  }
  local byid_mt = {
    __index = function(self,idx)
      -- Ensure its a number
      -- Note: Without this, ByID.optional (.unsaved, .is_subtable, etc) will be tables
      if type(idx) ~= "number" then
        return nil
      end

      -- Copy from the default table
      local ret = Table.DeepCopy(RAIL.Validate.ActorOptions.Default)

      -- Loop through, adding optional to all values
      for k,v in ret do
        if type(v) == "table" then
          -- Set the value as optional, so nil will cause fall through to next table
          --  (first ByID, then ByType, then Default)
          v.optional = true
        end
      end
      ret.unsaved = true

      -- Add the return value to the validate table
      rawset(self,idx,ret)

      -- And return it
      return ret
    end,
  }

  -- Set the metatable for both ByType and ByID
  setmetatable(RAIL.Validate.ActorOptions.ByType,bytype_mt)
  setmetatable(RAIL.Validate.ActorOptions.ByID,byid_mt)
end

-- Actor Type names
do
  names = {
    -- Player Class IDs
    [0] = "Novice",
    [1] = "Swordsman",
    [2] = "Mage",
    [3] = "Archer",
    [4] = "Acolyte",
    [5] = "Merchant",
    [6] = "Thief",
    [7] = "Knight",
    [8] = "Priest",
    [9] = "Wizard",
    [10] = "Blacksmith",
    [11] = "Hunter",
    [12] = "Assassin",
    [13] = "Knight (Peco)",
    [14] = "Crusader",
    [15] = "Monk",
    [16] = "Sage",
    [17] = "Rogue",
    [18] = "Alchemist",
    [19] = "Bard",
    [20] = "Dancer",
    [21] = "Crusader (Peco)",
    --[22] = ?
    [23] = "Super Novice",
    [24] = "Gunslinger",
    [25] = "Ninja",

    --[45] = "Portal",  -- identified by Actor.ActorType, so this is redundant

    -- Monster IDs
    -- Note: More at http://forums.roempire.com/archive/index.php?t-138313.html
    [1001] = "Scorpion",
    [1002] = "Poring",
    [1004] = "Hornet",
    [1005] = "Familiar",
    [1007] = "Fabre",
    [1008] = "Pupa",
    [1009] = "Condor",
    [1010] = "Willow",
    [1011] = "Chonchon",
    [1012] = "Roda Frog",
    [1013] = "Wolf",
    [1014] = "Spore",
    [1015] = "Zombie",
    -- ...
    [1025] = "Boa",
    -- ...
    [1031] = "Poporing",
    -- ...
    [1038] = "Osiris",                -- MVP
    [1039] = "Baphomet",              -- MVP
    -- ...
    [1042] = "Steel Chonchon",
    -- ...
    [1046] = "Doppelganger",          -- MVP
    -- ...
    [1057] = "Yoyo",
    [1058] = "Metaller",
    [1059] = "Mistress",              -- MVP
    -- ...
    [1076] = "Skeleton",
    [1077] = "Poison Spore",
    [1078] = "Red Plant",
    [1079] = "Blue Plant",
    [1080] = "Green Plant",
    [1081] = "Yellow Plant",
    [1082] = "White Plant",
    [1083] = "Shining Plant",
    [1084] = "Black Mushroom",
    [1085] = "Red Mushroom",
    [1086] = "Golden Thief Bug",      -- MVP
    [1087] = "Orc Hero",              -- MVP
    [1088] = "Vocal",                 -- Miniboss
    -- ...
    [1095] = "Andre",
    [1096] = "Angeling",              -- Miniboss
    [1097] = "Ant Egg",
    -- ...
    [1105] = "Deniro",
    -- ...
    [1111] = "Drainliar",
    -- ...
    [1121] = "Giearth",
    -- ...
    [1139] = "Mantis",
    -- ...
    [1152] = "Orc Skeleton",
    [1153] = "Orc Zombie",
    -- ...
    [1160] = "Piere",
    -- ...
    [1176] = "Vitata",
    [1177] = "Zenorc",
    -- ...
    [1214] = "Choco",                 -- Miniboss
    -- ...
    [1555] = "Summoned Parasite",     -- Alchemist Summon
    [1575] = "Summoned Flora",        -- Alchemist Summon
    [1579] = "Summoned Hydra",        -- Alchemist Summon
    [1589] = "Summoned Mandragora",   -- Alchemist Summon
    [1590] = "Summoned Geographer",   -- Alchemist Summon
    -- ...
    [1880] = "Wood Goblin",
    [1881] = "Les",
  }

  -- Add homunculus names
  for i=1,16 do
    local mod = math.mod(i,4)
    if mod == 1 then
      names[6000 + i] = "Lif"
    elseif mod == 2 then
      names[6000 + i] = "Amistr"
    elseif mod == 3 then
      names[6000 + i] = "Filir"
    else
      names[6000 + i] = "Vanilmirth"
    end
  end

  -- Add mercenary names
  for i=1,30 do
    if i <= 10 then
      names[6016 + i] = "Archer Mercenary " .. tostring(i)
    elseif i <= 20 then
      names[6016 + i] = "Lancer Mercenary " .. tostring(i - 10)
    else
      names[6016 + i] = "Swordman Mercenary " .. tostring(i - 20)
    end
  end
end

-- Specialized Defaults
do
  -- Mushrooms / Plants
  do
    -- Metatable to get default value from RAIL.State.ActorOptions.Default
    local plant_mt = {
      __index = function(t,idx)
        if idx == 2 or idx == 3 then
          -- NOTE: Commented this out; the AI shouldn't prioritize a mob of
          --       plants over a single real target unless priority is
          --       specifically set in the state-file
          --if RAIL.State.ActorOptions.Default.Priority > 1 then
          --  return RAIL.State.ActorOptions.Default.Priority - 1
          --else
            -- This is below the minimum of 1, but it won't affect ChaseMap
            return 0.1
          --end
        end
      end,
    }
    for i=1078,1085,1 do
      -- Get the validation table
      local validate = RAIL.Validate.ActorOptions.ByType[i]

      -- Set default and minimum priority to nil
      validate.Priority[2] = nil
      validate.Priority[3] = nil

      -- Set metatable to return a default value at 1 below default actor priority
      setmetatable(validate.Priority,plant_mt)

      -- Disallow skills by default
      validate.SkillsAllowed[2] = false

      -- Remove optional
      validate.Priority.optional = nil
      validate.SkillsAllowed.optional = nil
    end
  end

  -- Alchemist summons
  do
    local summons = {
      [1555] = true,  -- Summoned Parasite
      [1575] = true,  -- Summoned Flora
      [1579] = true,  -- Summoned Hydra
      [1589] = true,  -- Summoned Mandragora
      [1590] = true,  -- Summoned Geographer
    }
    for type_num in pairs(summons) do
      -- Get the validation table for this type
      local validate = RAIL.Validate.ActorOptions.ByType[type_num]

      -- Set default for attacks and skills to false
      validate.AttackAllowed[2] = false
      validate.SkillsAllowed[2] = false

      -- Remove optional
      validate.AttackAllowed.optional = nil
      validate.SkillsAllowed.optional = nil
    end
  end
end
