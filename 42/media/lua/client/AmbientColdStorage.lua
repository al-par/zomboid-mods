-- Ambient Cold Storage (Build 42, singleplayer)
--
-- Food on an outdoor square (dropped on the ground, in bags, crates, corpses,
-- unpowered fridges...) follows the outdoor air temperature:
--   below ColdTemperature   -> spoils at the vanilla fridge rate
--   below FreezeTemperature -> freezes over HoursToFreeze, frozen food does not spoil
-- Food in a powered freezer (and optionally a powered fridge) does not spoil.
--
-- Vanilla Food.updateAge() keeps running untouched. Each pass lets vanilla catch
-- the item up, then caps its age gain at what the temperature model allows and
-- writes back the modelled freezing progress. A saved clock accumulates hours
-- spent in each temperature band, so time spent unloaded is credited correctly.

if isClient() or isServer() then return end

require "TimedActions/ISTransferAction"
require "TimedActions/ISGrabItemAction"

AmbientColdStorage = AmbientColdStorage or {}
local ACS = AmbientColdStorage

local STATE = "ACS"
local HOLD = "ACS_hold"
local LEGACY_HOLD = "FreezerNoSpoil_age"
local WARM, COLD, FREEZE = 1, 2, 3
local MAX_DEPTH = 8

-- Vanilla Food.updateFreezing() thaw times (hours from fully frozen to thawed).
local THAW_HOURS_OUTSIDE = 1.5
local THAW_HOURS_FRIDGE = 3.0

-- Vanilla Food.getFridgeFactor() / getFoodRotSpeed(), keyed by sandbox value.
local FRIDGE_FACTOR = { 0.4, 0.3, 0.2, 0.1, 0.03, 0.0 }
local ROT_SPEED = { 1.7, 1.4, 1.0, 0.7, 0.4 }

-- The band in effect right now is applied last when replaying a long interval.
local SEGMENT_ORDER = {
    [WARM] = { FREEZE, COLD, WARM },
    [COLD] = { WARM, FREEZE, COLD },
    [FREEZE] = { WARM, COLD, FREEZE },
}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function options()
    local v = SandboxVars and SandboxVars.AmbientColdStorage or {}
    return {
        cold = tonumber(v.ColdTemperature) or 4,
        freeze = tonumber(v.FreezeTemperature) or 0,
        hoursToFreeze = math.max(0.1, tonumber(v.HoursToFreeze) or 4),
        freezers = v.FreezersStopSpoilage ~= false,
        fridges = v.FridgesStopSpoilage == true,
        radius = math.floor(tonumber(v.ScanRadius) or 30),
    }
end

local function bandFor(temp, opt)
    if temp < opt.freeze then return FREEZE end
    if temp < opt.cold then return COLD end
    return WARM
end

-- Global clock ---------------------------------------------------------------

local clock

local function advanceClock(now, band)
    if not clock then
        clock = ModData.getOrCreate("AmbientColdStorage")
        if type(clock.t) ~= "number" then
            clock.t, clock.cold, clock.freeze = now, 0, 0
        end
    end
    local dt = now - clock.t
    if dt > 0 then
        if band == FREEZE then
            clock.freeze = clock.freeze + dt
        elseif band == COLD then
            clock.cold = clock.cold + dt
        end
    end
    clock.t = now
    return clock
end

local cachedContext

-- Set when food crosses a fresh/stale/rotten threshold; the inventory pages are
-- refreshed once when the current batch of work finishes.
local changed = false

local function context()
    local now = getGameTime():getWorldAgeHours()
    if cachedContext and cachedContext.now == now then return cachedContext end
    local cm = getClimateManager()
    local temp = cm and cm:getTemperature()
    if type(temp) ~= "number" then return nil end
    local opt = options()
    local band = bandFor(temp, opt)
    cachedContext = {
        now = now,
        band = band,
        opt = opt,
        clock = advanceClock(now, band),
        fridge = FRIDGE_FACTOR[tonumber(SandboxVars.FridgeFactor) or 3] or 0.2,
        rot = ROT_SPEED[tonumber(SandboxVars.FoodRotSpeed) or 3] or 1.0,
    }
    return cachedContext
end

-- Location -------------------------------------------------------------------

