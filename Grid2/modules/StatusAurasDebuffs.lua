-- Group of Debuffs status
-- 3.3.5: no Grid2.API.UnitAuraLite/SpellGetVisibilityInfo/TooltipData API (see guards below),
-- group scanning falls back to UnitDebuff(); full multi-aura support needs the new aura engine.
local Grid2 = Grid2
local wipe = wipe
local SpellGetVisibilityInfo = SpellGetVisibilityInfo -- nil on 3.3.5, guarded in Grid2.IsRelevantDebuff()
local UnitAura = (Grid2.API and Grid2.API.UnitAuraLite) or function(unit, index) return UnitDebuff(unit, index) end
local GetSpellInfo = (Grid2.API and Grid2.API.GetSpellInfo) or GetSpellInfo -- 3.3.5: no Grid2.API
local typeColors = Grid2.debuffTypeColors or {} -- 3.3.5: table does not exist, fall back to status color

local emptyTable = {}
local textures = {}
local counts = {}
local expirations = {}
local durations = {}
local colors = {}
local slots = {}
local spells = {}

local code_standard = [[
local spells = Grid2.statuses["%s"].spells
local dispel = Grid2.debuffPlayerDispelTypes
local rdebuffs = Grid2.raidDebuffsLoaded
local IsRelevantDebuff = Grid2.IsRelevantDebuff
return function(self, unit, sid, name, count, duration, caster, boss, typ)
	return %s
end ]]

local code_stacks = [[
local spells = Grid2.statuses["%s"].spells
local dispel = Grid2.debuffPlayerDispelTypes
local rdebuffs = Grid2.raidDebuffsLoaded
local IsRelevantDebuff = Grid2.IsRelevantDebuff
return function(self, unit, sid, name, count, duration, caster, boss, typ)
	if not (%s) then return end
	if not self.seen then self.currentName=name; return true; end
	if name==self.currentName then self.cnt[unit] = self.cnt[unit] + count; end
end ]]

-- helper functions
local function GetColorStd(self) -- single color for multiple-icons
	return self.color
end

local function GetColorTyp(self, typ, bos) -- color by debuff type for multiple-icons
	return (typ and typeColors[typ]) or (bos and typeColors.Boss) or self.color
end

-- code to manage dbx.filterRelevant debuffs filter
local raidFilter = "RAID_OUTOFCOMBAT"
local raid_statuses = {}

function Grid2.IsRelevantDebuff(spellId, caster)
	if not SpellGetVisibilityInfo then return true end -- 3.3.5: API missing, every debuff is relevant
	local hasCustom, alwaysShowMine, showForMySpec = SpellGetVisibilityInfo(spellId, raidFilter)
	return not hasCustom or showForMySpec or (alwaysShowMine and (caster=="player" or caster=="pet" or caster=="vehicle"))
end

local function UpdateRaidStatuses(event)
	local newFilter = (event=='PLAYER_REGEN_DISABLED') and "RAID_INCOMBAT" or "RAID_OUTOFCOMBAT"
	if newFilter~=raidFilter then
		raidFilter = newFilter
		for status in next, raid_statuses do
			status:UpdateAllUnits()
		end
	end
end

local function status_OnEnableAura(self)
	if not next(raid_statuses) then
		self:RegisterEvent("PLAYER_REGEN_ENABLED", UpdateRaidStatuses)
		self:RegisterEvent("PLAYER_REGEN_DISABLED", UpdateRaidStatuses)
	end
	raid_statuses[self] = true
end

local function status_OnDisableAura(self)
	raid_statuses[self] = nil
	if not next(raid_statuses) then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED", UpdateRaidStatuses)
		self:UnregisterEvent("PLAYER_REGEN_DISABLED", UpdateRaidStatuses)
	end
end

