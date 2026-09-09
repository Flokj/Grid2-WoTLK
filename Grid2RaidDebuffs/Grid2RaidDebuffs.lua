-- Raid Debuffs module, implements raid-debuffs statuses

local L = LibStub("AceLocale-3.0"):GetLocale("Grid2")
-- 3.3.5 backport: core already provides a built-in "Grid2RaidDebuffs" module
-- (modules/StatusRaidDebuffs.lua). Reuse it instead of NewModule() which would
-- throw "Module already exists" — this file then upgrades the engine in place.
local GSRD = Grid2:GetModule("Grid2RaidDebuffs", true) or Grid2:NewModule("Grid2RaidDebuffs")
local frame = CreateFrame("Frame")

local Grid2 = Grid2
local next = next
local ipairs = ipairs
local strfind = strfind
local GetTime = GetTime
local UnitGUID = UnitGUID
local isClassic = Grid2.versionCli<50000 -- for this module MoP is not considered classic because supports EncounterJournal IDs
-- 3.3.5: Grid2.API.UnitAuraLite does not exist and raw UnitDebuff() returns
-- (name, rank, icon, count, dispelType, duration, expiration, caster, ..., spellId?)
-- with the spellID in 11th position (when the client provides it). Adapt to the
-- modern order this file unpacks everywhere (id at 11, isBoss unused on 3.3.5).
local UnitAura = (Grid2.API and Grid2.API.UnitAuraLite) or function(unit, index, filter)
	local name, _, icon, count, dtype, duration, expiration, caster, _, _, spellId = UnitDebuff(unit, index, filter)
	if not name then return end
	return name, icon, count, dtype, duration, expiration, caster, nil, nil, nil, spellId, nil
end

local GetSpellInfo = Grid2.API.GetSpellInfo
local LoadAddOn = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn;

local EJ_GetInstanceForMap = EJ_GetInstanceForMap or function(mapID) return mapID-100000 end
local EJ_SelectInstance = EJ_SelectInstance or Grid2.Dummy
local EJ_GetEncounterInfoByIndex = EJ_GetEncounterInfoByIndex or Grid2.Dummy

GSRD.defaultDB = { profile = { debuffs = {}, enabledModules = {} } }

-- general variables
local instance_ej_id
local instance_map_id
local instance_bmap_id
local instance_map_name
local statuses = {}
local spells_order = {}
local spells_status = {}
local spells_count = 0

-- autdetect debuffs variables
local auto_status
local auto_time
local auto_boss
local auto_instance
local auto_encounter
local auto_debuffs
local auto_blacklist = { [160029] = true, [36032] = true, [6788] = true, [80354] = true, [95223] = true, [114216] = true, [57723] = true, [225080] = true, [25771] = true }

