require "TimedActions/ISBaseTimedAction"
require "PGP/PGP_Barrels"

-- Pumps petrol into a barrel standing near the pump, at the vanilla jerry can rate.
PGP_FillBarrelAction = ISBaseTimedAction:derive("PGP_FillBarrelAction")

local function barrelAmount(barrel)
	local fc = PGP.Barrels.fluidContainer(barrel)
	return fc and fc:getAmount() or 0
end

local function inReach(character, sq)
	if sq:getZ() ~= math.floor(character:getZ()) then return false end
	local dx = sq:getX() + 0.5 - character:getX()
	local dy = sq:getY() + 0.5 - character:getY()
	return dx * dx + dy * dy <= 6.5
end

function PGP_FillBarrelAction:isValid()
	if self.barrel:getObjectIndex() == -1 or self.pump:getObjectIndex() == -1 then return false end
	if self.pump:getPipedFuelAmount() <= 0 or not PGP.Barrels.pumpPowered(self.pump) then return false end
	return inReach(self.character, self.pump:getSquare()) and PGP.Barrels.petrolSpace(self.barrel) > 0
end

function PGP_FillBarrelAction:waitToStart()
	self.character:faceThisObject(self.pump)
	return self.character:shouldBeTurning()
end

function PGP_FillBarrelAction:update()
	self.character:faceThisObject(self.pump)
	self.character:setMetabolicTarget(Metabolics.LightWork)
	if not isClient() then
		self:updateUse(self:getJobDelta())
	end
end

-- Moves whole litres from the pump into the barrel, up to the share of the job done so far.
function PGP_FillBarrelAction:updateUse(delta)
	if self.barrel:getObjectIndex() == -1 then return end
	local fc = PGP.Barrels.ensureContainer(self.barrel)
	local target = math.min(math.floor(self.amount * delta + 0.001) + self.barrelStart, self.barrelTarget)
	local before = fc:getAmount()
	if target <= before then return end
	local pumpCurrent = tonumber(self.pump:getPipedFuelAmount()) or 0
	local want = math.min(target - before, pumpCurrent)
	if want <= 0 then return end
	fc:addFluid(Fluid.Petrol, want)
	local added = fc:getAmount() - before
	if added <= 0 then return end
	self.pump:setPipedFuelAmount(pumpCurrent - added)
	if isServer() then self.barrel:sync() end
end

function PGP_FillBarrelAction:start()
	self:setActionAnim("TakeGasFromPump")
	self:setOverrideHandModels(nil, nil)
	self.sound = self.character:playSound("CanisterAddFuelFromGasPump")
end

function PGP_FillBarrelAction:stop()
	self.character:stopOrTriggerSound(self.sound)
	ISBaseTimedAction.stop(self)
end

function PGP_FillBarrelAction:perform()
	self.character:stopOrTriggerSound(self.sound)
	ISBaseTimedAction.perform(self)
end

function PGP_FillBarrelAction:complete()
	if self.barrel:getObjectIndex() == -1 then return false end
	self:updateUse(1)
	return true
end

function PGP_FillBarrelAction:serverStart()
	emulateAnimEvent(self.netAction, 100, "pgpFill", nil)
end

function PGP_FillBarrelAction:animEvent(event, parameter)
	if isServer() and event == "pgpFill" then
		self:updateUse(self.netAction:getProgress())
	end
end

function PGP_FillBarrelAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	return math.max(1, self.amount * 50)
end

function PGP_FillBarrelAction:new(character, pump, barrel)
	local o = ISBaseTimedAction.new(self, character)
	o.pump = pump
	o.barrel = barrel
	local space = PGP.Barrels.petrolSpace(barrel)
	o.barrelStart = barrelAmount(barrel)
	o.amount = math.floor(math.min(tonumber(pump:getPipedFuelAmount()) or 0, space))
	o.barrelTarget = o.barrelStart + o.amount
	o.maxTime = o:getDuration()
	return o
end
