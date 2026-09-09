-- Statuses Load filter management, by MiCHaEL
-- 3.3.5 port notes:
-- * C_Timer.After does not exist on 3.3.5, cooldown rechecks use Grid2:ScheduleTimer (AceTimer-3.0).
-- * Grid2Frame.activatedFrames does not exist here, frames are enumerated through
--   Grid2Frame.registeredFrames using frame.unit.
-- * Grid2:IterateGroupedPlayers() does not exist here, Grid2:IterateRosterUnits() is used.
-- * Grid2.roster_types / roster_deads do not exist here, unit type is derived from the
--   unitId and dead state is queried with UnitIsDeadOrGhost().
-- * Grid2.UnitGroupRolesAssigned and Grid2.API.GetSpellCooldown come from GridShims.lua.
local Grid2 = Grid2
local Grid2Frame = Grid2Frame
local next = next
local pairs = pairs
local rawget = rawget
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitIsFriend = UnitIsFriend
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetInstanceInfo = GetInstanceInfo
local GetSpellCooldown = (Grid2.API and Grid2.API.GetSpellCooldown) or GetSpellCooldown
local UnitGroupRolesAssigned = Grid2.UnitGroupRolesAssigned or _G.UnitGroupRolesAssigned or function() return 'NONE' end
local empty = {}

-- 3.3.5 unit type resolver, replaces the BCC Grid2.roster_types table.
-- Returns: 'player' for grouped players, 'pet' for pets, 'boss' for boss units,
-- the unitId itself for target/focus like units, nil otherwise.
local fixed_types = { target = 'target', focus = 'focus', targettarget = 'targettarget', focustarget = 'focustarget' }
local function GetUnitType(unit)
	local r = fixed_types[unit]
	if r then return r end
	if unit == 'player' or unit == 'vehicle' then
		return 'player'
	end
	if Grid2:UnitIsPet(unit) then
		return 'pet'
	end
	local prefix = unit:match('^%a+')
	if prefix == 'boss' then
		return 'boss'
	elseif prefix == 'party' or prefix == 'raid' or prefix == 'arena' then
		return 'player'
	end
end

-------------------------------------------------------------------------
-- Register/Unregister filtered statuses
-------------------------------------------------------------------------

local statuses = { combat = {}, playerClassSpec = {}, groupInstType = {}, instNameID = {}, unitFilter = {}, unitRole = {}, unitAlive = {}, cooldown = {} }

local function RegisterMsgFilter(status, filterType, message, func, enabled)
	local registered = statuses[filterType]
	if not enabled ~= not registered[status] then
		if enabled then
			if not next(registered) then Grid2.RegisterMessage(statuses, message, func) end
			registered[status] = enabled
		else
			registered[status] = nil
			if not next(registered) then Grid2.UnregisterMessage(statuses, message) end
		end
	end
end

local function RegisterEventFilter(status, filterType, event, func, enabled)
	local registered = statuses[filterType]
	if not enabled ~= not registered[status] then
		if enabled then
			if not next(registered) then Grid2:RegisterEvent(event, func) end
			registered[status] = enabled
		else
			registered[status] = nil
			if not next(registered) then Grid2:UnregisterEvent(event) end
		end
	end
end

-------------------------------------------------------------------------
-- General filters: class/spec/zone/group type
-- statuses are suspended&unregistered from indicators
-------------------------------------------------------------------------

