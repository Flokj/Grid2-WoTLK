local Grid2 = Grid2
local Direction = Grid2.statusPrototype:new("direction")
local Grid2Frame = Grid2Frame

local PI = math.pi
local PI2 = PI * 2
local floor = math.floor
local atan2 = math.atan2
local GetPlayerFacing = GetPlayerFacing
local GetPlayerMapPosition = GetPlayerMapPosition
local SetMapToCurrentZone = SetMapToCurrentZone
local UnitIsUnit = UnitIsUnit

local timer
local directions = {}
local UnitCheck
local mouseover = ""

local CODE = [[
local UnitIsUnit = UnitIsUnit
local UnitInRange = UnitInRange
local UnitIsVisible = UnitIsVisible
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitGroupRolesAssigned = Grid2.UnitGroupRolesAssigned
return function(unit, mouseover) return (%s) end
]]

local function UpdateDirections()
	local x1, y1 = GetPlayerMapPosition("player")
	if x1 == 0 then
		Direction:ClearDirections()
		return
	end
	local facing = GetPlayerFacing()
	for unit, _ in Grid2:IterateRosterUnits() do
		local direction
		if not UnitIsUnit(unit, "player") and UnitCheck(unit, mouseover) then
			local x2, y2 = GetPlayerMapPosition(unit)
			if x2 ~= 0 then
				direction = floor((PI - atan2(x1 - x2, y2 - y1) - facing) / PI2 * 32 + 0.5) % 32
			end
		end
		if direction ~= directions[unit] then
			directions[unit] = direction
			Direction:UpdateIndicators(unit)
		end
	end
end

local function ZoneChanged()
	if not WorldMapFrame:IsVisible() then
		SetMapToCurrentZone()
	end
end

function Direction:SetTimer(enable)
	if enable then
		timer = timer or Grid2:ScheduleRepeatingTimer(UpdateDirections, self.dbx.updateRate or 0.2)
	elseif timer then
		Grid2:CancelTimer(timer, true)
		timer = nil
	end
end

function Direction:RestartTimer()
	if timer then
		self:SetTimer(false)
		self:SetTimer(true)
	end
end

function Direction:ClearDirections()
	for unit, _ in pairs(directions) do
		directions[unit] = nil
		self:UpdateIndicators(unit)
	end
end

-- 3.3.5: no Grid2Frame:SetEventHook, track mouseover via frame hooks
local SetMouseoverHooks
do
	local hooksInstalled
	local function OnMouseEnter(_, frame)
		if frame and frame.unit then
			mouseover = frame.unit
		end
	end
	local function OnMouseLeave()
		mouseover = ""
	end
	SetMouseoverHooks = function(enable)
		if enable and not hooksInstalled and Grid2Frame.OnFrameEnter then
			hooksecurefunc(Grid2Frame, "OnFrameEnter", OnMouseEnter)
			hooksecurefunc(Grid2Frame, "OnFrameLeave", OnMouseLeave)
			hooksInstalled = true
		end
		if not enable then
			mouseover = ""
		end
	end
end

function Direction:UpdateDB()
	local dbx, t, u = self.dbx, {}, {}
	SetMouseoverHooks(dbx.StickyMouseover)
	if dbx.ShowOutOfRange then u[#u + 1] = "(not UnitInRange(unit))" end
	if dbx.ShowVisible then u[#u + 1] = "UnitIsVisible(unit)" end
	if dbx.ShowDead then u[#u + 1] = "UnitIsDeadOrGhost(unit)" end
	if #u > 0 then t[#t + 1] = table.concat(u, dbx.lazyFilter and " or " or " and ") end
	wipe(u)
	if dbx.StickyTarget then u[#u + 1] = "UnitIsUnit(unit,'target')" end
	if dbx.StickyMouseover then u[#u + 1] = "UnitIsUnit(unit,mouseover)" end
	if dbx.StickyFocus then u[#u + 1] = "UnitIsUnit(unit,'focus')" end
	if dbx.StickyTanks then u[#u + 1] = "UnitGroupRolesAssigned(unit)=='TANK'" end
	if #u > 0 then t[#t + 1] = table.concat(u, " or ") end
	local s = string.format(CODE, #t > 0 and table.concat(t, dbx.showAlwaysStickyUnits and ") or (" or ") and (") or "true")
	UnitCheck = assert(loadstring(s))()
end

function Direction:OnEnable()
	self:UpdateDB()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", ZoneChanged)
	self:RegisterEvent("ZONE_CHANGED", ZoneChanged)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", ZoneChanged)
	self:RegisterEvent("ZONE_CHANGED_INDOORS", ZoneChanged)
	self:SetTimer(true)
end

function Direction:OnDisable()
	SetMouseoverHooks(false)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("ZONE_CHANGED")
	self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	self:UnregisterEvent("ZONE_CHANGED_INDOORS")
	self:SetTimer(false)
end

function Direction:IsActive(unit)
	return directions[unit] and true
end

function Direction:GetIcon(unit)
	return "Interface\\Addons\\Grid2\\media\\Arrows32-32x32"
end

function Direction:GetTexCoord(unit)
	local y = directions[unit] / 32
	return 0.05, 0.95, y + 0.0015625, y + 0.028125
end

Direction.GetVertexColor = Grid2.statusLibrary.GetColor

local function Create(baseKey, dbx)
	Grid2:RegisterStatus(Direction, {"icon"}, baseKey, dbx)

	return Direction
end

Grid2.setupFunc["direction"] = Create
Grid2:DbSetStatusDefaultValue("direction", {type = "direction", color1 = {r = 0, g = 1, b = 0, a = 1}})
