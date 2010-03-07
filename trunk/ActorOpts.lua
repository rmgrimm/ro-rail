-- Actor options
RAIL.Validate.ActorOptions = {is_subtable=true}
RAIL.Validate.ActorOptions.Default = {is_subtable=true,
	Name = {"string","unknown"},
	Friend = {"boolean",false},
	Priority = {"number",0},		-- higher number, higher priority; eg, 10 is higher than 1
	AttackAllowed = {"boolean",true},
	DefendOnly = {"boolean",false},

	SkillsAllowed = {"boolean",true},
	MinSkillLevel = {"number",1,1,10},
	MaxSkillLevel = {"number",5,1,10},
	TicksBetweenSkills = {"number",0,0},
	MaxCastsAgainst = {"number",-1,-1},	-- -1 is unlimited

	-- amount of time to ignore the actor
	DefaultIgnoreTicks = {"number",10000,1000},
	-- When chasing fails, ignore actor after this many ticks
	--	(-1 is never; values below 2000 will use 2000 instead)
	IgnoreAfterChaseFail = {"number",5000,-1},
}
RAIL.Validate.ActorOptions.ByType = {is_subtable=true}
RAIL.Validate.ActorOptions.ByID = {is_subtable=true}

-- Max homunculus skill level is 5
if not RAIL.Mercenary then
	RAIL.Validate.ActorOptions.Default.MinSkillLevel[4] = 5
	RAIL.Validate.ActorOptions.Default.MaxSkillLevel[4] = 5
end

