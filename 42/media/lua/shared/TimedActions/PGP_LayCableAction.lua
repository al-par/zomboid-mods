require "TimedActions/ISBaseTimedAction"
require "PGP/PGP_Core"

PGP_LayCableAction = ISBaseTimedAction:derive("PGP_LayCableAction")

function PGP_LayCableAction:isValid()
	return self.square ~= nil and
		PGP.isCableItem(self.item) and
		self.character:getInventory():containsRecursive(self.item) and
		PGP.checkCable(self.square:getX(), self.square:getY(), self.square:getZ()) ~= nil
end

function PGP_LayCableAction:waitToStart()
	self.character:faceLocation(self.square:getX(), self.square:getY())
	return self.character:shouldBeTurning()
end

function PGP_LayCableAction:update()
	self.character:faceLocation(self.square:getX(), self.square:getY())
end

function PGP_LayCableAction:start()
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Low")
	self.character:reportEvent("EventLootItem")
end

function PGP_LayCableAction:stop()
	ISBaseTimedAction.stop(self)
end

function PGP_LayCableAction:perform()
	ISBaseTimedAction.perform(self)
end

function PGP_LayCableAction:complete()
	if not PGP.checkCable(self.square:getX(), self.square:getY(), self.square:getZ()) then return false end
	local container = self.item:getContainer()
	if not container then return false end
	self.character:removeFromHands(self.item)
	container:Remove(self.item)
	sendRemoveItemFromContainer(container, self.item)
	if PGP.Server then PGP.Server.placeCable(self.square, self.item:getFullType()) end
	return true
end

function PGP_LayCableAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	return 60
end

function PGP_LayCableAction:new(character, item, square)
	local o = ISBaseTimedAction.new(self, character)
	o.item = item
	o.square = square
	o.maxTime = o:getDuration()
	return o
end
