--[[ Tooltip indicator backported from Grid2 2.9.31-bcc to 3.3.5a.
Differences vs bcc:
- No Grid2Frame:SetEventHook on 3.3.5: hooks installed with hooksecurefunc()
  on Grid2Frame:OnFrameEnter/OnFrameLeave (installed once, gated by flag).
- No Grid2:CreateTimer object API: refresh polling uses AceTimer
  ScheduleRepeatingTimer/CancelTimer (Grid2 embeds AceTimer-3.0).
- SetPropagateMouseMotion/SetPropagateMouseClicks/SetMouseClickEnabled
  guarded (missing on some 3.3.5 frame types).
]]

local Grid2 = Grid2
local Tooltip = Grid2.indicatorPrototype:new("tooltip")
local next = next

Tooltip.Create = Grid2.Dummy
Tooltip.Layout = Grid2.Dummy

-- tooltip indicator settings
local TooltipCheck = {
	[1] = function() return false end, -- never
	[2] = function() return true  end, -- always
	[3] = InCombatLockdown,             -- in combat
	[4] = function() return not InCombatLockdown() end, -- out of combat
}
local tooltipOOC
local tooltipDefault
local tooltipCheck
local tooltipOwner  -- default frame to anchor the tooltip if no indicator is provided
local tooltipDisplayed
local tooltipHookEnabled
local hooksInstalled
-- whole unit frame
local tooltipFrame  -- unit frame under the mouse, usually parent in indicators code
local OnFrameEnter
local OnFrameLeave
-- indicator under the mouse
local tooltipIndicatorFrame -- indicator frame under the mouse, usually parent[indicator.name]
local tooltipIndicatorEnabled
local OnFrameIndicatorEnter
local OnFrameIndicatorLeave
local ShowFrameTooltip
local RefreshFrameTooltip

-- 3.3.5: AceTimer based refresh polling (replaces bcc Grid2:CreateTimer object)
local refreshHandle
local RefreshStop
local function RefreshPlay()
	if not refreshHandle then
		refreshHandle = Grid2:ScheduleRepeatingTimer(function()
			if tooltipIndicatorFrame then
				ShowFrameTooltip(tooltipIndicatorFrame)
			else
				RefreshStop()
			end
		end, 0.25)
	end
end
RefreshStop = function()
	if refreshHandle then
		Grid2:CancelTimer(refreshHandle)
		refreshHandle = nil
	end
end
-- bcc compatibility: RefreshFrameTooltip:Play() / :Stop()
RefreshFrameTooltip = setmetatable({}, { __index = function(_, key)
	if key == "Play" then return RefreshPlay
	elseif key == "Stop" then return RefreshStop end
end })

ShowFrameTooltip = function(frame)
	local indicator = frame.tooltipIndicator
	if indicator then
		local unit = tooltipFrame and tooltipFrame.unit or frame:GetParent().unit
		local func = indicator.GetMouseOverStatus or (unit and indicator.GetCurrentStatus)
		if func then
			local status, _, extraID, tframe, tunit = func(indicator, unit, tooltipFrame, frame)
			if status and status.GetTooltip then
				Tooltip:Display(tunit or unit, status, extraID, tframe or frame, indicator.dbx.tooltipAnchor)
				tooltipIndicatorFrame = frame
				return true
			elseif tooltipIndicatorFrame then
				Tooltip:Hide()
				OnFrameEnter(tooltipFrame)
				return false
			end
		end
	end
end

function Grid2.indicatorPrototype:EnableFrameTooltips(frame, enabled)
	enabled = not not enabled
	frame.tooltipIndicator = enabled and self or nil
	frame:EnableMouse(enabled)
	if frame.SetPropagateMouseMotion then frame:SetPropagateMouseMotion(enabled) end
	if frame.SetPropagateMouseClicks then frame:SetPropagateMouseClicks(enabled) end
	if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
	frame:SetScript("OnEnter", enabled and OnFrameIndicatorEnter or nil)
	frame:SetScript("OnLeave", enabled and OnFrameIndicatorLeave or nil)
	if enabled then
		Tooltip:SetMouseHooks(true)
		tooltipIndicatorEnabled = enabled
	end