-- Returns the square an item ultimately sits on, a key describing where on it,
-- and the world container holding it (nil when it lies on the ground, possibly
-- inside a bag). Returns nil when the item is carried or in a vehicle.
local function locate(item)
    local path = ""
    local node = item
    for _ = 1, MAX_DEPTH do
        local worldItem = node:getWorldItem()
        local square = worldItem and worldItem:getSquare()
        if square then return square, path .. "w", nil end
        local container = node:getContainer()
        if not container then return nil end
        local bag = container:getContainingItem()
        if bag then
            path = path .. tostring(bag:getID()) .. "/"
            node = bag
        else
            local parent = container:getParent()
            if not parent or instanceof(parent, "IsoGameCharacter")
                or instanceof(parent, "BaseVehicle") then return nil end
            square = parent:getSquare()
            if not square then return nil end
            return square, path .. tostring(container:getType()), container
        end
    end
    return nil
end

local function stopsSpoilage(container, opt)
    if container:isFreezer() then return opt.freezers and container:isPowered() end
    if container:isFridge() then return opt.fridges and container:isPowered() end
    return false
end

-- Powered fridges/freezers, lit stoves, grills etc. report a temperature other
-- than the neutral 1.0 and are left to vanilla.
local function vanillaControlsTemperature(container)
    return math.abs(container:getTemperature() - 1.0) > 0.001
end

-- Food updates ---------------------------------------------------------------

local function setAge(food, age)
    local wasFresh, wasRotten = food:isFresh(), food:isRotten()
    food:setAge(age)
    if food:isFresh() ~= wasFresh or food:isRotten() ~= wasRotten then
        changed = true
    end
end

-- Pins the age of food sitting in a powered freezer/fridge to the value it had
-- when it was first seen there.
local function holdAge(food, md)
    local held = md[HOLD] or md[LEGACY_HOLD]
    md[LEGACY_HOLD] = nil
    local age = food:getAge()
    if held == nil or age < held then
        md[HOLD] = age
    else
        md[HOLD] = held
        if age > held then setAge(food, held) end
    end
end

-- Advances freezing state st = { ft, frozen } by `hours` at `perHour` freezing
-- points per hour (negative thaws). Returns spoilage hours, already scaled by
-- `mult`; vanilla food does not age at all while its frozen flag is set.
local function advanceSegment(st, hours, mult, perHour)
    local agingHours
    if perHour > 0 then
        if st.frozen then
            agingHours = 0
            st.ft = math.min(100, st.ft + perHour * hours)
        else
            local toFull = (100 - st.ft) / perHour
            if hours >= toFull then
                agingHours = toFull
                st.ft, st.frozen = 100, true
            else
                agingHours = hours
                st.ft = st.ft + perHour * hours
            end
        end
    elseif st.frozen then
        local toThawed = st.ft / -perHour
        if hours >= toThawed then
            agingHours = hours - toThawed
            st.ft, st.frozen = 0, false
        else
            agingHours = 0
            st.ft = st.ft + perHour * hours
        end
    else
        agingHours = hours
        st.ft = math.max(0, st.ft + perHour * hours)
    end
    return agingHours * mult
end

local function snapshot(food, md, key, ctx)
    md[STATE] = {
        k = key, t = ctx.now, a = food:getAge(),
        f = food:getFreezingTime(), z = food:isFrozen(),
        cc = ctx.clock.cold, cf = ctx.clock.freeze,
    }
end

local function applyOutdoorTemperature(food, md, key, ctx)
    food:updateAge()
    local age = food:getAge()
    local s = md[STATE]
    if not s or s.k ~= key or ctx.now <= s.t or age < s.a - 0.0001 then
        snapshot(food, md, key, ctx)
        return
    end

    local dt = ctx.now - s.t
    local freezeH = clamp(ctx.clock.freeze - s.cf, 0, dt)
    local coldH = clamp(ctx.clock.cold - s.cc, 0, dt - freezeH)
    local canFreeze = food:canBeFrozen()
    local segments = {
        [WARM] = { dt - freezeH - coldH, 1.0, -100 / THAW_HOURS_OUTSIDE },
        [COLD] = { coldH, ctx.fridge, -100 / THAW_HOURS_FRIDGE },
        [FREEZE] = { freezeH, ctx.fridge,
            canFreeze and 100 / ctx.opt.hoursToFreeze or -100 / THAW_HOURS_FRIDGE },
    }

    local st = { ft = s.f, frozen = s.z }
    local agingHours = 0
    for _, band in ipairs(SEGMENT_ORDER[ctx.band]) do
        local seg = segments[band]
        if seg[1] > 0 then
            agingHours = agingHours + advanceSegment(st, seg[1], seg[2], seg[3])
        end
    end

    -- Never spoil food faster than vanilla did; only take back the excess.
    local allowed = s.a + agingHours * ctx.rot / 24
    if age > allowed then setAge(food, allowed) end

    if canFreeze then
        -- setFreezingTime() only changes the frozen flag at 0% and 100%.
        food:setFrozen(st.frozen)
        food:setFreezingTime(st.ft)
    end

    snapshot(food, md, key, ctx)
