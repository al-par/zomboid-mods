if isClient() then return end

local BOW = "Base.CA_Bow"
local ARROW = "Base.CA_Arrow"
local RECOVER_PERCENT = 70

-- The arrow stays in the zombie; it only reaches the corpse if this zombie dies before unloading.
local function onHitZombie(zombie, attacker, bodyPart, weapon)
    if not weapon or weapon:getFullType() ~= BOW then return end
    if ZombRand(100) >= RECOVER_PERCENT then return end
    zombie:addItemToSpawnAtDeath(instanceItem(ARROW))
end

Events.OnHitZombie.Add(onHitZombie)
