require "HomeHeating/HH_Shared"

local HH = HomeHeating
HH.Build = HH.Build or {}
local Build = HH.Build

local function removeThumpable(thumpable)
    if thumpable:getSquare() ~= nil then
        thumpable:removeFromWorld()
        thumpable:removeFromSquare()
        thumpable:setSquare(nil)
    end
end

function HH.newContainer(obj, kind, capacity, acceptFn)
    local c = ItemContainer.new(kind, obj:getSquare(), obj)
    c:setCapacity(capacity)
    c:setExplored(true)
    if acceptFn then c:setAcceptItemFunction(acceptFn) end
    return c
end

-- One call per square of the hearth. The fire square becomes an IsoFireplace with the firewood box;
-- the others stay masonry thumpables. Masonry 7+ builds the neat look.
function Build.hearthOnCreate(params)
    local thumpable = params.thumpable
    local info = HH.parseHearthSprite(HH.spriteName(thumpable))
    if not info then return end
    local sq = thumpable:getSquare()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local character = params.character
    local quality = (character and character:getPerkLevel(Perks.Masonry) >= HH.NEAT_MASONRY) and "neat" or "rough"
    local sprite = HH.hearthSprite(info.design, info.material, quality, info.west, false, false, info.i)
    local function stamp(obj)
        local md = obj:getModData()
        md.hhDesign, md.hhMat, md.hhQ = info.design, info.material, quality
        md.hhI, md.hhWest, md.hhKit = info.i, info.west, false
        md.hhX = info.west and x or x - info.i
        md.hhY = info.west and y - info.i or y
    end
    if info.i ~= HH.DESIGNS[info.design].fire then
        thumpable:setSpriteFromName(sprite)
        stamp(thumpable)
        return
    end
    local fire = IsoFireplace.new(getCell(), sq, getSprite(sprite))
    stamp(fire)
    fire:setContainer(HH.newContainer(fire, HH.BIN_WOOD, HH.binCapacity(HH.BIN_WOOD), "HomeHeating_AcceptWood"))
    sq:AddTileObject(fire)
    removeThumpable(thumpable)
    if HH.World then HH.World.register(fire) end
    return { replaceObject = true, object = fire }
end

-- The sprite's ContainerCapacity gives the IsoFireplace its "woodstove" cooking container;
-- the charcoal bin goes in beside it.
function Build.coalOnCreate(params)
    local thumpable = params.thumpable
    local sq = thumpable:getSquare()
    local fire = IsoFireplace.new(getCell(), sq, getSprite(HH.spriteName(thumpable)))
    fire:getModData().hhKind = "coal"
    fire:addSecondaryContainer(HH.newContainer(fire, HH.BIN_COAL, HH.binCapacity(HH.BIN_COAL), "HomeHeating_AcceptCharcoal"))
    sq:AddTileObject(fire)
    removeThumpable(thumpable)
    if HH.World then HH.World.register(fire) end
    return { replaceObject = true, object = fire }
end

function Build.electricOnCreate(params)
    local thumpable = params.thumpable
    local md = thumpable:getModData()
    md.hhKind, md.hhOn = "electric", false
    if HH.World then HH.World.register(thumpable) end
end

local function bareHearthOn(sq, north)
    if not sq then return nil end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local o = objects:get(i)
        local md = HH.hearthPart(o)
        if md and not md.hhKit and md.hhWest == not north then return o, md end
    end
    return nil
end

-- The pot bar can only go onto a hearth along the same wall that doesn't have one yet.
function Build.potBarOnIsValid(params)
    if not bareHearthOn(params.square, params.north) then return false end
    params.testCollisions = false
    return true
end

function Build.potBarOnCreate(params)
    local thumpable = params.thumpable
    local sq = thumpable:getSquare()
    local part, md = bareHearthOn(sq, thumpable:getNorth())
    sq:transmitRemoveItemFromSquare(thumpable)
    if part then HH.attachPotBar(part, md) end
    return { objectAlreadyTransmitted = true }
end

function HH.attachPotBar(part, md)
    local z = part:getSquare():getZ()
    local def = HH.DESIGNS[md.hhDesign]
    for i, p in pairs(HH.hearthParts(md, z)) do
        local pmd = p:getModData()
        pmd.hhKit = true
        p:setSpriteFromName(HH.hearthSprite(pmd.hhDesign, pmd.hhMat, pmd.hhQ, pmd.hhWest, true, false, i))
        p:transmitUpdatedSpriteToClients()
        if i == def.fire then
            if not p:getContainerByType(HH.COOKING) then
                p:addSecondaryContainer(HH.newContainer(p, HH.COOKING, 20, nil))
            end
            if HH.World then HH.World.register(p, true) end
        end
    end
end
