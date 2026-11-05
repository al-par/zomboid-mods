require "TimedActions/ISBaseTimedAction"
require "PGP/PGP_Barrels"

-- Puts a carried barrel into a big empty trunk, whatever it weighs.
PGP_LoadBarrelAction = ISBaseTimedAction:derive("PGP_LoadBarrelAction")

-- The item may have been re-sent by the server since the action was queued.
function PGP_LoadBarrelAction:findItem()
	local found = self.character:getInventory():getItemWithID(self.item:getID())
	if found then self.item = found end
	return found ~= nil
end

function PGP_LoadBarrelAction:isValid()
	return self:findItem() and PGP.Barrels.trunkReason(self.character, self.container) == nil
end

function PGP_LoadBarrelAction:waitToStart()
	self.character:faceThisObject(self.container:getVehiclePart():getVehicle())
	return self.character:shouldBeTurning()
end

function PGP_LoadBarrelAction:update()
	self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function PGP_LoadBarrelAction:start()
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Mid")
	self.character:reportEvent("EventLootItem")
end

function PGP_LoadBarrelAction:stop()
	ISBaseTimedAction.stop(self)
end

function PGP_LoadBarrelAction:perform()
	ISBaseTimedAction.perform(self)
end

function PGP_LoadBarrelAction:complete()
	if not self:findItem() then return false end
	if PGP.Barrels.trunkReason(self.character, self.container) then return false end
	local inv = self.character:getInventory()
	self.character:removeFromHands(self.item)
	inv:Remove(self.item)
	sendRemoveItemFromContainer(inv, self.item)
	self.container:AddItem(self.item)
	sendAddItemToContainer(self.container, self.item)
	self.container:getVehiclePart():setContainerContentAmount(self.container:getCapacityWeight())
	sendEquip(self.character)
	return true
end

function PGP_LoadBarrelAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	return 100
end

function PGP_LoadBarrelAction:new(character, item, container)
	local o = ISBaseTimedAction.new(self, character)
	o.item = item
	o.container = container
	o.maxTime = o:getDuration()
	return o
end
