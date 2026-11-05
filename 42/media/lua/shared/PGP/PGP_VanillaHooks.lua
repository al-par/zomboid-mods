-- Vanilla "Connect Generator" starts a new pool, "Disconnect" leaves it, and turning a generator
-- on or off updates the pool's running state.
require "TimedActions/ISPlugGenerator"
require "TimedActions/ISActivateGenerator"
require "PGP/PGP_Core"

local plugIsValid = ISPlugGenerator.isValid
function ISPlugGenerator:isValid()
	if not plugIsValid(self) then return false end
	if self.plug and not PGP.checkConnect(self.generator) then return false end
	return true
end

local plugComplete = ISPlugGenerator.complete
function ISPlugGenerator:complete()
	local result = plugComplete(self)
	if PGP.Server then
		if self.plug then
			PGP.Server.createPool(self.generator)
		else
			PGP.Server.removeGenerator(self.generator)
		end
	end
	return result
end

local activateComplete = ISActivateGenerator.complete
function ISActivateGenerator:complete()
	local result = activateComplete(self)
	if PGP.Server then PGP.Server.onActivated(self.generator) end
	return result
end
