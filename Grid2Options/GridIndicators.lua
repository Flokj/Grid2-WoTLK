--[[ Indicators options ]]--
local Grid2Options = Grid2Options
local L = Grid2Options.L

-- Direct link to AceConfigTable indicators list
Grid2Options.indicatorOptions = Grid2Options.options.args.indicators.args
-- Path to indicator icons
Grid2Options.indicatorIconPath = "Interface\\Addons\\Grid2Options\\media\\indicator-"
-- Creatable indicators list
Grid2Options.indicatorTypes = {}
-- Indicators sort order
Grid2Options.indicatorTypesOrder = {background = 1, alpha = 2, border = 3, glowborder = 4, multibar = 5, bar = 6, text = 7, square = 8, shape = 9, icon = 10, icons = 11, portrait = 12}

-- Register indicator options
function Grid2Options:RegisterIndicatorOptions(type, isCreatable, funcMakeOptions, optionParams)
	self.typeMakeOptions[type] = funcMakeOptions
	self.optionParams[type] = optionParams
	if isCreatable then
		self.indicatorTypes[type] = L[type]
	end
end

Grid2Options.indicatorTitleIconsOptions = {
	size = 24, offsetx = -4, offsety = -3, anchor = 'TOPRIGHT', spacing = 5,
	{ image = "Interface\\AddOns\\Grid2Options\\media\\delete", tooltip = L["Delete Indicator"],    func = function(info) Grid2Options:DeleteIndicatorConfirm( info.option.arg.indicator )  end },
	{ image = "Interface\\AddOns\\Grid2Options\\media\\rename", tooltip = L["Rename Indicator"],    func = function(info) Grid2Options:RenameIndicatorConfirm( info.option.arg.indicator )  end },
	{ image = "Interface\\AddOns\\Grid2Options\\media\\test",   tooltip = L["Highlight Indicator"], func = function(info) Grid2Options:ToggleIndicatorTestMode( info.option.arg.indicator ) end },
}

-- Creates an indicator title with delete/rename/highlight action icons
function Grid2Options:MakeIndicatorTitleOptions(options, indicator)
	local isDeletable = self.indicatorTypes[indicator.dbx.type]
	self:MakeTitleOptions( options,
		L[indicator.name] or indicator.name,
		string.format( "%s: %s", L['indicator'] or 'indicator', L[indicator.dbx.type] or indicator.dbx.type ),
		nil,
		self.indicatorIconPath .. (self.indicatorTypesOrder[indicator.dbx.type] and indicator.dbx.type or "default"),
		nil,
		isDeletable and { indicator = indicator, icons = Grid2Options.indicatorTitleIconsOptions }
		)
end

local function DeleteIndicatorReal(indicator)
	local name = indicator.name
	Grid2Options.LI[name] = nil
	Grid2Frame:WithAllFrames(indicator, "Disable")
	Grid2:DbSetIndicator(name, nil)
	if indicator.dbx.sideKick then
		Grid2:DbSetIndicator(indicator.dbx.sideKick.name, nil)
	end
	Grid2:UnregisterIndicator(indicator)
	Grid2Frame:UpdateIndicators()
	Grid2Options:DeleteIndicatorOptions(indicator)
	Grid2Options:SelectGroup('indicators')
end

function Grid2Options:DeleteIndicatorConfirm(indicator)
	if self:IndicatorIsInUse(indicator) then
		self:MessageDialog( L["This indicator cannot be deleted because is in use. Uncheck the statuses linked to the indicator first."] )
	else
		self:ConfirmDialog( L["Are you sure you want to delete this indicator?"], function() DeleteIndicatorReal(indicator) end )
	end
end

