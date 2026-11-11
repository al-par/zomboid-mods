-- The Java side lets a dead main player load; PlayerDB.loadPlayer then sets his health to 0.
-- OnCreatePlayer fires from GameLoadingState.exit(), before the first update would kill him again.
--
-- On death the inventory, worn and attached items move to an IsoDeadBody at the death spot
-- (items in hand drop to the floor instead). The corpse keeps the SurvivorDesc, so match by name.

if not ZombieBuddy then
    print("[ReviveGil] ZombieBuddy isn't running; dead characters can't be loaded")
end

local SEARCH_RADIUS = 5
local SCAN_INTERVAL = 30
local GIVE_UP_TICKS = 3600

local tickCount = 0

local function findOwnCorpse(player)
    local desc = player:getDescriptor()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local cell = getCell()
    for dx = -SEARCH_RADIUS, SEARCH_RADIUS do
        for dy = -SEARCH_RADIUS, SEARCH_RADIUS do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local objects = sq:getStaticMovingObjects()
                for i = 0, objects:size() - 1 do
                    local body = objects:get(i)
                    if instanceof(body, "IsoDeadBody") and not body:isZombie() and not body:isAnimal() then
                        local bodyDesc = body:getDescriptor()
                        if bodyDesc and bodyDesc:getForename() == desc:getForename()
                                and bodyDesc:getSurname() == desc:getSurname() then
                            return body
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function takeGearFromCorpse(player, body)
    local worn = {}
    local wornItems = body:getWornItems()
    for i = 0, wornItems:size() - 1 do
        local wornItem = wornItems:get(i)
        table.insert(worn, { location = wornItem:getLocation(), item = wornItem:getItem() })
    end
    local attached = {}
    local attachedItems = body:getAttachedItems()
    for i = 0, attachedItems:size() - 1 do
        local attachedItem = attachedItems:get(i)
        table.insert(attached, { location = attachedItem:getLocation(), item = attachedItem:getItem() })
    end

    local src = body:getContainer()
    local dest = player:getInventory()
    local items = {}
    for i = 0, src:getItems():size() - 1 do
        table.insert(items, src:getItems():get(i))
    end
    for _, item in ipairs(items) do
        src:DoRemoveItem(item)
        dest:AddItem(item)
    end

    for _, entry in ipairs(worn) do
        player:setWornItem(entry.location, entry.item)
    end
    for _, entry in ipairs(attached) do
        player:setAttachedItem(entry.location, entry.item)
    end

    body:getSquare():removeCorpse(body, false)

    player:resetModel()
    getPlayerInventory(player:getPlayerNum()):refreshBackpacks()
    local hotbar = getPlayerHotbar(player:getPlayerNum())
    if hotbar then hotbar.needsRefresh = true end
    triggerEvent("OnClothingUpdated", player)

    print("[ReviveGil] took back " .. #items .. " items (" .. #worn .. " worn, " .. #attached .. " attached) from the corpse")
end

local function onTick()
    tickCount = tickCount + 1
    if tickCount % SCAN_INTERVAL ~= 0 then return end
    local player = getPlayer()
    if not player then return end
    local modData = player:getModData()
    if not modData.ReviveGilPendingGear then
        Events.OnTick.Remove(onTick)
        return
    end
    local body = findOwnCorpse(player)
    if body then
        takeGearFromCorpse(player, body)
        modData.ReviveGilPendingGear = nil
        Events.OnTick.Remove(onTick)
    elseif tickCount >= GIVE_UP_TICKS then
        print("[ReviveGil] no corpse named " .. player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname() .. " within " .. SEARCH_RADIUS .. " tiles; gear not restored")
        modData.ReviveGilPendingGear = nil
        Events.OnTick.Remove(onTick)
    end
end

local function onCreatePlayer(playerIndex, player)
    local modData = player:getModData()
    if player:isDead() then
        player:getBodyDamage():RestoreToFullHealth()
        player:setHealth(1.0)
        modData.ReviveGilPendingGear = true
        print("[ReviveGil] revived " .. player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname())
    end
    if modData.ReviveGilPendingGear then
        tickCount = 0
        Events.OnTick.Add(onTick)
    end
end

Events.OnCreatePlayer.Add(onCreatePlayer)
