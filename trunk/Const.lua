--[[

This file is part of RampageAI.

RampageAI is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

RampageAI is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with RampageAI; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

--]]

-----------------------
-- GRAVITY provided* --
-----------------------

-- *Comments added


--  c function

--[[
function	TraceAI (string) end
function	MoveToOwner (id) end
function 	Move (id,x,y) end
function	Attack (id,id) end
function 	GetV (V_,id) end
function	GetActors () end
function	GetTick () end
function	GetMsg (id) end
function	GetResMsg (id) end
function	SkillObject (id,level,skill,target) end
function	SkillGround (id,level,skill,x,y) end
function	IsMonster (id) end

--]]





-------------------------------------------------
-- constants
-------------------------------------------------

----------------------------------
-- Values for the GetV function --
----------------------------------
V_OWNER				=	0		-- Homunculus owner's ID
V_POSITION			=	1		-- Current (X,Y) coordinates
V_TYPE				=	2		-- Defines an object (Not Implemented)
V_MOTION			=	3		-- Returns current action
V_ATTACKRANGE			=	4		-- Attack range
V_TARGET			=	5		-- Target of an attack or skill
V_SKILLATTACKRANGE		=	6		-- Skill attack range
V_HOMUNTYPE			=	7		-- Returns the type of Homunculus
V_HP				=	8		-- Current HP amount
V_SP				=	9		-- Current SP amount
V_MAXHP				=	10		-- Maximum HP amount
V_MAXSP				=	11		-- Maximum SP amount
V_MERTYPE			=	12		-- Mercenary Type
----------------------------------





--------------------------------------------
-- Return values for GetV(V_HOMUNTYPE,id) --
--------------------------------------------

LIF			= 1
AMISTR			= 2
FILIR			= 3
VANILMIRTH		= 4
LIF2			= 5
AMISTR2			= 6
FILIR2			= 7
VANILMIRTH2		= 8
LIF_H			= 9
AMISTR_H		= 10
FILIR_H			= 11
VANILMIRTH_H		= 12
LIF_H2			= 13
AMISTR_H2		= 14
FILIR_H2		= 15
VANILMIRTH_H2		= 16

--------------------------------------------


-----------------------------------------
-- Return values for GetV(V_MOTION,id) --
-----------------------------------------
MOTION_STAND	=  0	-- Standing still
MOTION_MOVE	=  1	-- Moving
MOTION_ATTACK	=  2	-- Attacking
MOTION_DEAD     =  3	-- Laying dead
MOTION_DAMAGE	=  4	-- Taking damage
MOTION_BENDDOWN	=  5	-- Bending over (pick up item, set trap)
MOTION_SIT	=  6	-- Sitting down
MOTION_SKILL	=  7	-- Used a skill
MOTION_CASTING	=  8	-- Casting a skill
MOTION_ATTACK2	=  9	-- Attacking (double dagger?)
MOTION_TOSS	= 12	-- Toss something (spear boomerang / aid potion)
MOTION_COUNTER	= 13	-- Counter-attack
MOTION_PERFORM	= 17	-- Performance
MOTION_JUMP_UP	= 19	-- TaeKwon Kid Leap -- rising
MOTION_JUMP_FALL= 20	-- TaeKwon Kid Leap -- falling
MOTION_SOULLINK	= 23	-- Soul linker using a link skill
MOTION_TUMBLE	= 25	-- Tumbling / TK Kid Leap Landing
MOTION_BIGTOSS	= 28 	-- A heavier toss (slim potions / acid demonstration)
-----------------------------------------

------------------------------------------
-- Return values for GetV(V_MERTYPE,id) --
------------------------------------------
ARCHER01	=  1
ARCHER02	=  2
ARCHER03	=  3
ARCHER04	=  4
ARCHER05	=  5
ARCHER06	=  6
ARCHER07	=  7
ARCHER08	=  8
ARCHER09	=  9
ARCHER10	= 10
LANCER01	= 11
LANCER02	= 12
LANCER03	= 13
LANCER04	= 14
LANCER05	= 15
LANCER06	= 16
LANCER07	= 17
LANCER08	= 18
LANCER09	= 19
LANCER10	= 20
SWORDMAN01	= 21		
SWORDMAN02	= 22	
SWORDMAN03	= 23
SWORDMAN04	= 24
SWORDMAN05	= 25
SWORDMAN06	= 26
SWORDMAN07	= 27
SWORDMAN08	= 28
SWORDMAN09	= 29
SWORDMAN10	= 30
------------------------------------------

-------------------------------------------------
-- Return values for GetMsg(id), GetResMsg(id) --
-------------------------------------------------
NONE_CMD			= 0		-- (Cmd)
MOVE_CMD			= 1		-- (Cmd, X, Y)
STOP_CMD			= 2		-- (Cmd)		** NOT USED **
ATTACK_OBJECT_CMD		= 3		-- (Cmd, ID)
ATTACK_AREA_CMD			= 4		-- (Cmd, X, Y)		** NOT USED **
PATROL_CMD			= 5		-- (Cmd, X, Y)		** NOT USED **
HOLD_CMD			= 6		-- (Cmd)		** NOT USED **
SKILL_OBJECT_CMD		= 7		-- (Cmd, Level, Type, ID)
SKILL_AREA_CMD			= 8		-- (Cmd, Level, Type, X, Y)
FOLLOW_CMD			= 9		-- (Cmd)
-------------------------------------------------