end

local function processFood(food)
    local ctx = context()
    if not ctx then return end
    local md = food:getModData()
    local square, path, container = locate(food)
    if container and stopsSpoilage(container, ctx.opt) then
        md[STATE] = nil
        holdAge(food, md)
        return
    end
    md[HOLD], md[LEGACY_HOLD] = nil, nil
    if not square or not square:isOutside()
        or (container and vanillaControlsTemperature(container)) then
        md[STATE] = nil
        return
    end
    local key = square:getX() .. "," .. square:getY() .. "," .. square:getZ() .. "|" .. path
    applyOutdoorTemperature(food, md, key, ctx)
end

-- Traversal ------------------------------------------------------------------

local processList

local function processItem(item, depth)
    if instanceof(item, "Food") then
        processFood(item)
    elseif depth < MAX_DEPTH and instanceof(item, "InventoryContainer") then
        local inv = item:getItemContainer()
        if inv then processList(inv:getItems(), depth + 1) end
    end
end

processList = function(items, depth)
    for i = 0, items:size() - 1 do
        processItem(items:get(i), depth)
    end
end

local function forget(item, depth)
    if not item then return end
    depth = depth or 0
    if instanceof(item, "Food") then
        local md = item:getModData()
        md[STATE], md[HOLD], md[LEGACY_HOLD] = nil, nil, nil
    elseif depth < MAX_DEPTH and instanceof(item, "InventoryContainer") then
        local inv = item:getItemContainer()
        if inv then
            local items = inv:getItems()
            for i = 0, items:size() - 1 do forget(items:get(i), depth + 1) end
        end
    end
end

-- Indoors only fridges and freezers matter; they are visited even when
-- unpowered so food that lost power stops being held.
local function processObjectContainers(obj, outside)
    for j = 0, obj:getContainerCount() - 1 do
        local container = obj:getContainerByIndex(j)
        if container and (outside or container:isFreezer() or container:isFridge())
            and not container:getItems():isEmpty() then
            processList(container:getItems(), 0)
        end
    end
end

local function scanSquare(sq)
    local outside = sq:isOutside()
    if outside then
        local worldObjects = sq:getWorldObjects()
        for i = 0, worldObjects:size() - 1 do
            local item = worldObjects:get(i):getItem()
            if item then processItem(item, 0) end
        end
    end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        processObjectContainers(objects:get(i), outside)
    end
    if outside then
        -- Corpses live in this list rather than getObjects().
        local moving = sq:getStaticMovingObjects()
        for i = 0, moving:size() - 1 do
            processObjectContainers(moving:get(i), true)
        end
    end
end

-- Background work ------------------------------------------------------------
-- Every 10 minutes the squares around each player are swept a few columns per
-- tick, over about SWEEP_TICKS ticks, instead of all in one frame. Squares that load
-- before the game starts are queued by coordinate (squares are pooled and
-- reused) and drained the same way. Results are identical either way: each
-- item replays its own history from its snapshot whenever it is processed.

local SWEEP_TICKS = 60
local MIN_SQUARES_PER_TICK = 200

local areas = {}
local areaCount, areaIndex, sweepX = 0, 1, 0
local sweepBudget = MIN_SQUARES_PER_TICK
local sweeping, sweepRequested = false, false

local queueX, queueY, queueZ = {}, {}, {}
local queueHead, queueTail = 1, 0
local queueBudget = MIN_SQUARES_PER_TICK

local ticking = false
local onTick

local function startTicking()
    if ticking then return end
    ticking = true
    Events.OnTick.Add(onTick)
end

