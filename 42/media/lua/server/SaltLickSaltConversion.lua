if isClient() then return end

-- Existing saves can hold vanilla moveable salt licks, and brine cooked under 1.0 stayed brine
-- instead of turning into a Pot of Salt. Swap both for the current items once a player carries them.
local SALT_LICK_TYPES = { Mov_SaltLick = "Base.SLS_SaltLick" }
local BRINE_TYPES = {
    SLS_PotOfBrine = "Base.SLS_PotOfSalt",
    SLS_PotForgedOfBrine = "Base.SLS_PotForgedOfSalt",
}

local function replaceItem(player, item, newType)
    local container = item:getContainer()
    if not container then return end
    player:removeFromHands(item)
    container:Remove(item)
    sendRemoveItemFromContainer(container, item)
    local newItem = container:AddItem(newType)
    if newItem then
        sendAddItemToContainer(container, newItem)
    end
end

local function convertInventory(player)
    local inv = player:getInventory()
    for oldType, newType in pairs(SALT_LICK_TYPES) do
        local items = inv:getAllTypeRecurse(oldType)
        for i = items:size() - 1, 0, -1 do
            replaceItem(player, items:get(i), newType)
        end
    end
    for oldType, newType in pairs(BRINE_TYPES) do
        local items = inv:getAllTypeRecurse(oldType)
        for i = items:size() - 1, 0, -1 do
            local item = items:get(i)
            if item:isCooked() or item:isBurnt() then
                replaceItem(player, item, newType)
            end
        end
    end
end

Events.EveryOneMinute.Add(function()
    local players = getOnlinePlayers()
    local last = isServer() and players:size() - 1 or getNumActivePlayers() - 1
    for i = 0, last do
        local player = isServer() and players:get(i) or getSpecificPlayer(i)
        if player and not player:isDead() then
            convertInventory(player)
        end
    end
end)
