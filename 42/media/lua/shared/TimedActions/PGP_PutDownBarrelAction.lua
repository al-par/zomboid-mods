require "TimedActions/ISBaseTimedAction"
require "PGP/PGP_Barrels"

-- Letting go of a barrel takes no time. With a square it goes exactly there (or not at all);
-- without one it goes on the free square in front of the character.
PGP_PutDownBarrelAction = ISBaseTimedAction:derive("PGP_PutDownBarrelAction")

-- The item may have been re-sent by the server since the action was queued.
function PGP_PutDownBarrelAction:findItem()
	local found = self.character:getInventory():getItemWithID(self.item:getID())
	if found then self.item = found end
	return found ~= nil
end

function PGP_PutDownBarrelAction:isValid()
	if not self:findItem() then return false end
	if self.square then return PGP.Barrels.canPlaceFrom(self.character, self.square) end
	return PGP.Barrels.findPlaceSquare(self.character, nil) ~= nil
end

function PGP_PutDownBarrelAction:waitToStart()
	if self.square then self.character:faceLocation(self.square:getX(), self.square:getY()) end
	return false
end

function PGP_PutDownBarrelAction:update()
end

function PGP_PutDownBarrelAction:start()
end

function PGP_PutDownBarrelAction:stop()
	ISBaseTimedAction.stop(self)
end

function PGP_PutDownBarrelAction:perform()
	ISBaseTimedAction.perform(self)
end

function PGP_PutDownBarrelAction:complete()
	if not self:findItem() then return false end
	return PGP.Barrels.putDown(self.character, self.item, self.square, self.spriteName)
end

function PGP_PutDownBarrelAction:getDuration()
	return 1
end

function PGP_PutDownBarrelAction:new(character, item, square, spriteName)
	local o = ISBaseTimedAction.new(self, character)
	o.item = item
	o.square = square
	o.spriteName = spriteName
	o.stopOnWalk = false
	o.stopOnRun = false
	o.maxTime = o:getDuration()
	return o
end
