"""Runs AmbientColdStorage.lua against an emulation of vanilla Food aging (from 42.21 bytecode).

Usage: python simulate_aging.py [path/to/AmbientColdStorage.lua] [[room-]swing|freeze|deepfreeze|cold|warm]
"""
import math, os, sys
from lupa import LuaRuntime

MOD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "42", "media", "lua", "client", "AmbientColdStorage.lua")

HARNESS = r"""
local H = {}
H.now = 3000.0
H.temp = -5
H.loaded = true
function isClient() return false end
function isServer() return false end
function require() end
ISTransferAction = { transferItem = function(self, c, item) return item end }
ISGrabItemAction = { transferItem = function(self, item) return item end }
SandboxVars = { FridgeFactor = 3, FoodRotSpeed = 3, AmbientColdStorage = {} }
local events = {}
Events = setmetatable({}, { __index = function(t, k)
    local e = { list = {} }
    function e.Add(f) table.insert(e.list, f) end
    function e.Remove(f) for i, g in ipairs(e.list) do if g == f then table.remove(e.list, i) return end end end
    rawset(t, k, e); return e end })
function H.fire(name, ...) local l = {} for i, f in ipairs(Events[name].list) do l[i] = f end for _, f in ipairs(l) do f(...) end end
local md = {}
ModData = { getOrCreate = function(k) md[k] = md[k] or {}; return md[k] end }
function getGameTime() return { getWorldAgeHours = function() return H.now end } end
H.daylight = 0.5
H.inRoom = false
-- vanilla ClimateManager.getAirTemperatureForSquare (42.21), no heat sources, grid power off
local function airTemperatureForSquare(sq)
    local t = H.temp
    if not sq:isInARoom() or t > 22 then return t end
    local gap = 22 - t
    if sq:getZ() >= 1 then gap = gap * 0.85 end
    return t + gap * (0.4 + 0.2 * H.daylight)
end
local climate = {
    getTemperature = function() return H.temp end,
    getDayLightStrength = function() return H.daylight end,
    getAirTemperatureForSquare = function(_, sq) return airTemperatureForSquare(sq) end,
}
function getClimateManager() return climate end
function getSandboxOptions()
    return { getElecShutModifier = function() return 14 end, getTimeSinceApo = function() return 1 end }
end
function triggerEvent(name, arg) H.fire(name, arg) end

local function jlist(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end,
             isEmpty = function() return #t == 0 end, t = t }
end
H.jlist = jlist

function instanceof(o, cls) return type(o) == "table" and o.__cls ~= nil and o.__cls[cls] == true end

-- vanilla Food, transcribed from zombie.inventory.types.Food (42.21)
local Food = {}
Food.__index = Food
function H.newFood(age)
    local f = setmetatable({ __cls = { Food = true, InventoryItem = true }, age = age, lastAged = H.now,
        lastFrozenUpdate = H.now, freezingTime = 0, frozen = false, md = {}, offAge = 5, offAgeMax = 8 }, Food)
    return f
end
function Food:getModData() return self.md end
function Food:getAge() return self.age end
function Food:setAge(a) self.age = a end
function Food:isFresh() return self.age < self.offAge end
function Food:isRotten() return self.age >= self.offAgeMax end
function Food:canBeFrozen() return true end
function Food:isFrozen() return self.frozen end
function Food:setFrozen(b) self.frozen = b end
function Food:getFreezingTime() return self.freezingTime end
function Food:setFreezingTime(v)
    if v >= 100 then self.frozen = true; v = 100 elseif v <= 0 then v = 0; self.frozen = false end
    self.freezingTime = v
end
function Food:getWorldItem() return self.worldItem end
function Food:getContainer() return self.container end
function Food:outermost() return self.container end
function Food:isThawing()
    if self.freezingTime <= 0 then return false end
    local c = self:outermost()
    return not (c and c.freezer) or not c.powered
end
function Food:isFreezing()
    if self.freezingTime >= 100 then return false end
    local c = self:outermost()
    return c ~= nil and c.freezer and c.powered
end
function Food:updateFreezing(c, now)
    if now > self.lastFrozenUpdate then
        local dt = now - self.lastFrozenUpdate
        if self:isFreezing() then self:setFreezingTime(self.freezingTime + dt / 4 * 100) end
        if self:isThawing() then
            local thaw = 1.5
            if c and c.temperature > 1 then thaw = thaw / 6 end
            self:setFreezingTime(self.freezingTime - dt / thaw * 100)
        end
        self.lastFrozenUpdate = now
    end
end
function Food:updateAge()
    local now = H.now
    local c = self:outermost()
    self:updateFreezing(c, now)
    if now > self.lastAged then
        local dt = now - self.lastAged
        if self.frozen then dt = 0 end
        local wasFresh, wasRotten = self:isFresh(), self:isRotten()
        self.age = self.age + dt * 1.0 / 24
        self.lastAged = now
        if wasFresh ~= self:isFresh() or wasRotten ~= self:isRotten() then
            H.vanillaEvents = (H.vanillaEvents or 0) + 1
            triggerEvent("OnContainerUpdate", self)
        end
    end
end

-- one outdoor square with a crate, a player standing next to it
local crateItems = {}
local crate = { __cls = {}, freezer = false, fridge = false, powered = false, temperature = 1.0, items = crateItems }
function crate:isFreezer() return self.freezer end
function crate:isFridge() return self.fridge end
function crate:isPowered() return self.powered end
function crate:getTemperature() return self.temperature end
function crate:getItems() return jlist(crateItems) end
function crate:getContainingItem() return nil end
function crate:getType() return "crate" end
local ground = {}
local square = { x = 421, y = 9766, z = 0 }
function square:getX() return 421 end
function square:getY() return 9766 end
function square:getZ() return 0 end
-- covered outdoor square (porch roof above) by default; H.inRoom puts it in an unpowered room
function square:isOutside() return false end
function square:isInARoom() return H.inRoom end
function square:getWorldObjects() return jlist(ground) end
local crateObj = { getContainerCount = function() return 1 end, getContainerByIndex = function() return crate end,
                   getSquare = function() return square end }
function crate:getParent() return crateObj end
function square:getObjects() return jlist({ crateObj }) end
function square:getStaticMovingObjects() return jlist({}) end
H.square, H.crate, H.crateItems, H.ground = square, crate, crateItems, ground

function H.putInCrate(f) f.container = crate; table.insert(crateItems, f) end
function H.putOnGround(f)
    local wi = { getSquare = function() return square end, getItem = function() return f end }
    f.worldItem = wi; f.container = nil; table.insert(ground, wi)
end

local player = { getX = function() return H.px end, getY = function() return 9766 end, getZ = function() return 0 end,
                 isDead = function() return false end,
                 getInventory = function() return { getItems = function() return jlist({}) end } end }
H.px = 421
function getNumActivePlayers() return 1 end
function getSpecificPlayer() return player end
function getCell()
    return { getGridSquare = function(_, x, y, z)
        if H.loaded and x == 421 and y == 9766 and z == 0 then return square end
        return nil end }
end
return H
"""

