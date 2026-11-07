require "BuildingObjects/ISBuildingObject"
require "PGP/PGP_Barrels"

-- Ghost of the carried barrel; click a square to put it down exactly there. Rotate Building turns it.
PGP_BarrelCursor = ISBuildingObject:derive("PGP_BarrelCursor")

local B = PGP.Barrels

-- The item may have been re-sent by the server since the cursor opened.
function PGP_BarrelCursor:isHeld()
	local id = self.item:getID()
	local held = self.character:getPrimaryHandItem()
	if not held or held:getID() ~= id then held = self.character:getSecondaryHandItem() end
	if held and held:getID() == id then
		self.item = held
		return true
	end
	return false
end

function PGP_BarrelCursor:isValid(square)
	if not square or not self:isHeld() then return false end
	if square:getZ() ~= math.floor(self.character:getZ()) then return false end
	return B.isFreeSquare(square, self.character)
end

-- Standing on the chosen square: step off it first.
function PGP_BarrelCursor:walkTo(x, y, z)
	local square = getCell():getGridSquare(x, y, z)
	if not square then return false end
	if square == self.character:getCurrentSquare() then
		local adjacent = AdjacentFreeTileFinder.Find(square, self.character)
		if not adjacent then return false end
		ISTimedActionQueue.add(ISWalkToTimedAction:new(self.character, adjacent))
		return true
	end
	return luautils.walkAdj(self.character, square, true)
end

function PGP_BarrelCursor:create(x, y, z, north, sprite)
	local square = getCell():getGridSquare(x, y, z)
	if not square or not self:isHeld() then return end
	ISTimedActionQueue.add(PGP_PutDownBarrelAction:new(self.character, self.item, square, sprite))
end

function PGP_BarrelCursor:getAPrompt()
	return getText("ContextMenu_PGP_PutDownBarrel", self.item:getDisplayName())
end

function PGP_BarrelCursor:getLBPrompt()
	return nil
end

function PGP_BarrelCursor:getRBPrompt()
	return nil
end

function PGP_BarrelCursor:new(character, item)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o:init()
	o.character = character
	o.item = item
	o.player = character:getPlayerNum()
	o.skipBuildAction = true
	o.noNeedHammer = true
	o.dragNilAfterPlace = true
	local current = B.itemSprite(item)
	local facings = B.facingsOf(current)
	o:setSprite(facings[1])
	o:setNorthSprite(facings[2] or facings[1])
	o.nSprite = current == facings[2] and 2 or 1
	return o
end
