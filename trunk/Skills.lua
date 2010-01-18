-- Skill Database
do
	Skills = {
	-- Homunculus Skills
		-- Lif
		[8001] = {
			Name = "Healing Hands",
			CastFunction = "actor",
			MaxLevel = 5,
			SPCost = function(level) return 10 + level*3 end,
		},
		[8002] = {
			Name = "Urgent Escape",
			CastFunction = "self",
			MaxLevel = 5,
			SPCost = function(level) return 15 + level*5 end,
			CastDelay = 35 * 1000,
			Duration = function(level) return (45 - level*5) * 1000 end,
		},
		[8003] = {
			Name = "Brain Surgery",
			MaxLevel = 5,
			Unusable = true,
		},
		[8004] = {
			Name = "Mental Charge",
			CastFunction = "self",
			MaxLevel = 3,
			SPCost = 100,
			CastDelay = function(level) return (5 + level*5) * 60 * 1000 end,
			Duration = function(level) return (-1 + level*2) * 60 * 1000 end,
		},
		-- Amistr
		[8005] = {
			Name = "Castling",
			CastFunction = "self",
			MaxLevel = 5,
			SPCost = 10,
		},
		[8006] = {
			Name = "Amistr Bulwark",
			CastFunction = "self",
			MaxLevel = 5,
			SPCost = function(level) return 15 + level*5 end,
			Duration = function(level) return (45 - level*5) * 1000 end,
		},
		[8007] = {
			Name = "Adamantium Skin",
			Unusable = true,
			MaxLevel = 5,
		},
		[8008] = {
			Name = "Blood Lust",
			CastFunction = "self",
			MaxLevel = 3,
			CastDelay = function(level) return level*300 * 1000 end,
			Duration = function(level)
				if level < 3 then
					return level*60 * 1000
				else
					return 300 * 1000
				end
			end,
		},
		-- Filir
		[8009] = {
			Name = "Moonlight",
			CastFunction = "actor",
			MaxLevel = 5,
			SPCost = function(level) return 4 * level end,
		},
		[8010] = {
			Name = "Flitting",
			CastFunction = "self",
			MaxLevel = 5,
			SPCost = function(level) return 20 + level*10 end,
			CastDelay = function(level)
				if level < 5 then
					return (50 + level*10) * 1000
				else
					return 120 * 1000
				end
			end,
			Duration = function(level) return (65 - level*5) * 1000 end,
		},
		[8011] = {
			Name = "Accelerated Flight",
			CastFunction = "self",
			MaxLevel = 5,
			CastDelay = function(level)
				if level < 5 then
					return (50 + level*10) * 1000
				else
					return 120 * 1000
				end
			end,
		},
		[8012] = {
			Name = "S.B.R.44",
			CastFunction = "actor",
			MaxLevel = 3,
			SPCost = 1,
		},
		-- Vanilmirth
		[8013] = {
			Name = "Caprice",
			CastFunction = "actor",
			MaxLevel = 5,
			SPCost = function(level) return 20 + level*2 end,
			CastDelay = function(level) return level * 700 end,
		},
		[8014] = {
			Name = "Chaotic Blessings",
			CastFunction = "self",
			MaxLevel = 5,
			SPCost = 40,
		},
		[8015] = {
			Name = "Instruction Change",
			MaxLevel = 5,
			Unusable = true,
		},
		[8016] = {
			Name = "Self-Destruction",
			CastFunction = "actor",
			MaxLevel = 3,
			SPCost = 15,
		},

	-- Mercenary Skills
		-- Fencer specific
		[8201] = {
			Name = "Bash",
			CastFunction = "actor",
			MaxLevel = 10,
			SPCost = function(level)
				if level <= 5 then
					return 8
				else
					return 15
				end
			end,
		},
		[8202] = {
			Name = "Magnum Break",
			CastFunction = "self",
			MaxLevel = 10,
			SPCost = function(level) return 21 - math.ceil(level/2) end,
			CastDelay = 2 * 1000,
		},
		[8203] = {
			Name = "Bowling Bash",
			CastFunction = "actor",
			MaxLevel = 10,
			SPCost = function(level) return 12 + level end,
		},
		[8204] = {
			Name = "Parry",
			CastFunction = "self",
			MaxLevel = 10,
			SPCost = 50,
			Duration = function(level) return (10 + level*5) * 1000 end,
		},
		[8205] = {
			Name = "Shield Reflect",
			CastFunction = "self",
			MaxLevel = 10,
			SPCost = function(level) return 30 + level*5 end,
			CastDelay = 1 * 1000,
			Duration = 300 * 1000,
		},
		[8206] = {
			Name = "Frenzy",
			CastFunction = "self",
			MaxLevel = 1,
			SPCost = 200,
			-- TODO: special duration (lasts until HP < 100)
		},

		-- Archer specific
		[8207] = {
			Name = "Double Strafe",
			CastFunction = "actor",
			MaxLevel = 10,
			SPCost = 12,
		},
		[8208] = {
			Name = "Arrow Shower",
			CastFunction = "ground",
			MaxLevel = 10,
			SPCost = 15,
			CastDelay = 1 * 1000,
		},
		[8209] = {
			Name = "Skid Trap",
			CastFunction = "ground",
			MaxLevel = 5,
			SPCost = 10,
		},
		[8210] = {
			Name = "Land Mine",
			CastFunction = "ground",
			MaxLevel = 5,
			SPCost = 10,
		},
		[8211] = {
			Name = "Sandman",
			CastFunction = "ground",
			MaxLevel = 5,
			SPCost = 12,
		},
		[8212] = {
			Name = "Freezing Trap",
			CastFunction = "ground",
			MaxLevel = 5,
			SPCost = 10,
		},
		[8213] = {
			Name = "Remove Trap",
			-- TODO: are traps actors?
			CastFunction = function(self,target) end,
			MaxLevel = 1,
			SPCost = 5,
		},
		[8214] = {
			Name = "Arrow Repel",
			CastFunction = "actor",
			MaxLevel = 1,
			SPCost = 15,
		},
		[8215] = {
			Name = "Focused Arrow Strike",
			CastFunction = "actor",
			MaxLevel = 5,
			SPCost = function(level) return 15 + level*3 end,
			CastTime = 2 * 1000,
			CastDelay = 1.5 * 1000,
		},

		-- Lancer specific
		[8216] = {
			Name = "Pierce",
			CastFunction = "actor",
			MaxLevel = 10,
			SPCost = 7,
		},
		[8217] = {
			Name = "Brandish Spear",
			CastFunction = "actor",
			MaxLevel = 10,
			SPCost = 12,
			CastTime = 1 * 1000,
			CastDelay = 1 * 1000,
		},
		[8218] = {
			Name = "Clashing Spiral",
			CastFunction = "actor",
			MaxLevel = 5,
			SPCost = function(level) return 15 + level*3 end,
			CastTime = function(level)
				if level < 5 then
					return (0.1 + level*0.2) * 1000
				else
					return 1 * 1000
				end
			end,
			CastDelay = function(level) return (1 + level*0.2) * 1000 end,
		},
		[8219] = {
			Name = "Defending Aura",
			CastFunction = "self",
			MaxLevel = 5,
			SPCost = 30,
			CastDelay = 1 * 1000,
			Duration = 180 * 1000,
		},
		[8220] = {
			Name = "Guard",
			CastFunction = "self",
			MaxLevel = 10,
			SPCost = function(level) return 10 + level*2 end,
			Duration = 300 * 1000,
		},
		[8221] = {
			Name = "Sacrifice",
			CastFunction = "actor",
			MaxLevel = 5,
			SPCost = 25,
			CastTime = 3 * 1000,
			CastDelay = 3 * 1000,
			Duration = function(level) return (15 + level*15) * 1000 end,
		},

		-- Mercenary inspecific
		[8222] = {
			Name = "Magnificat",
			CastFunction = "self",
			MaxLevel = 5,
			SPCost = 40,
			CastTime = 4 * 1000,
			CastDelay = 2 * 1000,
			Duration = function(level) return (15 + level*15) * 1000 end,
		},
		[8223] = {
			Name = "Weapon Quicken",
			CastFunction = "self",
			MaxLevel = 10,
			SPCost = function(level)
				if level < 3 or level >=5 then
					return 10 + level*4
				else
					return 20 + level*2
				end
			end,
			Duration = function(level) return (level*30) * 1000 end,
		},
		[8224] = {
			Name = "Sight",
			CastFunction = "self",
			MaxLevel = 1,
			SPCost = 10,
			Duration = 10 * 1000,
		},
		[8225] = {
			Name = "Crash",
			-- 3 hits x 100% + 10%/level attack; 6%/level chance to stun
			CastFunction = "actor",
			MaxLevel = 5,
			SPCost = 10,
			CastTime = 1 * 1000,
			CastDelay = 2 * 1000,
		},
		[8226] = {
			Name = "Regain",
			-- Sleep and stun recovery
			CastFunction = "actor",
			MaxLevel = 1,
			SPCost = 10,
		},
		[8227] = {
			Name = "Tender",
			-- Frozen and stone recovery
			CastFunction = "actor",
			MaxLevel = 1,
			SPCost = 10,
		},
		[8228] = {
			Name = "Benediction",
			-- Curse and blind recovery
			CastFunction = "actor",
			MaxLevel = 1,
			SPCost = 10,
		},
		[8229] = {
			Name = "Recuperate",
			-- Poison and silence recovery
			CastFunction = "actor",
			MaxLevel = 1,
			SPCost = 10,
		},
		[8230] = {
			Name = "Mental Cure",
			-- Hallucination and chaos recovery
			CastFunction = "actor",
			MaxLevel = 1,
			SPCost = 10,
		},
		[8231] = {
			Name = "Compress",
			-- Bleeding recovery
			CastFunction = "actor",
			MaxLevel = 1,
			SPCost = 10,
		},
		[8232] = {
			Name = "Provoke",
			CastFunction = "actor",
			MaxLevel = 10,
			SPCost = function(level) return 3 + level*1 end,
			Duration = 30 * 1000,
		},
		[8233] = {
			Name = "Berserk",
			-- Auto-provoke self; not Frenzy
			MaxLevel = 1,
			Unusable = true,
		},
		[8234] = {
			Name = "Decrease AGI",
			CastFunction = "actor",
			MaxLevel = 10,
			SPCost = function(level) return 13 + level*2 end,
			CastTime = 1 * 1000,
			CastDelay = 1 * 1000,
			Duration = function(level) return (20 + level*10) * 1000 end,
		},
		[8235] = {
			Name = "Scapegoat",
			CastFunction = "self",
			MaxLevel = 1,
			SPCost = 5,
			CastTime = 3 * 1000,
		},
		[8236] = {
			Name = "Lex Divina",
			CastFunction = "actor",
			MaxLevel = 10,
			SPCost = function(level)
				if level < 6 then
					return 20
				else
					return 20 - level*2
				end
			end,
			CastDelay = 3 * 1000,
			Duration = function(level)
				if level < 6 then
					return (25 + level*5) * 1000
				else
					return 60 * 1000
				end
			end,
		},
		[8237] = {
			Name = "Sense",
			CastFunction = "actor",
			MaxLevel = 1,
			SPCost = 10,
		},
	}

	-- Standard cast functions
	local CastFunctions = {
		["self"] = function(self)
			-- TODO: Log the skill usage

			-- Use the skill
			SkillObject(RAIL.Self.ID,self.Level,self.ID,RAIL.Self.ID)
		end,
		["actor"] = function(self,actor)
			-- TODO: Log the skill usage against actor

			-- Use the skill
			SkillObject(RAIL.Self.ID,self.Level,self.ID,actor)
		end,
		["ground"] = function(self,x,y)
			-- Ensure we've got coordinates
			if RAIL.IsActor(x) then
				-- TODO: Log the skill usage against ground
				y = x.Y[0]
				x = x.X[0]
			else
				-- TODO: Log the skill usage against ground
			end

			-- Use the skill
			SkillGround(RAIL.Self.ID,self.Level,self.ID,x,y)
		end,
	}

	local function_or_number = function(f,arg)
		if type(f) == "function" then
			return f(arg)
		elseif type(f) == "number" then
			return f
		end
		return 0
	end

	-- Build a RAIL-usable skill table
	do
		local Skills_rebuild = { }
		for id,parameters in Skills do
			-- Create a skill table
			local skill = {
				Name = parameters.Name,
			}

			-- Select the cast function
			local cast_func
			if type(parameters.CastFunction) == "function" then
				cast_func = parameters.CastFunction
			elseif type(parameters.CastFunction) == "string" then
				cast_func = CastFunctions[parameters.CastFunction]
			else
				cast_func = function(self)
					-- TODO: Log this
				end
			end

			-- Build the skill-level tables
			for i=1,parameters.MaxLevel do
				-- Build the table
				skill[i] = {
					Name = StringBuffer.New()
						:Append(parameters.Name)
						:Append(" (level ")
						:Append(i)
						:Append(")")
						:Get(),
					ID = id,
					Level = i,
					Cast = cast_func,
					SPCost = function_or_number(parameters.SPCost,i),
					CastTime = function_or_number(parameters.CastTime,i),
					CastDelay = function_or_number(parameters.CastDelay,i),
					Duration = function_or_number(parameters.Duration,i),
				}
			end

			-- Skills that have a max level of 1 don't need to specify level
			if parameters.MaxLevel == 1 then
				skill[1].Name = skill.Name
			end

			-- Default the skill to using the highest level
			setmetatable(skill,{
				__index = skill[parameters.MaxLevel],
			})

			-- Add the skill to the skill-table rebuild
			Skills_rebuild[id] = skill
		end

		-- Replace the skills table
		Skills = Skills_rebuild
	end
end
