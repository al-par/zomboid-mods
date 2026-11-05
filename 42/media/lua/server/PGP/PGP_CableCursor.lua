require "BuildingObjects/ISBuildingObject"
require "PGP/PGP_Core"

PGP_CableCursor = ISBuildingObject:derive("PGP_CableCursor")

function PGP_CableCursor:findCable()
	return self.character:getInventory():getFirstTypeRecurse(self.itemType)
end

function PGP_CableCursor:isValid(square)
	if not square or not self:findCable() then return false end
	if not square:getFloor() or square:isSolid() or square:isSolidTrans() then return false end
	return PGP.checkCable(square:getX(), square:getY(), square:getZ()) ~= nil
end

function PGP_CableCursor:render(x, y, z, square)
	local name = PGP.cableSpriteName(PGP.cableMask(x, y, z))
	if not self.RENDER_SPRITE then
		self.RENDER_SPRITE = IsoSprite.new()
	end
	if self.RENDER_SPRITE_NAME ~= name then
		self.RENDER_SPRITE:LoadSingleTexture(name)
		self.RENDER_SPRITE_NAME = name
	end
	if self:isValid(square) then
		self.RENDER_SPRITE:RenderGhostTile(x, y, z)
	else
		self.RENDER_SPRITE:RenderGhostTileRed(x, y, z)
	end
end

function PGP_CableCursor:walkTo(x, y, z)
	local square = getCell():getGridSquare(x, y, z)
	return square ~= nil and luautils.walkAdj(self.character, square, true)
end

function PGP_CableCursor:create(x, y, z, north, sprite)
	local square = getCell():getGridSquare(x, y, z)
	local item = self:findCable()
	if not square or not item then return end
	local inv = self.character:getInventory()
	if luautils.haveToBeTransfered(self.character, item) then
		ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(self.character, item, item:getContainer(), inv))
	end
	ISTimedActionQueue.add(PGP_LayCableAction:new(self.character, item, square))
end

function PGP_CableCursor:getAPrompt()
	return getText("ContextMenu_PGP_LayCable")
end

function PGP_CableCursor:getLBPrompt()
	return nil
end

function PGP_CableCursor:getRBPrompt()
	return nil
end

function PGP_CableCursor:new(character, item)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o:init()
	o.character = character
	o.itemType = item:getType()
	o.player = character:getPlayerNum()
	o.skipBuildAction = true
	o.noNeedHammer = true
	o:setSprite(PGP.cableSpriteName(0))
	o:setNorthSprite(PGP.cableSpriteName(0))
	return o
end
