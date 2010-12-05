------------------------
-- Validation Options --
------------------------

if not RAIL.Validate.SkillOptions then
  RAIL.Validate.SkillOptions = {is_subtable = true}
end

RAIL.Validate.SkillOptions.BuffBasePriority = {"number",40,0}

-- Mental Charge
RAIL.Validate.SkillOptions[8004] = {
    MaxFailures = {"number",4},
    PriorityOffset = {"number",15},
}

--------------------------
-- Skill Initialization --
--------------------------
RAIL.Event["AI CYCLE"]:Register(-35,                    -- Priority
                                "Skill initialization", -- Handler name
                                1,                      -- Max runs
                                function()
  -- Map of patterns to event names
  local pattern_event_map = {
    --AreaOfEffect  = "SKILL INIT/AREA EFFECT",   -- TODO: Use custom TileMap for AoE skills
    Attack        = "SKILL INIT/ATTACK",        -- also fires SKILL INIT/OFFENSIVE
    Buff          = "SKILL INIT/BUFF",
    Debuff        = "SKILL INIT/OFFENSIVE",
    --Defense       = "SKILL INIT/DEFENSE",
    --Emergency     = "SKILL INIT/EMERGENCY",
    --HealOwner     = "SKILL INIT/HEAL OWNER",
    --HealSelf      = "SKILL INIT/HEAL SELF",
    PartySupport  = "SKILL INIT/PARTY BUFF",
    --Pushback      = "SKILL INIT/PUSHBACK",
    --Recover       = "SKILL INIT/RECOVER",
    Reveal        = "SKILL INIT/REVEAL",        -- also fires SKILL INIT/OFFENSIVE
  }

  -- Loop through each skill
  for skill_type,skill in RAIL.Self.Skills do
    -- Only initialized skills with named script AIs
    if type(skill_type) == "string" then
      -- Loop through each pattern-event mapping
      for pattern,event in pairs(pattern_event_map) do
        -- Check if the skill type matches a pattern
        if string.find(skill_type,pattern,nil,true) then
          -- Initialize the skill
          RAIL.Event["SKILL INIT/GENERIC/PRE"]:Fire(skill)
          RAIL.Event[event]:Fire(skill)
          RAIL.Event["SKILL INIT/GENERIC/POST"]:Fire(skill)

          -- Stop looping through pattern-event mappings
          break
        end
      end -- pattern,event in pairs(pattern_event_map)
    end -- type(skill_type) == "string"
  end -- skill_type,skill in RAIL.Self.Skills
end)

do
  local byID = RAIL.Validate.SkillOptions
  
  -- Default options that all skills use
  local defaults = {is_subtable = true,
    Enabled = {"boolean",true},
    Name = {"string",nil},                      -- default set by init function
    Condition = {"function",nil,unsaved=true},  -- default set by init function
    ReservedSP = {"number",0,0},
    ReservedSPisPercent = {"boolean",false},
  }

  RAIL.Event["SKILL INIT/GENERIC/POST"]:Register(0,               -- Priority
                                                 "Post Init",     -- Handler name
                                                 -1,              -- Max runs (negative means infinite)
                                                 function(self,skill)
    -- Copy validation options from defaults, but don't overwrite
    byID[skill.ID] = Table.DeepCopy(defaults,byID[skill.ID],false)
    
    -- Set the default skill name
    byID[skill.ID].Name[2] = AllSkills[skill.ID]:GetName()

    -- Rework the skill to now use name from the state file
    AllSkills[skill.ID].GetName = function(self)
      return RAIL.State.SkillOptions[self.ID].Name
    end
    
    -- Get the name, just so it'll show up in the state file
    AllSkills[skill.ID]:GetName()

    -- Set the default condition function
    byID[skill.ID].Condition[2] = AllSkills[skill.ID].Condition
  end)
end

