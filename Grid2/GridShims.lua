-- Compatibility shims for the 3.3.5a client (Lua 5.1).
-- The 3.3.5 client has no C_Spell / C_UnitAuras / C_Timer / C_IncomingSummon /
-- UnitGetTotalAbsorbs / UnitPhaseReason / IsInRaid-style modern APIs and no
-- Frame:SetSize / Frame:SetShown, so this file publishes version flags and a
-- Grid2.API table bound to the native 3.3.5 functions. Must be loaded right
-- after GridCore.lua and before any file using Grid2.API or Grid2.isClassic.

local Grid2 = Grid2

-- Client version flags (Grid2 core for 3.3.5 does not define them)
Grid2.versionCli = Grid2.versionCli or select(4, GetBuildInfo())
Grid2.isClassic = true
Grid2.isVanilla = false
Grid2.isTBC     = false
Grid2.isWrath   = true
Grid2.isCata    = false
Grid2.isMoP     = false
Grid2.isWoW90   = false
Grid2.isSoD     = false

-- Player class and group/instance defaults at file scope (BCC sets these in
-- GridCore.lua, here Grid2.playerClass is assigned only in OnInitialize, i.e.
-- after all files are loaded, so files capturing it at load time would see nil).
Grid2.playerClass = Grid2.playerClass or select(2, UnitClass("player"))
Grid2.groupType = Grid2.groupType or "solo"
Grid2.instType = Grid2.instType or "other"

-- Public API table, mirrors the interface used by the BCC core files
local API = Grid2.API or {}
Grid2.API = API

-- GetSpellInfo() : native on 3.3.5
API.GetSpellInfo = GetSpellInfo

-- IsSpellInRange() : native on 3.3.5, already returns 1 / 0 / nil
API.IsSpellInRange = IsSpellInRange

-- GetSpellCooldown() : native on 3.3.5
API.GetSpellCooldown = GetSpellCooldown

-- GetSpellBookItemInfo() : native on 3.3.5
API.GetSpellBookItemInfo = GetSpellBookItemInfo

-- Role icon texcoords: natives exist on 3.3.5 for the base variants,
-- the small variants were added later, keep the BCC math fallbacks.
API.GetTexCoordsForRole = GetTexCoordsForRole or function(role)
	if role == "GUIDE" then
		return GetTexCoordsByGrid(1, 1, 256, 256, 67, 67)
	elseif role == "TANK" then
		return GetTexCoordsByGrid(1, 2, 256, 256, 67, 67)
	elseif role == "HEALER" then
		return GetTexCoordsByGrid(2, 1, 256, 256, 67, 67)
	elseif role == "DAMAGER" then
		return GetTexCoordsByGrid(2, 2, 256, 256, 67, 67)
	else
		error("Unknown role: " .. tostring(role))
	end
end

API.GetBackgroundTexCoordsForRole = GetBackgroundTexCoordsForRole or function(role)
	if role == "TANK" then
		return GetTexCoordsByGrid(2, 1, 256, 128, 75, 75)
	elseif role == "HEALER" then
		return GetTexCoordsByGrid(1, 1, 256, 128, 75, 75)
	elseif role == "DAMAGER" then
		return GetTexCoordsByGrid(3, 1, 256, 128, 75, 75)
	else
		error("Role does not have background: " .. tostring(role))
	end
end

API.GetTexCoordsForRoleSmallCircle = GetTexCoordsForRoleSmallCircle or function(role)
	if role == "TANK" then
		return 0, 19 / 64, 22 / 64, 41 / 64
	elseif role == "HEALER" then
		return 20 / 64, 39 / 64, 1 / 64, 20 / 64
	elseif role == "DAMAGER" then
		return 20 / 64, 39 / 64, 22 / 64, 41 / 64
	else
		error("Unknown role: " .. tostring(role))
	end
end

API.GetTexCoordsForRoleSmall = GetTexCoordsForRoleSmall or function(role)
	if role == "TANK" then
		return 0.5, 0.75, 0, 1
	elseif role == "HEALER" then
		return 0.75, 1, 0, 1
	elseif role == "DAMAGER" then
		return 0.25, 0.5, 0, 1
	else
		error("Unknown role: " .. tostring(role))
	end
end

-- Party/raid role assignment: native on 3.3.5 (LFD roles), MAINTANK based
-- fallback kept for safety. Used by the status load filters.
Grid2.UnitGroupRolesAssigned = Grid2.UnitGroupRolesAssigned or _G.UnitGroupRolesAssigned or function(unit)
	local index = UnitInRaid(unit)
	if index and select(10, GetRaidRosterInfo(index)) == "MAINTANK" then
		return "TANK"
	end
	return "NONE"
end
