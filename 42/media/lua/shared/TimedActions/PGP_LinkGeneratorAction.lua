require "TimedActions/ISBaseTimedAction"
require "PGP/PGP_Core"

PGP_LinkGeneratorAction = ISBaseTimedAction:derive("PGP_LinkGeneratorAction")

PGP_LinkGeneratorAction.MATERIALS = { "ElectricWire", "ElectronicsScrap" }

function PGP_LinkGeneratorAction.canOperate(character)
	return character:getPerkLevel(Perks.Electricity) >= 3 or character:isRecipeActuallyKnown("Generator")
end

function PGP_LinkGeneratorAction.hasMaterials(character)
	local inv = character:getInventory()
	for _, itemType in ipairs(PGP_LinkGeneratorAction.MATERIALS) do
		if not inv:containsTypeRecurse(itemType) then return false end
	end
	return true
end

function PGP_LinkGeneratorAction:isValid()
	return self.generator:getObjectIndex() ~= -1 and
		PGP.checkLink(self.generator) ~= nil and
		PGP_LinkGeneratorAction.canOperate(self.character) and
		PGP_LinkGeneratorAction.hasMaterials(self.character)
end

function PGP_LinkGeneratorAction:waitToStart()
	self.character:faceThisObject(self.generator)
	return self.character:shouldBeTurning()
end

function PGP_LinkGeneratorAction:update()
	self.character:faceThisObject(self.generator)
	self.character:setMetabolicTarget(Metabolics.UsingTools)
end

function PGP_LinkGeneratorAction:start()
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Low")
	self.character:reportEvent("EventLootItem")
	self.sound = self.character:playSound("GeneratorConnect")
end

function PGP_LinkGeneratorAction:stop()
	self.character:stopOrTriggerSound(self.sound)
	ISBaseTimedAction.stop(self)
end

function PGP_LinkGeneratorAction:perform()
	self.character:stopOrTriggerSound(self.sound)
	ISBaseTimedAction.perform(self)
end

function PGP_LinkGeneratorAction:complete()
	local pid = PGP.checkLink(self.generator)
	if not pid then return false end
	local inv = self.character:getInventory()
	local items = {}
	for _, itemType in ipairs(PGP_LinkGeneratorAction.MATERIALS) do
		local item = inv:getFirstTypeRecurse(itemType)
		if not item then return false end
		table.insert(items, item)
	end
	for _, item in ipairs(items) do
		local container = item:getContainer()
		self.character:removeFromHands(item)
		container:Remove(item)
		sendRemoveItemFromContainer(container, item)
	end
	self.generator:setConnected(true)
	if PGP.Server then PGP.Server.addMember(pid, self.generator) end
	addXp(self.character, Perks.Electricity, 5)
	return true
end

function PGP_LinkGeneratorAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	return 250 - (self.character:getPerkLevel(Perks.Electricity) * 5)
end

function PGP_LinkGeneratorAction:new(character, generator)
	local o = ISBaseTimedAction.new(self, character)
	o.generator = generator
	o.maxTime = o:getDuration()
	return o
end
