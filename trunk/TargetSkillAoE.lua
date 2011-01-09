-- Default validation options also come from TargetSkill.lua
local defaults = {
  PriorityOffset = {"number",0,},
  PriorityThreshold = {"number",4,1,nil,{ [-1] = true, },},
  TargetThreshold = {"number",-1,1,nil,{ [-1] = true, },},
}

-- TileMaps for AoE skills
local aoe_maps = {}

-- Table of skills
local aoe_skills = Table.New()

-- Functions to get the priority of AoE skill
local function GetPriority_ground(skill,x,y)
  -- Get the tile map
  local map = aoe_maps[skill.ID]
  
  -- Get the priority sum of monsters that would be hit from that location
  x,y = map:TranslateFromParent(x,y)
  local cell_prio = map(x,y).AoEPriority
  
  -- Get the priority offset
  local skill_prio = RAIL.State.SkillOptions[skill.ID].PriorityOffset
  
  -- Return the priority
  return cell_prio + skill_prio
end
local function GetPriority_actor(skill,actor)
  return GetPriority_ground(skill,actor.X[0],actor.Y[0])
end

RAIL.Event["SKILL INIT/AREA EFFECT"]:Register(0,            -- Priority
                                              "AoE Init",   -- Handler name
                                              -1,           -- Max runs (infinite)
                                              function(self,skill)
  local byID = RAIL.Validate.SkillOptions

  -- Copy validation options from defaults, but don't overwrite
  byID[skill.ID] = Table.DeepCopy(defaults,byID[skill.ID],false)

  -- Add to the offensive skills table
  aoe_skills:Append(skill)

  -- TODO: Add the callbacks
  --RAIL.SkillState.Callbacks:Add(skill,            -- Skill to add callbacks to
  --                              SuccessCallback,
  --                              FailureCallback,
  --                              true)             -- Persist past the first call

  -- Add the GetPriority support function
  local GetPriority = GetPriority_actor
  if skill.TargetType == "ground" then
    GetPriority = GetPriority_ground
  end
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

RAIL.Event["TARGET SELECT/PRE"]:Register(0,               -- Priority
                                         "AoE refresh",   -- Handler name
                                         -1,              -- Max runs (infinite)
                                         function(self)
  -- Generate the center and defaults for all submaps
  local center = {
    X = RAIL.Self.X[0],
    Y = RAIL.Self.Y[0],
  }
  local defaults = {
    AoEPriority = 0,
    AoEActors = 0,
    AoEBestActor = nil,
  }

  -- Loop through each AoE skill
  for i=1,aoe_skills:GetN() do
    local skill = aoe_skills[i]

    -- Generate the range table
    local range = {
      X = {-skill.Range,skill.Range},
      Y = {-skill.Range,skill.Range},
    }

    -- Reset the tilemap
    aoe_maps[skill.ID] = TileMap:SubMap(center,
                                        range,
                                        defaults,     -- Defaults
                                        defaults,     -- Invalid
                                        nil)          -- Passthrough
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/SKILL"]:Register(0,                   -- Priority
                                                 "AoE actor plot",    -- Handler name
                                                 -1,                  -- Max runs (infinite)
                                                 function(self,actor)
  -- Ensure there are AoE skills
  if aoe_skills:GetN() < 1 then
    -- Don't check this anymore
    self.RunsLeft = 0
  end

  -- Ensure the actor should be counted
  if not actor:IsSkillAllowed(10) then
    return
  end

  -- Get the actor priority
  local actor_prio = actor.BattleOpts.Priority

  -- Loop through each AoE skill
  for i=1,aoe_skills:GetN() do
    -- Get the skill
    local skill = aoe_skills[i]
    
    -- Get the map for this skill
    local map = aoe_maps[skill.ID]
    
    -- Get the actor location on this map
    local actor_x,actor_y = map:TranslateFromParent(actor.X[0],actor.Y[0])

    -- Plot the actor onto the map
    local map = aoe_maps[skill.ID]
    for cell,x,y in map:TilesAround(actor_x,actor_y,skill.SplashRange) do
      cell.AoEPriority = cell.AoEPriority + actor_prio
      cell.AoEActors = cell.AoEActors + 1
    end

    -- Check if the skill targets an actor and this one is better than previous
    if skill.TargetType == "actor" then
      local cell = map(actor_x,actor_y)

      if
        not cell.AoEBestActor or
        cell.AoEBestActor.BattleOpts.Priority < actor_prio
      then
        -- Set this actor as the best
        cell.AoEBestActor = actor
      end
    end
  end
end)

RAIL.Event["TARGET SELECT/POST"]:Register(0,                -- Priority
                                          "AoE select",     -- Handler name
                                          -1,               -- Max runs (infinite)
                                          function(self)
  -- Ensure there are AoE skills
  if aoe_skills:GetN() < 1 then
    -- Don't check this anymore
    self.RunsLeft = 0
  end

  -- Loop through all the AoE skills
  for i=1,aoe_skills:GetN() do
    -- Get the skill
    local skill = aoe_skills[i]
    
    -- Get options of the skill
    local prio_threshold = RAIL.State.SkillOptions[skill.ID].PriorityThreshold
    local targ_threshold = RAIL.State.SkillOptions[skill.ID].TargetThreshold

    -- Ensure that the skill is enabled
    if
      RAIL.State.SkillOptions[skill.ID].Enabled and
      (prio_threshold > 0 or targ_threshold > 0)
    then
      -- Loop through each cell of the AoE map
      for cell,x,y in aoe_maps[skill.ID]:TilesAround(0,0,skill.Range) do
        -- Check if the cell meets the thresholds
        if (prio_threshold == -1 or prio_threshold <= cell.AoEPriority) and
           (targ_threshold == -1 or targ_threshold <= cell.AoEActors)
        then
          -- Call a sub event based on skill target type
          if skill.TargetType == "ground" then
            RAIL.Event["TARGET SELECT/POST/AOE"]:Fire(skill,aoe_maps[skill.ID]:TranslateToParent(x,y))
          elseif skill.TargetType == "self" then
            RAIL.Event["TARGET SELECT/POST/AOE"]:Fire(skill,RAIL.Self)
          elseif skill.TargetType == "actor" then
            -- Get the best actor
            local best = cell.AoEBestActor
            -- Fire the event if there's an actor on this tile
            if best then
              RAIL.Event["TARGET SELECT/POST/AOE"]:Fire(skill,best)
            end
          end
        end
      end
    end
  end
end)

RAIL.Event["TARGET SELECT/POST/AOE"]:Register(0,              -- Priority
                                              "Acceptable",   -- Handler name
                                              -1,             -- Max runs (infinite)
                                              function(self,skill,...)
  if not RAIL.Target.Skill then
    RAIL.Target.Skill = { skill, unpack(arg) }
    return false
  end
end)

RAIL.Event["TARGET SELECT/POST/AOE"]:Register(10,                 -- Priority
                                              "Priority sieve",   -- Handler name
                                              -1,                 -- Max runs (infinite)
                                              function(self,skill,...)
  -- Get the priority of the skills
  local new_prio = skill:GetPriority(unpack(arg))
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
    RAIL.Target.Skill = { skill, unpack(arg) }
    return false
  end
end)