-- Compile a filter function, the function is called from StatusAura.lua to filter auras
local function CompileUpdateStateFilter(self, lazy, useSpellId, code)
	local dbx = self.dbx
	local t = {}
	if dbx.filterRaidDebuffs~=nil and Grid2.raidDebuffsLoaded then
		t[#t+1] = string.format("%s (rdebuffs[name] or rdebuffs[sid])", dbx.filterRaidDebuffs and 'not' or '')
	end
	if dbx.filterDispelDebuffs~=nil then
		t[#t+1] = string.format("%s dispel[typ]", dbx.filterDispelDebuffs and '' or 'not')
	end
	if dbx.filterLongDebuffs~=nil then
		t[#t+1] = string.format("%s (duration>=300)", dbx.filterLongDebuffs and 'not' or '')
	end
	if dbx.filterPermaDebuffs~=nil then
		t[#t+1] = string.format("%s (duration==0)", dbx.filterPermaDebuffs and 'not' or '')
	end
	if dbx.filterBossDebuffs~=nil then
		t[#t+1] = string.format("%s boss", dbx.filterBossDebuffs and 'not' or '')
	end
	if dbx.filterCaster~=nil then
		t[#t+1] = string.format("%s (caster=='player' or caster=='pet' or caster=='vehicle')", dbx.filterCaster and 'not' or '')
	end
	if dbx.filterTyped~=nil then
		t[#t+1] = string.format( "%s typ", dbx.filterTyped and 'not' or '' )
	end
	if dbx.filterRelevant~=nil then
		t[#t+1] = string.format( "%s IsRelevantDebuff(sid, caster)", dbx.filterRelevant and 'not' or '' )
	end
	local q -- special case for black/white lists because they are always strict (non lazy).
	if dbx.useWhiteList then
		q = useSpellId and "(spells[sid] or spells[name])" or "spells[name]"
	elseif next(self.spells) then
		q = useSpellId and "not (spells[sid] or spells[name])" or "not spells[name]"
	end
	local r = table.concat( t, lazy and ' or ' or ' and ' )
	if r=='' then
		r = q or 'true'
	elseif q then
		r = string.format("%s and (%s)", q, r)
	end
	return assert(loadstring( string.format(code, self.name, r) ))()
end

-- Called by "icons" indicator, standard
local function status_GetIconsFilterStandard(self, unit, max)
	local UpdateState, GetColor, i, j, name, debuffType, caster, sid, boss, _ = self.UpdateState, self.GetColorIcons, 1, 1
	repeat
		name, _, textures[j], counts[j], debuffType, durations[j], expirations[j], caster, _, _, sid = UnitAura(unit, i, 'HARMFUL')
		if not name then break end
		if UpdateState(self, unit, sid, name, counts[j], durations[j], caster, nil, debuffType) then
			colors[j] = GetColor(self, debuffType, boss)
			slots[j] = i
			j = j + 1
		end
		i = i + 1
	until j>max
	return j-1, textures, counts, expirations, durations, colors, slots
end

-- Called by "icons" indicator, combine stacks
local function status_GetIconsFilterStacks(self, unit, max)
	local CheckState, GetColor, i, j, name, texture, count, debuffType, duration, expiration, caster, sid, boss, _ = self.CheckState, self.GetColorIcons, 1, 1
	wipe(spells)
	repeat
		name, _, texture, count, debuffType, duration, expiration, caster, _, _, sid = UnitAura(unit, i, 'HARMFUL')
		if not name then break end
		if CheckState(self, unit, sid, name, count, duration, caster, nil, debuffType) then
			local k = spells[name]
			if k then -- add extra stacks
				counts[k] = counts[k] + (count==0 and 1 or count)
				if expiration > expirations[k] then
					expirations[k] = expiration
					slots[k] = i
				end
			else -- add new debuff
				spells[name]   = j
				textures[j]    = texture
				durations[j]   = duration
				expirations[j] = expiration
				counts[j]      = count==0 and 1 or count
				colors[j]      = GetColor(self, debuffType, boss)
				slots[j] = i
				j = j + 1
			end

		end
		i = i + 1
	until j>max
	return j-1, textures, counts, expirations, durations, colors, slots
end

-- color by debuff type
local function status_GetDebuffTypeColor(self, unit)
	local color = typeColors[ self.typ[unit] ] or self.color
	if color then
		return color.r, color.g, color.b, color.a
	else
		return 0,0,0,1
	end
end

-- to add/remove spells from a macro
local function status_IgnoreTooltipDebuff(self)
	if GameTooltip:IsVisible() then
		local dbx = self.dbx
		local spellID
		if GameTooltip.GetTooltipData then
			local data = GameTooltip:GetTooltipData()
			spellID = data and tonumber(data.id)
		end
		if spellID then
			local spellName = GetSpellInfo(spellID)
			if spellName then
				local spellKey = dbx.useSpellId and spellID or spellName
				if self.spells and self.spells[spellKey] then
					for i=#dbx.auras,1,-1 do
						local spell = dbx.auras[i]
						if spell==spellID or spell==spellKey then
							table.remove(dbx.auras,i)
						end
					end
					Grid2:Print( string.format('Spell "%s" |cFF%sremoved|r from "%s" status.',spellName, dbx.useWhiteList and 'ff0000' or '00ff00', self.name) )
				else
					if not dbx.auras then
						dbx.auras = {}
						dbx.useWhiteList = nil
					end
					table.insert(dbx.auras, spellID)
					Grid2:Print( string.format('Spell "%s" |cFF%sadded|r to "%s" status.',spellName, dbx.useWhiteList and '00ff00' or 'ff0000', self.name) )
				end
				self:Refresh()
			else
				Grid2:Print( string.format('Error, Unknown spellID: %d.',spellID) )
			end
		elseif not GameTooltip.GetTooltipData then
			-- 3.3.5: no TooltipData API, match the tooltip spell by name
			local tooltipName = GameTooltip:GetSpell()
			if tooltipName then
				if self.spells and self.spells[tooltipName] then
					for i=#dbx.auras,1,-1 do
						local spell = dbx.auras[i]
						if spell==tooltipName or GetSpellInfo(spell)==tooltipName then
							table.remove(dbx.auras,i)
						end
					end
					Grid2:Print( string.format('Spell "%s" |cFF%sremoved|r from "%s" status.',tooltipName, dbx.useWhiteList and 'ff0000' or '00ff00', self.name) )
				else
					if not dbx.auras then
						dbx.auras = {}
						dbx.useWhiteList = nil
					end
					table.insert(dbx.auras, tooltipName)
					Grid2:Print( string.format('Spell "%s" |cFF%sadded|r to "%s" status.',tooltipName, dbx.useWhiteList and '00ff00' or 'ff0000', self.name) )
				end
				self:Refresh()
			end
		end
	end
end

-- Called by status:UpdateDB()
local function status_Update(self, dbx)
	self.color = dbx.color1
	self.spells = self.spells or emptyTable
	self.GetColorIcons = dbx.debuffTypeColorize and GetColorTyp or GetColorStd
	self.UpdateState = CompileUpdateStateFilter(self, dbx.lazyFiltering, dbx.useSpellId, code_standard)
	if dbx.combineStacks then
		self.fullUpdate = true
		self.GetIcons = status_GetIconsFilterStacks
		self.CheckState = self.UpdateState
		self.UpdateState = CompileUpdateStateFilter(self, dbx.lazyFiltering, dbx.useSpellId, code_stacks)
	else
		self.fullUpdate = nil
		self.CheckState = nil
		self.GetIcons = status_GetIconsFilterStandard
	end
	if dbx.debuffTypeColorize then
		self.GetColor = status_GetDebuffTypeColor
	end
	self.OnEnableAura  = dbx.filterRelevant~=nil and status_OnEnableAura  or nil
	self.OnDisableAura = dbx.filterRelevant~=nil and status_OnDisableAura or nil
	self.IgnoreTooltipDebuff = status_IgnoreTooltipDebuff
end

-- Registration
do
	local statusTypes = { "color", "icon", "icons", "percent", "text", "tooltip" }
	Grid2.setupFunc["debuffs"] = function(baseKey, dbx)
		if Grid2.classicDurations then
			UnitAura = LibStub("LibClassicDurations").UnitAuraDirect
		end
		if dbx.spellName then -- fix possible wrong data in old database
			dbx.spellName = nil
		end
		local status = Grid2.statusPrototype:new(baseKey)
		status.OnUpdate = status_Update
		return Grid2.CreateStatusAura(status, basekey, dbx, 'debuff', statusTypes)
	end
end

--[[ status database configuration
	type = "debuffs"
	auras = { "Riptide", 12323, "Earth Shield", ... }
	useWhiteList = true | nil  				-- auras is a whitelist or blacklist
	-- nil=no filter; true=apply filter; false=apply inverted filter
	filterLong   = nil | true | false       -- long debuffs (>5min)
	filterBoss   = nil | true | false       -- boss debuffs
	filterCaster = nil | true | false       -- self casted or casted by me
	-- colors
	debuffTypeColorize = true | nil		-- return the color of the debuffType
	colorThresholdElapsed = true | nil 	-- true = color by elapsed time; nil= color by remaining time
	colorThreshold = { 10, 4, 2 } 	    -- thresholds in seconds to change the color
	colorCount = number
	color1 = { r=1,g=1,b=1,a=1 }
	color2 = { r=1,g=1,b=0,a=1 }
--]]
