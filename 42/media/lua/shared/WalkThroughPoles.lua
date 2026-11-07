-- Build 42.
-- Walking is blocked only by the solid and solidtrans flags. Cars are blocked by Bullet colliders that
-- IsoChunk builds from those flags, from PhysicsShape, and from StopCar (which makes the tile a
-- moveable object with a trunk collider).

local MODULE = "WalkThroughPoles"

local function sprites(prefix, ids)
    local list = {}
    for i = 1, #ids do
        list[i] = prefix .. ids[i]
    end
    return list
end

local function range(prefix, first, last)
    local ids = {}
    for i = first, last do
        ids[#ids + 1] = i
    end
    return sprites(prefix, ids)
end

local function set(list)
    local names = {}
    for i = 1, #list do
        names[list[i]] = true
    end
    return names
end

-- Walk through, cars still collide ------------------------------------------------------------

local WALK_THROUGH = {}
local NEEDS_TRUNK = {}

local function walkThrough(list, needsTrunk)
    for i = 1, #list do
        WALK_THROUGH[list[i]] = true
        if needsTrunk then
            NEEDS_TRUNK[list[i]] = true
        end
    end
end

-- Radio mast legs and public mailboxes keep their StopCar trunk for cars.
walkThrough(sprites("radio_tower_", { 1, 3, 6, 11 }))
walkThrough(range("street_decoration_01_", 8, 11))

-- Road signs and newspaper boxes have no car collider besides the solidtrans cube.
walkThrough(range("street_roadsigns_01_", 0, 3), true)
walkThrough(range("street_roadsigns_01_", 32, 41), true)
walkThrough(range("street_decoration_01_", 80, 95), true)

-- Wooden poles and posts: stop slow cars, get flattened by fast ones ---------------------------

-- Each debris set is four fence-debris tiles in the order north, south, east, west.
local DEBRIS_OFFSET = { north = 0, south = 1, east = 2, west = 3 }

local UTILITY_POLE = {
    sandbox = true,
    drag = 0.3,
    debris = 136,
    item = "Base.Log",
    stack = set(range("appliances_com_01_", 88, 95)),
}

local LOG_POST = {
    sandbox = true,
    drag = 0.3,
    debris = 128,
    item = "Base.Log",
    stack = set(range("location_shop_greenes_01_", 4, 7)),
}

local FARM_POST = {
    sandbox = true,
    drag = 0.1,
    debris = 168,
    item = "Base.Plank",
}

local BOOM_GATE = {
    speed = 10,
    drag = 0.05,
    debris = 124,
}

local BREAKABLE = {}

local function breakable(list, def)
    for i = 1, #list do
        BREAKABLE[list[i]] = def
    end
end

breakable(sprites("appliances_com_01_", { 88, 89, 94, 95 }), UTILITY_POLE)
breakable(range("location_shop_greenes_01_", 4, 7), LOG_POST)
breakable({ "location_farm_accesories_01_13" }, FARM_POST)
breakable(range("street_decoration_01_", 56, 63), BOOM_GATE)

local DEFAULT_BREAK_SPEED = 30

local function readBreakSpeed()
    local vars = SandboxVars and SandboxVars.WalkThroughPoles
    local speed = vars and tonumber(vars.BreakSpeed) or DEFAULT_BREAK_SPEED
    for _, def in pairs(BREAKABLE) do
        if def.sandbox then
            def.speed = speed
        end
    end
end

readBreakSpeed()

local function editTiles(manager)
    manager = manager or IsoSpriteManager.instance
    if not manager then return end
    readBreakSpeed()

    for name in pairs(WALK_THROUGH) do
        local sprite = manager:getSprite(name)
        if sprite then
            local props = sprite:getProperties()
            props:unset(IsoFlagType.solid)
            props:unset(IsoFlagType.solidtrans)
            if NEEDS_TRUNK[name] then
                props:set("PhysicsShape", "Tree")
            end
        end
    end

    -- Without HitByCar the vehicle code ignores these entirely; this file decides what happens.
    for name in pairs(BREAKABLE) do
        local sprite = manager:getSprite(name)
        if sprite then
            local props = sprite:getProperties()
            props:unset(IsoFlagType.solid)
            props:unset(IsoFlagType.solidtrans)
            props:unset("StopCar")
            props:unset("PhysicsShape")
            props:unset("HitByCar")
            if sprite:getTileType() == IsoObjectType.isMoveAbleObject then
                sprite:setTileType(IsoObjectType.MAX)
            end
        end
    end
end

local function breakableDef(obj)
    local sprite = obj:getSprite()
    local name = sprite and sprite:getName()
    return name and BREAKABLE[name], name
end

-- Flattening (single player and server) --------------------------------------------------------

local function fallDirection(square, vehicle)
    local dx = square:getX() + 0.5 - vehicle:getX()
    local dy = square:getY() + 0.5 - vehicle:getY()
    if math.abs(dx) > math.abs(dy) then
        return dx > 0 and "east" or "west"
    end
    return dy > 0 and "south" or "north"
end

local function removeStackParts(square, parts)
    local removed = false
    local objects = square:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        if name and parts[name] then
            square:transmitRemoveItemFromSquare(obj)
            removed = true
        end
    end
    return removed
end

local function clearStack(square, parts)
    local cell = getCell()
    for z = square:getZ() + 1, square:getZ() + 3 do
        local above = cell:getGridSquare(square:getX(), square:getY(), z)
        if not above or not removeStackParts(above, parts) then
            return
        end
    end
end

local function flatten(obj, def, vehicle)
    local index = obj:getObjectIndex()
    if index < 0 then return end
    local square = obj:getSquare()

    -- Hit sound and zombie noise, same as a mailbox. HitByCar is unset, so no damage is applied.
    obj:HitByVehicle(vehicle, 0)

    local spriteName = "fencing_damaged_01_" .. (def.debris + DEBRIS_OFFSET[fallDirection(square, vehicle)])
    local debris = IsoObject.getNew(square, spriteName, nil, false)
    local removedAt = square:transmitRemoveItemFromSquare(obj)
    if removedAt < 0 then return end
    square:transmitAddObjectToSquare(debris, math.min(removedAt, square:getObjects():size()))

    if def.item then
        square:AddWorldInventoryItem(def.item, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
    end
    if def.stack then
        clearStack(square, def.stack)
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE or command ~= "flatten" or type(args) ~= "table" then return end
    local cell = getCell()
    local square = cell and cell:getGridSquare(args.x, args.y, args.z)
    local vehicle = args.vehicle and getVehicleById(args.vehicle)
    if not square or not vehicle then return end

    local dx = square:getX() + 0.5 - vehicle:getX()
    local dy = square:getY() + 0.5 - vehicle:getY()
    if dx * dx + dy * dy > 64 then return end

    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local def, name = breakableDef(obj)
        if def and name == args.sprite then
            flatten(obj, def, vehicle)
            return
        end
    end
end

-- Driving (single player and the driver's client) ----------------------------------------------

-- Impulses only move a car on the machine that simulates it: single player or the driver's client.
local SCAN = 4
local CONTACT = 0.3
local CREEP_PUSH = 0.25
local SPEED_PUSH = 0.12
local RESEND_FRAMES = 60

-- Breakable objects around each driven vehicle are cached in a wider area, re-read once the car
-- has moved CACHE_MARGIN squares or after CACHE_FRAMES, so most frames touch no squares at all.
local CACHE_MARGIN = 2
local CACHE_FRAMES = 30

local hit = Vector2.new()
local frame = 0
local requested = {}
local caches = {}       -- vehicle -> { x, y, z, frame, used, count, objs, xs, ys, defs, names }

local function requestFlatten(player, vehicle, obj, def, name)
    -- Flattening one piece of a multi-tile gate removes the other pieces hit this tick.
    if obj:getObjectIndex() < 0 then return end
    local square = obj:getSquare()
    if not isClient() then
        vehicle:applyImpulseFromHitPlant(obj, def.drag)
        flatten(obj, def, vehicle)
        return
    end
    local key = square:getX() .. "," .. square:getY() .. "," .. square:getZ()
    if requested[key] and frame - requested[key] < RESEND_FRAMES then return end
    requested[key] = frame
    vehicle:applyImpulseFromHitPlant(obj, def.drag)
    sendClientCommand(player, MODULE, "flatten", {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        sprite = name,
        vehicle = vehicle:getId(),
    })
end

local function refreshCache(cache, cell, cx, cy, z)
    cache.x, cache.y, cache.z, cache.frame = cx, cy, z, frame
    local objs, xs, ys, defs, names = cache.objs, cache.xs, cache.ys, cache.defs, cache.names
    local n = 0
    local reach = SCAN + CACHE_MARGIN
    for x = cx - reach, cx + reach do
        for y = cy - reach, cy + reach do
            local square = cell:getGridSquare(x, y, z)
            if square then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local obj = objects:get(i)
                    local def, name = breakableDef(obj)
                    if def then
                        n = n + 1
                        objs[n], xs[n], ys[n], defs[n], names[n] = obj, x, y, def, name
                    end
                end
            end
        end
    end
    for i = n + 1, cache.count do
        objs[i], xs[i], ys[i], defs[i], names[i] = nil, nil, nil, nil, nil
    end
    cache.count = n
end

local function handleVehicle(cell, player, vehicle, speed)
    local vx = vehicle:getX()
    local vy = vehicle:getY()
    local cx = math.floor(vx)
    local cy = math.floor(vy)
    local z = math.floor(vehicle:getZ())

    local cache = caches[vehicle]
    if not cache then
        cache = { count = 0, objs = {}, xs = {}, ys = {}, defs = {}, names = {} }
        caches[vehicle] = cache
        refreshCache(cache, cell, cx, cy, z)
    elseif cache.used ~= frame - 1 or cache.z ~= z or frame - cache.frame >= CACHE_FRAMES
            or math.abs(cx - cache.x) > CACHE_MARGIN or math.abs(cy - cache.y) > CACHE_MARGIN then
        refreshCache(cache, cell, cx, cy, z)
    end
    cache.used = frame
    if cache.count == 0 then return end

    local push = (CREEP_PUSH + SPEED_PUSH * speed) * vehicle:getFudgedMass()
    local flattened = {}
    local objs, xs, ys, defs, names = cache.objs, cache.xs, cache.ys, cache.defs, cache.names

    for i = 1, cache.count do
        local x, y, obj = xs[i], ys[i], objs[i]
        -- Flattened or picked-up objects stay cached until the next refresh.
        if math.abs(x - cx) <= SCAN and math.abs(y - cy) <= SCAN and obj:getObjectIndex() >= 0 then
            local def, name = defs[i], names[i]
            -- A zero radius only matches when the pole's center is inside the car's footprint.
            if vehicle:testCollisionWithObject(obj, 0, hit) then
                flattened[#flattened + 1] = { obj, def, name }
            elseif vehicle:testCollisionWithObject(obj, CONTACT, hit) then
                local dx = vx - (x + 0.5)
                local dy = vy - (y + 0.5)
                if speed > def.speed then
                    flattened[#flattened + 1] = { obj, def, name }
                -- The shove direction is pole-to-car-center; at zero length it normalizes to NaN.
                elseif dx * dx + dy * dy > 0.0001 then
                    vehicle:applyImpulseFromHitObject(obj, push)
                end
            end
        end
    end

    for i = 1, #flattened do
        local entry = flattened[i]
        requestFlatten(player, vehicle, entry[1], entry[2], entry[3])
    end
end

local function pruneCaches()
    local stale = {}
    for vehicle, cache in pairs(caches) do
        if cache.used ~= frame then stale[#stale + 1] = vehicle end
    end
    for i = 1, #stale do caches[stale[i]] = nil end
end

local function onTick()
    frame = frame + 1
    local cell = getCell()
    if not cell then return end
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        local vehicle = player and player:getVehicle()
        if vehicle and vehicle:isDriver(player) then
            local speed = math.abs(vehicle:getCurrentSpeedKmHour())
            handleVehicle(cell, player, vehicle, speed)
            local trailer = vehicle:getVehicleTowing()
            if trailer then
                handleVehicle(cell, player, trailer, speed)
            end
        end
    end
    if frame % CACHE_FRAMES == 0 then pruneCaches() end
end

-- Built wooden poles ---------------------------------------------------------------------------

-- A built thumpable that is not a corner blocks its north or west edge like a fence. Vanilla's build
-- code never marks the Wooden Pole as a corner, so poles built before this fix are repaired on load.
local EDGE_FLAGS = { IsoFlagType.WallN, IsoFlagType.WallW, IsoFlagType.WallNW, IsoFlagType.WallNTrans,
    IsoFlagType.WallWTrans, IsoFlagType.DoorWallN, IsoFlagType.DoorWallW, IsoFlagType.doorN, IsoFlagType.doorW,
    IsoFlagType.WindowN, IsoFlagType.WindowW, IsoFlagType.HoppableN, IsoFlagType.HoppableW }

local function isBuiltPole(obj)
    if not instanceof(obj, "IsoThumpable") or obj:isCorner() or obj:isDoor() or obj:isStairs() then return false end
    local sprite = obj:getSprite()
    local props = sprite and sprite:getProperties()
    if not props or not props:has(IsoFlagType.WallSE) then return false end
    for i = 1, #EDGE_FLAGS do
        if props:has(EDGE_FLAGS[i]) then return false end
    end
    return true
end

local function onLoadGridsquare(square)
    local specials = square:getSpecialObjects()
    for i = 0, specials:size() - 1 do
        local obj = specials:get(i)
        if isBuiltPole(obj) then obj:setCorner(true) end
    end
end

local function onWorldReady()
    editTiles()
end

Events.OnLoadedTileDefinitions.Add(editTiles)
Events.OnGameStart.Add(onWorldReady)
Events.OnServerStarted.Add(onWorldReady)
-- Only the machine simulating a car (single player or the driver's client) watches for hits.
if not isServer() then
    Events.OnTick.Add(onTick)
end
Events.OnClientCommand.Add(onClientCommand)
Events.LoadGridsquare.Add(onLoadGridsquare)
