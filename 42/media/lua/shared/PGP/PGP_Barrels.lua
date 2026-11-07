-- Pooled Generator Power: fuel barrels.
--
-- Vanilla metal barrels and drums get a fluid container, so they can hold petrol and feed plumbed
-- generators. A barrel is carried as a two-handed heavy item whose contents live in its mod data
-- (not in a fluid container, so vanilla fuel and fluid menus can't touch it while it is carried).
-- Putting one down rebuilds the world barrel with the same contents.

require "PGP/PGP_Core"
require "Moveables/ISMoveableSpriteProps"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISTransferAction"

PGP.Barrels = PGP.Barrels or {}
local B = PGP.Barrels

B.CAPACITY = 200
B.CONTAINER_NAME = "PGP_Barrel"
B.WEIGHT_PER_LITRE = 1.0
B.PUMP_REACH = 2
B.TRUNK_MIN_CAPACITY = 100

local ORANGE = "Base.PGP_Barrel_Orange"
local LIGHT_GREEN = "Base.PGP_Barrel_LightGreen"
local DARK_GREEN = "Base.PGP_Barrel_DarkGreen"
local DRUM = "Base.PGP_Barrel_MetalDrum"

B.SPRITE_ITEMS = {
    industry_01_22 = ORANGE,
    industry_01_23 = ORANGE,
    location_military_generic_01_6 = LIGHT_GREEN,
    location_military_generic_01_7 = LIGHT_GREEN,
    location_military_generic_01_14 = DARK_GREEN,
    location_military_generic_01_15 = DARK_GREEN,
    crafted_01_24 = DRUM,
    crafted_01_25 = DRUM,
    crafted_01_28 = DRUM,
    crafted_01_29 = DRUM,
    crafted_01_32 = DRUM,
}

B.DEFAULT_SPRITE = {
    [ORANGE] = "industry_01_22",
    [LIGHT_GREEN] = "location_military_generic_01_6",
    [DARK_GREEN] = "location_military_generic_01_14",
    [DRUM] = "crafted_01_32",
}

-- Facings of the same barrel, in rotation order.
B.FACINGS = {
    { "industry_01_22", "industry_01_23" },
    { "location_military_generic_01_6", "location_military_generic_01_7" },
    { "location_military_generic_01_14", "location_military_generic_01_15" },
    { "crafted_01_24", "crafted_01_25" },
    { "crafted_01_28", "crafted_01_29" },
    { "crafted_01_32" },
}

function B.facingsOf(spriteName)
    for _, facings in ipairs(B.FACINGS) do
        for _, name in ipairs(facings) do
            if name == spriteName then return facings end
        end
    end
    return { spriteName }
end

function B.itemSprite(item)
    return item:getModData().pgpSprite or B.DEFAULT_SPRITE[item:getFullType()]
end

function B.spriteNames()
    local list = {}
    for name in pairs(B.SPRITE_ITEMS) do table.insert(list, name) end
    table.sort(list)
    return list
end

function B.spriteName(obj)
    local sprite = obj and obj:getSprite()
    return sprite and sprite:getName() or nil
end

function B.isBarrelObject(obj)
    if not obj or instanceof(obj, "IsoWorldInventoryObject") then return false end
    local name = B.spriteName(obj)
    return name ~= nil and B.SPRITE_ITEMS[name] ~= nil
end

function B.isBarrelItem(item)
    return item ~= nil and instanceof(item, "InventoryItem") and B.DEFAULT_SPRITE[item:getFullType()] ~= nil
end

-- A barrel item lying on the floor (only when there was no room to stand it up).
function B.isLooseBarrel(obj)
    return obj ~= nil and instanceof(obj, "IsoWorldInventoryObject") and B.isBarrelItem(obj:getItem())
end

function B.fluidContainer(obj)
    return obj and obj:getComponent(ComponentType.FluidContainer) or nil
end

-- Server side only: vanilla barrels have no fluid container until we give them one.
function B.ensureContainer(obj, capacity)
    local fc = B.fluidContainer(obj)
    if fc then return fc end
    fc = ComponentType.FluidContainer:CreateComponent()
    fc:setCapacity(capacity or B.CAPACITY)
    fc:setContainerName(B.CONTAINER_NAME)
    GameEntityFactory.AddComponent(obj, true, fc)
    return B.fluidContainer(obj)
end

function B.hasFluid(obj)
    local fc = B.fluidContainer(obj)
    return fc ~= nil and fc:getAmount() > 0.001
end

function B.barrelName(obj)
    return getItemNameFromFullType(B.SPRITE_ITEMS[B.spriteName(obj)] or DRUM)
end

---------------------------------------------------------------------------------------------------
-- Contents: { [fluidTypeString] = litres }
---------------------------------------------------------------------------------------------------

function B.readContents(fc)
    local contents = {}
    if not fc or fc:getAmount() <= 0 then return contents end
    local fluids = Fluid.getAllFluids()
    for i = 0, fluids:size() - 1 do
        local fluid = fluids:get(i)
        local amount = fc:getSpecificFluidAmount(fluid)
        if amount > 0 then contents[fluid:getFluidTypeString()] = amount end
    end
    return contents
end

function B.writeContents(fc, contents)
    fc:Empty()
    for name, amount in pairs(contents or {}) do
        local fluid = Fluid.Get(name)
        if fluid then fc:addFluid(fluid, amount) end
    end
end

function B.contentsTotal(contents)
    local total = 0
    for _, amount in pairs(contents or {}) do total = total + amount end
    return total
end

-- "183 L Petrol", or nil when empty.
function B.contentsLabel(contents)
    local best, bestAmount = nil, 0
    for name, amount in pairs(contents or {}) do
        if amount > bestAmount then best, bestAmount = name, amount end
    end
    local total = B.contentsTotal(contents)
    if not best or total < 0.5 then return nil end
    local fluid = Fluid.Get(best)
    return getText("IGUI_PGP_BarrelContents", math.floor(total + 0.5), fluid and fluid:getTranslatedName() or best)
end

function B.labelled(name, contents)
    local label = B.contentsLabel(contents)
    if not label then return name end
    return getText("IGUI_PGP_BarrelNamed", name, label)
end

function B.objectLabel(obj)
    if B.isLooseBarrel(obj) then return obj:getItem():getDisplayName() end
    return B.labelled(B.barrelName(obj), B.readContents(B.fluidContainer(obj)))
end

function B.applyItemState(item, spriteName, contents, capacity)
    local md = item:getModData()
    md.pgpSprite = spriteName
    md.pgpFluids = contents
    md.pgpCapacity = capacity
    local weight = item:getScriptItem():getActualWeight() + B.contentsTotal(contents) * B.WEIGHT_PER_LITRE
    item:setActualWeight(weight)
    item:setWeight(weight)
    item:setCustomWeight(true)
    item:setName(B.labelled(getItemNameFromFullType(item:getFullType()), contents))
    item:setCustomName(true)
end

---------------------------------------------------------------------------------------------------
-- Placement.
---------------------------------------------------------------------------------------------------

local DIR_VECTORS = {
    [IsoDirections.N] = { 0, -1 }, [IsoDirections.NE] = { 1, -1 }, [IsoDirections.E] = { 1, 0 },
    [IsoDirections.SE] = { 1, 1 }, [IsoDirections.S] = { 0, 1 }, [IsoDirections.SW] = { -1, 1 },
    [IsoDirections.W] = { -1, 0 }, [IsoDirections.NW] = { -1, -1 },
}

-- ignore: a character allowed to be standing on the square (it walks off before placing).
function B.isFreeSquare(sq, ignore)
    if not sq or not sq:TreatAsSolidFloor() then return false end
    if sq:isSolid() or sq:isSolidTrans() or sq:HasStairs() or sq:isVehicleIntersecting() then return false end
    local movers = sq:getMovingObjects()
    for i = 0, movers:size() - 1 do
        if movers:get(i) ~= ignore then return false end
    end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if instanceof(obj, "IsoGenerator") or B.isBarrelObject(obj) then return false end
        if not instanceof(obj, "IsoWorldInventoryObject") and B.fluidContainer(obj) then return false end
        local props = obj:getProperties()
        if props and (props:has(IsoFlagType.solid) or props:has(IsoFlagType.solidtrans) or props:has("BlocksPlacement")) then
            return false
        end
    end
    return true
end

local function reachable(from, to)
    if from:getZ() ~= to:getZ() then return false end
    if math.abs(from:getX() - to:getX()) > 1 or math.abs(from:getY() - to:getY()) > 1 then return false end
    return not from:isBlockedTo(to) and not from:isWindowTo(to)
end

function B.canPlaceFrom(character, sq)
    local cur = character and character:getCurrentSquare()
    if not cur or not sq or sq == cur then return false end
    return reachable(cur, sq) and B.isFreeSquare(sq)
end

-- Free squares around origin, the ones the character faces first.
function B.squaresAround(origin, character)
    local dir = character and DIR_VECTORS[character:getDir()] or { 0, 1 }
    local list = {}
    for dy = -1, 1 do
        for dx = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local sq = getCell():getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
                if sq and reachable(origin, sq) and B.isFreeSquare(sq) then
                    table.insert(list, { sq = sq, score = (dx * dir[1] + dy * dir[2]) / math.sqrt(dx * dx + dy * dy) })
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.score > b.score end)
    local out = {}
    for _, e in ipairs(list) do table.insert(out, e.sq) end
    return out