lua = LuaRuntime(unpack_returned_tuples=True)
H = lua.execute(HARNESS)
lua.execute(open(MOD, encoding="utf-8").read())
fire = H.fire

MODE = sys.argv[2] if len(sys.argv) > 2 else "swing"
# room-*: same weather, but the square is a ground-floor room in an unpowered building
if MODE.startswith("room-"):
    H.inRoom = True
    MODE = MODE[5:]

def temp_at(h):
    if MODE == "freeze":
        return -5
    if MODE == "deepfreeze":
        return -25
    if MODE == "cold":
        return 2
    if MODE == "warm":
        return 10
    # never warm: daily swing between -5 and +3 C
    return -1 + 4 * math.sin(2 * math.pi * (h % 24) / 24)

def run_hours(hours, vanilla_touch=True, away=False):
    steps = int(hours * 60)
    for i in range(steps):
        H.now = H.now + 1 / 60
        H.temp = temp_at(H.now)
        if int(round(H.now * 60)) % 10 == 0:
            fire("EveryTenMinutes")
        for _ in range(3):
            fire("OnTick")
        if vanilla_touch and H.loaded:
            for f in list(foods):
                f.updateAge(f)

fire("OnInitGlobalModData")
fire("OnGameStart")
foods = []
for kind in ("crate", "ground"):
    f = H.newFood(0.0)
    f.freezingTime = 100
    f.frozen = True
    (H.putInCrate if kind == "crate" else H.putOnGround)(f)
    foods.append(f)

def report(label):
    print("%-38s now=%.1f temp=%+.1f  " % (label, H.now, H.temp) +
          "  ".join("age=%.3f ft=%.0f frozen=%s" % (f.age, f.freezingTime, f.frozen) for f in foods))

report("start (both frozen, age 0)")
run_hours(48)
report("after 2 days nearby")
H.loaded = False
H.px = 2000
run_hours(72, vanilla_touch=False)
report("after 3 days away (chunk unloaded)")
H.loaded = True
H.px = 421
for f in foods:
    pass
fire("LoadGridsquare", H.square)
run_hours(0.5)
report("30 min after coming back")
run_hours(48)
report("2 more days nearby")
print("vanilla fresh/rotten events:", H.vanillaEvents)
