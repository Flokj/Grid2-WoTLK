--[[ Layout Section ]]--
local Grid2 = Grid2
local Grid2Options = Grid2Options
local L = Grid2Options.L

local order_layout = 20
local order_display = 30
local order_anchor = 40

Grid2Options:AddGeneralOptions("General", "Layout Settings", {
	horizontal = {
		type = "toggle",
		name = L["Horizontal groups"],
		desc = L["Switch between horzontal/vertical groups."],
		order = order_layout + 4,
		get = function()
			return Grid2Layout.db.profile.horizontal
		end,
		set = function()
			Grid2Layout.db.profile.horizontal = not Grid2Layout.db.profile.horizontal
			Grid2Layout:ReloadLayout()
			if Grid2Options.LayoutTestRefresh then
				Grid2Options:LayoutTestRefresh()
			end
		end
	},
	lock = {
		type = "toggle",
		name = L["Frame lock"],
		desc = L["Locks/unlocks the grid for movement."],
		order = order_layout + 6,
		get = function()
			return Grid2Layout.db.profile.FrameLock
		end,
		set = function()
			Grid2Layout:FrameLock()
		end
	},
	clickthrough = {
		type = "toggle",
		name = L["Click through the Grid Frame"],
		desc = L["Allows mouse click through the Grid Frame."],
		order = order_layout + 7,
		get = function()
			return Grid2Layout.db.profile.ClickThrough
		end,
		set = function()
			local v = not Grid2Layout.db.profile.ClickThrough
			Grid2Layout.db.profile.ClickThrough = v
			Grid2Layout.frame:EnableMouse(not v)
		end,
		disabled = function()
			return not Grid2Layout.db.profile.FrameLock
		end
	},
	displayheader = {
		type = "header",
		order = order_display,
		name = L["Display"]
	},
	display = {
		type = "select",
		name = L["Show Frame"],
		desc = L["Sets when the Grid is visible: Choose 'Always', 'Grouped', or 'Raid'."],
		order = order_display + 1,
		get = function()
			return Grid2Layout.db.profile.FrameDisplay
		end,
		set = function(_, v)
			Grid2Layout.db.profile.FrameDisplay = v
			Grid2Layout:CheckVisibility()
		end,
		values = {["Always"] = L["Always"], ["Grouped"] = L["Grouped"], ["Raid"] = L["Raid"]}
	},
	frameStrata = {
		type = "select",
		name = L["Frame Strata"],
		desc = L["Sets the strata in which the layout frame should be layered."],
		order = order_display + 2,
		get = function()
			return Grid2Layout.db.profile.FrameStrata or "MEDIUM"
		end,
		set = function(_, v)
			Grid2LayoutFrame:SetFrameStrata(v)
			Grid2Layout.db.profile.FrameStrata = (v ~= "MEDIUM") and v or nil
		end,
		values = {BACKGROUND = L["BACKGROUND"], LOW = L["LOW"], MEDIUM = L["MEDIUM"], HIGH = L["HIGH"]}
	},
	backgroundTexture = {
		type = "select",
		dialogControl = "LSM30_Background",
		order = order_display + 3,
		name = L["Background Texture"],
		desc = L["Adjust the background texture."],
		get = function(info)
			return Grid2Layout.db.profile.BackgroundTexture or "None"
		end,
		set = function(info, v)
			Grid2Layout.db.profile.BackgroundTexture = v
			Grid2Layout:UpdateTextures()
			Grid2Layout:UpdateColor()
		end,
		values = AceGUIWidgetLSMlists.background
	},
	borderTexture = {
		type = "select",
		dialogControl = "LSM30_Border",
		order = order_display + 3.1,
		name = L["Border Texture"],
		desc = L["Adjust the border texture."],
		get = function(info)
			return Grid2Layout.db.profile.BorderTexture or "Grid2 Flat"
		end,
		set = function(info, v)
			Grid2Layout.db.profile.BorderTexture = v
			Grid2Layout:UpdateTextures()
			Grid2Layout:UpdateColor()
		end,
		values = AceGUIWidgetLSMlists.border
	},
	background = {
		type = "color",
		name = L["Background Color"],
		desc = L["Adjust background color and alpha."],
		order = order_display + 3.2,
		get = function()
			local settings = Grid2Layout.db.profile
			return settings.BackgroundR, settings.BackgroundG, settings.BackgroundB, settings.BackgroundA
		end,
		set = function(_, r, g, b, a)
			local settings = Grid2Layout.db.profile
			settings.BackgroundR, settings.BackgroundG, settings.BackgroundB, settings.BackgroundA = r, g, b, a
			Grid2Layout:UpdateColor()
		end,
		hasAlpha = true
	},
	border = {
		type = "color",
		name = L["Border Color"],
		desc = L["Adjust border color and alpha."],
		order = order_display + 3.3,
		get = function()
			local settings = Grid2Layout.db.profile
			return settings.BorderR, settings.BorderG, settings.BorderB, settings.BorderA
		end,
		set = function(_, r, g, b, a)
			local settings = Grid2Layout.db.profile
			settings.BorderR, settings.BorderG, settings.BorderB, settings.BorderA = r, g, b, a
			Grid2Layout:UpdateColor()
		end,
		hasAlpha = true
	},
	backgroundTile = {
		type = "toggle",
		name = L["Tile"],
		desc = L["Tile the background texture."],
		order = order_display + 4,
		get = function()
			return Grid2Layout.db.profile.BackgroundTile
		end,
		set = function(info, v)
			Grid2Layout.db.profile.BackgroundTile = v
			Grid2Layout:UpdateTextures()
			Grid2Layout:UpdateColor()
		end
	},
	backgroundTileSize = {
		type = "range",
		name = L["Tile size"],
		desc = L["The size of the texture pattern."],
		order = order_display + 4.5,
		get = function()
			return Grid2Layout.db.profile.BackgroundTileSize
		end,
		set = function(info, v)
			Grid2Layout.db.profile.BackgroundTileSize = v
			Grid2Layout:UpdateTextures()
			Grid2Layout:UpdateColor()
		end,
		min = 0,
		max = floor(GetScreenWidth()),
		step = 1.0,
		bigStep = 1
	},
	spacing = {
		type = "range",
		name = L["Spacing"],
		desc = L["Adjust frame spacing."],
		order = order_display + 5,
		max = 25,
		min = 0,
		step = 1,
		get = function()
			return Grid2Layout.db.profile.Spacing
		end,
		set = function(_, v)
			Grid2Layout.db.profile.Spacing = v
			Grid2Layout:ReloadLayout()
		end
	},
	padding = {
		type = "range",
		name = L["Padding"],
		desc = L["Adjust frame padding."],
		order = order_display + 6,
		max = 20,
		min = 0,
		step = 1,
		get = function()
			return Grid2Layout.db.profile.Padding
		end,
		set = function(_, v)
			Grid2Layout.db.profile.Padding = v
			Grid2Layout:ReloadLayout()
		end
	},
	scale = {
		type = "range",
		name = L["Scale"],
		desc = L["Adjust Grid scale."],
		order = order_display + 7,
		min = 0.5,
		max = 2.0,
		step = 0.05,
		width = "double",
		isPercent = true,
		get = function()
			return Grid2Layout.db.profile.ScaleSize
		end,
		set = function(_, v)
			Grid2Layout.db.profile.ScaleSize = v
			Grid2Layout:Scale()
		end
	},
	anchorheader = {
		type = "header",
		order = order_anchor,
		name = L["Position and Anchor"]
	},
	layoutanchor = {
		type = "select",
		name = L["Layout Anchor"],
		desc = L["Sets where Grid is anchored relative to the screen."],
		order = order_anchor + 1,
		get = function()
			return Grid2Layout.db.profile.anchor
		end,
		set = function(_, v)
			Grid2Layout.db.profile.anchor = v
			Grid2Layout:SavePosition()
			Grid2Layout:RestorePosition()
		end,
		values = {
			["CENTER"] = L["CENTER"],
			["TOP"] = L["TOP"],
			["BOTTOM"] = L["BOTTOM"],
			["LEFT"] = L["LEFT"],
			["RIGHT"] = L["RIGHT"],
			["TOPLEFT"] = L["TOPLEFT"],
			["TOPRIGHT"] = L["TOPRIGHT"],
			["BOTTOMLEFT"] = L["BOTTOMLEFT"],
			["BOTTOMRIGHT"] = L["BOTTOMRIGHT"]
		}
	},
	groupanchor = {
		type = "select",
		name = L["Group Anchor"],
		desc = L["Sets where groups are anchored relative to the layout frame."],
		order = order_anchor + 2,
		get = function()
			return Grid2Layout.db.profile.groupAnchor
		end,
		set = function(_, v)
			Grid2Layout.db.profile.groupAnchor = v
			Grid2Layout:ReloadLayout()
			if Grid2Options.LayoutTestRefresh then
				Grid2Options:LayoutTestRefresh()
			end
		end,
		values = {
			["TOPLEFT"] = L["TOPLEFT"],
			["TOPRIGHT"] = L["TOPRIGHT"],
			["BOTTOMLEFT"] = L["BOTTOMLEFT"],
			["BOTTOMRIGHT"] = L["BOTTOMRIGHT"]
		}
	},
	detachheader = {
		type = "header",
		order = order_anchor + 10,
		name = L["Detached Groups"]
	},
	detachall = {
		type = "toggle",
		width = "full",
		name = L["Detach all groups"],
		desc = L["Enable this option to detach unit frame groups, so each group can be moved individually."],
		order = order_anchor + 11,
		get = function()
			return Grid2Layout.db.profile.detachedHeaders == "player"
		end,
		set = function(_, v)
			Grid2Layout.db.profile.detachedHeaders = v and "player" or nil
			Grid2Layout:ReloadLayout()
		end
	},
	detachpets = {
		type = "toggle",
		width = "full",
		name = L["Detach pets groups"],
		desc = L["Enable this option to detach the pets group, so pets group can be moved individually."],
		order = order_anchor + 12,
		get = function()
			return Grid2Layout.db.profile.detachedHeaders ~= nil
		end,
		set = function(_, v)
			if v then
				Grid2Layout.db.profile.detachedHeaders = "pet"
			elseif Grid2Layout.db.profile.detachedHeaders == "pet" then
				Grid2Layout.db.profile.detachedHeaders = nil
			end
			Grid2Layout:ReloadLayout()
		end,
		disabled = function()
			return Grid2Layout.db.profile.detachedHeaders == "player"
		end
	},
	clamp = {
		type = "toggle",
		name = L["Clamped to screen"],
		desc = L["Toggle whether to permit movement out of screen."],
		order = order_anchor + 3,
		get = function()
			return Grid2Layout.db.profile.clamp
		end,
		set = function()
			Grid2Layout.db.profile.clamp = not Grid2Layout.db.profile.clamp
			Grid2Layout:SetClamp()
		end
	},
	reset = {
		type = "execute",
		width = "half",
		name = L["Reset"],
		desc = L["Resets the layout frame's position and anchor."],
		order = order_anchor + 4,
		func = function()
			Grid2Layout:ResetPosition()
		end
	}
})