end

function B.findPlaceSquare(character, preferred)
    if preferred and B.canPlaceFrom(character, preferred) then return preferred end
    local cur = character:getCurrentSquare()
    if not cur then return nil end
    return B.squaresAround(cur, character)[1]
end

-- Server side: builds the world barrel for a carried barrel item.
function B.placeBarrel(item, sq)
    local md = item:getModData()
    local spriteName = B.itemSprite(item)
    local obj = IsoObject.new(getCell(), sq, getSprite(spriteName))
    obj:setMovedThumpable(true)
    sq:AddTileObject(obj)
    local fc = B.ensureContainer(obj, math.max(B.CAPACITY, md.pgpCapacity or 0))
    B.writeContents(fc, md.pgpFluids)
    sq:RecalcProperties()
    sq:RecalcAllWithNeighbours(true)
    if isServer() then obj:transmitCompleteItemToClients() end
    return obj
end

local function removeWorldItem(worldItem)
    local item = worldItem:getItem()
    local sq = worldItem:getSquare()
    sq:transmitRemoveItemFromSquare(worldItem)
    sq:removeWorldObject(worldItem)
    item:setWorldItem(nil)
    local container = item:getContainer()
    if container then container:DoRemoveItem(item) end
    return item
end

-- Server side: puts a world barrel (standing, or loose on the floor) into the character's hands.
function B.takeBarrel(character, barrel)
    local item
    if B.isLooseBarrel(barrel) then
        forceDropHeavyItems(character)
        item = removeWorldItem(barrel)
    else
        local sq = barrel:getSquare()
        local spriteName = B.spriteName(barrel)
        local fc = B.fluidContainer(barrel)
        item = instanceItem(B.SPRITE_ITEMS[spriteName])
        if not item then return false end
        B.applyItemState(item, spriteName, B.readContents(fc), fc and fc:getCapacity() or B.CAPACITY)
        forceDropHeavyItems(character)
        sq:transmitRemoveItemFromSquare(barrel)
        sq:RecalcProperties()
        sq:RecalcAllWithNeighbours(true)
    end

    local inv = character:getInventory()
    inv:AddItem(item)
    sendAddItemToContainer(inv, item)
    character:setPrimaryHandItem(item)
    character:setSecondaryHandItem(item)
    sendEquip(character)
    return true
