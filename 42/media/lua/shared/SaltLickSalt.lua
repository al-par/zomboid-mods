-- Placed salt licks have no item of their own; picking one up should yield the drainable.
Events.OnLoadedTileDefinitions.Add(function(manager)
    local sprite = manager:getSprite("location_farm_accesories_01_12")
    if sprite then
        sprite:getProperties():set("CustomItem", "Base.SLS_SaltLick")
    end
end)
