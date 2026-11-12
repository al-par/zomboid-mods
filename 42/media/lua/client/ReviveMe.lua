-- The Java side lets a dead main player load, heals him and sets modData.ReviveMePendingGear.
--
-- Most players install this after they died, so only what vanilla saves can identify the remains:
-- a player's corpse keeps his SurvivorDesc (name); a reanimated corpse becomes a zombie with a blank
-- descriptor but isReanimatedPlayer() and a copy of his HumanVisual, kept in reanimated.bin.
-- Items in hand drop to the floor on death and aren't collected.

if not ZombieBuddy then
    print("[ReviveMe] ZombieBuddy isn't running; dead characters can't be loaded")
end

local CORPSE_RADIUS = 10
local SCAN_INTERVAL = 30
local GIVE_UP_TICKS = 3600

local tickCount = 0

local function sameName(a, b)
    return a and b and a:getForename() == b:getForename() and a:getSurname() == b:getSurname()
end

local function looksLike(zombie, player)
    local zv, pv = zombie:getHumanVisual(), player:getHumanVisual()
    return zombie:isFemale() == player:isFemale()
        and zv:getSkinTextureIndex() == pv:getSkinTextureIndex()
        and zv:getHairModel() == pv:getHairModel()
        and zv:getBeardModel() == pv:getBeardModel()
end

local function findOwnCorpse(player)
    local desc = player:getDescriptor()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local cell = getCell()
    for dx = -CORPSE_RADIUS, CORPSE_RADIUS do
        for dy = -CORPSE_RADIUS, CORPSE_RADIUS do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local objects = sq:getStaticMovingObjects()
                for i = 0, objects:size() - 1 do
                    local body = objects:get(i)
                    if instanceof(body, "IsoDeadBody") and not body:isAnimal() and sameName(body:getDescriptor(), desc) then
                        return body
                    end
                end
            end
        end
    end
    return nil
end

local function findOwnZombie(player)
    local objects = getCell():getObjectListForLua()
    for i = 0, objects:size() - 1 do
        local zombie = objects:get(i)
        if instanceof(zombie, "IsoZombie") and zombie:isReanimatedPlayer() and not zombie:isDead() and looksLike(zombie, player) then
            return zombie
        end
    end
    return nil
end

local function takeGear(player, source)
    local worn = {}
    local wornItems = source:getWornItems()
    for i = 0, wornItems:size() - 1 do
        local wornItem = wornItems:get(i)
        table.insert(worn, { location = wornItem:getLocation(), item = wornItem:getItem() })
    end
    local attached = {}
    local attachedItems = source:getAttachedItems()
    for i = 0, attachedItems:size() - 1 do
        local attachedItem = attachedItems:get(i)
        table.insert(attached, { location = attachedItem:getLocation(), item = attachedItem:getItem() })
    end

    local src = instanceof(source, "IsoDeadBody") and source:getContainer() or source:getInventory()
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

    if instanceof(source, "IsoDeadBody") then
        source:getSquare():removeCorpse(source, false)
    else
        source:removeFromWorld()
        source:removeFromSquare()
    end

    player:resetModel()
    getPlayerInventory(player:getPlayerNum()):refreshBackpacks()
    local hotbar = getPlayerHotbar(player:getPlayerNum())
    if hotbar then hotbar.needsRefresh = true end
    triggerEvent("OnClothingUpdated", player)

    print("[ReviveMe] took back " .. #items .. " items (" .. #worn .. " worn, " .. #attached .. " attached) from the "
        .. (instanceof(source, "IsoDeadBody") and "corpse" or "zombie"))
end

local function onTick()
    tickCount = tickCount + 1
    if tickCount % SCAN_INTERVAL ~= 0 then return end
    local player = getPlayer()
    if not player then return end
    local modData = player:getModData()
    if not modData.ReviveMePendingGear then
        Events.OnTick.Remove(onTick)
        return
    end
    local source = findOwnCorpse(player) or findOwnZombie(player)
    if source then
        takeGear(player, source)
        modData.ReviveMePendingGear = nil
        Events.OnTick.Remove(onTick)
    elseif tickCount >= GIVE_UP_TICKS then
        print("[ReviveMe] found no corpse or zombie of " .. player:getDescriptor():getForename() .. " "
            .. player:getDescriptor():getSurname() .. "; gear not restored")
        modData.ReviveMePendingGear = nil
        Events.OnTick.Remove(onTick)
    end
end

local function onCreatePlayer(playerIndex, player)
    local modData = player:getModData()
    print("[ReviveMe] player " .. playerIndex .. " created, pendingGear=" .. tostring(modData.ReviveMePendingGear))
    if modData.ReviveMePendingGear then
        tickCount = 0
        Events.OnTick.Add(onTick)
    end
end

Events.OnCreatePlayer.Add(onCreatePlayer)