--------------------------
-- Skill Selection Base --
--------------------------
do
  -- Function to call a new event for each skill of a specified type
  local function FireSkillEvent(event_name,skill_name,...)
    -- Loop through all skills that match the skill name
    for idx,skill in FindPairs(RAIL.Self.Skills,skill_name,nil,true) do
      -- Check that the skill is enabled
      if
        RAIL.State.SkillOptions[skill.ID] and
        RAIL.State.SkillOptions[skill.ID].Enabled
      then
        -- Fire the event
        RAIL.Event[event_name]:Fire(skill,unpack(arg))
      end
    end
  end

  RAIL.Event["AI CYCLE"]:Register(810,                    -- Priority
                                  "Casting Terminate",    -- Handler name
                                  -1,                     -- Max runs (negative means infinite)
                                  function()              -- Handler function
    if RAIL.SkillState == RAIL.SkillState.CASTING then
      -- Too spammy
      --RAIL.LogT(7,"Casting motion prevents action; cycle terminating after data collection.")

      -- Discontinue this AI CYCLE
      return false
    end
  end)

  -- Check emergency skills
  RAIL.Event["AI CYCLE"]:Register(830,                -- Priority
                                  "Emergency Check",  -- Handler name
                                  -1,                 -- Max runs (negative means infinite)
                                  function()
    -- Fire an event to check emergency skills
    FireSkillEvent("TARGET SELECT/SKILL/EMERGENCY","Emergency")

    -- Check if a skill was selected
    if RAIL.Target.Skill then
      -- Log it
      RAIL.LogT(7, "Urgently casting {1}; cycle terminating after data collection.",RAIL.Target.Skill)
      
      -- Skip selection routines
      return true,900,1000
    end
  end)

  -- Check non-targeted skills
  RAIL.Event["TARGET SELECT/PRE"]:Register(0,             -- Priority
                                           "Non-target",  -- Handler name
                                           -1,            -- Max runs (negative means infinite)
                                           function()
    -- Check if skills are ready
    if RAIL.SkillState ~= RAIL.SkillState.READY then
      -- Skills aren't ready
      return false
    end

    -- Check if a skill was manually requested
    if RAIL.Target.Skill and RAIL.Target.Skill.Manual then
      -- Don't try a new skill
      return false
    end

    -- Check for party support skills
    FireSkillEvent("TARGET SELECT/SKILL/PARTY BUFF", "PartySupport", 0)

    -- Check for heal skills
    FireSkillEvent("TARGET SELECT/SKILL/HEAL OWNER", "HealOwner",  0)
    FireSkillEvent("TARGET SELECT/SKILL/HEAL SELF",  "HealSelf",   0)
  end)

  -- Check buff skills
  RAIL.Event["TARGET SELECT/POST"]:Register(10,                   -- Priority
                                            "Buff skill select",  -- Handler name
                                            -1,                   -- Max runs (negative means infinite)
                                            function()
    -- Check if skills are ready
    if RAIL.SkillState ~= RAIL.SkillState.READY then
      -- Skills aren't ready
      return
    end

    -- Check if a skill was manually requested
    if RAIL.Target.Skill and RAIL.Target.Skill.Manual then
      -- Don't try a new skill
      return
    end

    -- Check buff skills
    -- NOTE: Some buff skill conditions require knowledge of decided movement
    FireSkillEvent("TARGET SELECT/SKILL/BUFF","Buff")
  end)

  -- Check that the AI won't initiate a cast-time skill while chasing
  RAIL.Event["TARGET SELECT/POST"]:Register(50,               -- Priority
                                            "Walk+cast time", -- Handler name
                                            -1,
                                            function()
    -- Check that a skill was selected
    if not RAIL.Target.Skill then
      return
    end
    
    -- Check that a chase location was selected
    if not RAIL.Target.Chase then
      return
    end
    
    -- Check if the skill has a cast time
    if RAIL.Target.Skill[1].CastTime > 0 then
      -- Remove the skill
      RAIL.Target.Skill = nil
    end
  end)

  RAIL.Event["IDLE"]:Register(20,                   -- Priority
                              "Idle Skills",        -- Handler name
                              -1,                   -- Max runs (negative means infinite)
                              function(self,idletime)
      if RAIL.SkillState == RAIL.SkillState.READY then
        FireSkillEvent("TARGET SELECT/SKILL/HEAL OWNER", "HealOwner", idletime)
        FireSkillEvent("TARGET SELECT/SKILL/HEAL SELF",  "HealSelf",  idletime)

        -- Check if a skill was selected
        if RAIL.Target.Skill then
          -- TODO: Log it

          -- Since a skill target was found, don't continue processing
          return false
        end
      end
  end)
  
  RAIL.Event["AI CYCLE"]:Register(990,              -- Priority
                                  "Skill SP",       -- Handler name
                                  -1,               -- Max runs (negative means infinite)
                                  function()
    -- Checking SP only applies when a skill is selected
    local skill = RAIL.Target.Skill
    if not skill then
      return
    end

    -- Check to see if this was manually requested
    if skill.Manual then
      -- Let the user get a no SP message if there's not enough SP
      return
    end

    -- Check if there is enough SP left
    if RAIL.Self:GetUsableSP(skill[1]) <= skill[1].SPCost + 1 then
      -- Don't actually use a skill
      RAIL.Target.Skill = nil
    end
  end)
