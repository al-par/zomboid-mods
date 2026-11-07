SaltLickSalt = {}

local SALT_LICK_SPRITE = "location_farm_accesories_01_12"

-- A salt lick picked up off the map is a generic Moveables.Moveable, so the recipe has to accept that
-- script and filter it down to the salt lick sprite here. Every other input (hammers etc.) passes.
function SaltLickSalt.onTest(item, character)
    if instanceof(item, "Moveable") then
        return item:getWorldSprite() == SALT_LICK_SPRITE
    end
    return true
end

-- Breaking a vanilla salt lick consumes it whole; hand back the drainable with the first use spent.
function SaltLickSalt.onBreak(craftRecipeData, character)
    local consumed = craftRecipeData:getAllConsumedItems()
    for i = 0, consumed:size() - 1 do
        if instanceof(consumed:get(i), "Moveable") then
            local inv = character:getInventory()
            local lick = inv:AddItem("Base.SLS_SaltLick")
            if lick then
                lick:setUsedDelta(1 - lick:getUseDelta())
                sendAddItemToContainer(inv, lick)
            end
            return
        end
    end
end