--[[ Detached groups: position and anchors of every group detached in the active layout ]]--

-- 3.3.5 has no GetPhysicalScreenSize (AddOns provide it via LibCompat), so fall
-- back to the resolution list when the API is missing
local function PhysicalScreenSize()
	local width, height
	if GetPhysicalScreenSize then
		width, height = GetPhysicalScreenSize()
	elseif GetScreenResolutions then
		local resolutions = { GetScreenResolutions() }
		local current = GetCurrentResolution and GetCurrentResolution() or #resolutions
		local res = resolutions[current] or resolutions[#resolutions]
		width, height = string.match(res or "", "(%d+)x(%d+)")
	end
	return tonumber(width) or 1024, tonumber(height) or 768
end

local function GetScreenRatio(horizontal)
	local w, h = PhysicalScreenSize()
	local size = UIParent[horizontal and "GetWidth" or "GetHeight"](UIParent) * UIParent:GetEffectiveScale()
	return (horizontal and w or h) / size
end

local function GetPhysicalPos(value, horizontal)
	return floor(value * GetScreenRatio(horizontal) + 0.5)
end

-- AceDB removes defaults from inactive profiles; fetch the profile in each callback.
local function EnsureProfileTables()
	local p = Grid2Layout.db and Grid2Layout.db.profile
	if not p then return nil end
	p.Positions = p.Positions or {}
	p.anchors = p.anchors or {}
	p.groupAnchors = p.groupAnchors or {}
	p.groupHorizontals = p.groupHorizontals or {}
	return p
end

local function SetPositionValue(key, index, value, horizontal)
	local p = EnsureProfileTables()
	local pos = p and p.Positions[key]
	if not pos then
		pos = { p.anchors[key] or p.anchor, p.PosX, p.PosY }
		p.Positions[key] = pos
	end
	pos[index] = value / GetScreenRatio(horizontal)
	Grid2Layout:ReloadLayout()
end

local headerAnchorPoints = { [""] = L["Default"], CENTER = L["CENTER"], TOP = L["TOP"], BOTTOM = L["BOTTOM"], LEFT = L["LEFT"],
	RIGHT = L["RIGHT"], TOPLEFT = L["TOPLEFT"], TOPRIGHT = L["TOPRIGHT"], BOTTOMLEFT = L["BOTTOMLEFT"], BOTTOMRIGHT = L["BOTTOMRIGHT"] }
local groupAnchorPoints = { [""] = L["Default"], TOPLEFT = L["TOPLEFT"], TOPRIGHT = L["TOPRIGHT"], BOTTOMLEFT = L["BOTTOMLEFT"], BOTTOMRIGHT = L["BOTTOMRIGHT"] }
local orientationValues = { [""] = L["Default"], horizontal = L["Horizontal"], vertical = L["Vertical"] }

local function MakeDetachedGroupsOptions()
	local args = {}
	if not Grid2Layout.layoutHasDetached then
		args.none = {
			type = "description",
			order = 1,
			name = L["No detached groups in the current layout."] .. "\n\n" ..
				L["Detach groups in the Layout Settings section, or per header in the layouts editor, then refresh this list."],
		}
	else
		local order = 0
		for _, header in Grid2Layout:IterateHeaders(true) do
			order = order + 1
			local key, prefix = header.headerPosKey, "group" .. order
			local function GetPos(index, horizontal)
				local p = EnsureProfileTables()
				local pos = p.Positions[key]
				return GetPhysicalPos(pos and pos[index] or (index == 2 and p.PosX or p.PosY), horizontal)
			end
			args[prefix .. "head"] = {
				type = "header",
				order = order * 10,
				name = string.format("%s %d (%s)", L["Group"], header.headerSetupIndex or order, L[header.headerUnitType] or tostring(header.headerUnitType)),
			}
			args[prefix .. "posx"] = {
				type = "range",
				name = L["Horizontal Position"],
				desc = L["Adjust the horizontal position of this group."],
				order = order * 10 + 1,
				width = 1.2,
				softMin = -2048,
				softMax = 2048,
				step = 1,
				get = function() return GetPos(2, true) end,
				set = function(_, v) SetPositionValue(key, 2, v, true) end,
			}
			args[prefix .. "posy"] = {
				type = "range",
				name = L["Vertical Position"],
				desc = L["Adjust the vertical position of this group."],
				order = order * 10 + 2,
				width = 1.2,
				softMin = -2048,
				softMax = 2048,
				step = 1,
				get = function() return GetPos(3, false) end,
				set = function(_, v) SetPositionValue(key, 3, v, false) end,
			}
			args[prefix .. "anchor"] = {
				type = "select",
				name = L["Anchor"],
				desc = L["Sets where this group is anchored on the screen."],
				order = order * 10 + 3,
				width = 0.9,
				get = function() return EnsureProfileTables().anchors[key] or "" end,
				set = function(_, v)
					EnsureProfileTables().anchors[key] = v ~= "" and v or nil
					Grid2Layout:ReloadLayout()
				end,
				values = headerAnchorPoints,
			}
			args[prefix .. "ganchor"] = {
				type = "select",
				name = L["Group Anchor"],
				desc = L["Sets where the units of this group are anchored inside the group frame."],
				order = order * 10 + 4,
				width = 0.9,
				get = function() return EnsureProfileTables().groupAnchors[key] or "" end,
				set = function(_, v)
					EnsureProfileTables().groupAnchors[key] = v ~= "" and v or nil
					Grid2Layout:ReloadLayout()
				end,
				values = groupAnchorPoints,
			}
			args[prefix .. "orient"] = {
				type = "select",
				name = L["Groups Orientation"],
				desc = L["Switch between horzontal/vertical groups."],
				order = order * 10 + 5,
				width = 0.6,
				get = function()
					local v = EnsureProfileTables().groupHorizontals[key]
					if v == nil then return "" end
					return v and "horizontal" or "vertical"
				end,
				set = function(_, v)
					local groupHorizontals = EnsureProfileTables().groupHorizontals
					if v == "" then
						groupHorizontals[key] = nil
					else
						groupHorizontals[key] = (v == "horizontal")
					end
					Grid2Layout:ReloadLayout()
				end,
				values = orientationValues,
			}
		end
	end
	args.refresh = {
		type = "execute",
		width = "half",
		name = L["Refresh"],
		desc = L["Rebuild the list of detached groups."],
		order = 9000,
		func = function()
			local section = Grid2Options.options.args.general.args["General"].args["Detached Groups"]
			section.args = MakeDetachedGroupsOptions()
			LibStub("AceConfigRegistry-3.0"):NotifyChange("Grid2")
		end,
	}
	return args
end

Grid2Options:AddGeneralOptions("General", "Detached Groups", MakeDetachedGroupsOptions())