end

---------------------------
-- Offensive Skills Base --
---------------------------

do
  -- State validation options
  local defaults = {is_subtable = true,
    MaxFailures = {"number",10,1},
    PriorityOffset = {"number",0},
  }
  
  -- List of skills
  local offensive_skills = Table.New()
  
  -- Callbacks for the skills
  local function SuccessCallback(ticks,skill,target)
    -- Reset the failure count
    target.BattleOpts[skill.ID .. "failures"] = 0

    -- Set the next time that the skill should be cast
    if skill.Duration > 0 then
      target.BattleOpts[skill.ID .. "next"] = GetTick() - ticks + skill.Duration - skill.CastTime
    end
  end

  local function FailureCallback(ticks,skill,target)
    -- Increment the failure count if the skill hasn't been confirmed
    local key = skill.ID .. "failures"
    target.BattleOpts[key] = (target.BattleOpts[key] or 0) + 1
  end

  -- Helper function to get priority level of a skill against an actor
  local function GetPriority(self,actor)
    local actor_prio = actor.BattleOpts.Priority
    local skill_prio = RAIL.State.SkillOptions[self.ID].PriorityOffset
    return actor_prio + skill_prio
  end

  -- Initialization
  RAIL.Event["SKILL INIT/OFFENSIVE"]:Register(0,                  -- Priority
                                              "Offensive init",   -- Handler name
                                              -1,                 -- Max runs (infinite)
                                              function(self,skill)
    local byID = RAIL.Validate.SkillOptions

    -- Copy validation options from defaults, but don't overwrite
    byID[skill.ID] = Table.DeepCopy(defaults,byID[skill.ID],false)

    -- Add to the offensive skills table
    offensive_skills:Append(skill)

    -- Add the callbacks
    RAIL.SkillState.Callbacks:Add(skill,            -- Skill to add callbacks to
                                  SuccessCallback,
                                  FailureCallback,
                                  true)             -- Persist past the first call

    -- Add the GetPriority support function
    if not skill[1] then
      -- Skill level not selectable
      skill.GetPriority = GetPriority
    else
      -- Skill level selectable
      local i=1
      while skill[i] do
        skill[i].GetPriority = GetPriority
        i = i + 1
      end
    end
  end)

  -- Skill selection
  RAIL.Event["TARGET SELECT/ENEMY/SKILL"]:Register(0,                   -- Priority
                                                  "Offensive select",   -- Handler name
                                                  -1,                   -- Max runs
                                                  function(self,actor,can_chase)
    -- Ensure there are offensive skills
    if offensive_skills:GetN() < 1 then
      -- Don't check this anymore
      self.RunsLeft = 0
    end

    -- Loop through each offensive skill
    for i=1,offensive_skills:GetN() do
      local skill = offensive_skills[i]
      
      -- Check that the skill is enabled
      if RAIL.State.SkillOptions[skill.ID].Enabled then

        -- Check if skill level is selectable and there's not enough SP for
        -- maximum level
        local usable_sp = RAIL.Self:GetUsableSP(skill)
        if skill[1] and usable_sp <= skill.SPCost + 1 then
          -- Find the highest level available with the usable SP
          local found = false
          for i=skill.Level,1,-1 do
            if skill[i] and usable_sp > skill.SPCost then
              found = true
              skill = skill[i]
              break
            end
          end
          
          -- Check
        end
    
        -- Fire an event for this potential skill-target combo
        local r1,r2 = RAIL.Event["TARGET SELECT/ENEMY/SKILL/OFFENSIVE"]:Fire(skill,actor,can_chase)
        
        -- Set the return values of this event based on the child event
        if r1 then
          self.Event.RetVal[1] = true
        end
        if r2 then
          if self.Event.RetVal[1] == nil then self.Event.RetVal[1] = false end
          self.Event.RetVal[2] = true
        end
      end
    end -- i=1,offensive_skills:GetN()
  end)
