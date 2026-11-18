local Grid2 = Grid2
local Grid2Layout = Grid2:NewModule("Grid2Layout")

local pairs, ipairs, next = pairs, ipairs, next
local GetSetupValue = Grid2.GetSetupValue

--{{{ Frame config function for secure headers
local function GridHeader_InitialConfigFunction(self, name)
	Grid2Frame:RegisterFrame(self)
	RegisterUnitWatch(self)
	self:SetAttribute("*type1", "target")
	self:SetAttribute("useparent-toggleForVehicle", true)
	self:SetAttribute("useparent-allowVehicleTarget", true)
	self:SetAttribute("useparent-unitsuffix", true)
end
--}}}

--{{{ Class for group headers

local NUM_HEADERS = 0
local SecureHeaderTemplates = {
	party = "SecurePartyHeaderTemplate",
	partypet = "SecurePartyPetHeaderTemplate",
	raid = "SecureRaidGroupHeaderTemplate",
	raidpet = "SecureRaidPetHeaderTemplate"
}

local GridLayoutHeaderClass = {
	prototype = {},
	new = function(self, type)
		NUM_HEADERS = NUM_HEADERS + 1
		local frame
		if (type == "spacer") then
			frame = CreateFrame("Frame", "Grid2LayoutHeader" .. NUM_HEADERS, Grid2Layout.frame)
		else
			frame = CreateFrame("Frame", "Grid2LayoutHeader" .. NUM_HEADERS, Grid2Layout.frame, assert(SecureHeaderTemplates[type]))
			frame:SetAttribute("template", _G.ClickCastHeader and "ClickCastUnitTemplate,SecureUnitButtonTemplate" or "Grid2SecureUnitButtonTemplate")
			frame.initialConfigFunction = GridHeader_InitialConfigFunction
		end
		for name, func in pairs(self.prototype) do
			frame[name] = func
		end
		frame:Reset()
		frame:SetOrientation()
		return frame
	end
}

local HeaderAttributes = {
	"showPlayer",
	"showSolo",
	"nameList",
	"groupFilter",
	"strictFiltering",
	"sortDir",
	"groupBy",
	"groupingOrder",
	"maxColumns",
	"unitsPerColumn",
	"startingIndex",
	"columnSpacing",
	"columnAnchorPoint",
	"useOwnerUnit",
	"filterOnPet",
	"unitsuffix",
	"allowVehicleTarget",
	"toggleForVehicle"
}
function GridLayoutHeaderClass.prototype:Reset()
	-- bcc backport: hide the header BEFORE resetting attributes to avoid a lot
	-- of unnecessary SecureGroupHeader_Update() calls (each SetAttribute on a
	-- visible header triggers a full secure re-layout).
	self:Hide()
	if self.initialConfigFunction then
		self:SetLayoutAttribute("sortMethod", "NAME")
		for _, attr in ipairs(HeaderAttributes) do
			self:SetLayoutAttribute(attr, nil)
		end
	end
end

local anchorPoints = {
	[false] = {TOPLEFT = "TOP", TOPRIGHT = "TOP", BOTTOMLEFT = "BOTTOM", BOTTOMRIGHT = "BOTTOM"},
	[true] = {TOPLEFT = "LEFT", TOPRIGHT = "RIGHT", BOTTOMLEFT = "LEFT", BOTTOMRIGHT = "RIGHT"},
	TOP = -1,
	BOTTOM = 1,
	LEFT = 1,
	RIGHT = -1
}
-- nil or false for vertical
function GridLayoutHeaderClass.prototype:SetOrientation(horizontal)
	if not self.initialConfigFunction then return end
	local settings = Grid2Layout.db.profile
	local vertical = not horizontal
	local point = anchorPoints[not vertical][self.groupAnchor or settings.groupAnchor]
	local direction = anchorPoints[point]
	local xOffset = horizontal and settings.Padding * direction or 0
	local yOffset = vertical and settings.Padding * direction or 0
	self:SetLayoutAttribute("xOffset", xOffset)
	self:SetLayoutAttribute("yOffset", yOffset)
	self:SetLayoutAttribute("point", point)
end

-- MSaint fix see: http://forums.wowace.com/showpost.php?p=315982&postcount=215
-- To maintain the code consistent all calls to SetAttribute were replaced with SetLayoutAttribute
-- including those which not affect anchors, the only exception: calls from GridLayoutHeaderClass.new)
function GridLayoutHeaderClass.prototype:SetLayoutAttribute(name, value)
	if name == "point" or name == "columnAnchorPoint" or name == "unitsPerColumn" then
		self:ClearChildrenPoints()
	end
	self:SetAttribute(name, value)
end

function GridLayoutHeaderClass.prototype:ClearChildrenPoints()
	local count = 1
	local uframe = self:GetAttribute("child1")
	while uframe do
		uframe:ClearAllPoints()
		count = count + 1
		uframe = self:GetAttribute("child" .. count)
	end
end

--{{{ Grid2Layout

-- AceDB defaults
Grid2Layout.defaultDB = {
	profile = {
		debug = false,
		FrameDisplay = "Always",
		layouts = {
			solo = "Solo w/Pet",
			party = "By Group 5 w/Pets",
			raid10 = "By Group 10 w/Pets",
			raid15 = "By Group 15 w/Pets",
			raid25 = "By Group 25 w/Pets",
			raid40 = "By Group 40",
			arena = "By Group 5 w/Pets"
		},
		layoutScales = {},
		horizontal = true,
		clamp = true,
		FrameLock = false,
		ClickThrough = false,
		Padding = 0,
		Spacing = 10,
		ScaleSize = 1,
		BorderTexture = "Blizzard Tooltip",
		BorderR = .5,
		BorderG = .5,
		BorderB = .5,
		BorderA = 1,
		BackgroundR = .1,
		BackgroundG = .1,
		BackgroundB = .1,
		BackgroundA = .65,
		anchor = "TOPLEFT",
		groupAnchor = "TOPLEFT",
		PosX = 500,
		PosY = -200,
		Positions = {},
		anchors = {},
		groupAnchors = {},
		groupHorizontals = {},
		-- nil | 'player' (all groups) | 'pet' (group pet headers only)
		detachedHeaders = nil
	}
}

Grid2Layout.frameBackdrop = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = {left = 4, right = 4, top = 4, bottom = 4}
}

Grid2Layout.layoutSettings = {}

Grid2Layout.layoutHeaderClass = GridLayoutHeaderClass

function Grid2Layout:OnModuleInitialize()
	self.groups = {
		raid = {},
		raidpet = {},
		party = {},
		partypet = {},
		spacer = {}
	}
	self.groupsUsed = {}
	self.layoutHasDetached = nil
	self.indexes = {
		raid = 0,
		raidpet = 0,
		party = 0,
		partypet = 0,
		spacer = 0
	}
	self:AddCustomLayouts()
end

function Grid2Layout:OnModuleEnable()
	if not self.frame then
		self:CreateFrame()
	end
	self:RestorePosition()
	if self.layoutName then
		self:ReloadLayout()
	end
	self:RegisterMessage("Grid_GroupTypeChanged")
	self:RegisterMessage("Grid_UpdateLayoutSize", "QueueUpdateSize")
	self:RegisterMessage("Grid_RosterUpdated", "QueueUpdateSize")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function Grid2Layout:OnModuleDisable()
	self:CancelQueuedSize()
	self:UnregisterMessage("Grid_GroupTypeChanged")
	self:UnregisterMessage("Grid_UpdateLayoutSize", "QueueUpdateSize")
	self:UnregisterMessage("Grid_RosterUpdated", "QueueUpdateSize")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self.frame:Hide()
end

--{{{ Event handlers
function Grid2Layout:PLAYER_REGEN_ENABLED()
	if self.reloadLayoutQueued then
		return self:ReloadLayout()
	end
	if self.updateSizeQueued then
		return self:UpdateSize()
	end
	if self.restorePositionQueued then
		return self:RestorePosition()
	end
end

-- cancel dragging of a detached group if combat starts
function Grid2Layout:PLAYER_REGEN_DISABLED()
	local header = self.movingHeader
	if header == self.frame then
		return self:StopMoveFrame()
	elseif header and header.isMoving then
		header:StopMovingOrSizing()
		header.isMoving = nil
		self.movingHeader = nil
		self:SaveHeaderPosition(header)
		self:RestoreHeaderPosition(header)
	end
end

function Grid2Layout:Grid_GroupTypeChanged(_, type)
	Grid2Layout:Debug("GroupTypeChanged", type)
	self.partyType = type
	self:ReloadLayout()
end

--}}}

function Grid2Layout:StartMoveFrame(button)
	if button == "LeftButton" and self:FramesCanBeMoved() then
		self.frame:StartMoving()
		self.frame.isMoving = true
		self.movingHeader = self.frame
		self:StartHeaderTracking(self.frame) -- bcc parity: snap the window to detached groups too
	end
end

function Grid2Layout:StopMoveFrame()
	if self.frame.isMoving then
		self.frame:StopMovingOrSizing()
		self.frame.isMoving = false
		self.movingHeader = nil
		self:SearchSnapToNearestHeader(self.frame, true)
		self:SavePosition()
		self:RestorePosition()
	end
end

-- nil:toggle, false:disable movement, true:enable movement
function Grid2Layout:FrameLock(locked)
	local p = self.db.profile
	if (locked == nil) then
		p.FrameLock = not p.FrameLock
	else
		p.FrameLock = locked
	end
	if (not p.FrameLock and p.ClickThrough) then
		p.ClickThrough = false
		self.frame:EnableMouse(true)
	end
	if self.frame.frameDrag then
		self.frame.frameDrag:EnableMouse(not p.FrameLock)
	end
	for _, header in self:IterateHeaders(true) do -- detached groups: arm/disarm their drag handles
		self:UpdateDetachedVisibility(header)
	end
end

--{{{ ConfigMode support
CONFIGMODE_CALLBACKS = CONFIGMODE_CALLBACKS or {}
CONFIGMODE_CALLBACKS["Grid2"] = function(action)
	if (action == "ON") then
		Grid2Layout:FrameLock(false)
	elseif (action == "OFF") then
		Grid2Layout:FrameLock(true)
	end
end
--}}}

function Grid2Layout:CreateFrame()
	local p = self.db.profile
	-- create main frame to hold all our gui elements
	local f = CreateFrame("Frame", "Grid2LayoutFrame", UIParent)
	self.frame = f
	f:SetMovable(true)
	f:SetClampedToScreen(p.clamp)
	f:SetPoint("CENTER", UIParent, "CENTER")
	f:SetScript("OnMouseUp", function() self:StopMoveFrame() end)
	f:SetScript("OnHide", function() self:StopMoveFrame() end)
	f:SetScript("OnMouseDown", function(_, button) self:StartMoveFrame(button) end)
	f:SetFrameStrata(p.FrameStrata or "MEDIUM")
	f:SetFrameLevel(0)
	-- drag handle: covers the unit buttons so the window can be grabbed anywhere while
	-- unlocked, same as detached groups. Mouse is toggled by SetFrameLock/FrameLock.
	local drag = CreateFrame("Frame", nil, f)
	drag:SetAllPoints(f)
	drag:SetFrameLevel(5) -- above the unit buttons, below detached group handles
	drag:SetScript("OnMouseUp", function() self:StopMoveFrame() end)
	drag:SetScript("OnHide", function() self:StopMoveFrame() end)
	drag:SetScript("OnMouseDown", function(_, button) self:StartMoveFrame(button) end)
	drag:Show()
	f.frameDrag = drag
	self:UpdateTextures()
	self:SetFrameLock(p.FrameLock, p.ClickThrough)
	self.CreateFrame = nil
end

local relativePoints = {
	[false] = {TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT", BOTTOMLEFT = "TOPLEFT", BOTTOMRIGHT = "TOPRIGHT"},
	[true] = {TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT", BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT"},
	xMult = {TOPLEFT = 1, TOPRIGHT = -1, BOTTOMLEFT = 1, BOTTOMRIGHT = -1},
	yMult = {TOPLEFT = -1, TOPRIGHT = -1, BOTTOMLEFT = 1, BOTTOMRIGHT = 1}
}
local previousFrame
function Grid2Layout:PlaceGroup(frame, groupNumber, isDetached)
	local settings = self.db.profile
	local horizontal = settings.horizontal
	local vertical = not horizontal
	local padding = settings.Padding
	local spacing = settings.Spacing
	local anchor = settings.groupAnchor
	local relPoint = relativePoints[vertical][anchor]
	local xMult = relativePoints.xMult[anchor]
	local yMult = relativePoints.yMult[anchor]
	frame:ClearAllPoints()
	frame:SetParent(self.frame)
	if isDetached then
		return -- detached groups use the position saved in p.Positions, see PlaceDetachedHeader
	end
	if groupNumber == 1 then
		frame:SetPoint(anchor, self.frame, anchor, spacing * xMult, spacing * yMult)
	else
		xMult = vertical and xMult * padding or 0
		yMult = horizontal and yMult * padding or 0
		frame:SetPoint(anchor, previousFrame, relPoint, xMult, yMult)
	end
	self:Debug("Placing group", groupNumber, frame:GetName(), anchor, previousFrame and previousFrame:GetName(), relPoint)
	previousFrame = frame
end

function Grid2Layout:AddLayout(layoutName, layout)
	self.layoutSettings[layoutName] = layout
end

function Grid2Layout:SetClamp()
	self.frame:SetClampedToScreen(self.db.profile.clamp)
end

function Grid2Layout:ReloadLayout(force)
	if InCombatLockdown() and not force then
		self.reloadLayoutQueued = true
		return
	end
	self.reloadLayoutQueued = nil
	self:LoadLayout(self.db.profile.layouts[self.partyType or "solo"])
end

function Grid2Layout:RefreshLayout()
	return self:ReloadLayout(true)
end

local function SetAllAttributes(header, p, list, fix)
	local petgroup = false
	for attr, value in next, list do
		if attr == "unitsPerColumn" then
			header:SetLayoutAttribute("columnSpacing", p.Padding)
			header:SetLayoutAttribute("unitsPerColumn", value)
			header:SetLayoutAttribute("columnAnchorPoint", anchorPoints[not p.horizontal][p.groupAnchor] or p.groupAnchor)
		elseif attr ~= "type" then
			header:SetLayoutAttribute(attr, value)
		else
			petgroup = (value == "partypet" or value == "raidpet")
		end
	end
	if fix and petgroup then
		-- force these so that the bug in SecureGroupPetHeader_Update doesn't trigger
		header:SetLayoutAttribute("useOwnerUnit", false)
		header:SetLayoutAttribute("unitsuffix", nil)
		-- 3.3.5 FrameXML strsplit-crashes (line 1124) when a pet header has groupBy
		-- set but no groupingOrder; pets then just sort by the owner class order
		if header:GetAttribute("groupBy") and not header:GetAttribute("groupingOrder") then
			header:SetLayoutAttribute("groupingOrder", Grid2Layout.DEFAULT_PET_ORDER)
		end
	end
end

-- Precreate frames to avoid a blizzard bug that prevents initializing unit frames in combat
-- http://forums.wowace.com/showpost.php?p=307503&postcount=3163
-- (3.3.5 backport: full pet grid pre-spawned out of combat, as in bcc 2.9.31;
-- a pet button created by the client mid-combat taints, so we eat the load lag.)
local function ForceFramesCreation(header)
	local startingIndex = header:GetAttribute("startingIndex")
	local maxColumns = header:GetAttribute("maxColumns") or 1
	local unitsPerColumn = header:GetAttribute("unitsPerColumn") or 5
	local maxFrames = maxColumns * unitsPerColumn
	local count = header.FrameCount
	if not count or count < maxFrames then
		header:Show()
		header:SetAttribute("startingIndex", 1 - maxFrames)
		header:SetAttribute("startingIndex", startingIndex)
		header.FrameCount = maxFrames
		-- bcc backport: hide again, the header is shown for real later by LoadLayout
		header:Hide()
	end
end

function Grid2Layout:LoadLayout(layoutName)
	local layout = self.layoutSettings[layoutName]
	if not layout then return end
	self:Debug("LoadLayout", layoutName)

	self.layoutName = layoutName
	self:Scale()

	local p = self.db.profile
	local horizontal = p.horizontal
	self.layoutHasDetached = nil
	wipe(self.groupsUsed)

	for type, headers in pairs(self.groups) do
		self.indexes[type] = 0
		for _, g in ipairs(headers) do
			g:Reset()
		end
	end

	local defaults = layout.defaults
	local default_type = defaults and defaults.type or "raid"

	-- profiles created before the detached groups feature have no Positions table
	p.Positions = p.Positions or {}

	for i, l in ipairs(layout) do
		local type = l.type or default_type
		local headers = assert(self.groups[type], "Bad " .. type)
		local index = self.indexes[type] + 1
		local layoutGroup = headers[index]
		if not layoutGroup then
			layoutGroup = self.layoutHeaderClass:new(type)
			headers[index] = layoutGroup
		end
		self.indexes[type] = index
		self.groupsUsed[#self.groupsUsed + 1] = layoutGroup

		if type ~= "spacer" then
			if defaults then
				SetAllAttributes(layoutGroup, p, defaults)
			end
			SetAllAttributes(layoutGroup, p, l, true)
			self:SetHeaderProperties(layoutGroup, i, l, type)
			self:SetupDetachedHeader(layoutGroup)
			ForceFramesCreation(layoutGroup)
			-- note: groupHorizontal can be false, so no 'and/or' shortcut here
			local groupHorizontal = layoutGroup.isDetached and layoutGroup.groupHorizontal
			if groupHorizontal == nil then
				groupHorizontal = horizontal
			end
			layoutGroup:SetOrientation(groupHorizontal)
		else
			layoutGroup.isDetached = nil
		end
		self:PlaceGroup(layoutGroup, i, layoutGroup.isDetached)

		layoutGroup:Show()
	end

	for _, layoutGroup in ipairs(self.groupsUsed) do
		if layoutGroup.isDetached then
			self:PlaceDetachedHeader(layoutGroup)
		end
	end

	self:UpdateDisplay()
end

function Grid2Layout:UpdateDisplay()
	self:UpdateTextures()
	self:UpdateColor()
	self:CheckVisibility()
	self:UpdateSize()
end

-- bcc parity (RunThrottled in 2.9.33): defer the size recalc so that Blizzard
-- has already resized the secure headers when UpdateSize reads their bounds;
-- a synchronous call measures stale full-pool sizes (bg for 8 slots, 5 units).
function Grid2Layout:QueueUpdateSize()
	if self.updateSizeTimer then return end
	self.updateSizeTimer = Grid2:ScheduleTimer(function()
		Grid2Layout.updateSizeTimer = nil
		Grid2Layout:UpdateSize()
	end, 0.1)
end

-- cancel a pending deferred resize so it cannot fire while the module is off
function Grid2Layout:CancelQueuedSize()
	if self.updateSizeTimer then
		Grid2:CancelTimer(self.updateSizeTimer, true)
		self.updateSizeTimer = nil
	end
end

function Grid2Layout:UpdateSize()
	if InCombatLockdown() then
		self.updateSizeQueued = true
		return
	end
	self.updateSizeQueued = nil

	local p = self.db.profile
	local curWidth, curHeight, maxWidth, maxHeight = 0, 0, 0, 0
	local Padding, Spacing = p.Padding, p.Spacing * 2

	local frameWidth, frameHeight = Grid2Frame:GetFrameSize()
	for i = 1, self.indexes.spacer do
		self.groups.spacer[i]:SetSize(frameWidth, frameHeight)
	end

	for type, headers in pairs(self.groups) do
		for i = 1, self.indexes[type] do
			local g = headers[i]
			if g.isDetached then
				self:UpdateDetachedVisibility(g)
			else
				local width, height = g:GetWidth(), g:GetHeight()
				curWidth = curWidth + width + Padding
				curHeight = curHeight + height + Padding
				if maxWidth < width then
					maxWidth = width
				end
				if maxHeight < height then
					maxHeight = height
				end
			end
		end
	end

	local x = p.horizontal and maxWidth + Spacing or curWidth + Spacing - Padding
	local y = p.horizontal and curHeight + Spacing - Padding or maxHeight + Spacing

	self.frame:SetWidth(x)
	self.frame:SetHeight(y)
end

function Grid2Layout:UpdateTextures()
	local f = self.frame
	local p = self.db.profile
	-- a fresh cached backdrop table per texture set: reusing one mutable table made
	-- detached groups keep a stale border after they were detached a second time
	self.frameBackdrop = Grid2:GetBackdropTable(
		Grid2:MediaFetch("border", p.BorderTexture),
		16,
		Grid2:MediaFetch("background", p.BackgroundTexture, "Interface\\ChatFrame\\ChatFrameBackground"),
		p.BackgroundTile,
		p.BackgroundTileSize or 16,
		4
	)
	Grid2:SetFrameBackdrop(f, self.frameBackdrop)
	for _, header in self:IterateHeaders(true) do -- detached groups
		if header.frameBack then
			Grid2:SetFrameBackdrop(header.frameBack, self.frameBackdrop)
		end
	end
end

function Grid2Layout:UpdateColor()
	local settings = self.db.profile
	self.frame:SetBackdropBorderColor(settings.BorderR, settings.BorderG, settings.BorderB, settings.BorderA)
	self.frame:SetBackdropColor(settings.BackgroundR, settings.BackgroundG, settings.BackgroundB, settings.BackgroundA)
	for _, header in self:IterateHeaders(true) do -- detached groups
		local frameBack = header.frameBack
		if frameBack then
			frameBack:SetBackdropColor(settings.BackgroundR, settings.BackgroundG, settings.BackgroundB, settings.BackgroundA)
		end
		self:UpdateDetachedVisibility(header)
	end
end

function Grid2Layout:CheckVisibility()
	local frameDisplay = self.db.profile.FrameDisplay
	if
		(frameDisplay == "Always") or (frameDisplay == "Grouped" and self.partyType ~= "solo") or
			(frameDisplay == "Raid" and self.partyType:find("raid"))
	 then
		self.frame:Show()
	else
		self.frame:Hide()
	end
end

function Grid2Layout:SavePosition(header)
	local f = header or self.frame
	if f:GetLeft() and f:GetWidth() then
		local p = self.db.profile
		local a = f.headerAnchor or p.anchor
		local s = f:GetEffectiveScale()
		local t = UIParent:GetEffectiveScale()
		local x = (a:find("LEFT") and f:GetLeft() * s) or (a:find("RIGHT") and f:GetRight() * s - UIParent:GetWidth() * t) or (f:GetLeft() + f:GetWidth() / 2) * s - UIParent:GetWidth() / 2 * t
		local y = (a:find("BOTTOM") and f:GetBottom() * s) or (a:find("TOP") and f:GetTop() * s - UIParent:GetHeight() * t) or (f:GetTop() - f:GetHeight() / 2) * s - UIParent:GetHeight() / 2 * t
		if f.headerPosKey then
			p.Positions[f.headerPosKey] = {a, x, y}
		else
			p.PosX = x
			p.PosY = y
		end
		self:Debug("Saved Position", a, x, y)
	end
end

function Grid2Layout:ResetPosition()
	local s = UIParent:GetEffectiveScale()
	self.db.profile.PosX = UIParent:GetWidth() / 2 * s
	self.db.profile.PosY = -UIParent:GetHeight() / 2 * s
	self.db.profile.anchor = "TOPLEFT"
	self:RestorePosition()
	self:SavePosition()
	local positions = self.db.profile.Positions
	if self.layoutHasDetached and positions then
		for _, header in self:IterateHeaders(true) do
			positions[header.headerPosKey] = nil
		end
		self:ReloadLayout()
	end
end

--{{{ Detached groups management

-- calculate and store the properties of a layout header
function Grid2Layout:SetHeaderProperties(header, setupIndex, dbx, type)
	local p = self.db.profile
	local isDetached = setupIndex > 1 and (
		dbx.detachHeader or p.detachedHeaders == "player" or
		(p.detachedHeaders == "pet" and (type == "raidpet" or type == "partypet"))
	)
	header.wasDetached = header.isDetached
	header.isDetached = isDetached or nil
	header.headerPosKey = header.isDetached and (self.layoutName .. setupIndex) or nil
	header.headerSetupIndex, header.headerUnitType = setupIndex, type
	local key = header.headerPosKey
	if header.isDetached then
		-- detached groups keep their own position, anchor and orientation
		header.headerAnchor = GetSetupValue(true, p.anchors[key], p.anchor)
		header.groupAnchor = GetSetupValue(true, p.groupAnchors[key], p.groupAnchor)
		header.groupHorizontal = GetSetupValue(true, p.groupHorizontals[key], p.horizontal)
	else
		header.headerAnchor = p.anchor
		header.groupAnchor = nil
		header.groupHorizontal = p.horizontal
	end
end

-- create/destroy the frames used as backdrop and as drag handle of a detached group
function Grid2Layout:SetupDetachedHeader(header)
	local isDetached = header.isDetached
	if isDetached ~= header.wasDetached then
		local frameBack, frameDrag = header.frameBack, header.frameDrag
		header.wasDetached = isDetached
		header:SetMovable(not not isDetached)
		if isDetached then
			frameBack = frameBack or CreateFrame("Frame", nil, header)
			frameBack.header = header
			frameDrag = frameDrag or CreateFrame("Frame", nil, header)
			frameDrag.header = header
			frameDrag:SetScript("OnMouseUp", self.StopMoveHeader)
			frameDrag:SetScript("OnHide", self.StopMoveHeader)
			frameDrag:SetScript("OnMouseDown", self.StartMoveHeader)
			header.frameBack, header.frameDrag = frameBack, frameDrag
		elseif frameBack then
			frameBack:Hide()
			frameBack:ClearAllPoints()
			if frameDrag then
				frameDrag:Hide()
				frameDrag:ClearAllPoints()
				frameDrag:EnableMouse(false)
				frameDrag:SetScript("OnMouseUp", nil)
				frameDrag:SetScript("OnHide", nil)
				frameDrag:SetScript("OnMouseDown", nil)
			end
		end
	end
	if isDetached then
		local Spacing, headerLevel = self.db.profile.Spacing, header:GetFrameLevel()
		local frameBack, frameDrag = header.frameBack, header.frameDrag
		-- backdrop: drawn above the main window background (frame level 0) but under the unit buttons
		frameBack:ClearAllPoints()
		frameBack:SetPoint("TOPLEFT", header, "TOPLEFT", -Spacing, Spacing)
		frameBack:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", Spacing, -Spacing)
		frameBack:SetFrameLevel(headerLevel > 0 and headerLevel or 1)
		frameBack:Hide()
		-- drag handle: invisible overlay above the unit buttons, takes the mouse only while unlocked
		frameDrag:ClearAllPoints()
		frameDrag:SetPoint("TOPLEFT", frameBack, "TOPLEFT")
		frameDrag:SetPoint("BOTTOMRIGHT", frameBack, "BOTTOMRIGHT")
		frameDrag:SetFrameLevel(headerLevel + 5)
		frameDrag:Show()
		self.layoutHasDetached = true
		self:UpdateDetachedVisibility(header)
	end
end

-- show/hide the backdrop of a detached group and arm/disarm its drag handle
function Grid2Layout:UpdateDetachedVisibility(header)
	local frameBack, frameDrag = header.frameBack, header.frameDrag
	if not frameBack then return end
	local p = self.db.profile
	if frameDrag then
		frameDrag:EnableMouse(not p.FrameLock)
	end
	if p.FrameLock then
		-- locked: the group looks like part of the grid, the handle mirrors its first button
		local button = header:GetAttribute("child1") or _G[header:GetName() .. "UnitButton1"]
		-- 3.3.5 has no Frame:SetShown
		if button and button:IsVisible() then
			frameBack:Show()
		else
			frameBack:Hide()
		end
		frameBack:SetBackdropBorderColor(p.BorderR, p.BorderG, p.BorderB, p.BorderA)
	else
		-- unlocked (config mode): always visible so the group can be grabbed anywhere;
		-- the border keeps the profile colors, same as the main window (bcc parity)
		frameBack:Show()
		frameBack:SetBackdropBorderColor(p.BorderR, p.BorderG, p.BorderB, p.BorderA)
	end
end

-- true = detached headers; false|nil = non detached headers
function Grid2Layout:IterateHeaders(detached)
	if detached and not self.layoutHasDetached then return Grid2.Dummy end
	local i, t, d = 0, self.groupsUsed, detached or nil
	return function()
		repeat
			i = i + 1; if i > #t then return end
		until d == t[i].isDetached
		return i, t[i]
	end
end

function Grid2Layout:EnableMouse(enabled)
	self.frame:EnableMouse(enabled)
	if self.frame.frameDrag then
		self.frame.frameDrag:EnableMouse(enabled)
	end
	for _, header in self:IterateHeaders(true) do
		if header.frameDrag then
			header.frameDrag:EnableMouse(enabled)
		end
	end
end

function Grid2Layout:SaveHeaderPosition(header)
	self:SavePosition(header)
end

function Grid2Layout:RestoreHeaderPosition(header)
	if InCombatLockdown() then return end
	local p = self.db.profile
	local pos = header.headerPosKey and p.Positions[header.headerPosKey]
	if pos then
		local s = header:GetEffectiveScale()
		local a, x, y = pos[1], pos[2] / s, pos[3] / s
		header:ClearAllPoints()
		header:SetPoint(a, UIParent, a, x, y)
		header:Show()
		self:Debug("Placing detached group", header.headerPosKey, a, x, y)
		if a ~= header.headerAnchor then
			-- the anchor option changed: re-store the position using the new anchor and re-place
			self:SaveHeaderPosition(header)
			return self:RestoreHeaderPosition(header)
		end
		return true
	end
end

-- restore the main window position and all detached groups (usable from external code too)
function Grid2Layout:RestorePositions()
	self:RestorePosition()
	for _, header in self:IterateHeaders(true) do
		self:RestoreHeaderPosition(header)
	end
end

function Grid2Layout:PlaceDetachedHeader(header)
	header:SetParent(self.frame)
	if self:RestoreHeaderPosition(header) then return end
	-- first time this group is detached: cascade it next to the previous group in the
	-- layout, so detaching several groups at once does not pile them up
	local p = self.db.profile
	local idx = header.headerSetupIndex
	local prev = idx and idx > 1 and self.groupsUsed[idx - 1]
	local anchor = header.groupAnchor or p.groupAnchor
	local horizontal = header.groupHorizontal
	if horizontal == nil then
		horizontal = p.horizontal
	end
	local vertical = not horizontal
	local relPoint = relativePoints[vertical][anchor]
	local offset = p.Spacing * 2
	local x = vertical and relativePoints.xMult[anchor] * offset or 0
	local y = (not vertical) and relativePoints.yMult[anchor] * offset or 0
	local relativeTo = (prev and prev:IsShown()) and prev or self.frame
	header:ClearAllPoints()
	header:SetPoint(anchor, relativeTo, relPoint, x, y)
	header:Show()
	-- the header has no resolved screen rect yet, so store the position once the layout settled
	local key, layoutName = header.headerPosKey, self.layoutName
	Grid2:ScheduleTimer(function()
		if header.headerPosKey == key and self.layoutName == layoutName and not InCombatLockdown() then
			Grid2Layout:SaveHeaderPosition(header)
			Grid2Layout:RestoreHeaderPosition(header)
		end
	end, 0.1)
end


--{{{ Snap to other groups (ported from Grid2 bcc)
do
	local LCG = LibStub("SpecializedLibGlow-1.0", true)
	local colors = { [false] = { 1, 1, 0, 1 }, [true] = { 1, 0, 0, 1 } }
	local trackedHeader, nearestHeader, nearestOverlap

	local function HighlightHeader(header, enable, overlap)
		if not header or not LCG then return end
		local target = header.isDetached and header.frameBack or header
		if enable then
			LCG.PixelGlow_Start(target, colors[overlap], 8, .2, nil, 1, 0, 0, false, "Grid2DragHighlight")
		else
			LCG.PixelGlow_Stop(target, "Grid2DragHighlight")
		end
	end

	local TrackHeader
	function TrackHeader()
		local newHeader, newOverlap
		if trackedHeader.isMoving and not IsShiftKeyDown() then
			newHeader, newOverlap = Grid2Layout:SearchSnapToNearestHeader(trackedHeader)
		end
		if newHeader ~= nearestHeader or newOverlap ~= nearestOverlap then
			HighlightHeader(nearestHeader, false)
			HighlightHeader(newHeader, newHeader ~= nil, newOverlap)
			HighlightHeader(trackedHeader, newHeader ~= nil, newOverlap)
			nearestHeader, nearestOverlap = newHeader, newOverlap
		end
		if trackedHeader.isMoving and not InCombatLockdown() then
			Grid2:ScheduleTimer(TrackHeader, 0.2)
		end
	end

	function Grid2Layout:StartHeaderTracking(header)
		if self.layoutHasDetached then
			trackedHeader, nearestHeader, nearestOverlap = header, nil, nil
			TrackHeader()
		end
	end

	-- snap header1 to the a2 point of header2
	function Grid2Layout:SnapHeaderToPoint(a1, header1, a2, x2, y2, intersect)
		local p = self.db.profile
		local mf = header1 == self.frame and 0 or 1
		local xm = relativePoints.xMult[a1]
		local ym = relativePoints.yMult[a1]
		local x = x2 + p.Spacing * xm * mf
		local y = y2 + p.Spacing * ym * mf
		if intersect then -- intersect, substract border
			local sp = p.Padding - p.Spacing * 2
			x = x + sp * xm * (not strfind(a1, "LEFT") ~= not strfind(a2, "LEFT") and 1 or 0)
			y = y + sp * ym * (not strfind(a1, "TOP") ~= not strfind(a2, "TOP") and 1 or 0)
		end
		header1:ClearAllPoints()
		header1:SetPoint(a1, UIParent, "BOTTOMLEFT", x, y)
	end

	-- the main window has no frameBack in this port, so fall back to the frame itself
	local function SnapRect(frame)
		return frame.frameBack or frame
	end

	function Grid2Layout:SearchSnapToNearestHeader(header, adjust)
		if IsShiftKeyDown() or not self.layoutHasDetached or InCombatLockdown() then return end
		local rect = SnapRect(header)
		local x1, x2, y1, y2, xx1, xx2, yy1, yy2, intersect = rect:GetLeft(), rect:GetRight(), rect:GetTop(), rect:GetBottom()
		if not x1 then return end
		local function Check(a1, xxx1, yyy1, a2, xxx2, yyy2)
			if a1 ~= a2 and (xxx2 - xxx1) ^ 2 + (yyy2 - yyy1) ^ 2 < 512 then
				intersect = not (x1 >= xx2 or xx1 >= x2 or y1 <= yy2 or yy1 <= y2)
				if adjust then self:SnapHeaderToPoint(a1, header, a2, xxx2, yyy2, intersect) end
				return true
			end
		end
		local function CheckPoint(a, x, y)
			return Check("TOPLEFT", x1, y1, a, x, y) or Check("TOPRIGHT", x2, y1, a, x, y) or Check("BOTTOMLEFT", x1, y2, a, x, y) or Check("BOTTOMRIGHT", x2, y2, a, x, y)
		end
		local function CheckFrame(frame, force)
			if header ~= frame and (frame.isDetached or force) then -- check only the main frame and the detached headers
				local f = SnapRect(frame)
				xx1, xx2, yy1, yy2 = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
				if xx1 then
					return (CheckPoint("TOPLEFT", xx1, yy1) or CheckPoint("TOPRIGHT", xx2, yy1) or CheckPoint("BOTTOMLEFT", xx1, yy2) or CheckPoint("BOTTOMRIGHT", xx2, yy2)) and frame
				end
			end
		end
		local result = CheckFrame(self.frame, true) -- check the main frame (parent of all non-detached headers)
		if not result then
			for _, frame in ipairs(self.groupsUsed) do
				result = CheckFrame(frame)
				if result then break end
			end
		end
		return result, intersect
	end

	function Grid2Layout:FramesCanBeMoved()
		return (not InCombatLockdown()) and (self.testLayoutName or not self.db.profile.FrameLock)
	end

	-- dragging management (self is header.frameBack inside the script handlers)
	function Grid2Layout:StartMoveHeader(button)
		if button == "LeftButton" and Grid2Layout:FramesCanBeMoved() then
			self.header:StartMoving()
			self.header.isMoving = true
			Grid2Layout.movingHeader = self.header
			Grid2Layout:StartHeaderTracking(self.header)
		end
	end

	function Grid2Layout:StopMoveHeader()
		local header = self.header
		if header and header.isMoving then
			header:StopMovingOrSizing()
			header.isMoving = nil
			Grid2Layout.movingHeader = nil
			Grid2Layout:SearchSnapToNearestHeader(header, true)
			-- clear the snap highlight when the drag ends, otherwise it would stay on screen
			HighlightHeader(nearestHeader, false)
			HighlightHeader(trackedHeader, false)
			nearestHeader, nearestOverlap = nil, nil
			Grid2Layout:SaveHeaderPosition(header)
			Grid2Layout:RestoreHeaderPosition(header)
		end
	end
end
--}}}

function Grid2Layout:RestorePosition()
	if InCombatLockdown() then
		self.restorePositionQueued = true
		return
	end
	self.restorePositionQueued = nil
	local f = self.frame
	local s = f:GetEffectiveScale()
	local x = self.db.profile.PosX / s
	local y = self.db.profile.PosY / s
	local a = self.db.profile.anchor
	f:ClearAllPoints()
	f:SetPoint(a, x, y)
	self:Debug("Restored Position", a, x, y)
end

function Grid2Layout:Scale()
	local settings = self.db.profile
	self:SavePosition()
	self.frame:SetScale(settings.ScaleSize * (settings.layoutScales[self.layoutName or "solo"] or 1))
	self:RestorePosition()
	for _, header in self:IterateHeaders(true) do
		self:RestoreHeaderPosition(header)
	end
end

function Grid2Layout:SetFrameLock(FrameLock, ClickThrough)
	local p = self.db.profile
	p.FrameLock = FrameLock
	if not FrameLock then
		ClickThrough = false
	end
	p.ClickThrough = ClickThrough
	self.frame:EnableMouse(not ClickThrough)
	if self.frame.frameDrag then
		self.frame.frameDrag:EnableMouse(not FrameLock)
	end
	for _, header in self:IterateHeaders(true) do
		self:UpdateDetachedVisibility(header)
	end
end

function Grid2Layout:AddCustomLayouts()
	local customLayouts = self.db.global.customLayouts
	if customLayouts then
		for n, l in pairs(customLayouts) do
			Grid2Layout:AddLayout(n, l)
		end
	end
end

_G.Grid2Layout = Grid2Layout