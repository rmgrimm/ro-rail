-- Validation options
RAIL.Validate.AcquireWhileLocked = {"boolean",false}
RAIL.Validate.Aggressive = {"boolean",false}
RAIL.Validate.AssistOptions = {is_subtable = true,
  Owner = {"string","indifferent",nil},
  Other = {"string","indifferent",nil},   -- allowed options are set further down this file
  Friend = {"string","indifferent",nil},  --  (search "RAIL.Validate.AssistOptions.Owner")
}
RAIL.Validate.AutoPassiveHP = {"number",0,0}
setmetatable(RAIL.Validate.AutoPassiveHP,{
  __index = function(self,idx)
    -- If percentages, then maximum should be 99
    if idx == 4 and RAIL.State.AutoPassiveHPisPercent then
      return 99
    end
  end,
})
RAIL.Validate.AutoPassiveHPisPercent = {"boolean",false}
RAIL.Validate.AutoUnPassiveHP = {"number"}
setmetatable(RAIL.Validate.AutoUnPassiveHP,{
  __index = function(self,idx)
    -- AutoUnPassiveHP should have a default and minimum of AutoPassiveHP
    if idx == 2 or idx == 3 then
      return RAIL.State.AutoPassiveHP + 1
    end
    
    -- And maximum should be 100 if using percents
    if idx == 4 and RAIL.State.AutoPassiveHPisPercent then
      return 100
    end

    return nil
  end,
})
RAIL.Validate.DefendOptions = {is_subtable = true,
  DefendWhilePassive = {"boolean",true},
  DefendWhileAggro = {"boolean",true},
  OwnerThreshold = {"number",1,0},
  SelfThreshold = {"number",5,0},
  FriendThreshold = {"number",4,0},
}
RAIL.Validate.AttackWhileChasing = {"boolean",false}

do
  -- Aggressive Support
  RAIL.IsAggressive = function(actor)
    -- TODO: Add support for checking RAIL.Other's aggressive state

    -- Non-aggressive means always non-aggressive
    if not RAIL.State.Aggressive then
      return false
    end
    
    -- Check for HP changes updating auto-passive mode
    do
      local hp = actor.HP[0]
      local log_percent = ""
      if RAIL.State.AutoPassiveHPisPercent then
        hp = math.floor(hp / actor:GetMaxHP() * 100)
        log_percent = "%"
      end
      
      if not actor.AutoPassive then
        if hp < RAIL.State.AutoPassiveHP then
          RAIL.LogT(10,"Temporarily entering passive mode due to HP below threshold; hp={1}{3}, threshold={2}{3}.",
            hp, RAIL.State.AutoPassiveHP, log_percent)
          actor.AutoPassive = true
        end
      else
        if hp >= RAIL.State.AutoUnPassiveHP then
          RAIL.LogT(10,"Disabling temporary passive mode due to HP above threshold; hp={1}{3}, threshold={2}{3}.",
            hp, RAIL.State.AutoUnPassiveHP, log_percent)
          actor.AutoPassive = nil
        end
      end
    end
    
    -- If auto-passive, don't return aggressive mode
    if actor.AutoPassive then
      return false
    end

    return true
  end
end