-- Actor Battle Options
do
	-- TODO: Optimize Actor Options... (if it becomes a problem)
	--
	--	Actor[id].BattleOpts (metatable; checks ByID, ByType, Default)
	--	ByID checks ByTypes
	--	ByTypes checks Defaults
	--	Defaults/ByID/ByTypes all trigger validation of tables
	--		RAIL.State.ActorOptions
	--		RAIL.State.ActorOptions.[Defaults/ByID/ByType]
	--
	--	Called almost every cycle...
	--

	-- Defaults
	do
		BattleOptsDefaults = { }
		setmetatable(BattleOptsDefaults,{
			__index = function(t,key)
				return RAIL.State.ActorOptions.Default[key]
			end
		})
	end

	-- Default special actor types
	-- TODO: Clean up this ugly mess
	local SpecialTypes = {}
	do
		-- Plants
		SpecialTypes.Plants = {
			Types = {
				[1078] = true,	-- Red Plant
				[1079] = true,	-- Blue Plant
				[1080] = true,	-- Green Plant
				[1081] = true,	-- Yellow Plant
				[1082] = true,	-- White Plant
				[1083] = true,	-- Shining Plant
				[1084] = true,	-- Red Mushroom
				[1085] = true,	-- Black Mushroom
			},
			Options = {
				Name = "Plant",
				SkillsAllowed = false,
			},
		}
		setmetatable(SpecialTypes.Plants.Options,{
			__index = function(t,idx)
				if idx == "Priority" then
					return BattleOptsDefaults.Priority - 1
				end
	
				return BattleOptsDefaults[idx]
			end,
		})

		-- Alchemist-summoned plants
		SpecialTypes.Summons = {
			Types = {
				[1555] = true,	-- Summoned Parasite
				[1575] = true,	-- Summoned Flora
				[1579] = true,	-- Summoned Hydra
				[1589] = true,	-- Summoned Mandragora
				[1590] = true,	-- Summoned Geographer
			},
			Options = {
				Name = "Summoned",
				AttackAllowed = false,
				SkillsAllowed = false,
			},
		}

		-- Homunculi
		SpecialTypes.Lif = {
			Types = {},
			Options = {
				Name = "Lif",
			},
		}
		SpecialTypes.Amistr = {
			Types = {},
			Options = {
				Name = "Amistr",
			},
		}
		SpecialTypes.Filir = {
			Types = {},
			Options = {
				Name = "Filir",
			},
		}
		SpecialTypes.Vanilmirth = {
			Types = {},
			Options = {
				Name = "Vanilmirth",
			},
		}
		-- Populate the homunculus types
		for i=1,16 do
			local mod = math.mod(i,4)
			if mod == 1 then
				SpecialTypes.Lif.Types[6000 + i] = true
			elseif mod == 2 then
				SpecialTypes.Amistr.Types[6000 + i] = true
			elseif mod == 3 then
				SpecialTypes.Filir.Types[6000 + i] = true
			else
				SpecialTypes.Vanilmirth.Types[6000 + i] = true
			end
		end

		-- Mercenary types
		SpecialTypes.ArcherMerc = {
			Types = {},
			Options = {
				Name = "Archer Mercenary",
			},
		}
		SpecialTypes.LancerMerc = {
			Types = {},
			Options = {
				Name = "Lancer Mercenary",
			},
		}
		SpecialTypes.SwordmanMerc = {
			Types = {},
			Options = {
				Name = "Swordman Mercenary",
			},
		}
		-- Populate the mercenary types
		for i=1,30 do
			if i <= 10 then
				SpecialTypes.ArcherMerc.Types[6016 + i] = true
			elseif i <= 20 then
				SpecialTypes.LancerMerc.Types[6016 + i] = true
			else
				SpecialTypes.SwordmanMerc.Types[6016 + i] = true
			end
		end


		-- Ensure all the special types' options tables have metatables
		local st_mt = {
			__index = BattleOptsDefaults,
		}
		-- And redo the SpecialTypes table
		local SpecialTypes_redo = {}
		for id,table in SpecialTypes do
			if
				type(table) == "table" and
				type(table.Types) == "table" and
				type(table.Options) == "table"
			then
				local mt = getmetatable(table.Options)

				if mt == nil then
					setmetatable(table.Options,st_mt)
				end

				for type in table.Types do
					SpecialTypes_redo[type] = table.Options
				end
			end
		end
		SpecialTypes = SpecialTypes_redo
	end

	-- By Type
	do
		-- Private key to access each type
		local type_key = {}

		-- Private key to access the default table
		local default_key = {}

		-- Auto-generated subtables will use this metatable
		local mt = {
			__index = function(t,key)
				-- Check the RAIL.State.ActorOptions.ByType table
				local ByType = RAIL.State.ActorOptions.ByType
				local type_num = t[type_key]
				if type(ByType[type_num]) ~= "table" then
					ByType[type_num] = { }
				end

				-- Use value from ByType table if non-nil
				local value = ByType[type_num][key]
				if value ~= nil then
					local validated = RAIL.Validate(value,RAIL.Validate.ActorOptions.Default[key])

					-- Check to see if it was changed during validation
					if value ~= validated then
						-- Save the updated version
						ByType[id_num][key] = validated

						-- TODO: set dirty flag
					end

					return validated
				end

				-- Otherwise, use default
				return t[default_key][key]
			end
		}

		BattleOptsByType = {
			-- Mercenaries will use default options against actors of unknown type
			[-2] = BattleOptsDefaults
		}

		-- Generate subtables for each type requested
		setmetatable(BattleOptsByType,{
			__index = function(t,key)
				-- Make sure there are options for it
				if RAIL.State.ActorOptions.ByType[key] == nil then
					-- Check for special types
					local special = SpecialTypes[key]
					if special then
						return special
					end

					return nil
				end

				local ret = {
					[type_key] = key,
					[default_key] = BattleOptsDefaults,
				}

				-- Check for special types
				local special = SpecialTypes[key]
				if special then
					ret[default_key] = special
				end

				setmetatable(ret,mt)
				t[key] = ret

				return ret
			end
		})
	end

	-- By ID
	do
		-- Private key to access each ID
		local id_key = {}

		local mt = {
			__index = function(t,key)
				-- Check the RAIL.State.ActorOptions.ByID table
				local ByID = RAIL.State.ActorOptions.ByID
				local id_num = t[id_key]
				if type(ByID[id_num]) ~= "table" then
					ByID[id_num] = { }
				end

				-- Use value from ByID table if non-nil
				local value = ByID[id_num][key]
				if value ~= nil then
					local validated = RAIL.Validate(value,RAIL.Validate.ActorOptions.Default[key])

					-- Check to see if it was changed during validation
					if value ~= validated then
						-- Save the updated version
						ByID[id_num][key] = validated

						-- TODO: set dirty flag
					end

					return validated
				end

				-- Otherwise, use ByType table
				local t = BattleOptsByType[Actors[id_num].Type]
					or BattleOptsDefaults
				return t[key]
			end
		}

		BattleOptsByID = { }
		setmetatable(BattleOptsByID,{
			__index = function(t,key)
				-- Make sure there are options for it
				if RAIL.State.ActorOptions.ByID[key] == nil then
					return nil
				end

				local ret = {
					[id_key] = key,
				}

				setmetatable(ret,mt)
				t[key] = ret

				return ret
			end
		})
	end

end
