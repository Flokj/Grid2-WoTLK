local Status = Grid2.statusPrototype:new("unit-index")

local Grid2 = Grid2

local tostring = tostring
local tonumber = tonumber
local empty = {}

-- 3.3.5: roster has no party_indexes/grouped_units tables and no GetGroupType(),
-- the index is derived from the unit id: player=>0, partyN=>N, raidN=>N (pets share owner index).
local function UnitIndex(unit)
	if unit == 'player' or unit == 'pet' then
		return 0
	end
	local n = unit:match('^party(%d+)$') or unit:match('^raid(%d+)$')
	if n then return tonumber(n) end
	n = unit:match('^partypet(%d+)$') or unit:match('^raidpet(%d+)$')
	if n then return tonumber(n) end
end

local party_units = setmetatable( {}, { __index = function(_, unit)
	if unit == 'player' or unit == 'pet' then
		return 0
	end
	local n = unit:match('^party(%d+)$') or unit:match('^partypet(%d+)$')
	return n and tonumber(n) or nil
end } )

local all_units = setmetatable( {}, { __index = function(_, unit)
	return UnitIndex(unit)
end } )

local valid_units = empty

function Status:GetText(unit)
	return tostring( valid_units[unit] )
end

local function IsActive1(self, unit)
	return valid_units[unit]~=nil
end

local function IsActive2(self, unit)
	return unit~='player' and valid_units[unit]~=nil
end

function Status:Grid_GroupTypeChanged()
	self:UpdateDB()
end

function Status:OnEnable()
	self:RegisterMessage("Grid_GroupTypeChanged")
end

function Status:OnDisable()
	self:UnregisterMessage("Grid_GroupTypeChanged")
end

function Status:UpdateDB()
	self.IsActive =	self.dbx.playerUnit and IsActive1 or IsActive2
	valid_units = ( (Grid2.groupType or 'solo')=='solo' and empty) or (self.dbx.partyUnits and party_units) or all_units -- 3.3.5: no GetGroupType()/party_indexes/grouped_units, index derived from unit id
end

Grid2.setupFunc["unit-index"] = function(baseKey, dbx)
	Grid2:RegisterStatus(Status, {"text"}, baseKey, dbx)
	return Status
end

Grid2:DbSetStatusDefaultValue( "unit-index", {type = "unit-index"})