do
  local Potential = List.New()

  RAIL.Event["AI CYCLE"]:Register(10,                         -- Priority
                                  "Reset Potential Targets",  -- Handler name
                                  -1,                         -- Max runs (negative means infinite)
                                  function()
    Potential:Clear()
  end)

  do
    -- A function to return true only if the argument passed is an offensive motion
    local offensive_motions = {
      [MOTION.ATTACK] = true,
      [MOTION.ATTACK2] = true,
      [MOTION.SKILL] = true,
      [MOTION.CASTING] = true,

      [MOTION.FOCUSED_ARROW] = true,

      [MOTION.TK_COUNTER] = true,
      [MOTION.TK_FLYINGKICK] = true,
      [MOTION.TK_TORNADO] = true,
      [MOTION.TK_HEELDROP] = true,
      [MOTION.TK_ROUNDHOUSE] = true,

      [MOTION.NJ_SKILL] = true,
      [MOTION.NJ_CASTING] = true,
      [MOTION.GS_GATLING] = true,
      [MOTION.GS_CASTING] = true,
    }
    local function offensive_motion(v) return offensive_motions[v] == true end

    -- A function to find the target of an actor's offensive motion
    local function offensive_target(actor)
      -- Find the most recent offensive motion
      local most_recent = History.FindMostRecent(actor.Motion,offensive_motion,nil,3000)
      
      -- If no offensive motion, no target
      if most_recent == nil then return nil end
      
      -- Return the target
      return Actors[actor.Target[most_recent]]
    end
    
    -- Functions to sort into categories
    local sorters = {
      ["indifferent"] = function(assist,avoid,actor)
        -- Do nothing; indifferent to their target
      end,
      ["assist"] = function(assist,avoid,actor)
        local target = offensive_target(actor)

        if target ~= nil then
          assist[target.ID] = target
        end
      end,
      ["avoid"] = function(assist,avoid,actor)
        local target = offensive_target(actor)
        
        if target ~= nil then
          avoid[target.ID] = target
        end
      end,
    }
    
    -- Set the valid options for AssistOptions
    RAIL.Validate.AssistOptions.Owner[3] = sorters
    RAIL.Validate.AssistOptions.Other[3] = sorters
    RAIL.Validate.AssistOptions.Friend[3] = sorters
  
    RAIL.Event["TARGET SELECT/ENEMY"]:Register(10,               -- Priority
                                               "Assist/avoid",   -- Handler name
                                               -1,               -- Max runs (negative means infinite)
                                               function()        -- Handler function
      -- First build tables of assist/avoid (and drop indifferent)
      local assist = {}
      local avoid = {}
      
      do
        sorters[RAIL.State.AssistOptions.Owner](assist,avoid,RAIL.Owner)
        sorters[RAIL.State.AssistOptions.Other](assist,avoid,RAIL.Other)
        
        local f = sorters[RAIL.State.AssistOptions.Friend]
        for id,actor in RAIL.ActorLists.Friends do
          f(assist,avoid,actor)
        end
      end
      
      -- Loop through each assist
      for id,target in pairs(assist) do
        -- Check if target is on the enemy actor list
        if RAIL.ActorLists.Enemies[id] then
          -- Assist against this target; add a 1-item table of potentials to
          -- the potential target list
          Potential:PushRight{ [id] = target, Name = "Assist", }
  
          -- Continue handling the event
          return true
        end
      end
      
      -- Create a new list of enemies to contain the non-avoided ones
      local enemies,enemies_n = {},0
  
      -- Loop through each enemy, and only add it to the new enemy table if it is
      -- not avoided
      for id,target in pairs(RAIL.ActorLists.Enemies) do
        if not avoid[id] then
          -- Add it to the new table
          enemies[id] = target
          
          -- Count the number added
          enemies_n = enemies_n + 1
        end
      end
  
      -- Check to see if there are actors left after the avoid logic
      if enemies_n < 1 then
        -- Don't modify the actual enemies list
        return true
      end
      
      -- Replace the enemies list with one that's had avoided targets removed
      RAIL.ActorLists.Enemies = enemies
    end)
  end
  
  do
    local function prioritization(defend_actors,defend_n,defend_prio,actors,n,prio)
      -- Make sure something is attacking this actor, and the priority threshold
      -- is above 0
      if n < 1 or prio < 1 then
        return defend_actors,defend_n,defend_prio
      end
      
      -- Check if this actor reaches the prioritization threshold
      if n >= prio then
        -- Check the priority against the existing defense priority
        if
          prio > defend_prio or
          (prio == defend_prio and n > defend_n)
        then
          -- Reset the defense list
          return Table.New():Append(actors),n,prio
        elseif prio == defend_priority and n == defend_n then
          -- Add to the defense list
          defend_actors:Append(actors)
        end
  
      -- Check if anything else was prioritized
      elseif defend_prio == 0 then
        -- Nothing was, add actor to the list
        defend_actors:Append(actors)
      end
  
      return defend_actors,defend_n,defend_prio
    end
    
    -- Target counting support function
    local function getN(actor,potentials)
      -- Get the number of targets attacking actor
      local n = actor.TargetOf:GetN()
      
      -- Ensure that at least one is in the enemies list
      for i=1,n do
        if RAIL.ActorLists.Enemies[actor.TargetOf[i].ID] then
          -- One of the actor's attackers is in the potentials list, return N
          return n
        end
      end
  
      -- Nothing in actor's TargetOf list is attackable, return 0
      return 0
    end
    
    RAIL.Event["TARGET SELECT/ENEMY"]:Register(20,          -- Priority
                                               "Defense",   -- Handler name
                                               -1,          -- Max runs (negative means infinite)
                                               function()   -- Handler function
      if not RAIL.IsAggressive(RAIL.Self) then
        -- If not aggressive and not defending while passive, don't run
        -- defense code
        if not RAIL.State.DefendOptions.DefendWhilePassive then
          return true
        end
      else
        -- If aggressive and not prioritizing defense, don't run defense code
        if not RAIL.State.DefendOptions.DefendWhileAggro then
          return true
        end
      end
      
      -- Get the number of targets attacking owner and self
      local owner_n = getN(RAIL.Owner,RAIL.ActorLists.Enemies)
      local self_n  = getN(RAIL.Self, RAIL.ActorLists.Enemies)
  
      -- Check for the highest number of actors attacking friends/other
      local friends_n,friends_actors = 0,Table.New()
      if RAIL.State.DefendOptions.FriendThreshold > 0 then
        -- First set other as the actor
        if RAIL.Self ~= RAIL.Other then
          friends_n = getN(RAIL.Other,RAIL.ActorLists.Enemies)
          friends_actors:Append(RAIL.Other)
        end
        
        -- Check all the friends
        for id,actor in RAIL.ActorLists.Friends do
          local n = getN(actor,RAIL.ActorLists.Enemies)
          
          if n > friends_n then
            friends_actors = Table.New()
            friends_actors:Append(actor)
            friends_n = n
          elseif n == friends_n then
            friends_actors:Append(actor)
          end
        end
      end
      
      -- Check if any actor is being attacked
      if owner_n == 0 and self_n == 0 and friends_n == 0 then
        -- Don't add a table of potentials
        return true
      end
      
      -- Keep a list of the actors that will be defended
      local defend_actors = Table.New()
      local defend_n = 0
      local defend_prio = 0

      -- Check to see if we should defend ourself
      defend_actors,defend_n,defend_prio = prioritization(defend_actors,
                                                          defend_n,
                                                          defend_prio,
                                                          RAIL.Self,
                                                          self_n,
                                                          RAIL.State.DefendOptions.SelfThreshold)

      -- Check to see if we should defend our owner
      defend_actors,defend_n,defend_prio = prioritization(defend_actors,
                                                          defend_n,
                                                          defend_prio,
                                                          RAIL.Owner,
                                                          owner_n,
                                                          RAIL.State.DefendOptions.OwnerThreshold)
  
      -- Check to see if we should defend our friends
      defend_actors,defend_n,defend_prio = prioritization(defend_actors,
                                                          defend_n,
                                                          defend_prio,
                                                          friends_actors,
                                                          friends_n,
                                                          RAIL.State.DefendOptions.FriendThreshold)
  
      -- Create a table with potential defend targets
      local defense = { Name = "Defense", }
      for id,defend_actor in ipairs(defend_actors) do
        for idx,actor in ipairs(defend_actor.TargetOf) do
          if RAIL.ActorLists.Enemies[actor.ID] ~= nil then
            defense[actor.ID] = actor
          end
        end
      end
      
      -- Add the table to the potentials list
      Potential:PushRight(defense)
    end)
  end
  
  RAIL.Event["TARGET SELECT/ENEMY"]:Register(30,                -- Priority
                                             "Aggressive/KS",   -- Handler name
                                             -1,                -- Max runs (negative means infinite)
                                             function()         -- Handler function
    -- If not aggressive, don't add any potential targets table
    if not RAIL.IsAggressive(RAIL.Self) then
      return true
    end
    
    -- Create a table with potential targets
    local offense,n = { Name = "Aggro", },0
    for id,actor in pairs(RAIL.ActorLists.Enemies) do
      -- Check that attacking this target would not be kill-stealing
      if not actor:WouldKillSteal() then
        offense[id] = actor
        n = n + 1
      end
    end
    
    -- If there are targets, add to the potentials list
    if n > 0 then
      Potential:PushRight(offense)
    end
  end)
  
  RAIL.Event["TARGET SELECT/ENEMY"]:Register(100,           -- Priority
                                             "Split",       -- Handler name
                                             -1,            -- Max runs (negative means infinite)
                                             function()     -- Handler function
    -- Loop through each set of actors until attack and skill potentials
    -- have been selected
    local attack = (RAIL.Target.Attack ~= nil)
    local skill  = (RAIL.Target.Skill  ~= nil) or
                   (RAIL.Self.SkillState:Get() ~= RAIL.Self.SkillState.Enum.READY)
    local attack_oor = false
    local skill_oor  = false
    repeat
      -- Get the farthest left set of tar
      local targets = Potential:PopLeft()

      -- Ensure there is a table of targets
      if not targets then break end

      -- Argument to the events, whether out-of-range targets should be
      -- added to the ChaseMap
      local attack_arg = not attack_oor
      local skill_arg  = not skill_oor

      -- Loop through each actor in the group
      for id,actor in pairs(targets) do
        if type(id) == "number" then
          -- Check if a potential attack target has been found yet
          if not attack then
            -- Run this actor through the attack selection event
            local r1,r2 = RAIL.Event["TARGET SELECT/ENEMY/ATTACK"]:Fire(actor,attack_arg)

            -- If the actor was usable, don't continue checking other groups
            -- of actors
            if r1 then
              attack = true
            end
  
            -- If the actor is preferred but is out of range, don't add other
            -- groups to the ChaseMap
            if r2 then
              attack_oor = true
            end
          end
  
          -- Check if a potential skill target has been found yet
          if not skill then
            -- Run this actor through the skill selection event
            local r1 = RAIL.Event["TARGET SELECT/ENEMY/SKILL"]:Fire(actor,skill_arg)
  
            -- If the actor was usable, don't continue checking other groups
            -- of actors
            if r1 then
              skill = true
            end
  
            -- If the actor is preferred but is out of range, don't add other
            -- groups to the ChaseMap
            if r2 then
              skill_oor = true
            end
          end
        end
      end
    until attack and target
  end)