local function startSweep()
    local ctx = context()
    if not ctx then return end
    local r = ctx.opt.radius
    local n = 0
    for p = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(p)
        if player and not player:isDead() then
            local px, py = math.floor(player:getX()), math.floor(player:getY())
            local pz = math.floor(player:getZ())
            n = n + 1
            areas[n] = { px - r, px + r, py - r, py + r, 0 }
            for z = pz - 1, pz + 1 do
                if z ~= 0 then
                    n = n + 1
                    areas[n] = { px - r, px + r, py - r, py + r, z }
                end
            end
            local items = player:getInventory():getItems()
            for i = 0, items:size() - 1 do forget(items:get(i)) end
        end
    end
    areaCount = n
    if n == 0 then return end
    local side = 2 * r + 1
    sweepBudget = math.max(MIN_SQUARES_PER_TICK, math.ceil(n * side * side / SWEEP_TICKS))
    areaIndex, sweepX = 1, areas[1][1]
    sweeping = true
    startTicking()
end

-- Advances the clock every 10 minutes even while a sweep is still running.
function ACS.scanAroundPlayers()
    if not context() then return end
    if sweeping then
        sweepRequested = true
    else
        startSweep()
    end
end

onTick = function()
    local cell = getCell()
    if not cell then return end

    local budget = queueBudget
    while queueHead <= queueTail and budget > 0 do
        local sq = cell:getGridSquare(queueX[queueHead], queueY[queueHead], queueZ[queueHead])
        queueX[queueHead], queueY[queueHead], queueZ[queueHead] = nil, nil, nil
        queueHead = queueHead + 1
        budget = budget - 1
        if sq then scanSquare(sq) end
    end
    if queueHead <= queueTail then return end
    queueHead, queueTail = 1, 0

    if sweeping then
        budget = sweepBudget
        while budget > 0 and areaIndex <= areaCount do
            local area = areas[areaIndex]
            local x, z = sweepX, area[5]
            for y = area[3], area[4] do
                local sq = cell:getGridSquare(x, y, z)
                if sq then scanSquare(sq) end
            end
            budget = budget - (area[4] - area[3] + 1)
            if x < area[2] then
                sweepX = x + 1
            else
                areaIndex = areaIndex + 1
                if areaIndex <= areaCount then sweepX = areas[areaIndex][1] end
            end
        end
        if areaIndex <= areaCount then return end
        sweeping = false
    end

    if changed then
        changed = false
        triggerEvent("OnContainerUpdate")
    end
    if sweepRequested then
        sweepRequested = false
        startSweep()
        if sweeping then return end
    end
    ticking = false
    Events.OnTick.Remove(onTick)
end

-- Transfers: credit the item's time at its old spot, drop its history, then
-- start tracking it at the destination straight away.
local function beforeMove(item)
    if item then processItem(item, 0) end
end

local function afterMove(item)
    if not item then return end
    forget(item)
    processItem(item, 0)
end

local originalTransferItem = ISTransferAction.transferItem
function ISTransferAction:transferItem(character, item, srcContainer, destContainer, dropSquare)
    beforeMove(item)
    local result = originalTransferItem(self, character, item, srcContainer, destContainer, dropSquare)
    afterMove(result or item)
    return result
end

local originalGrabItem = ISGrabItemAction.transferItem
function ISGrabItemAction:transferItem(item)
    local inventoryItem = self.item and self.item:getItem()
    beforeMove(inventoryItem)
    local result = originalGrabItem(self, item)
    afterMove(inventoryItem)
    return result
end

-- Events ---------------------------------------------------------------------

local started = false

Events.OnInitGlobalModData.Add(function()
    clock = nil
    cachedContext = nil
end)

-- Correct food in an area as soon as it loads, before vanilla's catch-up
-- spoilage can rot it or trigger ReplaceOnRotten (e.g. ice cream melting).
Events.LoadGridsquare.Add(function(sq)
    if started then
        scanSquare(sq)
    else
        queueTail = queueTail + 1
        queueX[queueTail], queueY[queueTail], queueZ[queueTail] = sq:getX(), sq:getY(), sq:getZ()
    end
end)

-- Vanilla fires this with the Food itself when it turns stale or rotten; fix
-- it up immediately, before rotten-food removal can act on it.
local inContainerUpdate = false
Events.OnContainerUpdate.Add(function(arg)
    if not started or inContainerUpdate or not arg or not instanceof(arg, "Food") then return end
    inContainerUpdate = true
    processFood(arg)
    inContainerUpdate = false
end)

Events.OnGameStart.Add(function()
    started = true
    if queueTail >= queueHead then
        queueBudget = math.max(MIN_SQUARES_PER_TICK, math.ceil((queueTail - queueHead + 1) / SWEEP_TICKS))
        startTicking()
    end
    ACS.scanAroundPlayers()
end)

Events.EveryTenMinutes.Add(ACS.scanAroundPlayers)