local FilterG_Register, FilterG_Unregister, FilterG_Refresh
do
	local indicators = {} -- indicators marked for update

	local function RegisterIndicators(self)
		if self.suspended then
			-- suspend: keep status.priorities[] intact passing suspend=true, so the
			-- status can be linked back to the indicators later (BCC drops them).
			for indicator, priority in pairs(self.priorities) do
				indicator:UnregisterStatus(self, true)
				indicators[indicator] = true
			end
		else
			-- wakeup: link the status back to the indicators
			for indicator, priority in pairs(self.priorities) do
				indicator:RegisterStatus(self, priority)
				indicators[indicator] = true
			end
		end
	end

	local function UpdateMarkedIndicators()
		for _, frame in next, Grid2Frame.registeredFrames do
			local unit = frame.unit
			if unit then
				for indicator in next, indicators do
					indicator:Update(frame, unit)
				end
			end
		end
		wipe(indicators)
	end

	local function CheckZoneFilter(filter)
		local instanceName,_,_,_,_,_,_,instanceID = GetInstanceInfo()
		return filter[instanceName] or filter[instanceID]
	end

	local function SuspendStatus(self, load)
		local prev = self.suspended
		if load then
			self.suspended =
				( load.disabled ) or
				( load.playerClass     and not load.playerClass[ Grid2.playerClass ]         ) or
				( load.playerClassSpec and not load.playerClassSpec[ Grid2.playerClassSpec ] ) or
				( load.groupType       and not load.groupType[ Grid2.groupType ]             ) or
				( load.instType        and not load.instType[ Grid2.instType ]               ) or
				( load.instNameID      and not CheckZoneFilter(load.instNameID)              ) or nil
			return self.suspended ~= prev
		else
			self.suspended = nil
			return prev
		end
	end

	local function RefreshStatuses(filterType)
		local notify
		for status, load in pairs(statuses[filterType]) do
			if SuspendStatus(status, load) then
				RegisterIndicators(status)
				notify = true
			end
		end
		UpdateMarkedIndicators()
		if notify then
			Grid2:SendMessage("Grid_StatusLoadChanged")
		end
	end

	-- message events
	local function GroupTypeEvent()
		RefreshStatuses('groupInstType')
	end

	local function PlayerSpecEvent()
		RefreshStatuses('playerClassSpec')
	end

	local function ZoneChangedEvent()
		RefreshStatuses('instNameID')
	end

	-- public
	function FilterG_Register(self, load)
		RegisterMsgFilter( self, "instNameID",      "Grid_ZoneChangedNewArea", ZoneChangedEvent, load and load.instNameID and load )
		RegisterMsgFilter( self, "playerClassSpec", "Grid_PlayerSpecChanged",  PlayerSpecEvent,  load and load.playerClassSpec and load )
		RegisterMsgFilter( self, "groupInstType",   "Grid_GroupTypeChanged",   GroupTypeEvent,   load and (load.groupType or load.instType) and load )
		return SuspendStatus(self, load)
	end

	function FilterG_Unregister(self)
		RegisterMsgFilter( self, "instNameID",      "Grid_ZoneChangedNewArea" )
		RegisterMsgFilter( self, "playerClassSpec", "Grid_PlayerSpecChanged" )
		RegisterMsgFilter( self, "groupInstType",   "Grid_GroupTypeChanged" )
	end

	function FilterG_Refresh(self, load)
		if FilterG_Register(self, load or empty) then
			RegisterIndicators(self)
			UpdateMarkedIndicators()
		end
	end

end

-------------------------------------------------------------------------
-- Unit filters: type/class/role/reaction
-- self.filtered[unit] check inside status:IsActive() method is necessary
-------------------------------------------------------------------------