end

-- tooltip for indicator frames
function OnFrameIndicatorEnter(frame)
	if ShowFrameTooltip(frame) then
		RefreshFrameTooltip:Play()
	end
end

function OnFrameIndicatorLeave(frame)
	if tooltipDisplayed then
		Tooltip:Hide()
		OnFrameEnter(tooltipFrame)
	end
end

-- tooltip for the whole unit frame
function OnFrameEnter(frame)
	if frame then
		local unit = frame.unit
		if unit then
			if tooltipOOC and not InCombatLockdown() then
				Tooltip:Display(unit, Tooltip)
			elseif tooltipCheck() then
				local status = Tooltip:GetCurrentStatus(unit, frame)
				if status or tooltipDefault then
					Tooltip:Display(unit, status or Tooltip)
				end
			end
		end
	end
	tooltipFrame, tooltipIndicatorFrame = frame, nil
end

function OnFrameLeave()
	if tooltipDisplayed then
		Tooltip:Hide()
		tooltipFrame = nil
	end
end

-- Tooltip indicator methods
function Tooltip:GetTooltip(unit, tip)
	tip:SetUnit(unit) -- Special case to get unit info without linking "name" status to the indicator
end

function Tooltip:Display(unit, status, extraID, owner, anchor)
	if anchor and owner then
		GameTooltip:SetOwner(owner, anchor)
	elseif self.dbx.tooltipAnchor and tooltipOwner then
		GameTooltip:SetOwner(tooltipOwner, self.dbx.tooltipAnchor)
	else
		GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
	end
	status:GetTooltip(unit, GameTooltip, extraID)
	GameTooltip:Show()
	tooltipDisplayed = true
end

function Tooltip:Hide()
	GameTooltip:Hide()
	tooltipDisplayed = nil
end

function Tooltip:OnUpdate(parent, unit, status)
	if parent == tooltipFrame then
		if status then
			OnFrameEnter(parent)
		elseif tooltipDisplayed then
			Tooltip:Hide()
		end
	end
end

function Tooltip:SetMouseHooks(flag)
	if flag ~= tooltipHookEnabled and (flag or not tooltipIndicatorEnabled) then -- if another indicator has tooltips we cannot disable the unit frame event hook
		-- 3.3.5: no Grid2Frame:SetEventHook, hook the frame enter/leave methods once
		if flag and not hooksInstalled and Grid2Frame and Grid2Frame.OnFrameEnter then
			hooksecurefunc(Grid2Frame, "OnFrameEnter", function(_, frame)
				if tooltipHookEnabled then OnFrameEnter(frame) end
			end)
			hooksecurefunc(Grid2Frame, "OnFrameLeave", function()
				if tooltipHookEnabled then OnFrameLeave() end
			end)
			hooksInstalled = true
		end
		tooltipHookEnabled = flag
	end
end

function Tooltip:OnSuspend()
	self:SetMouseHooks(false)
end

function Tooltip:UpdateDB()
	local dbx  = self.dbx
	tooltipOOC = dbx.displayUnitOOC
	tooltipDefault = dbx.showDefault
	tooltipCheck = TooltipCheck[dbx.showTooltip or 4]
	tooltipOwner = Grid2Layout and Grid2Layout.frame and Grid2Layout.frame.frameBack or nil
	self:SetMouseHooks(dbx.showTooltip ~= 1)
end

local function Create(indicatorKey, dbx)
	Tooltip.dbx = dbx
	Grid2:RegisterIndicator(Tooltip, { "tooltip" })
	return Tooltip
end

Grid2.setupFunc["tooltip"] = Create