end

-- Server side: puts a carried barrel down on the chosen square, or with no square chosen, on the
-- best free square next to the character. spriteName picks the facing.
function B.putDown(character, item, sq, spriteName)
    if sq then
        if not B.canPlaceFrom(character, sq) then return false end
    else
        sq = B.findPlaceSquare(character, nil)
        if not sq then return false end
    end
    if spriteName and B.SPRITE_ITEMS[spriteName] == item:getFullType() then
        item:getModData().pgpSprite = spriteName
    end
    B.placeBarrel(item, sq)
    character:removeFromHands(item)
    local container = item:getContainer()
    if container then
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    end
    sendEquip(character)
    return true
end

-- Server side: a barrel item that ended up loose on the floor is stood back up as a world barrel.
-- With no free square nearby it stays loose; picking it up still works.
function B.standWorldItem(worldItem, character)
    local item = worldItem:getItem()
    local origin = worldItem:getSquare()
    if not item or not origin then return false end
    local target = origin
    if not B.isFreeSquare(origin) or (character and character:getCurrentSquare() == origin) then
        target = B.squaresAround(origin, character)[1]
    end
    if not target then return false end
    removeWorldItem(worldItem)
    B.placeBarrel(item, target)
    return true
end

local function standDropped(character, a, b)
    if isClient() then return end
    for _, item in ipairs({ a or false, b or false }) do
        if item and B.isBarrelItem(item) and item:getWorldItem() then
            B.standWorldItem(item:getWorldItem(), character)
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Pumps.
---------------------------------------------------------------------------------------------------

function B.isPump(obj)
    local sprite = obj and obj:getSprite()
    return sprite ~= nil and sprite:getProperties():has("fuelAmount")
end

-- Same rule as the vanilla pump menu.
function B.pumpPowered(pump)
    local sq = pump:getSquare()
    if not sq then return false end
    return (SandboxVars.AllowExteriorGenerator and sq:haveElectricity()) or sq:hasGridPower()
end

