require "TimedActions/ISBaseTimedAction"
require "PGP/PGP_Core"

PGP_PlumbGeneratorAction = ISBaseTimedAction:derive("PGP_PlumbGeneratorAction")

function PGP_PlumbGeneratorAction:isValid()
	return self.generator:getObjectIndex() ~= -1 and
		not PGP.isPlumbed(self.generator) and
		self.character:isEquipped(self.wrench)
end

function PGP_PlumbGeneratorAction:waitToStart()
	self.character:faceThisObject(self.generator)
	return self.character:shouldBeTurning()
end

function PGP_PlumbGeneratorAction:update()
	self.character:faceThisObject(self.generator)
	self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function PGP_PlumbGeneratorAction:start()
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Low")
	self.sound = self.character:playSound("RepairWithWrench")
end

function PGP_PlumbGeneratorAction:stop()
	self.character:stopOrTriggerSound(self.sound)
	ISBaseTimedAction.stop(self)
end

function PGP_PlumbGeneratorAction:perform()
	self.character:stopOrTriggerSound(self.sound)
	ISBaseTimedAction.perform(self)
end

function PGP_PlumbGeneratorAction:complete()
	if self.generator:getObjectIndex() == -1 then return false end
	self.generator:getModData().pgpPlumbed = true
	self.generator:transmitModData()
	if PGP.Server then PGP.Server.onPlumbed(self.generator) end
	return true
end

function PGP_PlumbGeneratorAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	return 100
end

function PGP_PlumbGeneratorAction:new(character, generator, wrench)
	local o = ISBaseTimedAction.new(self, character)
	o.generator = generator
	o.wrench = wrench
	o.maxTime = o:getDuration()
	return o
end
