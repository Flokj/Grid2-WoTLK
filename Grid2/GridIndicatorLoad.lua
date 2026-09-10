-- Implements indicator load filter

local Grid2 = Grid2
local indicatorPrototype = Grid2.indicatorPrototype

function indicatorPrototype:CanCreate(parent)
	local load = self.load
	return not ( load and (
		( load.unitType    and not load.unitType[ parent:GetParent().headerName ] ) or
		-- 3.3.5 backport: read the class live instead of a file-load upvalue,
		-- which would freeze the value (or nil) depending on module load order.
		( load.playerClass and not load.playerClass[ Grid2.playerClass ] )
	) )
end

-- If a Load filter is setup for an indicator, the default Update() function is
-- wrapped to check the filter on every refresh: excluded indicators hide their
-- frame instead of updating. Called from Grid2:RegisterIndicator() in
-- GridIndicator.lua and re-applied by MakeIndicatorLoadOptions() options.
-- 3.3.5 backport: this core has no per-frame Create/Release (frames live at
-- parent[name]), so filtering happens inside Update rather than at creation.
function indicatorPrototype:UpdateFilter()
	self.load = self.dbx and self.dbx.load
	if self.load and not self.parentName then
		if not self.UpdateF then
			local base = self.UpdateO or self.Update
			self.UpdateF = base
			self.Update = function(ind, parent, unit)
				if ind:CanCreate(parent) then
					return base(ind, parent, unit)
				end
				local f = parent[ind.name]
				if f then f:Hide() end
			end
		end
	elseif self.UpdateF then
		self.Update, self.UpdateF = self.UpdateF, nil
	end
end