local function scanNear(sq, reach, test)
    local found = {}
    if not sq then return found end
    for dy = -reach, reach do
        for dx = -reach, reach do
            local s = getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            if s then
                local objects = s:getObjects()
                for i = 0, objects:size() - 1 do
                    local obj = objects:get(i)
                    if test(obj) then table.insert(found, obj) end
                end
            end
        end
    end
    return found
end

function B.pumpsNear(sq)
    return scanNear(sq, B.PUMP_REACH, B.isPump)
end

function B.barrelsNear(sq)
    return scanNear(sq, B.PUMP_REACH, B.isBarrelObject)
end

-- Litres of petrol the barrel can still take, or 0 and a reason key.
function B.petrolSpace(barrel)
    local fc = B.fluidContainer(barrel)
    if not fc then return B.CAPACITY end
    if fc:getFreeCapacity() <= 0.001 then return 0, "BarrelFull" end
    if fc:getAmount() > 0.001 and not fc:isPureFluid(Fluid.Petrol) then return 0, "BarrelOtherFluid" end
    return fc:getFreeCapacity()
end

-- Returns the best pump for filling, or nil and a reason key.
function B.choosePump(pumps)
    local reason = "NoPump"
    for _, pump in ipairs(pumps) do
        if not B.pumpPowered(pump) then
            reason = "PumpNoPower"
        elseif pump:getPipedFuelAmount() <= 0 then
            if reason ~= "PumpNoPower" then reason = "PumpEmpty" end
        else
            return pump
        end
    end
    return nil, reason
end

---------------------------------------------------------------------------------------------------
-- Trunks: any barrel fits a big empty trunk, whatever it weighs.
---------------------------------------------------------------------------------------------------

function B.trunkPart(container)
    local part = container and container:getVehiclePart()
    if not part or part:getItemContainer() ~= container then return nil end
    local id = part:getId()
    if id == "TruckBed" or id == "TruckBedOpen" or string.find(id, "Trunk", 1, true) then return part end
    return nil
end

-- nil when the barrel may go in, otherwise a reason key.
function B.trunkReason(character, container)
    local part = B.trunkPart(container)
    if not part then return "NotTrunk" end
    if container:getEffectiveCapacity(character) < B.TRUNK_MIN_CAPACITY then return "TrunkTooSmall" end
    if not container:getItems():isEmpty() then return "TrunkNotEmpty" end
    if not part:getVehicle():canAccessContainer(part:getIndex(), character) then return "TrunkClosed" end
    return nil
end

---------------------------------------------------------------------------------------------------
-- Vanilla hooks.
---------------------------------------------------------------------------------------------------

-- Barrels are carried, not packed as furniture: furniture pickup would turn a full barrel into an
-- ordinary inventory item. Scrapping is only blocked while the barrel holds something.
local vanillaCanPickUp = ISMoveableSpriteProps.canPickUpMoveableInternal
function ISMoveableSpriteProps:canPickUpMoveableInternal(_character, _square, _object, _isMulti)
    if _object and B.isBarrelObject(_object) then return false end
    return vanillaCanPickUp(self, _character, _square, _object, _isMulti)
end

local vanillaCanScrap = ISMoveableSpriteProps.canScrapObjectInternal
function ISMoveableSpriteProps:canScrapObjectInternal(_result, _object)
    if _object and B.isBarrelObject(_object) and B.hasFluid(_object) then return false end
    return vanillaCanScrap(self, _result, _object)
end

-- Every vanilla way of letting go of a heavy item leaves it loose on the floor; stand barrels back up.
local vanillaForceDrop = forceDropHeavyItems
function forceDropHeavyItems(character)
    local primary = character and character:getPrimaryHandItem()
    local secondary = character and character:getSecondaryHandItem()
    vanillaForceDrop(character)
    standDropped(character, primary, secondary)
end

-- Parameter names must match vanilla: multiplayer sends the fields named after them to the server.
local vanillaUnequipNew = ISUnequipAction.new
function ISUnequipAction:new(character, item, maxTimeInit, reason)
    local o = vanillaUnequipNew(self, character, item, maxTimeInit, reason)
    if B.isBarrelItem(item) then
        o.maxTimeInit = 1
        o.maxTime = 1
    end
    return o
end

local vanillaUnequipComplete = ISUnequipAction.complete
function ISUnequipAction:complete()
    local result = vanillaUnequipComplete(self)
    standDropped(self.character, self.item)
    return result
end

local vanillaTransferItem = ISTransferAction.transferItem
function ISTransferAction:transferItem(character, item, srcContainer, destContainer, dropSquare)
    local result = vanillaTransferItem(self, character, item, srcContainer, destContainer, dropSquare)
    if destContainer:getType() == "floor" then standDropped(character, result) end
    return result
end

Events.onItemFall.Add(function(item)
    standDropped(nil, item)
end)