end

RAIL.Event["TARGET SELECT/ENEMY/SKILL/OFFENSIVE"]:Register(0,           -- Priority
                                                           "Allowed",   -- Handler name
                                                           -1,          -- Max runs (infinite)
                                                           function(self,skill,actor)
  -- Check that the skill is allowed
  -- NOTE: Pretend skill level is 10 for generic offensive skills; attack
  --       skills will add another check into this handler chain
  if not actor:IsSkillAllowed(10) then
    -- Don't continue this event
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/SKILL/OFFENSIVE"]:Register(10,            -- Priority
                                                           "Condition",   -- Handler name
                                                           -1,            -- Max runs (infinite)
                                                           function(self,skill,actor)
  if not RAIL.State.SkillOptions[skill.ID].Condition(RAIL._G,actor) then
    -- Don't continue this event
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/SKILL/OFFENSIVE"]:Register(20,            -- Priority
                                                           "Failures",    -- Handler name
                                                           -1,            -- Max runs (infinite)
                                                           function(self,skill,actor)
  -- Check that the skill hasn't failed too many times
  if (actor.BattleOpts[skill.ID .. "failures"] or 0) >= RAIL.State.SkillOptions[skill.ID].MaxFailures then
    -- Don't continue this event
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/SKILL/OFFENSIVE"]:Register(25,          -- Priority
                                                           "Duration",  -- Handler name
                                                           -1,          -- Max runs (infinite)
                                                           function(self,skill,actor)
  -- Ensure there's a duration
  if skill.Duration < 1 then
    return
  end

  -- Check if the duration has expired
  if (actor.BattleOpts[skill.ID .. "next"] or 0) > GetTick() then
    -- Don't continue this event
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/SKILL/OFFENSIVE"]:Register(40,              -- Priority
                                                           "Range/chase",   -- Handler name
                                                           -1,              -- Max runs (infinite)
                                                           function(self,skill,actor,can_chase)
  -- Get the skill range
  local srange = skill.Range

  -- If the actor was allowed it can be chased
  if can_chase then
    -- Set the second return value of this event to true
    self.Event.RetVal[2] = true

    -- Ensure that it will unpack properly
    if self.Event.RetVal[1] == nil then self.Event.RetVal[1] = false end

    -- Fire an event to add the target to the ChaseMap
    RAIL.Event["TARGET SELECT/ENEMY/CHASE"]:Fire(actor,
                                                 srange,
                                                 skill:GetPriority(actor),
                                                 true)    -- srange uses PythagDistance
  end

  -- Check the range
  if RAIL.Self:DistanceTo(actor) > srange then
    -- Don't continue this event
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/SKILL/OFFENSIVE"]:Register(50,            -- Priority
                                                           "Acceptable",  -- Handler name
                                                           -1,            -- Max runs (infinite)
                                                           function(self,skill,actor)
  -- Set the 1st return value of this event to true
  self.Event.RetVal[1] = true
  
  -- If no other skill has been selected yet, choose this
  if not RAIL.Target.Skill then
    RAIL.Target.Skill = { skill, actor }
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/SKILL/OFFENSIVE"]:Register(100,               -- Priority
                                                           "Priority sieve",  -- Handler name
                                                           -1,                -- Max runs (infinite)
                                                           function(self,skill,actor)
  -- Get the priority of the skills
  local new_prio = skill:GetPriority(actor)
  local old_prio = RAIL.Target.Skill[1]:GetPriority(RAIL.Target.Skill[2],   -- X or actor
                                                    RAIL.Target.Skill[3])   -- Y

  -- Check if the new skill is worse
  if new_prio < old_prio then
    -- Don't continue this event
    return false
  end
  
  -- Check if the new skill is better
  if new_prio > old_prio then
    -- Set the skill target
    RAIL.Target.Skill = { skill, actor }
    return false
  end
end)