-- Per-indicator highlight test mode (ported from bcc, adapted: SpecializedLibGlow,
-- AceTimer instead of C_Timer, registeredFrames instead of activatedFrames)
do
	local LCG = LibStub("SpecializedLibGlow-1.0")
	local Test -- Test indicator
	local TestIcons = {}
	local TestAuras = {
	tex = {}, cnt = {}, exp = {}, dur = {}, col = {}, idx = {} }
	local Exclude = { bar = true, multibar = true, alpha = true }
	local ExcludeHigh = { glowborder = true, text = true }
	local COLOR ={1,1,0,1}
	local InitTestMode, testIndicator, highIndicator
	local function HighlightStop()
		if highIndicator then
			for _, parent in pairs(Grid2Frame.registeredFrames) do
				-- 3.3.5 backport: no indicator:GetFrame() here, frames live at parent[name]
				local frame = parent[highIndicator.name]
				if frame then
					LCG.ButtonGlow_Stop(frame)
					LCG.PixelGlow_Stop( frame, 'Grid2IndicatorHighlight' )
				end
			end
			highIndicator = nil
		end
	end
	local function HighlightIndicator(indicator)
		if indicator and not indicator.suspended then
			if ExcludeHigh[indicator.dbx.type] then testIndicator = indicator; return true end
			local active
			for _, parent in pairs(Grid2Frame.registeredFrames) do
				-- 3.3.5 backport: no indicator:GetFrame() here, frames live at parent[name]
				local frame = parent[indicator.name]
				if frame then
					if indicator.dbx.type == 'icon' then
						LCG.ButtonGlow_Start(frame, COLOR, 0.12)
					else
						LCG.PixelGlow_Start(frame, COLOR, 8, .3, nil, 1, 0,0, false, 'Grid2IndicatorHighlight')
					end
				end
				active = active or frame
			end
			if active then
				testIndicator, highIndicator = indicator, indicator
				Grid2:ScheduleTimer(HighlightStop, .7)
				return true
			end
		end
	end
	local function RegisterIndicator(indicator)
		if not Exclude[indicator.dbx.type] then
			indicator:RegisterStatus(Test, 10000)
		end
	end
	local function UnregisterIndicators()
		for indicator in pairs(Test.indicators) do
			indicator:UnregisterStatus(Test)
		end
		testIndicator = nil
	end
	function InitTestMode()
		local time, color = GetTime(), { r=1,g=1,b=1,a=0.6 }
		for _, category in pairs(Grid2Options.categories) do
			if category.icon then TestIcons[#TestIcons+1] = category.icon end
		end
		for i=1,#TestIcons do
			TestAuras.tex[i] = TestIcons[i]
			TestAuras.cnt[i] = math.random(1,3)
			TestAuras.exp[i] = time+math.random(10,60)
			TestAuras.dur[i] = math.random(30) + 3
			TestAuras.col[i] = color
		end
		-- create test status
		Test = Grid2.statusPrototype:new("/@@@test@@@/",false)
		function Test:IsActive()    return true end
		function Test:GetText()     return "99999" end
		function Test:GetColor()    return math.random(0,1),math.random(0,1),math.random(0,1),1 end
		function Test:GetPercent()	return math.random() end
		function Test:GetDuration() return 60 end
		function Test:GetExpirationTime() return GetTime() + 60 end
		function Test:GetIcon()	    return TestIcons[ math.random(#TestIcons) ] end
		function Test:GetIcons(_,m) return math.min(m,#TestIcons), TestAuras.tex, TestAuras.cnt, TestAuras.exp, TestAuras.dur, TestAuras.col, TestAuras.idx end
		function Test:GetBorder()	return 0 end
		function Test:GetTooltip()  return end
		Test.dbx = TestIcons -- Asigned to TestIcons to avoid creating a new table
		Grid2:RegisterStatus( Test, {"text","color", "percent", "icon"}, "test" )
		InitTestMode = Grid2.Dummy
	end
	function Grid2Options:ToggleIndicatorTestMode(indicator)
		local enable = indicator~=testIndicator
		InitTestMode()
		HighlightStop()
		UnregisterIndicators()
		if enable then
			RegisterIndicator(indicator)
			if not HighlightIndicator(indicator) then
				Grid2Options:MessageDialog(L["This indicator cannot be highlighted because is disabled for the current theme or layout."])
			end
		end
		Grid2Frame:UpdateIndicators()
	end
end

-- Insert options of a indicator in AceConfigTable
function Grid2Options:AddIndicatorOptions(indicator, statusOptions, layoutOptions, colorOptions, loadOptions)
	local options = self.indicatorOptions[indicator.name].args
	wipe(options)
	self:MakeIndicatorTitleOptions(options, indicator)
	if statusOptions then
		options["statuses"] = {type = "group", order = 10, name = L["statuses"], args = statusOptions}
	end
	if colorOptions then
		options["colors"] = {type = "group", order = 20, name = L["Colors"], args = colorOptions}
	end
	if layoutOptions then
		options["layout"] = {type = "group", order = 30, name = L["Layout"], args = layoutOptions}
	end
	if loadOptions then
		options["load"] = {type = "group", order = 40, name = L["Load"], args = loadOptions}
	end
end

-- Don't remove options param (openmanager hooks this function and needs this parameter)
function Grid2Options:MakeIndicatorChildOptions(indicator, options)
	local funcMakeOptions = self.typeMakeOptions[indicator.dbx.type]
	if funcMakeOptions then
		funcMakeOptions(self, indicator)
	end
end

-- Insert indicator group option in AceConfigTable
function Grid2Options:MakeIndicatorOptions(indicator)
	local type, options = indicator.dbx.type, {}
	self.indicatorOptions[indicator.name] = {
		type = "group",
		childGroups = "tab",
		icon = self.indicatorIconPath .. (self.indicatorTypesOrder[type] and type or "default"),
		order = self.indicatorTypesOrder[type] or nil,
		name = L[indicator.name],
		desc = L["Options for %s."]:format(indicator.name),
		args = options
	}
	self:MakeIndicatorChildOptions(indicator, options)
end

-- Remove indicator options from AceConfigTable
function Grid2Options:DeleteIndicatorOptions(indicator)
	self.indicatorOptions[indicator.name] = nil
	if indicator.OnDelete then
		indicator:OnDelete()
	end
end

-- Refresh indicator options
function Grid2Options:RefreshIndicatorOptions(indicator)
	local options = self.indicatorOptions[indicator.name]
	if not options and indicator.parentName then
		options = self.indicatorOptions[indicator.parentName]
		indicator = Grid2.indicators[indicator.parentName]
	end
	if indicator and options and not options.args.openManager then
		self:MakeIndicatorOptions(indicator)
	end
end

-- Create all indicators options (dont remove options param, is used by openmanager)
function Grid2Options:MakeIndicatorsOptions(options)
	-- remove old options
	options = options or self.indicatorOptions
	wipe(options)
	-- make new indicator options
	if self.MakeNewIndicatorOptions then
		self:MakeNewIndicatorOptions()
	end
	-- make indicators options
	local indicators = Grid2.db.profile.indicators
	for baseKey, dbx in pairs(indicators) do
		if self.typeMakeOptions[dbx.type] then -- filter bar-color&text-color indicators
			local indicator = Grid2.indicators[baseKey]
			if indicator then
				self:MakeIndicatorOptions(indicator)
			end
		end
	end
end