end

RAIL.Event["TARGET SELECT/ENEMY/ATTACK"]:Register(0,            -- Priority
                                                  "Allowed",    -- Handler name
                                                  -1,           -- Max runs (negative means infinite)
                                                  function(self,actor)
  -- Check if the actor is allowed
  if not actor:IsAttackAllowed() then
  RAIL.LogT(0,"allowed")
    -- Don't continue this event
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/ATTACK"]:Register(5,            -- Priority
                                                  "Hiding",     -- Handler name
                                                  -1,           -- Max runs (negative means infinite)
                                                  function(self,actor)
  -- Check if the actor is hidden (can't attack hidden)
  if actor.Hide then
    -- Don't continue this event
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/ATTACK"]:Register(10,                 -- Priority
                                                  "Chase/range",      -- Handler name
                                                  -1,                 -- Max runs (negative means infinite)
                                                  function(self,actor,can_chase)
  -- Get the attack range
  local range = RAIL.Self.AttackRange

  -- If the actor was allowed it can be chased
  if can_chase then
    -- Set the 2nd return value of the event to true
    self.Event.RetVal[2] = true
    
    -- Ensure that it will unpack properly
    if self.Event.RetVal[1] == nil then self.Event.RetVal[1] = false end

    RAIL.Event["TARGET SELECT/ENEMY/CHASE"]:Fire(actor,
                                                 range - 0.5,
                                                 actor.BattleOpts.Priority)
  end

  -- Check if the actor is outside attack range
  if RAIL.Self:DistanceTo(actor) > range then
    -- Don't continue this event
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/ATTACK"]:Register(50,             -- Priority
                                                  "Acceptable",   -- Handler name
                                                  -1,             -- Max runs (negative means infinite)
                                                  function(self,actor)
  -- Set the 1st return value of the event to true
  self.Event.RetVal[1] = true

  -- If no attack target has been selected yet, this is the best one
  if not RAIL.Target.Attack then
    RAIL.Target.Attack = actor
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/ATTACK"]:Register(60,                 -- Priority
                                                  "Priority Sieve",   -- Handler name
                                                  -1,                 -- Max runs (negative means infinite)
                                                  function(self,actor)
  -- Get the priority of the new actor and the current target
  local actor_prio  = actor.BattleOpts.Priority
  local target_prio = RAIL.Target.Attack.BattleOpts.Priority

  -- If the new actor is worse, don't continue this event
  if actor_prio < target_prio then
    return false
  end

  -- If the new actor is better, use it
  if actor_prio > target_prio then
    RAIL.Target.Attack = actor
    return false
  end
end)

do
  local last

  RAIL.Event["TARGET SELECT/ENEMY/ATTACK"]:Register(70,             -- Priority
                                                    "Select last",  -- Handler name
                                                    -1,             -- Max runs (negative means infinite)
                                                    function(self,actor)
    -- Check if the selected target is already the last target
    if RAIL.Target.Attack == last then
      -- Don't let it be replaced
      return false
    end

    -- Check if the new actor is the last target
    if actor == last then
      -- Use last cycle's target
      RAIL.Target.Attack = actor
      
      -- And don't continue this event
      return false
    end
  end)
  
  RAIL.Event["TARGET SELECT/POST"]:Register(100,                -- Priority
                                            "Save last attack", -- Handler name
                                            -1,                 -- Max runs (infinite)
                                            function()
    -- Save the attack target
    last = RAIL.Target.Attack
  end)
end
  
RAIL.Event["TARGET SELECT/ENEMY/ATTACK"]:Register(80,               -- Priority
                                                  "Self-closest",   -- Handler name
                                                  -1,               -- Max runs (negative means infinite)
                                                  function(self,actor)
  -- Get the distances
  local actor_dist  = RAIL.Self:DistanceTo(actor)
  local target_dist = RAIL.Self:DistanceTo(RAIL.Target.Attack)
  
  -- Go after the shorter distance target
  if actor_dist < target_dist then
    RAIL.Target.Attack = actor
    return false
  end
  
  if actor_dist > target_dist then
    return false
  end
end)

RAIL.Event["TARGET SELECT/ENEMY/ATTACK"]:Register(90,                       -- Priority
                                                  "Select owner's closer",  -- Handler name
                                                  -1,                       -- Max runs (negative means infinite)
                                                  function(self,actor)
  -- Get the distances
  local actor_dist  = RAIL.Owner:DistanceTo(actor)
  local target_dist = RAIL.Owner:DistanceTo(RAIL.Target.Attack)
  
  -- Go after the shorter distance target
  if actor_dist < target_dist then
    RAIL.Target.Attack = actor
    return false
  end
  
  if actor_dist > target_dist then
    return false
  end
end)

RAIL.Event["TARGET SELECT/POST"]:Register(25,                     -- Priority
                                          "AttackWhileChasing",   -- Handler name
                                          -1,                     -- Max runs (negative means infinite)
                                          function()
  -- Don't do anything if AttackWhileChasing is set
  if RAIL.State.AttackWhileChasing then
    return
  end

  -- Check if there is a chase target and an attack target
  if not RAIL.Target.Chase or not RAIL.Target.Attack then
    return
  end

  -- Get the distance of the movement
  local dist = RAIL.Self:BlocksTo(unpack(RAIL.Target.Chase))
  
  -- Check if it's a significant enough move (not just a dance attack)
  if dist > 3 then
    -- Don't attack while chasing
    RAIL.Target.Attack = nil
  end
end)