------------------------------
-- Offensive Skiils: Attack --
------------------------------
do
  local function SuccessCallback(ticks,skill,target)
    -- Increment skill counter
    -- NOTE: This is checked in Actor.lua's IsSkillAllowed()
    target.BattleOpts.CastsAgainst = (target.BattleOpts.CastsAgainst or 0) + 1
  end
  
  local skill_ids = {}
  local have_attacks = false

  RAIL.Event["SKILL INIT/ATTACK"]:Register(0,                     -- Priority
                                           "Attack skill init",   -- Handler name
                                           -1,                    -- Max runs (infinite)
                                           function(self,skill)
    -- Count attacks as a offensive skills too
    RAIL.Event["SKILL INIT/OFFENSIVE"]:Fire(skill)

    -- Save this skill's ID so we can later add success callbacks
    skill_ids[skill.ID] = true

    -- Register that we do indeed have attacks
    have_attacks = true
  end)
  
  RAIL.Event["TARGET SELECT/ENEMY/SKILL/OFFENSIVE"]:Register(0,                         -- Priority
                                                             "Attack Skill Allowed",    -- Handler name
                                                             -1,                        -- Max runs (infinite)
                                                             function(self,skill,actor)
    -- Ensure the skill is an attack skill
    if not skill_ids[skill.ID] then
      -- Don't affect this chain
      return
    end

    -- Check that the skill is allowed
    if not actor:IsSkillAllowed(skill.Level) then
      -- Don't continue this event
      return false
    end
  end)

  RAIL.Event["TARGET SELECT/POST"]:Register(0,                  -- Priority
                                            "Attack callback",  -- Handler name
                                            -1,                 -- Max runs (negative means infinite)
                                            function(self)
    -- Ensure that there are attack skills to check
    if not have_attacks then
      -- Don't check this again
      self.RunsLeft = 0
      return
    end
    
    -- Check that a skill was selected
    if not RAIL.Target.Skill then
      return
    end
    
    -- Get the selected skill
    local skill = RAIL.Target.Skill[1]

    -- Check if the selected skill is an attack skill
    if skill_ids[RAIL.Target.Skill[1].ID] then
      -- Add the callback for the next cast
      RAIL.SkillState.Callbacks:Add(skill,
                                    SuccessCallback,
                                    nil,
                                    false)            -- not persistent
    end
  end)
end

------------------------------
-- Offensive Skills: Reveal --
------------------------------
do
  local skill_ids = {}

  RAIL.Event["SKILL INIT/REVEAL"]:Register(0,             -- Priority
                                           "Reveal init", -- Handler name
                                           -1,            -- Max runs (infinite)
                                           function(self,skill)
    -- Save this skill as a revealing skill
    skill_ids[skill.ID] = true

    -- Count reveal as an offensive skill too
    return RAIL.Event["SKILL INIT/OFFENSIVE"]:Fire(skill)
  end)

  RAIL.Event["TARGET SELECT/ENEMY/SKILL/OFFENSIVE"]:Register(5,               -- Priority
                                                             "Hiding/reveal", -- Handler name
                                                             -1,              -- Max runs (infinite)
                                                             function(self,skill,actor)
    -- Check if the actor is hiding and the skill isn't a revealer
    if actor.Hide and not skill_ids[skill.ID] then
      -- Don't continue this event
      return false
    end
  end)
end

-----------------
-- Buff Skills --
-----------------

