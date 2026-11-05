if isClient() then return end

require "PGP/PGP_Barrels"

local B = PGP.Barrels

local function ensure(obj)
    if B.isBarrelObject(obj) then B.ensureContainer(obj) end
end

-- A callback registered for the same sprite at the same priority replaces the earlier one.
local PRIORITY = 4217
MapObjects.OnNewWithSprite(B.spriteNames(), ensure, PRIORITY)
MapObjects.OnLoadWithSprite(B.spriteNames(), ensure, PRIORITY)

-- Barrels placed as furniture were already sent to clients without the container.
Events.OnObjectAdded.Add(function(obj)
    if not B.isBarrelObject(obj) or B.fluidContainer(obj) then return end
    B.ensureContainer(obj)
    if isServer() then obj:sync() end
end)