-- Fix some bugged maps (EJ_GetInstanceForMap does not return valid instanceID for the listed maps)
-- We replace bugged mapIDs with another non-bugged mapIDs of the same instance.
local bugged_maps = {
	-- Fix for Uldir map 1150 (ticket #588)
	[1150] = 1148,
	-- Fixes for Eternal Palace (ticket #691)
	[1515] = 1512,
	[1516] = 1512,
	-- Fixes for Ny'alotha the Waking City (ticket #786)
	[1580] = 1581,
	[1582] = 1581,
	-- Spires of Ascension
	[1692] = 1693,
	-- The Rookery (CF ticket #1333)
	[2315] = 2319,
	[2317] = 2319,
	[2318] = 2319,
	-- Liberation of Undermine (CF ticket #1338)
	[2428] = 2406,
}

-- LDB Tooltip (Grid2.tooltipFunc does not exist on 3.3.5, tooltip integration disabled)
if Grid2.tooltipFunc then
Grid2.tooltipFunc['RaidDebuffsCount'] = function(tooltip)
	if instance_map_name and next(statuses) then
		tooltip:AddDoubleLine( instance_map_name, string.format("|cffff0000%d|r %s",spells_count,L['debuffs']), 255,255,255, 255,255,0)
	end
end
end

-- debuffs statuses integration
Grid2.raidDebuffsLoaded = spells_order

-- roster units (3.3.5: Grid2.roster_guids does not exist, roster_units maps guid->unit)
local roster_units = Grid2.roster_units
local function unit_in_roster(unit)
	local guid = UnitGUID(unit)
	return guid and roster_units[guid] ~= nil
end

-- debuffs type colors table (3.3.5: Grid2.debuffTypeColors does not exist, fall back to status color)
local debuffTypeColors = Grid2.debuffTypeColors or {}

-- GSRD
local function RefreshAuras(self, event, unit)
	if unit_in_roster(unit) then
		local index = 1
		while true do
			local name, te, co, ty, du, ex, ca, _, _, _, id, isBoss = UnitAura(unit, index, 'HARMFUL')
			if not name then break end
			-- 3.3.5: UnitDebuff has no spellID, id is nil — never index tables with it.
			local order = spells_order[name]
			if not order and id then
				order, name = spells_order[id], id
			end
			if order then
				spells_status[name]:AddDebuff(order, te, co, ty, du, ex, index)
			elseif id and auto_time and (not auto_blacklist[id]) and (ex<=0 or du<=0 or ex-du>=auto_time) then
				order = GSRD:RegisterNewDebuff(id, ca, te, co, ty, du, ex, isBoss)
				if order then
					auto_status:AddDebuff(order, te, co, ty, du, ex, index)
				end
			end
			index = index + 1
		end
		for status in next, statuses do
			status:UpdateState(unit)
		end
	end
end
frame:SetScript("OnEvent", RefreshAuras)

function GSRD:RefreshAuras()
	for unit in Grid2:IterateRosterUnits() do
		RefreshAuras(frame, nil, unit)
	end
end

function GSRD:OnModuleEnable()
	if Grid2.classicDurations then
		UnitAura = LibStub("LibClassicDurations").UnitAuraDirect
	end
	if not isClassic then
		self.db.global.cache_ejid = self.db.global.cache_ejid or {}
	end
	self:UpdateZoneSpells()
end

function GSRD:OnModuleDisable()
	self:ResetZoneSpells()
end

-- cache to remember ej_id for each instance, to fix subzones not recognized by EJ_GetInstanceForMap()
function GSRD:ValidateEJID(ej_id, map_id, bm)
	if isClassic then return ej_id end
	if IsInInstance() then
		local cache_ejid = self.db.global.cache_ejid
		if ej_id==0 then
			ej_id = cache_ejid[map_id]
			if self.debugging then self:Debug("Unknown SubZone detected bMapID[%d], using cache for instanceID[%d] => EJID[%d]",bm or -1, map_id or -1, ej_id or -1); end
		elseif not cache_ejid[map_id] then
			cache_ejid[map_id] = ej_id
		end
	end
	return ej_id or 0
end

-- 3.3.5 backport: database keys are classic select(8,GetInstanceInfo()) map ids,
-- which do not exist on 3.3.5 — resolve the current instance by (localized) name.
-- Only Classic/BC/WotLK instances: their data files are the ones loaded on 3.3.5,
-- and old LibBabble-Zone-3.0 errors on unknown (Cata/MoP) names.
local instanceKeysByName = {
	['Black Temple'] = 100564,
	['Blackwing Lair (BWL)'] = 469,
	['Icecrown Citadel'] = 100631,
	['Karazhan'] = 100532,
	['Molten Core (MC)'] = 100409,
	['Naxxramas'] = 100533,
	["Onyxia's Lair"] = 100249,
	["Ruins of Ahn'Qiraj (AQ20)"] = 100509,
	['Serpentshrine Cavern'] = 100548,
	['Sunwell Plateau'] = 100580,
	["Temple of Ahn'Qiraj (AQ40)"] = 100531,
	['The Eye of Eternity'] = 100616,
	['The Obsidian Sanctum'] = 100615,
	['The Ruby Sanctum'] = 100724,
	['Trial of the Crusader'] = 100649,
	['Ulduar'] = 100603,
	['Vault of Archavon'] = 100624,
	["Zul'gurub"] = 100309,
}
local BabbleZone = LibStub("LibBabble-Zone-3.0", true)
-- 3.3.5: use the unstrict table (plain, returns nil for missing keys) — the strict
-- lookup table warns through the error handler on unknown keys, which pcall cannot silence.
local BZunstrict = BabbleZone and BabbleZone:GetUnstrictLookupTable() or {}
-- Data names may carry a disambiguation suffix the real zone never has ("Molten Core (MC)").
local nameAliases = { ["Zul'gurub"] = "Zul'Gurub" }
local mapKeyByLocalizedName = {}
for enName, key in pairs(instanceKeysByName) do
	mapKeyByLocalizedName[enName] = key
	local base = enName:match("^(.-)%s*%([^)]*%)$") or enName
	for _, form in pairs({ base, nameAliases[enName] }) do
		if form then mapKeyByLocalizedName[BZunstrict[form] or form] = key end
	end
end
instanceKeysByName = nil

-- In Classic Encounter Journal data does not exist so we always use map_id so: instance_ej_id+100000=instance_map_id
function GSRD:UpdateZoneSpells(event)
	-- 3.3.5: C_Map does not exist, only used for retail EJ/bugged-maps logic (skipped on classic path)
	local bm = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
	if bm or isClassic then
		-- 3.3.5: GetInstanceInfo() has no mapID (8th return added later); fall back
		-- to the current map area ID, and to 0 (no crash) if that is missing too.
		local _,_,_,_,_,_,_,mapID = GetInstanceInfo()
		if not mapID and GetCurrentMapAreaID then
			if SetMapToCurrentZone then SetMapToCurrentZone() end
			mapID = GetCurrentMapAreaID()
		end
		local map_id = (mapID or 0) + 100000 -- +100000 to avoid collisions with instance_ej_id
		-- 3.3.5 backport: GetCurrentMapAreaID numbering differs from the database
		-- keys — when the instance name resolves to a key, prefer it.
		local iname = GetInstanceInfo()
		local nameKey = iname and mapKeyByLocalizedName[iname]
		if nameKey then map_id = nameKey end
		if event and map_id==instance_map_id and instance_ej_id~=0 then return end
		self:ResetZoneSpells()
		instance_ej_id = self:ValidateEJID( EJ_GetInstanceForMap( (isClassic and map_id) or bugged_maps[bm] or bm ), map_id, bm  )
		instance_map_id = map_id
		instance_map_name = GetInstanceInfo()
		instance_bmap_id = bm or -1
		for status in next,statuses do
			status:LoadZoneSpells()
		end
		self:UpdateEvents()
		self:ClearAllIndicators()
	else
		C_Timer.After(3, function() self:UpdateZoneSpells(true) end )
	end
end

function GSRD:GetCurrentZone()
	return instance_ej_id, instance_map_id
end

function GSRD:ClearAllIndicators()
	for status in next, statuses do
		status:ClearAllIndicators()
	end
end

function GSRD:ResetZoneSpells()
    spells_count = 0
	wipe(spells_order)
	wipe(spells_status)
end

function GSRD:UpdateEvents()
	local new = not ( next(spells_order) or auto_status )
	local old = not frame:IsEventRegistered("UNIT_AURA")
	if new ~= old then
		if new then
			frame:UnregisterEvent("UNIT_AURA")
			if Grid2.classicDurations then LibStub("LibClassicDurations"):Unregister(GSRD) end
		else
			frame:RegisterEvent("UNIT_AURA")
			if Grid2.classicDurations then LibStub("LibClassicDurations"):Register(GSRD) end
		end
	end
end

function GSRD:Grid_UnitLeft(_, unit)
	for status in next, statuses do
		status:ResetState(unit)
	end
end

-- raid debuffs autodetection
function GSRD:RegisterNewDebuff(spellId, caster, te, co, ty, du, ex, isBoss)
	-- 3.3.5: spellId is nil (UnitDebuff has no spellID) — nothing to key on.
	if not spellId then return end
	if (not isBoss) and (caster and Grid2:IsGUIDInRaid(UnitGUID(caster))) then return end
	if not auto_debuffs then
		self:RegisterEncounter()
	end
	local debuffs = auto_status.dbx.debuffs[auto_instance]
	if not debuffs then
		debuffs = {}; auto_status.dbx.debuffs[auto_instance] = debuffs
		if self.debugging then self:Debug("New Debuff detected: [%d] instance: [%d] boss: [%s]", spellId, auto_instance, auto_encounter or "nil"); end
	end
	local order = #debuffs + 1
	spells_order[spellId]  = order
	spells_status[spellId] = auto_status
	debuffs[order] = spellId
	auto_debuffs[#auto_debuffs+1] = spellId
	return order
end

function GSRD:RegisterEncounter(encounterName)
	encounterName  = encounterName or auto_boss or self:GetBossName()
	auto_encounter = encounterName
	auto_instance  = (IsInInstance() and instance_ej_id~=0) and instance_ej_id or instance_map_id
	local debuffs  = self.db.profile.debuffs[auto_instance]
	if not debuffs then
		debuffs = { { id = auto_instance, name = instance_map_name, raid = IsInRaid() or nil } }
		self.db.profile.debuffs[auto_instance] = debuffs
	end
	auto_debuffs = debuffs[encounterName]
	if not auto_debuffs then
		local instance = (instance_ej_id or 0)>0 and instance_ej_id or (isClassic and 1028 or 1192)-- 0=>asuming Azeroth(1028)(classic) or Shadowlands(1192)(retail)
		local encOrder, encName, encID, _ = 0
		EJ_SelectInstance(instance)
		repeat
			encOrder = encOrder + 1
			encName, _, encID = EJ_GetEncounterInfoByIndex(encOrder, instance)
		until encName==nil or encName == encounterName
		auto_debuffs = { order = encOrder, ejid = encID }
		debuffs[encounterName] = auto_debuffs
	end
end

function GSRD:GetBossName()
	-- 3.3.5: GetMaxPlayerLevel() does not exist, max level on WotLK is 80.
	local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 80
	return UnitName("boss1") or ((UnitLevel("target")==-1 or (UnitLevel("target") or 0)>=maxLevel+2) and UnitName("target")) or "unknown"
end

function GSRD:ENCOUNTER_START(_,encounterID,encounterName)
	self:RegisterEncounter(encounterName)
end

function GSRD:ZONE_CHANGED(event) -- general fix for subzones in instances with no assigned ejid
	if instance_ej_id==0 and IsInInstance() then
		if self.debugging then self:Debug("Wrong SubZone detected bMapID: [%d], reloading raid debuffs",instance_bmap_id or -1); end
		self:UpdateZoneSpells(false)
	end
end

function GSRD:PLAYER_REGEN_DISABLED()
	auto_time = GetTime()
	auto_boss = self:GetBossName()
end

function GSRD:PLAYER_REGEN_ENABLED()
	if not UnitIsDeadOrGhost("player") then
		auto_time = nil
		auto_boss = nil
		auto_debuffs = nil
	end
end

function GSRD:EnableAutodetect(status)
	auto_status = status
	self:UpdateEvents()
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("ENCOUNTER_START")
	if InCombatLockdown() then self:PLAYER_REGEN_DISABLED()	end
end

function GSRD:DisableAutodetect()
	auto_status  = nil
	auto_time    = nil
	auto_boss    = nil
	auto_debuffs = nil
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("ENCOUNTER_START")
	self:UpdateEvents()
end

-- statuses
local class = {
	GetColor          = Grid2.statusLibrary.GetColor,
	IsActive          = function(self, unit) return self.states[unit]      end,
	GetIcon           = function(self, unit) return self.textures[unit]    end,
	GetCount          = function(self, unit) return self.counts[unit]      end,
	GetDuration       = function(self, unit) return self.durations[unit]   end,
	GetExpirationTime = function(self, unit) return self.expirations[unit] end,
	GetTooltip        = function(self, unit, tip, slotID) local idx = slotID or self.states[unit];	if idx then tip:SetUnitDebuff(unit, idx) end; end,
}

do
	local textures, counts, expirations, durations, colors, slots = {}, {}, {}, {}, {}, {}
	function class:GetIconsMultiple(unit, max)
		local color, tc, i, j, name, id, dt, _ = self.dbx.color1, self.dbx.debuffTypeColorize, 1, 1
		repeat
			name, textures[j], counts[j], dt, durations[j], expirations[j], _, _, _, _, id = UnitAura(unit, i, 'HARMFUL')
			if not name then break end
			-- 3.3.5: id is nil, guard the lookup (indexing with nil errors).
			if spells_status[name]==self or (id and spells_status[id]==self) then
				colors[j] = tc and debuffTypeColors[dt] or color
				slots[j] = i
				j = j + 1
			end
			i = i + 1
		until j>max
		return j-1, textures, counts, expirations, durations, colors, slots
	end
end

function class:ClearAllIndicators()
	local states = self.states
	for unit in pairs(states) do
		states[unit] = nil
		self:UpdateIndicators(unit)
	end
end

function class:LoadZoneSpells()
	if instance_map_id then
		self.spells_count = 0
		local debuffs = self.dbx.debuffs
		local db = debuffs[instance_map_id] or debuffs[instance_ej_id]
		if db then
			for index, spell in ipairs(db) do
				local name = spell<0 and -spell or GetSpellInfo(spell)
				if name and (not spells_order[name]) then
					spells_order[name]  = index
					spells_status[name] = self
					self.spells_count = self.spells_count + 1
				end
			end
		end
		spells_count = spells_count + self.spells_count
		if GSRD.debugging then
			GSRD:Debug("Zone[%s] C_MapID[%d] EjID[%d] mapID[%d] Status [%s]: %d raid debuffs loaded from [%d]", instance_map_name, instance_bmap_id, instance_ej_id, instance_map_id, self.name, self.spells_count, (debuffs[instance_map_id] and instance_map_id) or (debuffs[instance_ej_id] and instance_ej_id) )
		end
	end
end

function class:UpdateDB()
	self.GetIcons = self.dbx.enableIcons and self.GetIconsMultiple or nil
	self.UpdateState = self.dbx.enableIcons and self.UpdateStateMultiple or self.UpdateStateSingle
	self.GetColor = self.dbx.debuffTypeColorize and self.GetDebuffTypeColor or Grid2.statusLibrary.GetColor
end

function class:UnloadZoneSpells()
	if next(statuses) then
		spells_count = spells_count - (self.spells_count or 0)
		for name,status in next,spells_status do
			if status==self then
				spells_order[name] = nil
				spells_status[name] = nil
			end
		end
	else
		GSRD:ResetZoneSpells()
	end
	self.spells_count = 0
end

function class:OnEnable()
	if not next(statuses) then
		GSRD:RegisterEvent("ZONE_CHANGED_NEW_AREA", "UpdateZoneSpells")
		GSRD:RegisterMessage("Grid_UnitLeft")
		if not isClassic then GSRD:RegisterEvent("ZONE_CHANGED"); end
	end
	statuses[self] = true
	self:UpdateDB()
	self:LoadZoneSpells()
	GSRD:UpdateEvents()
end

function class:OnDisable()
	wipe(self.states)
	statuses[self] = nil
	self:UnloadZoneSpells()
	if not next(statuses) then
	    GSRD:ResetZoneSpells()
		GSRD:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
		GSRD:UnregisterMessage("Grid_UnitLeft")
		if not isClassic then GSRD:UnregisterEvent("ZONE_CHANGED"); end
		GSRD:UpdateEvents()
	end
end

function class:AddDebuff(order, te, co, ty, du, ex, index)
	if order < self.order or ( order == self.order and co > self.count ) then
		self.index      = index
		self.order      = order
		self.count      = co
		self.texture    = te
		self.type       = ty
		self.duration   = du
		self.expiration = ex
	end
end

function class:UpdateStateSingle(unit)
	if self.order<10000 then
		if self.count==0 then self.count = 1 end
		if	false           ~= not self.states[unit] or
			self.count      ~= self.counts[unit]     or
			self.type       ~= self.types[unit]      or
			self.texture    ~= self.textures[unit]   or
			self.duration   ~= self.durations[unit]  or
			self.expiration ~= self.expirations[unit]
		then
			self.states[unit]      = self.index
			self.counts[unit]      = self.count
			self.textures[unit]    = self.texture
			self.types[unit]       = self.type
			self.durations[unit]   = self.duration
			self.expirations[unit] = self.expiration
			self:UpdateIndicators(unit)
		end
		self.order, self.count = 10000, 0
	elseif self.states[unit] then
		self.states[unit] = nil
		self:UpdateIndicators(unit)
	end
end

function class:UpdateStateMultiple(unit)
	if self.order<10000 then
		self.states[unit]      = self.index
		self.counts[unit]      = self.count==0 and 1 or self.count
		self.textures[unit]    = self.texture
		self.types[unit]       = self.type
		self.durations[unit]   = self.duration
		self.expirations[unit] = self.expiration
		self.order, self.count = 10000, 0
	elseif self.states[unit] then
		self.states[unit] = nil
	end
	self:UpdateIndicators(unit)
end

function class:ResetState(unit)
	self.states[unit]      = nil
	self.counts[unit]      = nil
	self.textures[unit]    = nil
	self.types[unit]       = nil
	self.durations[unit]   = nil
	self.expirations[unit] = nil
end

function class:GetDebuffTypeColor(unit)
	local c = debuffTypeColors[ self.types[unit] ] or self.dbx.color1
	return c.r, c.g, c.b, c.a
end

local function Create(baseKey, dbx)
	local status = Grid2.statusPrototype:new(baseKey, false)
	status.states      = {}
	status.textures    = {}
	status.counts      = {}
	status.types       = {}
	status.durations   = {}
	status.expirations = {}
	status.count       = 0
	status.order       = 10000
	status:Inject(class)
	Grid2:RegisterStatus(status, { 'icon', 'color', 'text', 'tooltip' }, baseKey, dbx)
	return status
end

Grid2.setupFunc["raid-debuffs"] = Create

Grid2:DbSetStatusDefaultValue( "raid-debuffs", {type = "raid-debuffs", debuffs={}, color1 = {r=1,g=.5,b=1,a=1}} )

-- Hook to update database config
local prev_UpdateDefaults = Grid2.UpdateDefaults
function Grid2:UpdateDefaults()
	prev_UpdateDefaults(self)
	local version = Grid2:DbGetValue("versions", "Grid2RaidDebuffs") or 0
	if version >= 4 then return end
	if version == 0 then
		Grid2:DbSetMap( "icon-center", "raid-debuffs", 145)
	else -- Remove all enabled debuffs
		for _,db in pairs(Grid2.db.profile.statuses) do
			if db.type == "raid-debuffs" then
				db.debuffs = {}
			end
		end
		GSRD.db.profile.debuffs = {}
		GSRD.db.profile.enabledModules = {}
	end
	Grid2:DbSetValue("versions","Grid2RaidDebuffs",4)
end

-- Hook to load Grid2RaidDebuffOptions module
local prev_LoadOptions = Grid2.LoadOptions
function Grid2:LoadOptions()
	LoadAddOn("Grid2RaidDebuffsOptions")
	prev_LoadOptions(self)
end
