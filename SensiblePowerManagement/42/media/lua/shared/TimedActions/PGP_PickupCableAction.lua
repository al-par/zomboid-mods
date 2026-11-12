require "TimedActions/ISBaseTimedAction"
require "PGP/PGP_Core"

PGP_PickupCableAction = ISBaseTimedAction:derive("PGP_PickupCableAction")

function PGP_PickupCableAction:isValid()
	return self.cable:getObjectIndex() ~= -1
end

function PGP_PickupCableAction:waitToStart()
	self.character:faceThisObject(self.cable)
	return self.character:shouldBeTurning()
end

function PGP_PickupCableAction:update()
	self.character:faceThisObject(self.cable)
end

function PGP_PickupCableAction:start()
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Low")
	self.character:reportEvent("EventLootItem")
end

function PGP_PickupCableAction:stop()
	ISBaseTimedAction.stop(self)
end

function PGP_PickupCableAction:perform()
	ISBaseTimedAction.perform(self)
end

-- A picked-up makeshift cable goes back onto a used one before starting a new one.
function PGP_PickupCableAction:findPartialCable(inv)
	local cables = inv:getAllTypeRecurse(PGP.CABLE_ITEM)
	for i = 0, cables:size() - 1 do
		local cable = cables:get(i)
		if PGP.cableUses(cable) < PGP.CABLE_USES then return cable end
	end
	return nil
end

function PGP_PickupCableAction:complete()
	local sq = self.cable:getSquare()
	if not sq then return false end
	local itemType = PGP.Server and PGP.Server.removeCable(sq, self.cable) or PGP.CABLE_ITEM
	local inv = self.character:getInventory()
	if itemType == PGP.CABLE_ITEM then
		local partial = self:findPartialCable(inv)
		if partial then
			PGP.setCableUses(partial, PGP.cableUses(partial) + 1)
			syncItemFields(self.character, partial)
			return true
		end
	end
	local item = inv:AddItem(itemType)
	if item then
		if itemType == PGP.CABLE_ITEM then PGP.setCableUses(item, 1) end
		sendAddItemToContainer(inv, item)
	end
	return true
end

function PGP_PickupCableAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	return 50
end

function PGP_PickupCableAction:new(character, cable)
	local o = ISBaseTimedAction.new(self, character)
	o.cable = cable
	o.maxTime = o:getDuration()
	return o
end
