require "TimedActions/ISBaseTimedAction"
require "PGP/PGP_Barrels"

-- Takes a standing barrel (or one lying loose on the floor) into both hands.
PGP_PickUpBarrelAction = ISBaseTimedAction:derive("PGP_PickUpBarrelAction")

local function isBarrel(obj)
	return PGP.Barrels.isBarrelObject(obj) or PGP.Barrels.isLooseBarrel(obj)
end

local function inReach(character, sq)
	if sq:getZ() ~= math.floor(character:getZ()) then return false end
	local dx = sq:getX() + 0.5 - character:getX()
	local dy = sq:getY() + 0.5 - character:getY()
	return dx * dx + dy * dy <= 6.5
end

function PGP_PickUpBarrelAction:isValid()
	local sq = self.barrel:getSquare()
	return sq ~= nil and self.barrel:getObjectIndex() ~= -1 and isBarrel(self.barrel) and inReach(self.character, sq)
end

function PGP_PickUpBarrelAction:waitToStart()
	self.character:faceThisObject(self.barrel)
	return self.character:shouldBeTurning()
end

function PGP_PickUpBarrelAction:update()
	self.character:faceThisObject(self.barrel)
	self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function PGP_PickUpBarrelAction:start()
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Low")
	self.character:reportEvent("EventLootItem")
end

function PGP_PickUpBarrelAction:stop()
	ISBaseTimedAction.stop(self)
end

function PGP_PickUpBarrelAction:perform()
	ISBaseTimedAction.perform(self)
end

function PGP_PickUpBarrelAction:complete()
	if self.barrel:getObjectIndex() == -1 or not isBarrel(self.barrel) then return false end
	return PGP.Barrels.takeBarrel(self.character, self.barrel)
end

function PGP_PickUpBarrelAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	return 100
end

function PGP_PickUpBarrelAction:new(character, barrel)
	local o = ISBaseTimedAction.new(self, character)
	o.barrel = barrel
	o.maxTime = o:getDuration()
	return o
end