do
  -- State validation options
  local defaults = {is_subtable = true,
    MaxFailures = {"number",10,1},
    PriorityOffset = {"number",0},
    NextCastTime = {"number",0},
  }
  
  -- Closure to keep track of skill failures
  local failures = {}
  
  -- Function to get the buff priority
  local function GetPriority(self)
    local base_prio   = RAIL.State.SkillOptions.BuffBasePriority
    local prio_offset = RAIL.State.SkillOptions[self.ID].PriorityOffset
    return base_prio + prio_offset
  end

  local function SuccessCallback(ticks,skill)
    -- Reset the failure count
    failures[skill.ID] = 0

    -- Set the next time we can use the buff
    RAIL.State.SkillOptions[skill.ID].NextCastTime = GetTick() - ticks + skill.Duration - skill.CastTime
  end

  local function FailureCallback(ticks,skill)
    -- Increment the failure count if the skill hasn't been confirmed
    failures[skill.ID] = failures[skill.ID] + 1
  end

  -- Initialization
  RAIL.Event["SKILL INIT/BUFF"]:Register(0,             -- Priority
                                         "Buff init",   -- Handler name
                                         -1,            -- Max runs (infinite)
                                         function(self,skill)
    local byID = RAIL.Validate.SkillOptions

    -- Copy validation options from defaults, but don't overwrite
    byID[skill.ID] = Table.DeepCopy(defaults,byID[skill.ID],false)

    -- Check if our ID has changed, which indicates that we'll have to recast
    -- buffs
    if RAIL.Self.ID ~= RAIL.State.Information.SelfID then
      RAIL.State.SkillOptions[skill.ID].NextCastTime = 0
    end

    -- Add callbacks to the skill
    failures[skill.ID] = 0

    RAIL.SkillState.Callbacks:Add(skill,            -- Skill to add callbacks to
                                  SuccessCallback,
                                  FailureCallback,
                                  true)             -- Persist past the first call


    -- Add the GetPriority support function
    if not skill[1] then
      -- Skill level not selectable
      skill.GetPriority = GetPriority
    else
      -- Skill level selectable
      local i=1
      while skill[i] do
        skill[i].GetPriority = GetPriority
        i = i + 1
      end
    end
  end)

  -- Skill selection
  RAIL.Event["TARGET SELECT/SKILL/BUFF"]:Register(0,                  -- Priority
                                                  "Failures check",   -- Handler name
                                                  -1,                 -- Max runs
                                                  function(self,skill,idleticks)
    -- Check if the skill has failed too many times
    if failures[skill.ID] >= RAIL.State.SkillOptions[skill.ID].MaxFailures then
      -- Probably don't have the skill; stop trying
      return false
    end
  end)
end

RAIL.Event["TARGET SELECT/SKILL/BUFF"]:Register(10,             -- Priority
                                                "Next cast",    -- Handler name
                                                -1,             -- Max runs
                                                function(self,skill,idleticks)
  -- Get the time that the buff will wear off
  local next_cast = RAIL.State.SkillOptions[skill.ID].NextCastTime

  -- Don't use the buff if it's still active
  if GetTick() < next_cast then
    return false
  end
end)

RAIL.Event["TARGET SELECT/SKILL/BUFF"]:Register(20,             -- Priority
                                                "Condition",    -- Handler name
                                                -1,             -- Max runs
                                                function(self,skill,idleticks)
  -- Check any custom condition
  if not RAIL.State.SkillOptions[skill.ID].Condition(RAIL._G,nil) then
    return false
  end
end)

RAIL.Event["TARGET SELECT/SKILL/BUFF"]:Register(50,             -- Priority
                                                "Acceptable",   -- Handler name
                                                -1,             -- Max runs
                                                function(self,skill,idleticks)
  -- If there's not a selected skill, use this one
  if not RAIL.Target.Skill then
    RAIL.Target.Skill = { skill, RAIL.Self }
    return false
  end
end)

RAIL.Event["TARGET SELECT/SKILL/BUFF"]:Register(60,             -- Priority
                                                "Priority",     -- Handler name
                                                -1,             -- Max runs
                                                function(self,skill,idleticks)
  -- Get the priority levels
  local new_prio = skill:GetPriority()
  local old_prio = RAIL.Target.Skill[1]:GetPriority(RAIL.Target.Skill[2],   -- X or actor
                                                    RAIL.Target.Skill[3])   -- Y
  -- Check if this skill is lower priority
  if new_prio < old_prio then
    -- Interrupt this event
    return false
  end
  
  -- Check if this skill is highest priority
  if new_prio > old_prio then
    -- Set the skill to this one and then interrupt the event
    RAIL.Target.Skill = { skill, RAIL.Self }
    return false
  end
end)

-----------------
-- Party Buffs --
-----------------