local FilterU_Register, FilterU_Unregister, FilterU_Enable, FilterU_Disable, FilterU_Refresh
do
	local coolExpireTimer

	local function IsSpellInCooldown(spellID)
		local start, duration = GetSpellCooldown(spellID)
		if start ~= 0 then
			local gcdStart, gcdDuration = GetSpellCooldown(61304)
			return start ~= gcdStart or duration ~= gcdDuration, start + duration
		end
		return false
	end

	local cooldowns_mt = { __index = function(t,spellID)
		local r = IsSpellInCooldown(spellID)
		t[spellID] = r
		return r
	end }
	setmetatable(cooldowns_mt, cooldowns_mt)

	local filter_mt = { __index = function(t,u)
		if UnitExists(u) then
			local load, r = t.source
			if load.unitType then
				r = not load.unitType[ GetUnitType(u) ]
			end
			if not r then
				if load.unitRole then
					r = not load.unitRole[ UnitGroupRolesAssigned(u) ]
				end
				if not r then
					if load.unitClass then
						local _,class = UnitClass(u)
						r = not load.unitClass[class]
					end
					if not r then
						if load.unitReaction then
							r = not UnitIsFriend('player',u)
							if load.unitReaction.hostile then r = not r end
						end
						if not r then
							if load.unitPlayer ~= nil then
								r = load.unitPlayer ~= UnitIsUnit(u,'player')
							end
							if not r then
								if load.unitAlive ~= nil then
									r = not UnitIsDeadOrGhost(u) == not load.unitAlive
								end
								if not r then
									if load.cooldown then
										r = cooldowns_mt[load.cooldown]
									end
								end
							end
						end
					end
				end
			end
			t[u] = r
			return r
		end
		t[u] = true
		return true
	end }

	local function ClearUnitFilters(_, unit)
		for status, filtered in next, statuses.unitFilter do
			filtered[unit] = nil
		end
	end

	local function RefreshAliveFilter(_, unit)
		for status, filtered in next, statuses.unitAlive do
			filtered[unit] = nil
			status:UpdateIndicators(unit)
		end
	end

	local function RefreshRoleFilter()
		for status, filtered in next, statuses.unitRole do
			wipe(filtered).source = status.dbx.load
			status:UpdateAllUnits()
		end
	end

	local function RefreshCooldownFilter(_, eventSpellID)
		coolExpireTimer = eventSpellID and coolExpireTimer or 2147483647
		local newExpire = coolExpireTimer
		for status, filtered in next, statuses.cooldown do
			local load = status.dbx.load
			local spellID = load.cooldown
			if spellID == (eventSpellID or spellID) then
				local cool, expire = IsSpellInCooldown(spellID)
				if cool ~= rawget( cooldowns_mt, spellID ) then
					cooldowns_mt[spellID] = cool
					wipe(filtered).source = load
					status:UpdateAllUnits()
				end
				if cool and expire < newExpire then
					newExpire = coolExpireTimer
				end
			end
		end
		if newExpire < coolExpireTimer then
			coolExpireTimer = newExpire
			-- 3.3.5 has no C_Timer.After, Grid2 embeds AceTimer-3.0.
			-- BCC calls an undefined RefreshCooldownTimer here, rechecking through
			-- this same function (nil eventSpellID refreshes every cooldown status).
			Grid2:ScheduleTimer(RefreshCooldownFilter, newExpire - GetTime() + 0.05)
		end
	end

	-- public
	function FilterU_Register(self, load)
		if load.unitType or load.unitReaction or load.unitClass or load.unitRole or load.cooldown or load.unitPlayer ~= nil or load.unitAlive ~= nil then
			self.filtered = setmetatable({source = load}, filter_mt)
		else
			self.filtered = nil
		end
	end

	function FilterU_Unregister(self, load)
		self.filtered = nil
	end

	function FilterU_Enable(self, load)
		local filtered = self.filtered
		if filtered then
			RegisterMsgFilter( self, "unitFilter", "Grid_UnitUpdated", ClearUnitFilters,  filtered )
			RegisterMsgFilter( self, "unitAlive", "Grid_UnitDeadUpdated", RefreshAliveFilter,  load.unitAlive ~= nil and filtered )
			RegisterMsgFilter( self, "unitRole", "Grid_PlayerRolesAssigned", RefreshRoleFilter, load.unitRole and filtered )
			RegisterEventFilter( self, "cooldown", "SPELL_UPDATE_COOLDOWN", RefreshCooldownFilter, load.cooldown and filtered )
		end
	end

	function FilterU_Disable(self, load)
		local filtered = self.filtered
		if filtered then
			RegisterMsgFilter( self, "unitFilter", "Grid_UnitUpdated" )
			RegisterMsgFilter( self, "unitAlive", "Grid_UnitDeadUpdated" )
			RegisterMsgFilter( self, "unitRole", "Grid_PlayerRolesAssigned" )
			RegisterEventFilter( self, "cooldown", "SPELL_UPDATE_COOLDOWN" )
			wipe(filtered).source = load
		end
	end

	function FilterU_Refresh(self, load)
		FilterU_Disable(self, load)
		FilterU_Register(self, load or empty)
		self:UpdateDB()
		if self.enabled then
			FilterU_Enable(self, load or empty)
			self:UpdateAllUnits()
		end
	end

