local Grid2 = Grid2
local Grid2Frame = Grid2Frame

Grid2.indicators = {}
Grid2.indicatorTypes = {}
Grid2.indicatorPrototype = {}

local indicator = Grid2.indicatorPrototype
indicator.__index = indicator

function indicator:new(name)
	local e = setmetatable({}, self)
	local p = {}
	e.sortStatuses = function(a, b) return p[a] > p[b] end
	e.priorities = p
	e.name = name
	e.statuses = {}
	e.prototype = self
	return e
end

function indicator:CreateFrame(ftype, parent)
	local f = parent[self.name]
	if not (f and f:GetObjectType() == ftype) then
		f = CreateFrame(ftype, nil, parent)
		parent[self.name] = f
	end
	f:Hide()
	return f
end

function indicator:AddFrame(f, parent)
	parent[self.name] = f
end

function indicator:Update(parent, unit)
	self:OnUpdate(parent, unit, self:GetCurrentStatus(unit))
end

function indicator:RegisterStatus(status, priority)
	if not self.priorities[status] and not status.suspended then
		self.priorities[status] = priority
		self.statuses[#self.statuses + 1] = status
		self:SortStatuses()
		if self.UpdateHighlight then self:UpdateHighlight(status) end -- GridIndicatorEffects.lua
	end
	status:RegisterIndicator(self, priority)
end

function indicator:UnregisterStatus(status, suspend)
	if self.priorities[status] then
		self.priorities[status] = nil
		tremove(self.statuses, self:GetStatusIndex(status))
		self:SortStatuses()
	end
	status:UnregisterIndicator(self, suspend)
end

function indicator:SortStatuses()
	table.sort(self.statuses, self.sortStatuses)
end

function indicator:SetStatusPriority(status, priority)
	if status then
		if not status.suspended then
			self.priorities[status] = priority
			self:SortStatuses()
		end
		status.priorities[self] = priority
	end
end

function indicator:GetStatusPriority(status)
	return status and status.priorities[self]
end

function indicator:GetStatusIndex(status)
	for i, s in ipairs(self.statuses) do
		if s == status then
			return i
		end
	end
end

function indicator:GetCurrentStatus(unit)
	if unit then
		local statuses = self.statuses
		for i = 1, #statuses do
			local status = statuses[i]
			local state = status:IsActive(unit)
			if state then
				return status, state
			end
		end
	end
end

-- Update functions
-- 3.3.5 backport: OnUpdate may be temporarily nil (e.g. Icon:Disable() clears it
-- while options rebuild the indicator). Never abort the whole frame update loop.
function indicator:UpdateBlink(parent, unit)
	local status, state = self:GetCurrentStatus(unit)
	local func = self.GetBlinkFrame
	if func then
		Grid2Frame:SetBlinkEffect(func(self, parent), state == "blink")
	end
	if self.OnUpdate then
		self:OnUpdate(parent, unit, status)
	end
end

function indicator:UpdateNoBlink(parent, unit)
	if self.OnUpdate then
		self:OnUpdate(parent, unit, self:GetCurrentStatus(unit))
	end
end

indicator.Update = indicator.UpdateBlink

function Grid2:RegisterIndicator(indicator, types)
	local name = indicator.name
	self.indicators[name] = indicator
	for _, itype in ipairs(types) do
		local t = self.indicatorTypes[itype] or {}
		self.indicatorTypes[itype] = t
		t[name] = indicator
	end
	if indicator.UpdateFilter then indicator:UpdateFilter() end -- GridIndicatorLoad.lua
end

function Grid2:UnregisterIndicator(indicator)
	local statuses = indicator.statuses
	while #statuses > 0 do
		indicator:UnregisterStatus(statuses[#statuses])
	end
	if indicator.Disable then
		Grid2Frame:WithAllFrames(indicator, "Disable")
	end
	local name = indicator.name
	self.indicators[name] = nil
	for _, t in pairs(self.indicatorTypes) do
		t[name] = nil
	end
	if indicator.sideKick then
		Grid2:UnregisterIndicator(indicator.sideKick)
		indicator.sideKick = nil
	end
end

function Grid2:GetIndicatorByName(name)
	return name and Grid2.indicators[name]
end

function Grid2:IterateIndicators(itype)
	return next, itype and self.indicatorTypes[itype] or self.indicators
end