do
  -- State validation options
  local defaults = {is_subtable = true,
    MaxFailures = {"number",10,1},
    PriorityOffset = {"number",0},
    AutoIncludeOwner = {"boolean",true},
  }

  -- Table of targets for each skill
  local targets = {}
  
  -- Number of failures by skill ID
  local failures = {}
  
  -- Boolean to set when a party support buff is initialized
  local have_partybuff = false

  -- Function to get the buff priority
  local function GetPriority(self,actor)
    local base_prio
    if actor.BattleOpts.Priority == RAIL.State.ActorOptions.Default.Priority then
      base_prio = RAIL.State.SkillOptions.BuffBasePriority
    else
      base_prio = actor.BattleOpts.Priority
    end
    local prio_offset = RAIL.State.SkillOptions[self.ID].PriorityOffset
    return base_prio + prio_offset
  end

  local function SuccessCallback(ticks,skill,target)
    -- Reset the failure count
    failures[skill.ID] = 0

    -- Set the next time we can use the buff
    target.BattleOpts[skill.ID .. "next"] = GetTick() - ticks + skill.Duration - skill.CastTime
  end

  local function FailureCallback(ticks,skill,target)
    -- Increment the failure count if the skill hasn't been confirmed
    failures[skill.ID] = failures[skill.ID] + 1
  end

  -- Initialization
  RAIL.Event["SKILL INIT/PARTY BUFF"]:Register(0,         -- Priority
                                               "Init",    -- Handler name
                                               -1,        -- Max runs (infinite)
                                               function(self,skill)
    local byID = RAIL.Validate.SkillOptions

    -- Copy validation options from defaults, but don't overwrite
    byID[skill.ID] = Table.DeepCopy(defaults,byID[skill.ID],false)
    
    -- Create the targets list
    targets[skill.ID] = List.New()
    
    -- Check if we should add the owner right away
    if RAIL.State.SkillOptions[skill.ID].AutoIncludeOwner then
      targets[skill.ID]:PushRight(RAIL.Owner)
    end

    -- Set initial failure count
    failures[skill.ID] = 0
    
    -- Set that a party buff exists
    have_partybuff = true

    -- Add callbacks to the skill
    RAIL.SkillState.Callbacks:Add(skill,            -- Skill to add callbacks to
                                  SuccessCallback,
                                  FailureCallback,
                                  true)             -- Persist past the first call


    -- Add the GetPriority support function
    if not skill[1] then
      -- Skill level not selectable
      skill.GetPriority = GetPriority
    else
      -- Skill level selectable
      local i=1
      while skill[i] do
        skill[i].GetPriority = GetPriority
        i = i + 1
      end
    end
  end)
  
  -- Check for new target
  RAIL.Event["AI CYCLE"]:Register(915,                        -- Priority
                                  "New party-buff target?",   -- Handler name
                                  -1,                         -- Max runs
                                  function(self)
    -- Ensure that there are party buffs to check for
    if not have_partybuff then
      -- Never run this handler again
      self.RunsLeft = 0
      return
    end

    -- Check that there is a selected skill
    if not RAIL.Target.Skill then
      return
    end
    
    -- Check that the selected skill is manually selected
    if not RAIL.Target.Skill.Manual then
      return
    end
    
    local skill = RAIL.Target.Skill[1]

    -- Check that the skill is a party buff skill
    local list = targets[skill.ID]
    if not list then
      return
    end
    
    -- Get the target of the skill
    local target = RAIL.Target.Skill[2]

    -- Check if the target of this skill is in the targets list
    for i=list.first,list.last do
      if list[i] == target then
        -- Don't add this target since its already in the list
        return
      end
    end
    
    -- Log that a new target was added
    RAIL.LogT(60,"New party-support target for {1}: {2}",skill,target)

    -- Add this target to the list
    list:PushRight(target)

    -- Ensure the list isn't too big
    if skill.MaxTargets > 0 then
      while list:Size() > skill.MaxTargets do
        -- Remove a target
        local old_target = list:PopLeft()

        -- Log the removal of this target
        RAIL.LogT(60,"Party-support target for {1} removed: {2}",RAIL.Target.Skill[1],target)
      end
    end
  end)
  
  -- Skill selection
  RAIL.Event["TARGET SELECT/SKILL/PARTY BUFF"]:Register(0,                  -- Priority
                                                        "Failures check",   -- Handler name
                                                        -1,                 -- Max runs
                                                        function(self,skill,idleticks)
    -- Check if the skill has failed too many times
    if failures[skill.ID] >= RAIL.State.SkillOptions[skill.ID].MaxFailures then
      -- Probably don't have the skill; stop trying
      return false
    end
  end)

  RAIL.Event["TARGET SELECT/SKILL/PARTY BUFF"]:Register(0,                  -- Priority
                                                        "Failures check",   -- Handler name
                                                        -1,                 -- Max runs
                                                        function(self,skill,idleticks)
    -- Check if the skill has failed too many times
    if failures[skill.ID] >= RAIL.State.SkillOptions[skill.ID].MaxFailures then
      -- Probably don't have the skill; stop trying
      return false
    end
  end)

  RAIL.Event["TARGET SELECT/SKILL/PARTY BUFF"]:Register(10,               -- Priority
                                                        "Per actor",      -- Handler name
                                                        -1,               -- Max runs (infinite)
                                                        function(self,skill,idleticks)
    -- Loop through target actors
    local list = targets[skill.ID]
    local i = list.first
    while i <= list.last do
      -- Check if the actor is active
      if list[i].Active then
        -- Fire a sub event
        RAIL.Event["TARGET SELECT/SKILL/PARTY BUFF/BY ACTOR"]:Fire(skill,list[i])

        -- Increment i
        i = i + 1
      else
        -- Remove the inactive actor by shifting others forward
        for j=i,list.last - 1 do
          list[j] = list[j + 1]
        end

        -- Set the former last element to nil
        list[list.last] = nil

        -- Decrement list.last
        list.last = list.last - 1
      end
    end
  end)