end

-------------------------------------------------------------------------
-- Combat filter
-------------------------------------------------------------------------

local FilterC_Enable, FilterC_Disable, FilterC_Refresh
do
	local statuses = statuses.combat
	local IsNotActive = Grid2.Dummy
	local frame, inCombat

	local function CombatEvent(_,event)
		inCombat = (event == 'PLAYER_REGEN_DISABLED')
		for status, load in next,statuses do
			local IsActive = status._IsActive
			local Update = status.UpdateIndicators
			status.IsActive = load.combat == inCombat and IsActive or IsNotActive
			for unit in Grid2:IterateRosterUnits() do
				if IsActive(status,unit) then
					Update(status,unit)
				end
			end
		end
	end

	-- public
	function FilterC_Enable(status, load)
		if load.combat ~= nil then
			frame = frame or CreateFrame("Frame", nil, Grid2LayoutFrame)
			if not next(statuses) then
				frame:SetScript("OnEvent", CombatEvent)
				frame:RegisterEvent("PLAYER_REGEN_ENABLED")
				frame:RegisterEvent("PLAYER_REGEN_DISABLED")
				inCombat = not not InCombatLockdown()
			end
			statuses[status] = load
			if status.IsActive ~= IsNotActive then
				status._IsActive = status.IsActive
			end
			if load.combat ~= inCombat then
				status.IsActive = IsNotActive
			end
		end
	end

	function FilterC_Disable(status)
		if statuses[status] then
			statuses[status] = nil
			if status._IsActive then
				status.IsActive = status._IsActive
				status._IsActive = nil
			end
			if not next(statuses) and frame then
				frame:SetScript("OnEvent", nil)
				frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
				frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
			end
		end
	end

	function FilterC_Refresh(status, load)
		FilterC_Disable(status, load)
		status:UpdateDB()
		if status.enabled and load then
			FilterC_Enable(status, load)
			status:UpdateAllUnits()
		end
	end

end

-----------------------------------------------------------------------
-- status methods
-----------------------------------------------------------------------

local status = Grid2.statusPrototype

function status:RegisterLoad() -- called from Grid2:RegisterStatus() in GridStatus.lua
	local load = self.dbx and self.dbx.load
	if load then
		FilterG_Register(self, load)
		FilterU_Register(self, load)
	end
end

function status:UnregisterLoad() -- called from Grid2:UnregisterStatus() in GridStatus.lua
	local load = self.dbx and self.dbx.load
	if load then
		FilterG_Unregister(self, load)
		FilterU_Unregister(self, load)
	end
	self.suspended = nil
end

function status:EnableLoad() -- called from status:RegisterIndicator() when the status is enabled
	local load = self.dbx and self.dbx.load
	if load then
		FilterU_Enable(self, load)
		FilterC_Enable(self, load)
	end
end

function status:DisableLoad() -- called from status:UnregisterIndicator() when the status is disabled
	local load = self.dbx and self.dbx.load
	if load then
		FilterU_Disable(self, load)
		FilterC_Disable(self, load)
	end
end

function status:RefreshLoad() -- used by Grid2Options
	local load = self.dbx and self.dbx.load
	FilterG_Refresh(self, load)
	FilterU_Refresh(self, load)
	FilterC_Refresh(self, load)
end
