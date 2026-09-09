local Grid2 = Grid2

local AuraFrame_OnEvent
local GetTime = GetTime
local UnitBuff = UnitBuff
local UnitDebuff = UnitDebuff
local abs = math.abs

local StatusList = {}
local DebuffHandlers = {}
local BuffHandlers = {}
local statusTypesBuffs = {"color", "icon", "percent", "text"}
local statusTypesDebuffs = {"color", "icon", "percent", "text"} --{ "color", "icon", "text" }	--added "percent" to allow a cooldown bar e.g. for Weakened Soul

local handlerArray = {}
local function MakeStatusColorHandler(status)
	local dbx = status.dbx
	local colorCount = dbx.colorCount or 1
	handlerArray[1] = "return function (self, unit)"
	if colorCount > 1 then
		handlerArray[#handlerArray + 1] = " local count = self:GetCount(unit)"
		for i = 1, colorCount - 1 do
			local color = dbx["color" .. i]
			handlerArray[#handlerArray + 1] = (" if count == %d then return %s, %s, %s, %s end"):format(i, color.r, color.g, color.b, color.a)
		end
	end
	color = dbx["color" .. colorCount]
	handlerArray[#handlerArray + 1] = (" return %s, %s, %s, %s end"):format(color.r, color.g, color.b, color.a)
	status.GetColor = assert(loadstring(table.concat(handlerArray)))()
	wipe(handlerArray)
end

local function GetStatusKey(self, spellName)
	return type(spellName) == "number" and (not self.dbx.useSpellId) and GetSpellInfo(spellName) or spellName
end

local function IterateStatusSpells(status)
	local auras = status.dbx.auras
	if auras then
		local i = 0
		return function()
			i = i + 1
			return auras[i]
		end
	else
		local spell, value = status.dbx.spellName
		return function()
			value, spell = spell, nil
			return value
		end
	end
end

local AddTimeTracker, RemoveTimeTracker
do
	local next = next
	local timetracker
	local tracked
	AddTimeTracker = function(status)
		tracked = {}
		timetracker = CreateFrame("Frame", nil, Grid2LayoutFrame):CreateAnimationGroup()
		timetracker:SetScript("OnFinished", function(self)
			local time = GetTime()
			for status in next, tracked do
				local tracker = status.tracker
				local thresholds = status.thresholds
				if status.trackElapsed then
					local durations = status.durations
					for unit, expiration in next, status.expirations do
						local timeElapsed = time - (expiration - durations[unit])
						local threshold = thresholds[tracker[unit]]
						if threshold and timeElapsed >= threshold then
							tracker[unit] = tracker[unit] + 1
							status:UpdateIndicators(unit)
						end
					end
				else
					for unit, expiration in next, status.expirations do
						local timeLeft = expiration - time
						local threshold = thresholds[tracker[unit]]
						if threshold and timeLeft <= threshold then
							tracker[unit] = tracker[unit] + 1
							status:UpdateIndicators(unit)
						end
					end
				end
			end
			self:Play()
		end)
		local timer = timetracker:CreateAnimation()
		timer:SetOrder(1)
		timer:SetDuration(0.10)
		AddTimeTracker = function(status)
			if not next(tracked) then
				timetracker:Play()
			end
			tracked[status] = true
		end
		RemoveTimeTracker = function(status)
			tracked[status] = nil
			if not next(tracked) then
				timetracker:Stop()
			end
		end
		return AddTimeTracker(status)
	end
end

local EnableAuraFrame, DisableAuraFrame
do
	local frame
	local count = 0
	function EnableAuraFrame()
		if count == 0 then
			if not frame then
				frame = CreateFrame("Frame", nil, Grid2LayoutFrame)
			end
			frame:SetScript("OnEvent", AuraFrame_OnEvent)
			frame:RegisterEvent("UNIT_AURA")
		end
		count = count + 1
	end
	function DisableAuraFrame()
		count = count - 1
		if count == 0 then
			frame:SetScript("OnEvent", nil)
			frame:UnregisterEvent("UNIT_AURA")
		end
	end
end
--}}

--{{ Methods shared by different status types
local function status_Refresh(self)
	for unit in Grid2:IterateRosterUnits() do
		AuraFrame_OnEvent(nil, nil, unit)
	end
end

local function status_Reset(self, unit)
	self.states[unit] = nil
	self.counts[unit] = nil
	self.expirations[unit] = nil
	return true
end

local function status_IsInactive(self, unit) -- used for "missing" status
	return not self.states[unit]
end

local function status_IsActive(self, unit)
	return self.states[unit]
end

local function status_IsActiveBlink(self, unit)
	if not self.states[unit] then
		return
	end
	if self.tracker[unit] == 1 then
		return true
	else
		return "blink"
	end
end

local function status_IsInactiveBlink(self, unit) -- A missing active status has no expiration, always returns blink
	return not self.states[unit] and "blink"
end

local function status_GetIcon(self, unit)
	return self.textures[unit]
end

local function status_GetIconMissing(self)
	return self.missingTexture
end

local function status_GetCount(self, unit)
	return self.counts[unit]
end

local function status_GetCountMissing()
	return 1
end

local function status_GetCountMax(self)
	return self.dbx.colorCount or 1
end

local function status_GetDuration(self, unit)
	return self.durations[unit]
end

local function status_GetExpirationTime(self, unit)
	return self.expirations[unit]
end

local function status_GetExpirationTimeMissing() -- Expiration time is unknown, return some hours in future to allow
	return GetTime() + 9999 -- blinking work and to avoid a crash of IndicatorText status
end

local function status_GetPercent(self, unit)
	local t = GetTime()
	local expiration = (self.expirations[unit] or t) - t
	return expiration / (self.durations[unit] or 1)
end

local function status_GetThresholdColor(self, unit)
	local colors = self.colors
	local index = self.tracker[unit]
	local color = colors[index] or colors[1]
	return color.r, color.g, color.b, color.a
end

-- This function includes a workaround to expiration variations of Druid WildGrowth HoT (little differences in expirations are ignored)
local function status_UpdateState(self, unit, iconTexture, count, duration, expiration)
	local prevexp = self.expirations[unit]
	if count == 0 then
		count = 1
	end
	if self.states[unit] == nil or self.counts[unit] ~= count or prevexp == nil or abs(prevexp - expiration) > 0.15 then
		self.states[unit] = true
		self.textures[unit] = iconTexture
		self.counts[unit] = count
		self.durations[unit] = duration
		self.expirations[unit] = expiration
		self.tracker[unit] = 1
		self.seen = 1
	else
		self.seen = self.states[unit] and 1 or -1
	end
end

local function status_UpdateStateMine(self, unit, iconTexture, count, duration, expiration, isMine)
	if isMine then
		status_UpdateState(self, unit, iconTexture, count, duration, expiration)
	end
end

local function status_UpdateStateNotMine(self, unit, iconTexture, count, duration, expiration, isMine)
	if not isMine then
		status_UpdateState(self, unit, iconTexture, count, duration, expiration)
	end
end

local function status_UpdateStateGroup(self, unit, iconTexture, count, duration, expiration)
	if self.states[unit] == nil or self.expirations[unit] ~= expiration then
		self.states[unit] = true
		self.textures[unit] = iconTexture
		self.durations[unit] = duration
		self.expirations[unit] = expiration
		self.counts[unit] = 1
		self.tracker[unit] = 1
		self.seen = 1
	else
		self.seen = -1
	end
end

local function status_UpdateStateGroupMine(self, unit, iconTexture, count, duration, expiration, isMine)
	if isMine then
		status_UpdateStateGroup(self, unit, iconTexture, count, duration, expiration)
	end
end

local function status_UpdateStateGroupNotMine(self, unit, iconTexture, count, duration, expiration, isMine)
	if not isMine then
		status_UpdateStateGroup(self, unit, iconTexture, count, duration, expiration)
	end
end
-- }}

-- {{ Buff & BuffGroup
local function status_OnBuffEnable(self)
	EnableAuraFrame()
	if self.thresholds then
		AddTimeTracker(self)
	end
	for spellName in IterateStatusSpells(self) do
		local key = GetStatusKey(self, spellName)
		local statuses = BuffHandlers[key]
		if not statuses then
			statuses = {}
			BuffHandlers[key] = statuses
		end
		statuses[self] = true
	end
	StatusList[self] = true
end

local function status_OnBuffDisable(self)
	DisableAuraFrame()
	if RemoveTimeTracker then
		RemoveTimeTracker(self)
	end
	for key, statuses in pairs(BuffHandlers) do
		if statuses[self] then
			statuses[self] = nil
			if not next(statuses) then
				BuffHandlers[key] = nil
			end
		end
	end
	StatusList[self] = nil
end
-- }}

-- {{ Debuff & DebuffGroup
local function status_OnDebuffEnable(self)
	EnableAuraFrame()
	if self.thresholds then
		AddTimeTracker(self)
	end
	for spellName in IterateStatusSpells(self) do
		DebuffHandlers[GetStatusKey(self, spellName)] = self
	end
	StatusList[self] = true
end

local function status_OnDebuffDisable(self)
	DisableAuraFrame()
	if RemoveTimeTracker then
		RemoveTimeTracker(self)
	end
	for key, status in pairs(DebuffHandlers) do
		if self == status then
			DebuffHandlers[key] = nil
		end
	end
	StatusList[self] = nil
end
-- }}

-- {{ DebuffType
local function status_OnDebuffTypeEnable(self)
	EnableAuraFrame()
	DebuffHandlers[self.subType] = self
	StatusList[self] = true
end

local function status_OnDebuffTypeDisable(self)
	DisableAuraFrame()
	DebuffHandlers[self.subType] = nil
	StatusList[self] = nil
end

local function status_UpdateStateDebuffType(self, unit, iconTexture, count, duration, expiration, name)
	if self.debuffFilter and self.debuffFilter[name] then
		return
	end
	self.states[unit] = true
	self.textures[unit] = iconTexture
	self.durations[unit] = duration
	self.expirations[unit] = expiration
	self.counts[unit] = count ~= 0 and count or 1
	self.seen = 1
end
-- }}

-- {{ UpdateDB shared by all statuses
local function status_UpdateDB(self)
	if self.enabled then
		self:OnDisable()
	end
	local dbx = self.dbx
	if dbx.missing then
		local _, _, texture = GetSpellInfo(dbx.auras and dbx.auras[1] or dbx.spellName)
		self.thresholds = nil
		self.missingTexture = texture or "Interface\\ICONS\\Achievement_General"
		self.GetIcon = status_GetIconMissing
		self.GetExpirationTime = status_GetExpirationTimeMissing
		self.GetCount = status_GetCountMissing
		self.IsActive = dbx.blinkThreshold and status_IsInactiveBlink or status_IsInactive
		MakeStatusColorHandler(self)
	else
		self.GetIcon = status_GetIcon
		self.GetExpirationTime = status_GetExpirationTime
		self.GetCount = status_GetCount
		if dbx.blinkThreshold then
			self.thresholds = {dbx.blinkThreshold}
			self.IsActive = status_IsActiveBlink
			MakeStatusColorHandler(self)
		elseif dbx.colorThreshold then
			self.colors = {}
			self.thresholds = dbx.colorThreshold
			self.trackElapsed = dbx.colorThresholdElapsed
			self.GetColor = status_GetThresholdColor
			self.IsActive = status_IsActive
			for i = 1, dbx.colorCount do
				self.colors[i] = dbx["color" .. i]
			end
		else
			self.thresholds = nil
			self.IsActive = status_IsActive
			MakeStatusColorHandler(self)
		end
	end
	if dbx.type == "debuffType" then
		self.subType = self.dbx.subType
		self.debuffFilter = self.dbx.debuffFilter
		self.GetBorder = Grid2.statusLibrary.GetBorder
		self.UpdateState = status_UpdateStateDebuffType
	else
		if dbx.auras then
			self.UpdateState = (dbx.mine == 2 and status_UpdateStateGroupNotMine) or (dbx.mine and status_UpdateStateGroupMine) or status_UpdateStateGroup
		else
			self.UpdateState = (dbx.mine == 2 and status_UpdateStateNotMine) or (dbx.mine and status_UpdateStateMine) or status_UpdateState
		end
	end
	if self.enabled then
		self:OnEnable()
	end
end
--}}

--{{ Aura creation functions
local function CreateAuraCommon(baseKey, dbx, types)
	local status = Grid2.statusPrototype:new(baseKey, false)

	status.states = {}
	status.textures = {}
	status.counts = {}
	status.expirations = {}
	status.durations = {}

	status.UpdateDB = status_UpdateDB
	status.Refresh = status_Refresh
	status.Reset = status_Reset
	status.GetCountMax = status_GetCountMax
	status.GetDuration = status_GetDuration
	status.GetPercent = status_GetPercent

	if dbx.type == "debuffType" then
		status.OnEnable = status_OnDebuffTypeEnable
		status.OnDisable = status_OnDebuffTypeDisable
	else
		status.tracker = {}
		status.OnEnable = dbx.type == "buff" and status_OnBuffEnable or status_OnDebuffEnable
		status.OnDisable = dbx.type == "buff" and status_OnBuffDisable or status_OnDebuffDisable
	end

	Grid2:RegisterStatus(status, types, baseKey, dbx)

	status:UpdateDB()

	return status
end

function Grid2.CreateBuff(baseKey, dbx, statusTypesOverride)
	return CreateAuraCommon(baseKey, dbx, statusTypesOverride or statusTypesBuffs)
end

function Grid2.CreateDebuff(baseKey, dbx, statusTypesOverride)
	return CreateAuraCommon(baseKey, dbx, statusTypesOverride or statusTypesDebuffs)
end
--}}

--{{ Aura Refresh
-- Passing StatusList instead of nil, because i dont know if nil is valid for RegisterMessage
Grid2.RegisterMessage(StatusList, "Grid_UnitUpdated", function(_, unit)
	AuraFrame_OnEvent(nil, nil, unit)
end)
-- }}

--{{ Aura events management
do
	local next = next
	local indicators = {}
	local myUnits = {player = true, pet = true, vehicle = true}
	function AuraFrame_OnEvent(_, _, unit)
		local frames = Grid2:GetUnitFrames(unit)
		if not next(frames) then return end

		-- scan Debuffs and debuff Types
		local i = 1
		local name, _, iconTexture, count, debuffType, duration, expirationTime, caster, _, _, spellId = UnitDebuff(unit, i)
		while name do
			local status = DebuffHandlers[name] or (spellId and DebuffHandlers[spellId]) -- 3.3.5: UnitDebuff() returns no spellId
			if status then
				status:UpdateState(unit, iconTexture, count, duration, expirationTime, myUnits[caster])
			end
			if debuffType then
				status = DebuffHandlers[debuffType]
				if status and (not status.seen) then
					status:UpdateState(unit, iconTexture, count, duration, expirationTime, name)
				end
			end
			i = i + 1
			name, _, iconTexture, count, debuffType, duration, expirationTime, caster, _, _, spellId = UnitDebuff(unit, i)
		end

		-- scan Buffs
		i = 1
		name, _, iconTexture, count, _, duration, expirationTime, caster, _, _, spellId = UnitBuff(unit, i)
		while name do
			local statuses = BuffHandlers[name] or (spellId and BuffHandlers[spellId]) -- 3.3.5: UnitBuff() returns no spellId
			if statuses then
				local isMine = myUnits[caster]
				for status in next, statuses do
					status:UpdateState(unit, iconTexture, count, duration, expirationTime, isMine)
				end
			end
			i = i + 1
			name, _, iconTexture, count, _, duration, expirationTime, caster, _, _, spellId = UnitBuff(unit, i)
		end

		-- Mark indicators that need updating
		for status in next, StatusList do
			local seen = status.seen
			if (seen == 1) or ((not seen) and status.states[unit] and status:Reset(unit)) then
				for indicator in next, status.indicators do
					indicators[indicator] = true
				end
			end
			status.seen = false
		end

		-- Update indicators that needs updating only once.
		for indicator in next, indicators do
			for frame in next, frames do
				indicator:Update(frame, unit)
			end
		end
		wipe(indicators)
	end
end
--}}

--{{
Grid2.setupFunc["buff"] = Grid2.CreateBuff
Grid2.setupFunc["debuff"] = Grid2.CreateDebuff
Grid2.setupFunc["debuffType"] = Grid2.CreateDebuff
--}}

--{{
Grid2:DbSetStatusDefaultValue("debuff-Magic", {type = "debuffType", subType = "Magic", color1 = {r = 0.2, g = 0.6, b = 1, a = 1}})
Grid2:DbSetStatusDefaultValue("debuff-Poison", {type = "debuffType", subType = "Poison", color1 = {r = 0, g = 0.6, b = 0, a = 1}})
Grid2:DbSetStatusDefaultValue("debuff-Curse", {type = "debuffType", subType = "Curse", color1 = {r = 0.6, g = 0, b = 1, a = 1}})
Grid2:DbSetStatusDefaultValue("debuff-Disease", {type = "debuffType", subType = "Disease", color1 = {r = 0.6, g = 0.4, b = 0, a = 1}})
--}}

--{{ New aura engine: Grid2.CreateStatusAura (ported from Grid2-bcc, adapted for 3.3.5)
-- Used by buffs/debuffs group statuses (StatusAurasBuffs.lua, StatusAurasDebuffs.lua).
-- The old engine above (CreateBuff/CreateDebuff + setupFunc buff/debuff/debuffType) is untouched.
-- 3.3.5 adaptations vs bcc:
-- * no UnitAura()/C_UnitAuras/spellId: UnitBuff()/UnitDebuff() are scanned, auras matched by name only.
--   Numeric spells registered by id are resolved to names with GetSpellInfo() at registration time.
-- * native GetSpellInfo() returns nil for spells not seen yet: every resolution falls back to a safe
--   default, a nil key is never used as a table index.
-- * no Grid2.owner_of_unit table: pets are detected with Grid2:UnitIsPet(unit).
-- * no Grid2.roster_my_units table: a local {player,pet,vehicle} set is used instead.
-- * no Grid2:CreateTimer() object API: time tracking uses an animation-frame timer like AddTimeTracker above.
-- * target Grid2:RegisterStatus() does not call status:UpdateDB() (bcc does), CreateStatusAura calls it explicitly.
local GetSpellInfo = GetSpellInfo -- 3.3.5: native, nil for spells not cached yet (guarded everywhere below)
local myUnits = { player = true, pet = true, vehicle = true } -- 3.3.5: no Grid2.roster_my_units

local Statuses = {}
local Buffs = {}
local Debuffs = {}
local DebuffTypes = {}
local DebuffGroups = {}

local debuffTypeSpells = {}
local debuffTypeColors = {}
Grid2.debuffTypeSpells = Grid2.debuffTypeSpells or debuffTypeSpells -- 3.3.5: table does not exist
Grid2.debuffTypeColors = Grid2.debuffTypeColors or debuffTypeColors -- 3.3.5: table does not exist

local AuraFrame_OnEventNew -- forward declaration (defined below, used by the event frame)
local UpdateAllAuras -- forward declaration (defined below, used by status OnEnable)

--{{ New engine UNIT_AURA scan (3.3.5: UnitBuff/UnitDebuff, match by aura name, no spellId/values/boss flag)
do
local next = next
local indicators = {}
function AuraFrame_OnEventNew(_, _, u)
	local frames = Grid2:GetUnitFrames(u)
	if not next(frames) then return end
	-- Scan Debuffs, Debuff Types, Debuff Groups
	local i = 1
	local nam, _, tex, cnt, typ, dur, exp, cas = UnitDebuff(u, i)
	while nam do
		if cnt==0 then cnt=1 end
		local statuses = Debuffs[nam]
		if statuses then
			for s in next, statuses do
				local mine = s.isMine
				if mine==false or mine==myUnits[cas] then
					if s.UpdateState then
						s:UpdateState(u, i, nil, nam, tex, cnt, dur, exp, typ)
					elseif exp~=s.exp[u] or cnt~=s.cnt[u] then
						s.seen, s.idx[u], s.tex[u], s.cnt[u], s.dur[u], s.exp[u], s.typ[u], s.tkr[u] = 1, i, tex, cnt, dur, exp, typ, 1
					else
						s.seen, s.idx[u] = -1, i
					end
				end
			end
		end
		local s = DebuffTypes[typ or 'Typeless']
		if s and not s.seen and not (s.debuffFilter and s.debuffFilter[nam]) then
			if exp~=s.exp[u] or cnt~=s.cnt[u] then
				s.seen, s.idx[u], s.tex[u], s.cnt[u], s.dur[u], s.exp[u] = 1, i, tex, cnt, dur, exp
			else
				s.seen, s.idx[u] = -1, i
			end
		end
		for s, update in next, DebuffGroups do
			if (update or not s.seen) and s:UpdateState(u, nil, nam, cnt, dur, cas, nil, typ) then
				s.seen, s.idx[u], s.tex[u], s.cnt[u], s.dur[u], s.exp[u], s.typ[u], s.tkr[u] = 1, i, tex, cnt, dur, exp, typ, 1
			end
		end
		i = i + 1
		nam, _, tex, cnt, typ, dur, exp, cas = UnitDebuff(u, i)
	end
	-- Scan Buffs
	i = 1
	nam, _, tex, cnt, _, dur, exp, cas = UnitBuff(u, i)
	while nam do
		if cnt==0 then cnt=1 end
		local statuses = Buffs[nam]
		if statuses then
			for s in next, statuses do
				local mine = s.isMine
				if (mine==false or mine==myUnits[cas]) and s.seen~=1 then
					if s.UpdateState then
						s:UpdateState(u, i, nil, nam, tex, cnt, dur, exp)
					elseif exp~=s.exp[u] or s.cnt[u]~=cnt or s.spells then
						s.seen, s.idx[u], s.tex[u], s.cnt[u], s.dur[u], s.exp[u], s.tkr[u] = 1, i, tex, cnt, dur, exp, 1
					else
						s.seen, s.idx[u] = -1, i
					end
				end
			end
		end
		i = i + 1
		nam, _, tex, cnt, _, dur, exp, cas = UnitBuff(u, i)
	end
	-- Mark indicators that need updating
	for s in next, Statuses do
		local seen = s.seen
		if (seen==1) or ((not seen) and s.idx[u] and s:Reset(u)) then
			for indicator in next, s.indicators do
				indicators[indicator] = true
			end
		end
		if s.ResetState then s:ResetState(u) end
		s.seen = false
	end
	-- Update indicators that needs updating only once.
	for indicator in next, indicators do
		for frame in next, frames do
			indicator:Update(frame, u)
		end
	end
	wipe(indicators)
end
end
--}}

--{{ Clear/update new engine auras when units change or leave the roster
do
local function UpdateFakedUnitsAuras(_,units)
	for unit in next, units do
		AuraFrame_OnEventNew(nil, true, unit)
	end
end
local function ClearAurasOfUnit(_, unit)
	for status in next, Statuses do
		status.idx[unit], status.exp[unit], status.val[unit] = nil, nil, nil
	end
end
local function UpdateAurasOfUnit(_, unit)
	AuraFrame_OnEventNew(nil, nil, unit)
end
function UpdateAllAuras()
	for unit in Grid2:IterateRosterUnits() do
		AuraFrame_OnEventNew(nil,nil,unit)
	end
end
Grid2.RegisterMessage( Statuses, "Grid_UnitLeft", ClearAurasOfUnit )
Grid2.RegisterMessage( Statuses, "Grid_UnitUpdated", UpdateAurasOfUnit )
Grid2.RegisterMessage( Statuses, "Grid_FakedUnitsUpdate", UpdateFakedUnitsAuras)
end
--}}

--{{ EnableAuraEvents() DisableAuraEvents(): own UNIT_AURA frame for the new engine (old engine frame untouched)
local EnableAuraEvents, DisableAuraEvents
do
local frame
EnableAuraEvents = function()
	if not next(Statuses) then
		if not frame then frame = CreateFrame("Frame", nil, Grid2LayoutFrame) end
		frame:SetScript("OnEvent", AuraFrame_OnEventNew)
		frame:RegisterEvent("UNIT_AURA")
	end
end
DisableAuraEvents = function()
	if not next(Statuses) then
		frame:SetScript("OnEvent", nil)
		frame:UnregisterEvent("UNIT_AURA")
	end
end
end
--}}

--{{ RegisterTimeTrackerStatus() UnregisterTimeTrackerStatus() (3.3.5: animation-frame timer, new engine tkr/exp/dur fields)
local RegisterTimeTrackerStatus, UnregisterTimeTrackerStatus
do
local tracked = {}
local timetracker
local function Tracker_OnFinished(self)
	local time = GetTime()
	for status,elapsed in next, tracked do
		local tracker    = status.tkr
		local thresholds = status.thresholds
		for unit, expiration in next, status.exp do
			local threshold = thresholds[tracker[unit]]
			if threshold and time >= expiration - (elapsed and status.dur[unit]-threshold or threshold) then
				tracker[unit] = tracker[unit] + 1
				status:UpdateIndicators(unit)
			end
		end
	end
	self:Play()
end
RegisterTimeTrackerStatus = function(status, elapsed)
	if not timetracker then
		timetracker = CreateFrame("Frame", nil, Grid2LayoutFrame):CreateAnimationGroup()
		timetracker:SetScript("OnFinished", Tracker_OnFinished)
		local timer = timetracker:CreateAnimation()
		timer:SetOrder(1)
		timer:SetDuration(0.1)
	end
	if not next(tracked) then timetracker:Play() end
	tracked[status] = elapsed or false
end
UnregisterTimeTrackerStatus = function(status)
	tracked[status] = nil
	if (not next(tracked)) and timetracker then timetracker:Stop() end
end
end
--}}

--{{ RegisterStatusAura() UnregisterStatusAura()
local function RegisterStatusAura(status, auraType, spell, update)
	EnableAuraEvents(status)
	if auraType=="debuffType" then
		DebuffTypes[spell] = status
	elseif not spell then
		DebuffGroups[status] = not not update
	else
		if type(spell)=="number" then spell = GetSpellInfo(spell) or spell end -- 3.3.5: scan matches by name, UnitBuff/UnitDebuff return no spellId
		local handler = auraType=="buff" and Buffs or Debuffs
		local statuses = handler[spell]
		if not statuses then
			statuses = {}
			handler[spell] = statuses
		end
		statuses[status] = true
	end
	Statuses[status] = true
end
local function UnregisterStatusAura(status, auraType, subType)
	local handler = (auraType=="buff" and Buffs) or (auraType=="debuff" and Debuffs)
	if handler then
		for key,statuses in pairs(handler) do
			if statuses[status] then
				statuses[status] = nil
				if not next(statuses) then handler[key] = nil end
			end
		end
		DebuffGroups[status] = nil
	else
		DebuffTypes[subType] = nil
	end
	Statuses[status] = nil
	DisableAuraEvents(status)
end
--}}

--{{ Grid2.CreateStatusAura()
local CreateStatusAura
do
	local fmt = string.format
	local UnitHealthMax = UnitHealthMax
	local function unit_is_pet(unit) return Grid2:UnitIsPet(unit) end -- 3.3.5: no Grid2.owner_of_unit table
	local function Reset(self, unit) -- multibar indicator needs val[unit]=nil because due to a speed optimization it does not check if status is active before calling GetPercent()
		self.idx[unit], self.exp[unit], self.val[unit] = nil, nil, nil
		return true
	end
	-- with unit class/reaction/role filters
	local function IsActiveFilter(self, unit)
		return not self.filtered[unit] and self.idx[unit]~=nil
	end
	local function IsActiveStacksFilter(self, unit)
		return not self.filtered[unit] and self.idx[unit] and self.cnt[unit]>=self.stacks
	end
	local function IsActiveBlinkFilter(self, unit)
		if self.filtered[unit] or not self.idx[unit] then return end
		return self.tkr[unit]==1 or "blink"
	end
	local function IsActiveStacksBlinkFilter(self, unit)
		if self.filtered[unit] or not (self.idx[unit] and self.cnt[unit]>=self.stacks) then return end
		return self.tkr[unit]==1 or "blink"
	end
	local function IsActiveBlinkAFilter(self, unit)
		if self.filtered[unit] or not self.idx[unit] then return end
		return "blink"
	end
	local function IsActiveStacksBlinkAFilter(self, unit)
		if self.filtered[unit] or not (self.idx[unit] and self.cnt[unit]>=self.stacks) then return end
		return "blink"
	end
	local function IsInactiveFilter(self, unit)
		return not self.filtered[unit] and not (self.idx[unit] or unit_is_pet(unit))
	end
	local function IsInactiveBlinkFilter(self, unit)
		return not self.filtered[unit] and not (self.idx[unit] or unit_is_pet(unit)) and "blink"
	end
	local function IsInactiveFilterPets(self, unit)
		return not self.filtered[unit] and not self.idx[unit]
	end
	local function IsInactiveBlinkFilterPets(self, unit)
		return not self.filtered[unit] and not self.idx[unit] and "blink"
	end
	-- no unit class/reaction/role filters
	local function IsActive(self, unit)
		if self.idx[unit] then return true end
	end
	local function IsActiveStacks(self, unit)
		if self.idx[unit] and self.cnt[unit]>=self.stacks then return true end
	end
	local function IsActiveBlink(self, unit)
		if not self.idx[unit] then return end
		return self.tkr[unit]==1 or "blink"
	end
	local function IsActiveStacksBlink(self, unit)
		if not (self.idx[unit] and self.cnt[unit]>=self.stacks) then return end
		return self.tkr[unit]==1 or "blink"
	end
	local function IsActiveBlinkA(self, unit)
		if not self.idx[unit] then return end
		return "blink"
	end
	local function IsActiveStacksBlinkA(self, unit)
		if not (self.idx[unit] and self.cnt[unit]>=self.stacks) then return end
		return "blink"
	end
	local function IsInactive(self, unit)
		return not (self.idx[unit] or unit_is_pet(unit))
	end
	local function IsInactiveBlink(self, unit)
		return not (self.idx[unit] or unit_is_pet(unit)) and "blink"
	end
	local function IsInactivePets(self, unit)
		return not self.idx[unit]
	end
	local function IsInactiveBlinkPets(self, unit)
		return not self.idx[unit] and "blink"
	end
	--
	local function GetIcon(self, unit)
		return self.tex[unit]
	end
	local function GetIconMissing(self)
		return self.missingTexture
	end
	local function GetCount(self, unit)
		return self.cnt[unit]
	end
	local function GetCountMissing()
		return 1
	end
	local function GetExpirationTime(self, unit)
		return self.exp[unit]
	end
	local function GetExpirationTimeMissing()
		return GetTime() + 9999
	end
	local function GetCountMax(self)
		return self.dbx.colorCount or 1
	end
	local function GetDuration(self, unit)
		return self.dur[unit]
	end
	local function GetDurationFixed(self)
		return self.dbx.maxDuration
	end
	local function GetDurationMissing()
		return
	end
	local function GetPercentHealth(self, unit)
		local m = UnitHealthMax(unit)
		return m>0 and (self.val[unit] or 0) / m or 0
	end
	local function GetPercentMax(self, unit)
		return (self.val[unit] or 0) / self.valMax
	end
	local function GetTextValue(self, unit)
		return fmt( "%.1fk", (self.val[unit] or 0) / 1000 )
	end
	local function GetTextSpell(self, unit)
		return self.spellText
	end
	local function GetTextCustom(self, unit)
		return self.customText
	end
	local function GetTimeColor(self, unit) -- Color by time remaining or time elapsed
		local colors = self.colors
		local i = self.tkr[unit]
		local c = colors[i] or colors[1]
		return c.r, c.g, c.b, c.a
	end
	local function GetValueColor(self, unit) -- Color by value
		local i = 1
		local value = self.val[unit] or 0
		local thresholds = self.thresholds
		while i<=#thresholds and value<thresholds[i] do
			i = i + 1
		end
		local c = self.colors[i]
		return c.r, c.g, c.b, c.a
	end
	local function GetBorderMandatory()
		return 1
	end
	local function GetBorderOptional()
		return 0
	end
	local function GetDebuffTooltip(self, unit, tip, slotID)
		local index = slotID or self.idx[unit]
		if index then
			tip:SetUnitDebuff(unit, index)
		end
	end
	local function GetBuffTooltip(self, unit, tip, slotID)
		local index = slotID or self.idx[unit]
		if index then
			tip:SetUnitBuff(unit, index)
		end
	end
	local function OnEnable(self)
		if self.spell then -- standalone buff or debuff
			RegisterStatusAura(self, self.handlerType, self.spell)
		elseif self.handlerType=='buff' then
			for spell in pairs(self.spells) do
				RegisterStatusAura( self, 'buff', spell )
			end
		else -- debuffType or group of filtered debuffs
			RegisterStatusAura(self, self.handlerType, self.dbx.subType, self.fullUpdate)
		end
		if self.thresholds and (not self.dbx.colorThresholdValue) then
			RegisterTimeTrackerStatus(self, self.dbx.colorThresholdElapsed)
		end
		UpdateAllAuras()
		if self.OnEnableAura then self:OnEnableAura() end
	end
	local function OnDisable(self)
		UnregisterStatusAura(self, self.handlerType, self.dbx.subType)
		UnregisterTimeTrackerStatus(self)
		wipe(self.idx); wipe(self.exp); wipe(self.val)
		if self.OnDisableAura then self:OnDisableAura() end
	end
	local function UpdateStateCombineStacks(s, u, i, sid, nam, tex, cnt, dur, exp, typ)
		if s.seen then -- adding extra debuffs stacks
			s.cnt[u] = s.cnt[u] + cnt
		else -- debuff must be always marked to be updated (seen=1) and cnt must be initialized even if first debuff is not new and didn't change
			s.seen, s.idx[u], s.tex[u], s.cnt[u], s.dur[u], s.exp[u], s.typ[u], s.tkr[u], s.val[u]  = 1, i, tex, cnt, dur, exp, typ, 1, nil
		end
	end
	local function UpdateDB(self,dbx)
		if self.enabled then self:OnDisable() end
		local dbx = dbx or self.dbx
		local blinkThreshold = dbx.blinkThreshold or nil
		self.vId = dbx.valueIndex or 0
		self.valMax = dbx.valueMax
		self.GetPercent = dbx.valueIndex and (dbx.valueMax and GetPercentMax or GetPercentHealth) or Grid2.statusLibrary.GetPercent
		if self.spells then wipe(self.spells) end
		if dbx.auras then -- multiple spells
			local useSpellId = dbx.useSpellId
			self.spells = self.spells or {}
			if dbx.useSpellId then
				for _,spell in ipairs(dbx.auras) do
					self.spells[spell] = true
				end
			else
				for _,spell in ipairs(dbx.auras) do
					local name = type(spell)=='number' and GetSpellInfo(spell) or spell -- 3.3.5: nil while spell not cached
					self.spells[ name or spell ] = true -- never a nil key: falls back to the spellId itself
				end
			end
		elseif dbx.spellName then -- single spell
			local spell = dbx.spellName
			self.spellText = type(spell)=='number' and GetSpellInfo(spell) or tostring(spell)
			if not self.spellText then self.spellText = tostring(spell) end -- 3.3.5: spellId not cached yet
			self.spell = dbx.useSpellId and spell or self.spellText
		end
		if dbx.mine==2 then  -- 2>nil = not mine;  1|true>true = mine;  false|nil>false = mine&not-mine
			self.isMine = nil
		else
			self.isMine = not not dbx.mine
		end
		if dbx.missing then
			local spell = dbx.auras and dbx.auras[1] or dbx.spellName
			self.missingTexture = (spell and select(3,GetSpellInfo(spell))) or "Interface\\ICONS\\Achievement_General"
			self.GetIcon  = GetIconMissing
			self.GetCount = GetCountMissing
			self.GetDuration = GetDurationMissing
			self.GetExpirationTime = GetExpirationTimeMissing
			if dbx.missingPets then
				if self.filtered then
					self.IsActive = blinkThreshold and IsInactiveBlinkFilterPets or IsInactiveFilterPets
				else
					self.IsActive = blinkThreshold and IsInactiveBlinkPets or IsInactivePets
				end
			else
				if self.filtered then
					self.IsActive = blinkThreshold and IsInactiveBlinkFilter or IsInactiveFilter
				else
					self.IsActive = blinkThreshold and IsInactiveBlink or IsInactive
				end
			end
			self.thresholds = nil
			self.UpdateState = nil
		else
			self.stacks = dbx.enableStacks
			self.GetIcon = GetIcon
			self.GetCount = GetCount
			self.GetExpirationTime = GetExpirationTime
			self.GetDuration = dbx.maxDuration and GetDurationFixed or GetDuration
			self.UpdateState = dbx.combineStacks and UpdateStateCombineStacks or nil
			if blinkThreshold then
				if blinkThreshold>0 then -- blink/glow active after some time threshold
					self.thresholds = { blinkThreshold }
					if self.filtered then
						self.IsActive = self.stacks and IsActiveStacksBlinkFilter or IsActiveBlinkFilter
					else
						self.IsActive = self.stacks and IsActiveStacksBlink or IsActiveBlink
					end
				else -- blink/glow always active, no timetracker is needed
					self.thresholds = nil
					if self.filtered then
						self.IsActive = self.stacks and IsActiveStacksBlinkAFilter or IsActiveBlinkAFilter
					else
						self.IsActive = self.stacks and IsActiveStacksBlinkA or IsActiveBlinkA
					end
				end
			else -- blinkThreshold==0 => always active
				self.thresholds = dbx.colorThreshold
				if self.filtered then
					self.IsActive = self.stacks and IsActiveStacksFilter or IsActiveFilter
				else
					self.IsActive = self.stacks and IsActiveStacks or IsActive
				end
			end
		end
		local colorCount = dbx.colorCount or 1
		if dbx.colorThreshold and colorCount>1 then -- color by time or value
			self.colors = self.colors or {}
			for i=1,colorCount do self.colors[i] = dbx["color"..i] end
			self.GetColor = dbx.colorThresholdValue and GetValueColor or GetTimeColor
		else -- single color or color by number of stacks
			MakeStatusColorHandler(self)
		end
		if dbx.type == "debuffType" then
			self.debuffFilter = dbx.debuffFilter
			self.GetBorder = GetBorderMandatory
		else
			self.GetBorder = GetBorderOptional
		end
		self.GetTooltip = (self.handlerType~="buff") and GetDebuffTooltip or GetBuffTooltip
		self.customText = dbx.text
		if dbx.text==1 then -- tracked value
			self.GetText = GetTextValue
		elseif dbx.text then -- custom text
			self.GetText = GetTextCustom
		else -- aura name
			self.GetText = GetTextSpell
		end
		if self.OnUpdate then self:OnUpdate(dbx) end
		if self.enabled then self:OnEnable() end
	end
	CreateStatusAura = function(status, baseKey, dbx, handlerType, statusTypes)
		status.handlerType = handlerType
		status.idx = {}
		status.tex = {}
		status.cnt = {}
		status.exp = {}
		status.dur = {}
		status.typ = {}
		status.val = {}
		status.tkr = {}
		status.Reset       = Reset
		status.GetCountMax = GetCountMax
		status.UpdateDB    = UpdateDB
		status.OnEnable    = OnEnable
		status.OnDisable   = OnDisable
		Grid2:RegisterStatus(status, statusTypes, baseKey, dbx)
		status:UpdateDB() -- 3.3.5: target RegisterStatus() does not call UpdateDB() (bcc does)
		return status
	end
end
Grid2.CreateStatusAura = CreateStatusAura
--}}