end

RAIL.Event["TARGET SELECT/SKILL/PARTY BUFF/BY ACTOR"]:Register(10,          -- Priority
                                                               "Next cast", -- Handler name
                                                               -1,          -- Max runs (infinite)
                                                               function(self,skill,actor)
  if GetTick() < (actor.BattleOpts[skill.ID .. "next"] or 0) then
    return false
  end
end)

RAIL.Event["TARGET SELECT/SKILL/PARTY BUFF/BY ACTOR"]:Register(20,          -- Priority
                                                               "Condition", -- Handler name
                                                               -1,          -- Max runs (infinite)
                                                               function(self,skill,actor)
  if not RAIL.State.SkillOptions[skill.ID].Condition(RAIL._G,actor) then
    return false
  end
end)

RAIL.Event["TARGET SELECT/SKILL/PARTY BUFF/BY ACTOR"]:Register(40,            -- Priority
                                                               "Range/Chase", -- Handler name
                                                               -1,            -- Max runs (infinite)
                                                               function(self,skill,actor)
  local srange = skill.Range

  -- Fire an event to add the target to the ChaseMap
  RAIL.Event["TARGET SELECT/ENEMY/CHASE"]:Fire(actor,
                                               srange,
                                               skill:GetPriority(actor),
                                               true)    -- srange uses PythagDistance

  -- Check the range
  if RAIL.Self:DistanceTo(actor) > srange then
    -- Don't continue this event
    return false
  end
end)


RAIL.Event["TARGET SELECT/SKILL/PARTY BUFF/BY ACTOR"]:Register(50,             -- Priority
                                                               "Acceptable",   -- Handler name
                                                               -1,             -- Max runs
                                                               function(self,skill,actor)
  -- If there's not a selected skill, use this one
  if not RAIL.Target.Skill then
    RAIL.Target.Skill = { skill, actor }
    return false
  end
end)

RAIL.Event["TARGET SELECT/SKILL/PARTY BUFF/BY ACTOR"]:Register(60,             -- Priority
                                                               "Priority",     -- Handler name
                                                               -1,             -- Max runs
                                                               function(self,skill,actor)
  -- Get the priority levels
  local new_prio = skill:GetPriority(actor)
  local old_prio = RAIL.Target.Skill[1]:GetPriority(RAIL.Target.Skill[2],   -- X or actor
                                                    RAIL.Target.Skill[3])   -- Y
  -- Check if this skill is lower priority
  if new_prio < old_prio then
    -- Interrupt this event
    return false
  end

  -- Check if this skill is highest priority
  if new_prio > old_prio then
    -- Set the skill to this one and then interrupt the event
    RAIL.Target.Skill = { skill, actor }
    return false
  end
end)

