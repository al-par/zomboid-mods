require "Items/ProceduralDistributions"
require "Items/SuburbsDistributions"
require "Vehicles/VehicleDistributions"

-- The archery magazine spawns exactly like the generator magazine: wherever vanilla lists
-- ElectronicsMag4, the same list gets CA_ArcheryMag with the same weight.
-- Vanilla shares one list under several names (SuburbsDistributions.clinic = ...medical), so each
-- table is visited once; otherwise shared lists would get several copies and multiply the rate.

local SOURCE = { ElectronicsMag4 = true, ["Base.ElectronicsMag4"] = true }
local MAGAZINE = "Base.CA_ArcheryMag"
local added = 0

local function mirrorInList(list)
    local weights = {}
    for i = 1, #list - 1, 2 do
        if SOURCE[list[i]] and type(list[i + 1]) == "number" then
            weights[#weights + 1] = list[i + 1]
        end
    end
    for i = 1, #weights do
        table.insert(list, MAGAZINE)
        table.insert(list, weights[i])
    end
    added = added + #weights
end

local function walk(t, seen)
    if seen[t] then return end
    seen[t] = true
    if type(t[1]) == "string" and type(t[2]) == "number" then
        mirrorInList(t)
        return
    end
    for _, v in pairs(t) do
        if type(v) == "table" then walk(v, seen) end
    end
end

local function onPostDistributionMerge()
    local seen = {}
    walk(SuburbsDistributions, seen)
    walk(ProceduralDistributions.list, seen)
    walk(VehicleDistributions, seen)
    if ClutterTables then walk(ClutterTables, seen) end
    if BagsAndContainers then walk(BagsAndContainers, seen) end
    print("SensibleArchery: archery magazine added to " .. added .. " loot entries (one per ElectronicsMag4 entry)")
end

Events.OnPostDistributionMerge.Add(onPostDistributionMerge)
