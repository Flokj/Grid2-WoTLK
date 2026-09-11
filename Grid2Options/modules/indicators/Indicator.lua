-- Library of common/shared methods
local Grid2 = Grid2
local Grid2Options = Grid2Options

local L = Grid2Options.L

-- Default values for new or morphed indicators
Grid2Options.indicatorDefaultValues = {
	icon = {size = 16, fontSize = 8},
	square = {size = 5},
	shape = {size = 5},
	text = {duration = true, stack = false, textlength = 12, fontSize = 8, font = "Friz Quadrata TT"}
}

-- Grid2Options:MakeIndicatorCurrentStatusOptions()
-- Grid2Options:MakeIndicatorStatusOptions()
-- Grid2Options:MakeStatusIndicatorOptions()
do
	local function GetIndexOfValue(map, status)
		for i, s in ipairs(map) do
			if s == status then
				return i
			end
		end
	end

	local function GetIndicatorNewPriority(indicator)
		local priority = 50
		local map = Grid2:DbGetValue("statusMap", indicator.name)
		if map then
			for _, p in pairs(map) do
				p = tonumber(p)
				if p and p >= priority then
					priority = p + 1
				end
			end
		end
		return priority
	end

	local function RegisterIndicatorStatus(indicator, status, value)
		if value then
			local priority = GetIndicatorNewPriority(indicator)
			Grid2:DbSetMap(indicator.name, status.name, priority)
			indicator:RegisterStatus(status, priority)
			status:Refresh()
		else
			Grid2:DbSetMap(indicator.name, status.name, nil)
			indicator:UnregisterStatus(status)
		end
		Grid2Options:RefreshIndicator(indicator, "Layout")
	end

	local function RefreshIndicatorCurrentStatusOptions(arg)
		local options = arg.options
		local curOptions = {}
		Grid2Options:MakeIndicatorCurrentStatusOptions(arg.indicator, curOptions)
		options.statusesCurrent = curOptions.statusesCurrent
		Grid2Options:NotifyChange()
	end

	local function SetIndicatorStatus(info, statusKey, value)
		-- custom widgets call set() directly with the container user table,
		-- which has no .arg (ACD only provides it on the full info table).
		local arg = info.arg or (info.option and info.option.arg)
		if not arg then return end
		for key, status in Grid2:IterateStatuses() do
			if key == statusKey then
				RegisterIndicatorStatus(arg.indicator, status, value)
				RefreshIndicatorCurrentStatusOptions(arg)
				return
			end
		end
	end

	local function SetIndicatorStatusCurrent(info, value)
		SetIndicatorStatus(info, info[#info], value)
	end

	local function SetStatusPriority(info, map, indicator, status, priority, index)
		Grid2:DbSetMap(indicator.name, status.name, priority)
		indicator:SetStatusPriority(status, priority)
		map[index], map[status] = status, priority
		local key, opt = status.name, info.arg.options
		opt[key].order = 500 - priority
		opt[key .. "U"].order = 500.1 - priority
		opt[key .. "D"].order = 500.2 - priority
		opt[key .. "S"].order = 500.3 - priority
	end

	local function StatusSwapPriorities(info, map, indicator, index1, index2)
		local status1 = map[index1]
		local status2 = map[index2]
		local priority1 = map[status1]
		local priority2 = map[status2]
		SetStatusPriority(info, map, indicator, status1, priority2, index2)
		SetStatusPriority(info, map, indicator, status2, priority1, index1)
	end

	local function StatusShiftUp(info, map, indicator, lowerStatus)
		local index = GetIndexOfValue(map, lowerStatus)
		if index then
			local newIndex = index > 1 and index - 1 or #map
			StatusSwapPriorities(info, map, indicator, index, newIndex)
			Grid2Options:RefreshIndicator(indicator, "Layout")
		end
	end

	local function StatusShiftDown(info, map, indicator, higherStatus)
		local index = GetIndexOfValue(map, higherStatus)
		if index then
			local newIndex = index < #map and index + 1 or 1
			StatusSwapPriorities(info, map, indicator, index, newIndex)
			Grid2Options:RefreshIndicator(indicator, "Layout")
		end
	end

	local function LoadStatusMap(indicator)
		local map = {}
		local dbx = Grid2:DbGetValue("statusMap", indicator.name)
		if dbx then
			for statusKey, priority in pairs(dbx) do
				local status = Grid2:GetStatusByName(statusKey)
				if status then
					map[#map + 1] = status
					map[status] = priority
				end
			end
		end
		table.sort(
			map,
			function(a, b)
				return map[a] > map[b]
			end
		)
		return map
	end

	-- Grid2Options:MakeIndicatorCurrentStatusOptions(indicator, options)
	-- bcc parity: checkbox list with unassign/up/down/go-to-status, driven by
	-- the Grid2IndicatorCurrentStatuses widget ('st' command jumps to the status).
	local function StatusShift(indicator, status, dir)
		local map = LoadStatusMap(indicator)
		local index1 = GetIndexOfValue(map, status)
		if index1 then
			local index2 = index1 + dir
			if index2 < 1 then
				index2 = #map
			elseif index2 > #map then
				index2 = 1
			end
			local status1 = map[index1]
			local status2 = map[index2]
			local priority1 = map[status1]
			local priority2 = map[status2]
			Grid2:DbSetMap(indicator.name, status1.name, priority2)
			indicator:SetStatusPriority(status1, priority2)
			Grid2:DbSetMap(indicator.name, status2.name, priority1)
			indicator:SetStatusPriority(status2, priority1)
			Grid2Options:RefreshIndicator(indicator, "Layout")
		end
	end

	function Grid2Options:MakeIndicatorCurrentStatusOptions(indicator, options)
		options.statusesCurrent = {
			type = "multiselect", dialogControl = "Grid2IndicatorCurrentStatuses",
			order = 1,
			width = "full",
			name = L["Current Statuses"],
			desc = L["Current statuses in order of priority"],
			values = function(info)
				local values = {}
				local dbx = Grid2:DbGetValue("statusMap", indicator.name)
				if dbx then
					for statusKey, priority in pairs(dbx) do
						local status = Grid2:GetStatusByName(statusKey)
						if status then
							values[string.format("%04d:%s", 1000 - priority, statusKey)] = Grid2Options.LocalizeStatus(status)
						end
					end
				end
				return values
			end,
			get = true,
			set = function(info, cmd, key)
				if not key then return end
				local status = Grid2:GetStatusByName(select(2, strsplit(':', key, 2)))
				if not status then return end
				if cmd == 'rm' then
					RegisterIndicatorStatus(indicator, status, false)
				elseif cmd == 'up' then
					StatusShift(indicator, status, -1)
				elseif cmd == 'dn' then
					StatusShift(indicator, status, 1)
				else
					-- no DB change here, so no refresh (a refresh would yank the
					-- dialog back to this page). Single deep select: SelectGroup
					-- itself marks every level expanded, one refresh feeds all.
					-- LoadOnDemand builds status pages on first visit: pre-build
					-- the target page (and the statuses level if needed), or the
					-- first jump feeds the openManager placeholder = empty panel.
					local category, statusName = Grid2Options:GetStatusCategory(status), status.name
					do
						local root = Grid2Options.options and Grid2Options.options.args
						local node = root and root.statuses
						if node and not (node.args and node.args[category]) then
							local buildAll = Grid2Options.MakeStatusesOptions_ or Grid2Options.MakeStatusesOptions
							if buildAll then buildAll(Grid2Options) end
						end
						local buildChild = Grid2Options.MakeStatusChildOptions_ or Grid2Options.MakeStatusChildOptions
						if buildChild then buildChild(Grid2Options, status) end
					end
					Grid2Options:SelectGroup('statuses', category, statusName)
				end
			end,
		}
	end

	-- Grid2Options:MakeIndicatorStatusOptions()
	-- bcc layout: no wrapper groups, the statuses tab shows the current-statuses
	-- widget, an "Available Statuses" title, then one subgroup per category
	-- (AceConfig renders subgroups as the left tree, like bcc).
	-- Filter = fork's GetAvailableStatusValues plus the category match.
	local function GetCategoryAvailableValues(indicator, catKey)
		local values = {}
		for statusKey, status in Grid2:IterateStatuses() do
			if Grid2Options:GetStatusCategory(status) == catKey
				and Grid2Options:IsCompatiblePair(indicator, status)
				and status.name ~= "test" and not status.suspended then
				values[statusKey] = Grid2Options.LocalizeStatus(status)
			end
		end
		if indicator.statuses then
			for _, status in ipairs(indicator.statuses) do
				values[status.name] = nil
			end
		end
		return values
	end
	function Grid2Options:MakeIndicatorStatusOptions(indicator, options)
		self:MakeIndicatorCurrentStatusOptions(indicator, options)
		options.statusesTitle = {
			type = "description", order = 2, fontSize = "medium",
			name = string.format("|cffffd200    %s|r", L["Available Statuses"]),
		}
		for catKey, category in pairs(self.categories) do
			options[catKey] = {
				type = "group", order = category.order,
				name = " " .. category.name,
				args = { statuses = {
					type = "multiselect", dialogControl = "Grid2SimpleMultiselect",
					order = 1, width = "full", name = "",
					values = function(info)
						return GetCategoryAvailableValues(indicator, info[#info-1])
					end,
					get = false,
					set = SetIndicatorStatus,
					arg = {indicator = indicator, options = options},
				} },
				hidden = function()
					return not next(GetCategoryAvailableValues(indicator, catKey))
				end,
			}
		end
	end

	-- Grid2Options:MakeStatusIndicatorOptions()
	function Grid2Options:MakeStatusIndicatorsOptions(status, options)
		options.indicators = {
			type = "multiselect",
			order = 10,
			name = L["Assigned indicators"],
			values = function()
				return self:GetAvailableIndicatorValues(status)
			end,
			get = function(info, key)
				local dbx = Grid2:DbGetValue("statusMap", key)
				return dbx and dbx[status.name] ~= nil
			end,
			set = function(info, key, value)
				local indicator = Grid2.indicators[key]
				if indicator.dbx.type ~= "multibar" then
					RegisterIndicatorStatus(indicator, status, value)
					self:RefreshIndicatorOptions(indicator)
				end
			end,
			confirm = function(info, key)
				return Grid2.indicators[key].dbx.type == "multibar" and L["This indicator cannot be changed from here: go to indicators section to assign/unassign statuses to this indicator."]
			end,
		}
		return options
	end
end

-- Grid2Options:RenameIndicatorConfirm()
-- Ported from Grid2 2.9.31-bcc, adapted for 3.3.5 (no themes database, target frame lifecycle).
do
	local function RegisterIndicatorStatusesFromDatabase(indicator)
		if indicator then
			local map = Grid2:DbGetValue("statusMap", indicator.name)
			if map then
				for statusKey, priority in pairs(map) do
					local status = Grid2.statuses[statusKey]
					if status and tonumber(priority) then
						indicator:RegisterStatus(status, priority)
					end
				end
			end
		end
	end

	local function RenameIndicatorReal(old_name, new_name)
		new_name = Grid2Options:GetValidatedName(new_name)
		if not new_name or Grid2.indicators[new_name] then return end
		local old_indicator = Grid2.indicators[old_name]
		if not old_indicator then return end
		local old_sideKick = old_indicator.sideKick
		local dbx = old_indicator.dbx
		-- destroy old indicator
		Grid2Frame:WithAllFrames(old_indicator, "Disable")
		Grid2:UnregisterIndicator(old_indicator)
		-- rename database stuff
		Grid2:DbSetValue("indicators", new_name, dbx)
		Grid2:DbSetValue("indicators", old_name, nil)
		local map = Grid2:DbGetValue("statusMap", old_name)
		if map then
			Grid2:DbSetValue("statusMap", new_name, map)
			Grid2:DbSetValue("statusMap", old_name, nil)
		end
		-- create new indicator
		local setupFunc = Grid2.setupFunc[dbx.type]
		local new_indicator = setupFunc and setupFunc(new_name, dbx)
		if not new_indicator then return end
		-- rename sidekick database stuff
		if old_sideKick and new_indicator.sideKick then
			local sideMap = Grid2:DbGetValue("statusMap", old_sideKick.name)
			if sideMap then
				Grid2:DbSetValue("statusMap", new_indicator.sideKick.name, sideMap)
				Grid2:DbSetValue("statusMap", old_sideKick.name, nil)
			end
		end
		-- register statuses from database
		RegisterIndicatorStatusesFromDatabase(new_indicator)
		RegisterIndicatorStatusesFromDatabase(new_indicator.sideKick)
		-- recreate indicators in frame units
		Grid2Frame:WithAllFrames(function(f)
			new_indicator:Create(f)
			new_indicator:Layout(f)
		end)
		-- update unit frames
		Grid2Frame:UpdateIndicators()
		-- refresh options
		Grid2Options:DeleteIndicatorOptions(old_indicator)
		Grid2Options:MakeIndicatorOptions(new_indicator)
		Grid2Options:SelectGroup("indicators")
	end

	function Grid2Options:IndicatorIsInUse(indicator)
		indicator = type(indicator) ~= "string" and indicator or Grid2.indicators[indicator]
		return indicator == nil or indicator.parentName or indicator.childName
	end

	function Grid2Options:RenameIndicatorConfirm(indicator)
		if Grid2Options:IndicatorIsInUse(indicator.name) then
			Grid2Options:MessageDialog(L["This indicator cannot be renamed because is anchored to another indicator."])
		else
			Grid2Options:ShowEditDialog("Rename Indicator:", L[indicator.name], function(text)
				local len = strlen(text)
				if len > 2 or len == 0 then
					RenameIndicatorReal(indicator.name, text)
				end
			end)
		end
	end
end

-- Grid2Options:MakeIndicatorSizeOptions()
function Grid2Options:MakeIndicatorSizeOptions(indicator, options, optionParams)
	options.size = {
		type = "range",
		order = 10,
		name = L["Size"],
		desc = L["Adjust the size of the indicator."],
		min = 5,
		max = 50,
		step = 1,
		get = function()
			return indicator.dbx.size
		end,
		set = function(_, v)
			indicator.dbx.size = v
			self:RefreshIndicator(indicator, "Layout")
		end
	}
end

-- Grid2Options:MakeIndicatorBorderSizeOptions()
function Grid2Options:MakeIndicatorBorderSizeOptions(indicator, options, optionParams)
	options.borderSize = {
		type = "range",
		order = 20,
		name = L["Border Size"],
		desc = L["Adjust the border size of the indicator."],
		min = 0,
		max = 20,
		step = 1,
		get = function()
			return indicator.dbx.borderSize or 0
		end,
		set = function(_, v)
			if v == 0 then
				v = nil
			end
			indicator.dbx.borderSize = v
			self:RefreshIndicator(indicator, "Layout", "Update")
		end
	}
end

-- Grid2Options:MakeIndicatorTextureOptions()
function Grid2Options:MakeIndicatorTextureOptions(indicator, options, optionParams)
	options.texture = {
		type = "select",
		dialogControl = "LSM30_Statusbar",
		order = 11,
		name = L["Frame Texture"],
		desc = L["Adjust the texture of the indicator."],
		get = function(info)
			return indicator.dbx.texture or "Grid2 Flat"
		end,
		set = function(info, v)
			indicator.dbx.texture = v
			self:RefreshIndicator(indicator, "Layout")
		end,
		values = AceGUIWidgetLSMlists.statusbar
	}
end

-- Grid2Options:MakeIndicatorBorderOptions()
function Grid2Options:MakeIndicatorBorderOptions(indicator, options, optionParams)
	optionParams = optionParams or {}
	optionParams.color1 = L["Border Color"]
	optionParams.colorDesc1 = L["Adjust border color and alpha."]
	self:MakeHeaderOptions(options, "Border")
	self:MakeIndicatorColorOptions(indicator, options, optionParams)
	self:MakeIndicatorBorderSizeOptions(indicator, options, optionParams)
end

-- Grid2Options:MakeIndicatorColorOptions()
do
	local function GetIndicatorColor(info)
		local indicator = info.arg.indicator
		local colorKey = "color" .. info.arg.colorIndex
		local c = indicator.dbx[colorKey]
		if c then
			return c.r, c.g, c.b, c.a
		end
		return 0, 0, 0, 0
	end
	local function SetIndicatorColor(info, r, g, b, a)
		local colorKey = "color" .. info.arg.colorIndex
		local indicator = info.arg.indicator
		local dbx = indicator.dbx
		local c = dbx[colorKey]
		if not c then
			c = {}
			dbx[colorKey] = c
		end
		c.r, c.g, c.b, c.a = r, g, b, a
		if indicator.UpdateDB then
			indicator:UpdateDB()
		end
		Grid2Frame:UpdateIndicators()
	end
	function Grid2Options:MakeIndicatorColorOptions(indicator, options, optionParams)
		local colorCount = indicator.dbx.colorCount or 1
		local name = L["Color"]
		local desc = L["Color for %s."]:format(indicator.name)
		for i = 1, colorCount, 1 do
			local colorKey = "color" .. i
			if (optionParams and optionParams[colorKey]) then
				name = optionParams[colorKey]
			elseif (colorCount > 1) then
				name = L["Color %d"]:format(i)
			end
			local colorDescKey = "colorDesc" .. i
			if (optionParams and optionParams[colorDescKey]) then
				desc = optionParams[colorDescKey]
			elseif (colorCount > 1) then
				desc = name
			end
			options[colorKey] = {
				type = "color",
				order = (20 + i),
				name = name,
				desc = desc,
				get = GetIndicatorColor,
				set = SetIndicatorColor,
				hasAlpha = true,
				arg = {indicator = indicator, colorIndex = i}
			}
		end
	end
end

-- Grid2Options:MakeIndicatorTypeOptions()
do
	local typeMorphValue = {}
	local typeMorphValues = {icon = L["icon"], square = L["square"], shape = L["shape"], text = L["text"]}

	local function RegisterIndicatorStatusesFromDatabase(indicator)
		if indicator then
			local map = Grid2:DbGetValue("statusMap", indicator.name)
			if map then
				for statusKey, priority in pairs(map) do
					local status = Grid2.statuses[statusKey]
					if (status and tonumber(priority)) then
						indicator:RegisterStatus(status, priority)
					end
				end
			end
		end
	end

	local function GetIndicatorTypeValues(info)
		local typeKey = info.arg.dbx.type
		if not typeMorphValues[typeKey] then
			wipe(typeMorphValue)
			typeMorphValue[typeKey] = L[typeKey]
			return typeMorphValue
		end
		return typeMorphValues
	end

	local function GetIndicatorTypeDisabled(info)
		return not typeMorphValues[info.arg.dbx.type]
	end

	local function GetIndicatorType(info)
		return info.arg.dbx.type
	end

	local function SetIndicatorType(info, value)
		local indicator = info.arg
		local baseKey = indicator.name
		local dbx = indicator.dbx
		local colorKey = baseKey .. "-color"
		local oldType = dbx.type

		if dbx.type == value then
			return
		end

		-- Set new fields width defaults values
		dbx.type = value
		for k, v in pairs(Grid2Options.indicatorDefaultValues[value]) do
			if (not dbx[k]) then
				indicator.dbx[k] = v
				dbx[k] = v
			end
		end
		-- Remove old indicator
		Grid2:UnregisterIndicator(indicator)
		-- Create new indicator
		local setupFunc = Grid2.setupFunc[dbx.type]
		local newIndicator = setupFunc(baseKey, dbx)
		-- Remove incompatible statuses from database
		local map = Grid2:DbGetValue("statusMap", baseKey)
		if map then
			for statusKey, priority in pairs(map) do
				local status = Grid2.statuses[statusKey]
				if (not status) or (not Grid2Options:IsCompatiblePair(newIndicator, status)) then
					map[statusKey] = nil
				end
			end
		end
		-- Register indicator statuses from database
		RegisterIndicatorStatusesFromDatabase(newIndicator)
		RegisterIndicatorStatusesFromDatabase(newIndicator.sideKick)
		-- Recreate indicators in frame units
		Grid2Frame:WithAllFrames(function(f)
			newIndicator:Create(f)
			newIndicator:Layout(f)
		end)
		-- Delete or Create associated text-color indicator in database
		if oldType == "text" then
			Grid2:DbSetIndicator(colorKey, nil)
		elseif value == "text" then
			Grid2:DbSetIndicator(colorKey, {type = "text-color"})
		end
		-- Update unit frames
		Grid2Frame:UpdateIndicators()
		-- Create new indicator options
		Grid2Options:MakeIndicatorOptions(newIndicator)
	end

	function Grid2Options:MakeIndicatorTypeOptions(indicator, options, optionParams)
		options.indicatorType = {
			type = "select",
			order = 1.91,
			name = L["Type of indicator"],
			desc = L["Change the indicator type"],
			values = GetIndicatorTypeValues,
			get = GetIndicatorType,
			set = SetIndicatorType,
			confirm = true,
			confirmText = L["Are you sure do you want to convert the indicator to the new selected type?"],
			arg = indicator
		}
	end
end

-- Grid2Options:MakeIndicatorLevelOptions()
do
	local levelValues = {1, 2, 3, 4, 5, 6, 7, 8, 9}
	function Grid2Options:MakeIndicatorLevelOptions(indicator, options)
		options.frameLevel = {
			type = "select",
			order = 6,
			name = L["Frame Level"],
			desc = L["Bars with higher numbers always show up on top of lower numbers."],
			get = function()
				return indicator.dbx.level or 1
			end,
			set = function(_, v)
				indicator.dbx.level = v
				self:RefreshIndicator(indicator, "Layout")
			end,
			values = levelValues
		}
	end
end

-- Grid2Options:MakeIndicatorTypeLevelOptions()
function Grid2Options:MakeIndicatorTypeLevelOptions(indicator, options)
	self:MakeHeaderOptions(options, "General")
	self:MakeIndicatorTypeOptions(indicator, options)
	self:MakeIndicatorLevelOptions(indicator, options)
end

-- Grid2Options:MakeIndicatorLocationOptions()
function Grid2Options:MakeIndicatorLocationOptions(indicator, options)
	local location = indicator.dbx.location
	self:MakeHeaderOptions(options, "Location")
	options.relPoint = {
		type = "select",
		order = 4,
		name = L["Location"],
		desc = L["Align my align point relative to"],
		values = self.pointValueList,
		get = function()
			return self.pointMap[location.relPoint]
		end,
		set = function(_, v)
			location.relPoint = self.pointMap[v]
			location.point = location.relPoint
			self:RefreshIndicator(indicator, "Layout")
		end
	}
	options.point = {
		type = "select",
		order = 5,
		name = L["Align Point"],
		desc = L["Align this point on the indicator"],
		values = self.pointValueList,
		get = function()
			return self.pointMap[location.point]
		end,
		set = function(_, v)
			location.point = self.pointMap[v]
			self:RefreshIndicator(indicator, "Layout")
		end
	}
	options.x = {
		type = "range",
		order = 7,
		name = L["X Offset"],
		desc = L["X - Horizontal Offset"],
		min = -50,
		max = 50,
		step = 1,
		bigStep = 1,
		get = function()
			return location.x
		end,
		set = function(_, v)
			location.x = v
			self:RefreshIndicator(indicator, "Layout")
		end
	}
	options.y = {
		type = "range",
		order = 8,
		name = L["Y Offset"],
		desc = L["Y - Vertical Offset"],
		min = -50,
		max = 50,
		step = 1,
		bigStep = 1,
		get = function()
			return location.y
		end,
		set = function(_, v)
			location.y = v
			self:RefreshIndicator(indicator, "Layout")
		end
	}
	self:MakeIndicatorLevelOptions(indicator, options)
end

-- Grid2Options:MakeIndicatorAnimationOptions()
function Grid2Options:MakeIndicatorAnimationOptions(indicator, options)
	self:MakeHeaderOptions(options, "Animation")
	options.animEnabled = {
		type = "toggle",
		order = 155,
		name = L["Enable animation"],
		desc = L["Turn on/off zoom animation of icons."],
		tristate = false,
		get = function()
			return indicator.dbx.animEnabled
		end,
		set = function(_, v)
			indicator.dbx.animEnabled = v or nil
			if not v then
				indicator.dbx.animScale = nil
				indicator.dbx.animDuration = nil
				indicator.dbx.animOrigin = nil
			end
			indicator:UpdateDB()
		end
	}
	options.animOnEnabled = {
		type = "toggle",
		order = 157,
		name = L["Only on Activation"],
		desc = L["Start the animation only when the indicator is activated, not on updates."],
		tristate = false,
		get = function()
			return indicator.dbx.animOnEnabled
		end,
		set = function(_, v)
			indicator.dbx.animOnEnabled = v or nil
			indicator:UpdateDB()
		end,
		hidden = function()
			return not indicator.dbx.animEnabled
		end
	}
	options.animDuration = {
		type = "range",
		order = 160,
		name = L["Duration"],
		desc = L["Sets the duration in seconds."],
		min = 0.1,
		max = 2,
		step = 0.1,
		get = function()
			return indicator.dbx.animDuration or 0.7
		end,
		set = function(_, v)
			indicator.dbx.animDuration = v
			Grid2Frame:WithAllFrames(function(f)
				local anim = indicator:GetBlinkFrame(f).scaleAnim
				if anim then
					anim.grow:SetDuration(v / 2)
					anim.shrink:SetDuration(v / 2)
				end
			end)
		end,
		hidden = function()
			return not indicator.dbx.animEnabled
		end
	}
	options.animScale = {
		type = "range",
		order = 164,
		name = L["Scale"],
		desc = L["Sets the zoom factor."],
		min = 1.1,
		max = 3,
		step = 0.1,
		get = function()
			return indicator.dbx.animScale or 1.5
		end,
		set = function(_, v)
			indicator.dbx.animScale = v
			Grid2Frame:WithAllFrames(function(f)
				local anim = indicator:GetBlinkFrame(f).scaleAnim
				if anim then
					anim.grow:SetScale(v, v)
					anim.shrink:SetScale(1 / v, 1 / v)
				end
			end)
		end,
		hidden = function()
			return not indicator.dbx.animEnabled
		end
	}
	options.animOrigin = {
		type = "select",
		order = 165,
		name = L["Origin"],
		desc = L["Zoom origin point"],
		values = self.pointValueList,
		get = function()
			return self.pointMap[indicator.dbx.animOrigin or "CENTER"]
		end,
		set = function(_, v)
			local point = self.pointMap[v]
			indicator.dbx.animOrigin = point ~= "CENTER" and point or nil
			Grid2Frame:WithAllFrames(function(f)
				local anim = indicator:GetBlinkFrame(f).scaleAnim
				if anim then
					anim.grow:SetOrigin(point, 0, 0)
					anim.shrink:SetOrigin(point, 0, 0)
				end
			end)
		end,
		hidden = function()
			return not indicator.dbx.animEnabled
		end
	}
end

-- Grid2Options:MakeIndicatorHighlightEffectOptions()
-- Ported from Grid2 2.9.31-bcc, adapted for 3.3.5: LibCustomGlow-1.0 does not
-- exist on this client, SpecializedLibGlow-1.0 provides the same API.
do
	local LCG = LibStub("SpecializedLibGlow-1.0", true)
	local DEFAULT_COLOR = { 1, 1, 0, 1 }
	local DEFAULT_FREQS = { 0.25, 0.12, 0.12 }
	local EFFECT_VALUES = { [-2] = L["Blink"], [-1] = L["Zoom In"], [0] = L["None"], [1] = L["Glow Border: Pixel"], [2] = L["Glow Border: Shine"], [3] = L["Glow Border: Blizzard"] }
	local ACTIVATION1_VALUES = { L["Always active"], L["Status Controlled"] }
	local ACTIVATION2_VALUES = { L["On Status Activation"], L["On Status Updates"] }

	local function ResetSettings(dbx)
		dbx.highlightAlways = nil
		dbx.animOnEnabled = nil
		dbx.animScale = nil
		dbx.animDuration = nil
		dbx.animOrigin = nil
		dbx.glow_color = nil
		dbx.glow_frequency = nil
		dbx.glow_linesCount = nil
		dbx.glow_thickness = nil
		dbx.glow_particlesCount = nil
		dbx.glow_particlesScale = nil
	end

	local function WithAllScaleAnimations(indicator, func)
		for _, f in next, Grid2Frame.registeredFrames do
			local frame = indicator.GetBlinkFrame and indicator:GetBlinkFrame(f)
			local anim = frame and frame.scaleAnim
			if anim then func(anim) end
		end
	end

	local function RefreshBlinkFrequencies(indicator, freq)
		for _, f in next, Grid2Frame.registeredFrames do
			local frame = indicator.GetBlinkFrame and indicator:GetBlinkFrame(f)
			local anim = frame and frame.blinkAnim
			if anim then anim.settings:SetDuration(1 / freq) end
		end
	end

	local function RefreshIndicator(indicator)
		for _, f in next, Grid2Frame.registeredFrames do
			local frame = indicator.GetBlinkFrame and indicator:GetBlinkFrame(f)
			if frame then
				if frame.blinkAnim then frame.blinkAnim:Stop() end -- cancel blink
				if LCG and LCG.stopList then
					for _, func in pairs(LCG.stopList) do -- cancel glow
						func(frame); frame.__glowEnabled = nil
					end
				end
			end
		end
		if indicator.UpdateHighlight then indicator:UpdateHighlight() end
		Grid2Frame:UpdateIndicators()
	end

	function Grid2Options:MakeIndicatorHighlightEffectOptions(indicator, options)
		if not LCG then return end
		self:MakeHeaderOptions(options, "Highlight")
		options.highlightType = {
			type = "select",
			order = 320,
			name = L["Highlight Effect"],
			desc = L["Select the Highlight effect."],
			get = function()
				return indicator.dbx.highlightType or -2 -- default blink
			end,
			set = function(_, v)
				indicator.dbx.highlightType = v ~= -2 and v or nil
				ResetSettings(indicator.dbx)
				RefreshIndicator(indicator)
			end,
			values = EFFECT_VALUES,
		}
		options.highlightActivation = {
			type = "select",
			order = 325,
			name = L["Activation"],
			desc = L["Select when to activate the highlight effect."],
			get = function()
				return indicator.dbx.highlightAlways and 1 or 2
			end,
			set = function(_, v)
				indicator.dbx.highlightAlways = v == 1 or nil
				RefreshIndicator(indicator)
			end,
			values = ACTIVATION1_VALUES,
			hidden = function() return indicator.dbx.highlightType == -1 or indicator.dbx.highlightType == 0 end, -- zoomIn or none
		}
		-- common options
		options.glowFrequency = { -- all glow
			type = "range",
			order = 340,
			name = L["Animation Speed"],
			desc = L["Animation Speed"],
			min = -1.5,
			max = 1.5,
			step = 0.01,
			get = function() return indicator.dbx.glow_frequency or DEFAULT_FREQS[indicator.dbx.highlightType] end,
			set = function(_, v)
				indicator.dbx.glow_frequency = (v ~= 0 and v ~= DEFAULT_FREQS[v]) and v or nil
				RefreshIndicator(indicator)
			end,
			hidden = function() return (indicator.dbx.highlightType or 0) <= 0 end,
		}
		-- blink (-2|nil)
		options.blinkFrequency = {
			type = "range",
			order = 340,
			width = "double",
			name = L["Blink Frequency"],
			desc = L["Adjust the frequency of the Blink effect."],
			min = 1,
			max = 10,
			step = 0.5,
			get = function()
				return indicator.dbx.blink_frequency or 2
			end,
			set = function(_, v)
				indicator.dbx.blink_frequency = v ~= 2 and v or nil
				RefreshBlinkFrequencies(indicator, v)
			end,
			hidden = function() return (indicator.dbx.highlightType or -2) ~= -2 end,
		}
		-- glow pixel (1)
		options.linesCount = {
			type = "range",
			order = 370,
			width = "normal",
			name = L["Number of Lines"],
			desc = L["Number of Lines"],
			min = 1,
			max = 20,
			step = 1,
			get = function() return indicator.dbx.glow_linesCount or 8 end,
			set = function(_, v)
				indicator.dbx.glow_linesCount = (v ~= 8) and v or nil
				RefreshIndicator(indicator)
			end,
			hidden = function() return indicator.dbx.highlightType ~= 1 end,
		}
		-- glow pixel (1)
		options.thickness = {
			type = "range",
			order = 380,
			width = "normal",
			name = L["Thickness"],
			desc = L["Thickness"],
			min = 1,
			max = 10,
			step = 1,
			get = function() return indicator.dbx.glow_thickness or 2 end,
			set = function(_, v)
				indicator.dbx.glow_thickness = (v ~= 2) and v or nil
				RefreshIndicator(indicator)
			end,
			hidden = function() return indicator.dbx.highlightType ~= 1 end
		}
		-- glow shine (2)
		options.particlesCount = {
			type = "range",
			order = 370,
			width = "normal",
			name = L["Number of particles"],
			desc = L["Number of particles"],
			min = 1,
			max = 10,
			step = 1,
			get = function() return indicator.dbx.glow_particlesCount or 4 end,
			set = function(_, v)
				indicator.dbx.glow_particlesCount = (v ~= 4) and v or nil
				RefreshIndicator(indicator)
			end,
			hidden = function() return indicator.dbx.highlightType ~= 2 end
		}
		options.particlesScale = {
			type = "range",
			order = 380,
			width = "normal",
			name = L["Scale of particles"],
			desc = L["Scale of particles"],
			min = 0.1,
			max = 5,
			step = 0.1,
			get = function() return indicator.dbx.glow_particlesScale or 1 end,
			set = function(_, v)
				indicator.dbx.glow_particlesScale = (v ~= 1) and v or nil
				RefreshIndicator(indicator)
			end,
			hidden = function() return indicator.dbx.highlightType ~= 2 end
		}
		-- glow common
		options.glowColor = {
			type = "color",
			hasAlpha = true,
			order = 390,
			name = L["Glow Color"],
			desc = L["Sets the glow color to display when the indicator is highlighted."],
			get = function() return unpack(indicator.dbx.glow_color or DEFAULT_COLOR) end,
			set = function(info, r, g, b, a)
				indicator.dbx.glow_color = { r, g, b, a }
				RefreshIndicator(indicator)
			end,
			hidden = function() return (indicator.dbx.highlightType or 0) <= 0 end
		}
		-- zoomIn
		options.animActivation = {
			type = "select",
			order = 325,
			name = L["Activation"],
			desc = L["Select when to start the Zoom In effect"],
			get = function()
				return indicator.dbx.animOnEnabled and 1 or 2
			end,
			set = function(_, v)
				indicator.dbx.animOnEnabled = v == 1 or nil
				indicator:UpdateDB()
			end,
			values = ACTIVATION2_VALUES,
			hidden = function() return indicator.dbx.highlightType ~= -1 end,
		}
		options.animOrigin = {
			type = "select",
			order = 340,
			name = L["Origin"],
			desc = L["Zoom origin point"],
			values = self.pointValueList,
			get = function() return self.pointMap[indicator.dbx.animOrigin or "CENTER"] end,
			set = function(_, v)
				local point = self.pointMap[v]
				indicator.dbx.animOrigin = point ~= "CENTER" and point or nil
				WithAllScaleAnimations(indicator, function(a) a.grow:SetOrigin(point, 0, 0); a.shrink:SetOrigin(point, 0, 0); end)
			end,
			hidden = function() return indicator.dbx.highlightType ~= -1 end,
		}
		options.animScale = {
			type = "range",
			order = 350,
			name = L["Scale"],
			desc = L["Sets the zoom factor."],
			min = 1.1,
			max = 3,
			step = 0.1,
			get = function() return indicator.dbx.animScale or 1.5 end,
			set = function(_, v)
				indicator.dbx.animScale = v
				WithAllScaleAnimations(indicator, function(a) a.grow:SetScale(v, v); a.shrink:SetScale(1 / v, 1 / v); end)
			end,
			hidden = function() return indicator.dbx.highlightType ~= -1 end,
		}
		options.animDuration = {
			type = "range",
			order = 360,
			width = "double",
			name = L["Duration"],
			desc = L["Sets the duration in seconds."],
			min = 0.1,
			max = 2,
			step = 0.1,
			get = function() return indicator.dbx.animDuration or 0.7 end,
			set = function(_, v)
				indicator.dbx.animDuration = v
				WithAllScaleAnimations(indicator, function(a) a.grow:SetDuration(v / 2); a.shrink:SetDuration(v / 2); end)
			end,
			hidden = function() return indicator.dbx.highlightType ~= -1 end,
		}
		return options
	end
end

-- Grid2Options:MakeIndicatorLoadOptions(indicator, options)
-- bcc parity, playerClass filter only: unitType needs headerName metadata that
-- the 3.3.5 layout core does not provide, and the theme filter needs the retail
-- theme-suspend core; both left out. The dbx.load schema stays compatible.
do
	local function RefreshIndicatorLoad(indicator)
		indicator:UpdateFilter()
		Grid2Frame:UpdateIndicators()
	end

	local function SetFilterOptions(indicator, options, order, key, values, defValue, name, desc)
		local dbx    = indicator.dbx
		local filter = dbx.load and dbx.load[key]
		local multi  = filter and next(filter, next(filter)) ~= nil
		options[key] = {
			type = "toggle",
			name = name,
			desc = desc or name,
			order = order,
			get = function() return filter end,
			set = function()
				if multi then
					multi, filter, dbx.load[key] = nil, nil, nil
					if not next(dbx.load) then dbx.load = nil end
				elseif filter then
					multi = true
				else
					dbx.load = dbx.load or {}
					filter = { [defValue] = true }
					dbx.load[key] = filter
				end
				RefreshIndicatorLoad(indicator)
			end,
		}
		options[key..'1'] = {
			type = "select",
			name = name,
			desc = desc or name,
			order = order + 1,
			get = function() return filter and next(filter) end,
			set = function(_, v)
				-- guard: a stale widget can fire after the toggle cleared the filter
				if filter then
					wipe(filter)[v] = true
					RefreshIndicatorLoad(indicator)
				end
			end,
			hidden = function() return multi end,
			values = values,
		}
		options[key..'2'] = {
			type = "multiselect",
			order = order + 2,
			name = name,
			get = function(_, value) return filter and filter[value] end,
			set = function(_, value)
				if filter then
					filter[value] = (not filter[value]) or nil
					RefreshIndicatorLoad(indicator)
				end
			end,
			hidden = function() return not multi end,
			values = values,
		}
		options[key.."3"] = {
			type = "description",
			name = "",
			order = order + 3,
		}
	end

	function Grid2Options:MakeIndicatorLoadOptions(indicator, options)
		SetFilterOptions( indicator, options, 10,
			'playerClass',
			self.PLAYER_CLASSES,
			Grid2.playerClass,
			L["Player Class"],
			L["Load the indicator only if your toon belong to the specified class."]
		)
		return options
	end
end