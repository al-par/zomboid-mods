require "Foraging/forageSystem"
require "Foraging/Categories/Junk"

-- Foraging finds the archery magazine as often as the generator magazine: copy its definition.
-- forageSystem.init() (OnLoadedMapZones) reads forageDefinitions later and fills in zones, so the
-- copy gets its own zones and categories tables.

local source = forageSystem.forageDefinitions.ElectronicsMag4
if source then
    local def = {}
    for k, v in pairs(source) do def[k] = v end
    def.type = "Base.CA_ArcheryMag"
    def.zones = {}
    for k, v in pairs(source.zones) do def.zones[k] = v end
    def.categories = {}
    for i, v in ipairs(source.categories) do def.categories[i] = v end
    forageSystem.addForageDef("CA_ArcheryMag", def)
else
    print("SensibleArchery: no ElectronicsMag4 forage definition; the archery magazine can't be foraged")
end
