-- The butcher hook sprite only has BlocksPlacement. Pickup needs IsMoveAble, and
-- disassembly needs CanScrap plus a Material that has a scrap definition.
-- These values already exist in the tile property map. A new CustomName would
-- not: unknown values collapse to the first known one.

local HOOK_SPRITE = "crafted_04_120"

local HOOK_RETURNS = {
    "Base.Plank",
    "Base.Plank",
    "Base.Nails",
    "Base.Nails",
    "Base.LargeHook",
}

local function isButcherHook(object)
    return object ~= nil and instanceof(object, "IsoButcherHook")
end

local function hookHasAnimal(object)
    return isButcherHook(object) and object:getAnimal() ~= nil
end

local function onLoadedTileDefinitions(manager)
    manager = manager or IsoSpriteManager.instance
    if not manager then
        return
    end
    local sprite = manager:getSprite(HOOK_SPRITE)
    if not sprite then
        return
    end
    local props = sprite:getProperties()
    if props:has("IsMoveAble") then
        return
    end
    props:set("IsMoveAble", "")
    props:set("PickUpWeight", "50")
    props:set("CanScrap", "")
    props:set("Material", "Wood")
    print("SensibleCraft: butcher hook sprite is now moveable")
end

Events.OnLoadedTileDefinitions.Add(onLoadedTileDefinitions)
Events.OnGameStart.Add(onLoadedTileDefinitions)
Events.OnServerStarted.Add(onLoadedTileDefinitions)

local newMoveableProps = ISMoveableSpriteProps.new
function ISMoveableSpriteProps.new(sprite)
    local props = newMoveableProps(sprite)
    if props.spriteName == HOOK_SPRITE then
        props.name = "Butcher Hook"
    end
    return props
end

local instanceMoveableItem = ISMoveableSpriteProps.instanceItem
function ISMoveableSpriteProps:instanceItem(spriteNameOverride)
    local item = instanceMoveableItem(self, spriteNameOverride)
    if item and self.spriteName == HOOK_SPRITE then
        item:setName("Butcher Hook")
        item:setCustomName(true)
    end
    return item
end

-- Placing furniture makes a plain IsoObject. MOButcherHook only turns
-- crafted_04_120 into an IsoButcherHook when the chunk loads, so swap it now
-- the way BuildRecipeCode.butcheringHook.OnCreate does.
local placeMoveableInternal = ISMoveableSpriteProps.placeMoveableInternal
function ISMoveableSpriteProps:placeMoveableInternal(character, square, item, spriteName)
    local obj = placeMoveableInternal(self, character, square, item, spriteName)
    if spriteName ~= HOOK_SPRITE or not obj or isButcherHook(obj) or not obj:getSquare() then
        return obj
    end
    local hook = IsoButcherHook.new(square)
    square:AddTileObject(hook)
    obj:removeFromWorld()
    obj:removeFromSquare()
    obj:setSquare(nil)
    return hook
end

local canPickUpMoveableInternal = ISMoveableSpriteProps.canPickUpMoveableInternal
function ISMoveableSpriteProps:canPickUpMoveableInternal(character, square, object, isMulti)
    if hookHasAnimal(object) then
        return false
    end
    return canPickUpMoveableInternal(self, character, square, object, isMulti)
end

local pickUpMoveableInternal = ISMoveableSpriteProps.pickUpMoveableInternal
function ISMoveableSpriteProps:pickUpMoveableInternal(character, square, object, sprInstance, spriteName, createItem, rotating)
    if hookHasAnimal(object) then
        return nil
    end
    return pickUpMoveableInternal(self, character, square, object, sprInstance, spriteName, createItem, rotating)
end

local canScrapObject = ISMoveableSpriteProps.canScrapObject
function ISMoveableSpriteProps:canScrapObject(character)
    local result, chance, perkName = canScrapObject(self, character)
    if hookHasAnimal(self.object) then
        result.canScrap = false
    end
    return result, chance, perkName
end

-- The hook is not an IsoThumpable, so vanilla scrap has no record of the
-- planks, nails and large hook that built it. Return those instead of the
-- random wood pile.
local scrapObjectInternal = ISMoveableSpriteProps.scrapObjectInternal
function ISMoveableSpriteProps:scrapObjectInternal(character, scrapDef, square, object, scrapResult, chance, perkName)
    if not isButcherHook(object) then
        return scrapObjectInternal(self, character, scrapDef, square, object, scrapResult, chance, perkName)
    end
    if hookHasAnimal(object) then
        return 0
    end

    if isClient() then
        square:transmitRemoveItemFromSquare(object)
    end
    if isServer() then
        square:transmitRemoveItemFromSquareOnClients(object)
    end
    square:RemoveTileObject(object)
    square:RecalcProperties()
    square:RecalcAllWithNeighbours(true)

    local added = 0
    for i = 1, #HOOK_RETURNS do
        local item = instanceItem(HOOK_RETURNS[i])
        if item then
            square:AddWorldInventoryItem(item, ZombRandFloat(0.1, 0.9), ZombRandFloat(0.1, 0.9), 0)
            added = added + 1
        end
    end
    if character and scrapDef then
        self:scrapGiveXp(character, scrapDef)
    end
    return added
end
