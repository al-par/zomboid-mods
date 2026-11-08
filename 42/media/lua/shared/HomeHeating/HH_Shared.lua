HomeHeating = HomeHeating or {}
local HH = HomeHeating

-- fire = the square along the wall that holds the IsoFireplace (heat, light, fuel, containers)
HH.DESIGNS = {
    hood3 = { width = 3, fire = 1 }, hood2 = { width = 2, fire = 1 },
    range3 = { width = 3, fire = 1 }, range2 = { width = 2, fire = 1 },
    oven3 = { width = 3, fire = 1 }, oven2 = { width = 2, fire = 0 },
}
HH.NEAT_MASONRY = 7

HH.MISC = "homeheating_misc"
HH.FRONTS = { "S", "E", "N", "W" }
HH.COAL_FIRST, HH.COAL_GLOW, HH.ELEC_FIRST, HH.ELEC_GLOW = 0, 4, 8, 12

HH.FUEL_LOW = 70     -- top the fire up from the bin below this many minutes
HH.FUEL_TARGET = 90  -- the vanilla fire keeps its full 8-tile heat radius from 60 minutes up
HH.COAL_MIN_PER_KG = 72
HH.ELEC_DRAW = 0.52  -- generator fuel per hour, before GeneratorFuelConsumption
HH.HEAT_RADIUS, HH.HEAT_TEMP = 8, 35

HH.BIN_WOOD, HH.BIN_COAL, HH.COOKING = "hhfirewood", "hhcharcoal", "hhcooking"
HH.WOOD_TYPES = {
    Log = true, Firewood = true, Plank = true, TreeBranch2 = true, Twigs = true, TwigsBundle = true,
    WoodenStick2 = true, UnusableWood = true, Splinters = true, PercedWood = true,
}
HH.COAL_TYPES = { Charcoal = true, CharcoalCrafted = true }

function HH.fuelHoursScale()
    local h = SandboxVars.MaximumFireFuelHours or 8
    return h / 8
end

function HH.binCapacity(kind)
    local kg = kind == HH.BIN_COAL and 25 or 24
    return math.max(1, math.min(100, math.floor(kg * HH.fuelHoursScale() + 0.5)))
end

function HH.hearthSheet(design, material, quality)
    return "homeheating_" .. design .. "_" .. material .. "_" .. quality
end

function HH.hearthSprite(design, material, quality, west, kit, lit, i)
    local idx = (((west and 1 or 0) * 2 + (kit and 1 or 0)) * 2 + (lit and 1 or 0)) * 4 + i
    return HH.hearthSheet(design, material, quality) .. "_" .. idx
end

function HH.parseHearthSprite(name)
    if not name then return nil end
    local design, material, quality, idx = string.match(name, "^homeheating_(%a+%d)_(%a+)_(%a+)_(%d+)$")
    if not design or not HH.DESIGNS[design] then return nil end
    idx = tonumber(idx)
    return { design = design, material = material, quality = quality, i = idx % 4,
             lit = math.floor(idx / 4) % 2 == 1, kit = math.floor(idx / 8) % 2 == 1, west = idx >= 16 }
end

function HH.heaterKind(name)
    if not name or string.sub(name, 1, #HH.MISC + 1) ~= HH.MISC .. "_" then return nil end
    local idx = tonumber(string.sub(name, #HH.MISC + 2))
    if not idx then return nil end
    if idx >= HH.COAL_FIRST and idx < HH.COAL_FIRST + 4 then return "coal", idx - HH.COAL_FIRST end
    if idx >= HH.ELEC_FIRST and idx < HH.ELEC_FIRST + 4 then return "electric", idx - HH.ELEC_FIRST end
    return nil
end

function HH.glowSprite(kind, k)
    if kind == "coal" then
        -- the firebox door faces away from the camera on the N and W fronts: nothing to glow
        if HH.FRONTS[k + 1] == "N" or HH.FRONTS[k + 1] == "W" then return nil end
        return HH.MISC .. "_" .. (HH.COAL_GLOW + k)
    end
    return HH.MISC .. "_" .. (HH.ELEC_GLOW + k)
end

function HH.key(x, y, z)
    return x .. "," .. y .. "," .. z
end

function HH.spriteName(obj)
    local s = obj and obj:getSprite()
    return s and s:getName() or nil
end

function HH.isWood(item)
    if not item then return false end
    if not HH.WOOD_TYPES[item:getType()] then return false end
    return ISCampingMenu.isValidFuel(item) and true or false
end

function HH.isCharcoal(item)
    return item ~= nil and HH.COAL_TYPES[item:getType()] == true
end

-- minutes of fire one item gives
function HH.fuelMinutes(kind, item)
    if kind == HH.BIN_COAL then
        return math.floor(item:getActualWeight() * HH.COAL_MIN_PER_KG + 0.5)
    end
    return math.floor(ISCampingMenu.getFuelDurationForItem(item) + 0.5)
end

function HomeHeating_AcceptWood(container, item)
    return HH.isWood(item)
end

function HomeHeating_AcceptCharcoal(container, item)
    return HH.isCharcoal(item)
end

-- The object of one of our hearths, or nil.
function HH.hearthPart(obj)
    if not obj then return nil end
    local md = obj:hasModData() and obj:getModData() or nil
    if md and md.hhDesign then return md end
    return nil
end

-- All loaded squares of the hearth that obj belongs to, as {i = object}.
function HH.hearthParts(md, z)
    local parts = {}
    local def = HH.DESIGNS[md.hhDesign]
    if not def then return parts end
    for i = 0, def.width - 1 do
        local x = md.hhWest and md.hhX or md.hhX + i
        local y = md.hhWest and md.hhY + i or md.hhY
        local sq = getCell():getGridSquare(x, y, z)
        if sq then
            local objects = sq:getObjects()
            for j = 0, objects:size() - 1 do
                local o = objects:get(j)
                local omd = HH.hearthPart(o)
                if omd and omd.hhX == md.hhX and omd.hhY == md.hhY and omd.hhI == i then
                    parts[i] = o
                    break
                end
            end
        end
    end
    return parts
end

function HH.fireOf(obj)
    local md = HH.hearthPart(obj)
    if not md then return nil end
    if instanceof(obj, "IsoFireplace") then return obj end
    local def = HH.DESIGNS[md.hhDesign]
    return HH.hearthParts(md, obj:getSquare():getZ())[def.fire]
end

function HH.isOurs(obj)
    if not obj then return false end
    if HH.hearthPart(obj) then return true end
    return HH.heaterKind(HH.spriteName(obj)) ~= nil
end
