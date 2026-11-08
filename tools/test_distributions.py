"""Run vanilla's distribution files plus SensibleArchery_Distributions.lua in standard Lua (lupa) and check
that every list gets exactly one archery magazine entry per generator magazine entry, at the same weight.

Standard Lua is not Kahlua; this checks the table walk only, not the game.
"""
import os

from lupa import LuaRuntime

GAME = r"C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\media\lua\server"
MOD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "42", "media", "lua", "server",
                   "SensibleArchery_Distributions.lua")
FILES = [
    r"Items\Distribution_BinJunk.lua", r"Items\Distribution_ClosetJunk.lua",
    r"Items\Distribution_BagsAndContainers.lua", r"Items\ProceduralDistributions.lua",
    r"Items\SuburbsDistributions.lua", r"Items\Distributions.lua", r"Vehicles\VehicleDistributions.lua",
]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("""
handlers = { pre = {}, merge = {}, post = {} }
local function ev(list) return { Add = function(f) table.insert(list, f) end } end
Events = { OnPreDistributionMerge = ev(handlers.pre), OnDistributionMerge = ev(handlers.merge),
           OnPostDistributionMerge = ev(handlers.post) }
Distributions = Distributions or {}
require = function() end
getActivatedMods = function() return { contains = function() return false end } end
isClient = function() return false end
isServer = function() return false end
""")
for f in FILES:
    src = open(os.path.join(GAME, f), encoding="utf-8", errors="replace").read()
    lua.execute(src)
lua.execute(open(MOD, encoding="utf-8").read())

lua.execute("""
function countAll(target)
    local seen, n, w = {}, 0, 0
    local function walk(t)
        if seen[t] then return end
        seen[t] = true
        if type(t[1]) == "string" and type(t[2]) == "number" then
            for i = 1, #t - 1, 2 do
                if t[i] == target or t[i] == "Base." .. target then n = n + 1; w = w + t[i + 1] end
            end
            return
        end
        for _, v in pairs(t) do if type(v) == "table" then walk(v) end end
    end
    for _, root in ipairs({ SuburbsDistributions or {}, ProceduralDistributions.list, VehicleDistributions,
                            ClutterTables or {}, BagsAndContainers or {} }) do walk(root) end
    return n, w
end
function listsMismatched()
    local seen, bad = {}, 0
    local function walk(t)
        if seen[t] then return end
        seen[t] = true
        if type(t[1]) == "string" and type(t[2]) == "number" then
            local a, b = 0, 0
            for i = 1, #t - 1, 2 do
                if t[i] == "ElectronicsMag4" or t[i] == "Base.ElectronicsMag4" then a = a + t[i + 1] end
                if t[i] == "Base.CA_ArcheryMag" then b = b + t[i + 1] end
            end
            if math.abs(a - b) > 1e-9 then bad = bad + 1 end
            return
        end
        for _, v in pairs(t) do if type(v) == "table" then walk(v) end end
    end
    for _, root in ipairs({ SuburbsDistributions or {}, ProceduralDistributions.list, VehicleDistributions,
                            ClutterTables or {}, BagsAndContainers or {} }) do walk(root) end
    return bad
end
""")
for phase in ("pre", "merge", "post"):
    for f in lua.globals().handlers[phase].values():
        f()
gen = lua.globals().countAll("ElectronicsMag4")
mag = lua.globals().countAll("CA_ArcheryMag")
print("generator magazine entries:", gen[0], "total weight", round(gen[1], 4))
print("archery magazine entries:  ", mag[0], "total weight", round(mag[1], 4))
print("lists where the two weights differ:", lua.globals().listsMismatched())
