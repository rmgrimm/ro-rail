-- Actor options
RAIL.Validate.ActorOptions = {is_subtable=true}
RAIL.Validate.ActorOptions.Default = {is_subtable=true,
	Name = {"string","unknown"},
	Friend = {"boolean",false},
	FreeForAll = {"boolean",false},

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
	--	(-1 is never; an exception to the minimum of 2000)
	IgnoreAfterChaseFail = {"number",5000,2000,nil,{ [-1] = true, },},
}
RAIL.Validate.ActorOptions.ByType = {is_subtable=true}
RAIL.Validate.ActorOptions.ByID = {is_subtable=true}

-- Max homunculus skill level is 5
if not RAIL.Mercenary then
	RAIL.Validate.ActorOptions.Default.MinSkillLevel[4] = 5
	RAIL.Validate.ActorOptions.Default.MaxSkillLevel[4] = 5
end

-- List of actor names based on type
--	Note: This is created and populated later in this file
local names

-- Set metatables to create validation options for IDs as they're referenced
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
						--	(first ByID, then ByType, then Default)
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
					--	(first ByID, then ByType, then Default)
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

		--[45] = "Portal",	-- identified by Actor.ActorType, so this is redundant

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
		-- ...
		[1025] = "Boa",
		-- ...


		[1038] = "Osiris",		-- MVP
		[1039] = "Baphomet",		-- MVP
		[1046] = "Doppelganger",	-- MVP
		[1059] = "Mistress",		-- MVP
		[1086] = "Golden Thief Bug",	-- MVP
		[1087] = "Orc Hero",		-- MVP

		-- Plants / Mushrooms
		[1078] = "Red Plant",
		[1079] = "Blue Plant",
		[1080] = "Green Plant",
		[1081] = "Yellow Plant",
		[1082] = "White Plant",
		[1083] = "Shining Plant",
		[1084] = "Black Mushroom",
		[1085] = "Red Mushroom",

		-- Alchemist Summons
		[1555] = "Summoned Parasite",
		[1575] = "Summoned Flora",
		[1579] = "Summoned Hydra",
		[1589] = "Summoned Mandragora",
		[1590] = "Summoned Geographer",
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
				if idx == 2 then
					return RAIL.State.ActorOptions.Default.Priority - 1
				end
			end,
		}
		for i=1078,1085,1 do
			-- Get the validation table
			local validate = RAIL.Validate.ActorOptions.ByType[i]

			-- Set default to nil
			validate.Priority[2] = nil

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
			[1555] = true,	-- Summoned Parasite
			[1575] = true,	-- Summoned Flora
			[1579] = true,	-- Summoned Hydra
			[1589] = true,	-- Summoned Mandragora
			[1590] = true,	-- Summoned Geographer
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
