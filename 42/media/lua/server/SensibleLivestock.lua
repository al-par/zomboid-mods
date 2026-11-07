-- Sensible Livestock (Build 42)
--
-- Animals damage structures through IsoThumpable.animalHit / IsoDoor.Damage, which apply
-- 1000 * baseDmg * strength gene regardless of the animal's size or the material, and destroy the
-- object inside the same Java call. Lua has no hook before that, so doors and thumpables near an
-- agitated animal carry a large health buffer. On each update the buffer loss is attributed to an
-- animal, converted into this mod's damage model, and the buffer is refilled. The real health is
-- mirrored in mod data so a buffer that gets saved (chunk unload, server save, crash) is repaired
-- when the square loads again.
--
-- Single player updates ten times a real second, and moves stumbling animals every tick so the
-- motion stays smooth. A server (dedicated or co-op host) updates every game minute to keep its
-- cost low; shields go up well before an animal is stressed enough to ram.

if isClient() then return end

local MODULE = "SensibleLivestock"
local MOD_KEY = "SL_realHealth"
local SERVER = isServer()

local UPDATE_INTERVAL_MS = 100
local RESCAN_UPDATES = 10               -- a resting agitated animal's surroundings are rescanned about once a second

local BUFFER = 100000
local SCAN_RADIUS = 2
local RAM_RANGE = 3
local SHIELD_HOURS = 0.1
local AGITATED_STRESS = 50
local AGITATED_NEED = 0.75

local REFERENCE_WEIGHT = 100
local REFERENCE_FORCE = 100
local DEFAULT_BASE_DMG = 0.5
local AVERAGE_STRENGTH_GENE = 0.4
local MATCH_TOLERANCE = 2.5

local CALM_STRESS = 60
local BACK_OFF_TILES = 4
local FUTILE_MEMORY_HOURS = 0.5
local LOCK_RELEASE_DISTANCE = 2         -- AnimalAttackState only drops its target this far from it
local ESCAPE_SEARCH_STEPS = 4
local STUMBLE_SPEED = 0.1               -- tiles per multiplier unit, about 5 tiles per real second
local STUMBLE_SETTLE_UNITS = 96

local SPOT_RADIUS = 10
local ZOMBIE_FLEE_RADIUS = 6
local VANILLA_RUN_STRESS = 1 / 1000     -- per GameTime multiplier unit, before the stress gene
local SPRINT_STRESS_FACTOR = 2
local MAX_SPOT_STRESS = 0.01            -- per multiplier unit; larger gains came from noise or injury
local UNITS_PER_SECOND = 48             -- GameTime multiplier accumulated per real second at 1x
local MAX_SERVER_GAP_SECONDS = 10

local NOBODY, HEAVY_ONLY, MEDIUM_UP, ANYONE = 1, 2, 3, 4
local LIGHT, MEDIUM, HEAVY = 1, 2, 3

local CATEGORIES = {
    masonryFull = { option = "MasonryWalls",    default = NOBODY,     mult = 0.1 },
    masonryLow  = { option = "MasonryLowWalls", default = HEAVY_ONLY, mult = 0.25 },
    metalFull   = { option = "MetalWalls",      default = NOBODY,     mult = 0.1 },
    metalDoor   = { option = "MetalDoors",      default = HEAVY_ONLY, mult = 0.1 },
    metalLow    = { option = "MetalFences",     default = NOBODY,     mult = 0.25 },
    wire        = { option = "WireFences",      default = HEAVY_ONLY, mult = 0.5 },
    timberFull  = { option = "WoodenWalls",     default = HEAVY_ONLY, mult = 0.5 },
    timberLow   = { option = "WoodenFences",    default = MEDIUM_UP,  mult = 1, hitsOption = "WoodenFenceHits" },
    furnishing  = { option = "Furnishings",     default = ANYONE,     mult = 1 },
}

-- Built metal doors have no base health, only 300 per welding level of the builder.
local METAL_DOOR_ENTITIES = { MetalDoorLvl1 = true, MetalDoorLvl2 = true }
local METAL_DOOR_HEALTH_PER_LEVEL = 300

local FULL_FLAGS = { "WallN", "WallW", "WallNW", "WindowN", "WindowW", "DoorWallN", "DoorWallW", "doorN", "doorW" }
local LOW_FLAGS = { "HoppableN", "HoppableW" }
local SEE_THROUGH_FLAGS = { "WallNTrans", "WallWTrans", "TallHoppableN", "TallHoppableW" }
local NORTH_FLAGS = { "WallN", "WallNTrans", "HoppableN", "TallHoppableN", "WindowN", "DoorWallN", "doorN" }
local WEST_FLAGS = { "WallW", "WallWTrans", "HoppableW", "TallHoppableW", "WindowW", "DoorWallW", "doorW" }

local shields = {}      -- object -> { real, category, untilHours }
local futile = {}       -- animal -> { count, hours }
local stumbles = {}     -- animal -> { route, step, obj, leader, waited }
local lastStress = {}   -- animal -> stress at the previous update
local wasJogging = {}   -- player -> true if jogging at the previous update
local wasSprinting = {} -- player -> true if sprinting at the previous update
local rammers = {}      -- tame animals that may have just rammed, refreshed every update
local scans = {}        -- animal -> { x, y, z, update, hours } of the last shield scan around it
local stumbleCount = 0
local updateCount = 0
local currentAnimals = {}
local currentZombies    -- zombies near currentAnimals, gathered on first use in an update
local lastUpdateMs
local nextUpdateMs = 0
local pendingUnits = 0

-- Options -------------------------------------------------------------------

local function option(name, default)
    local vars = SandboxVars and SandboxVars[MODULE]
    local value = vars and vars[name]
    if value == nil then return default end
    return value
end

-- Helpers -------------------------------------------------------------------

-- Wall, door and hoppable names are sprite flags; has(string) only checks named tile properties.
local function hasAny(props, flags)
    for i = 1, #flags do
        local flag = IsoFlagType[flags[i]]
        if flag and props:has(flag) then return true end
    end
    return false
end

local function lower(s)
    return s and string.lower(tostring(s)) or ""
end

local function worldHours()
    return getGameTime():getWorldAgeHours()
end

local function isBreakable(obj)
    return instanceof(obj, "IsoThumpable") or instanceof(obj, "IsoDoor")
end

local function isGone(obj)
    return obj:getObjectIndex() < 0 or obj:getSquare() == nil
end

local function players()
    local list = {}
    if SERVER then
        local online = getOnlinePlayers()
        for i = 0, online:size() - 1 do list[#list + 1] = online:get(i) end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p and not p:isDead() then list[#list + 1] = p end
        end
    end
    return list
end

-- Structures ----------------------------------------------------------------

local function entityName(obj)
    local script = obj:getEntityScript()
    return script and script:getName() or ""
end

local function classify(obj)
    local props = obj:getProperties()
    if not props or obj:getContainerCount() > 0 then return "furnishing" end

    local door = instanceof(obj, "IsoDoor") or obj:isDoor()
    local low = hasAny(props, LOW_FLAGS)
    local full = (door or hasAny(props, FULL_FLAGS)) and not low
    if not full and not low and not hasAny(props, SEE_THROUGH_FLAGS) then return "furnishing" end

    local name = entityName(obj)
    if METAL_DOOR_ENTITIES[name] then
        local weldingLevel = math.floor(obj:getMaxHealth() / METAL_DOOR_HEALTH_PER_LEVEL + 0.01)
        return weldingLevel >= option("MetalDoorWeldingLevel", 6) and "metalFull" or "metalDoor"
    end

    local sprite = obj:getSprite()
    local material = table.concat({
        lower(props:get("Material")), lower(props:get("Material2")), lower(props:get("MaterialType")),
        lower(name), lower(sprite and sprite:getName()),
    }, " ")

    local kind
    if material:find("stone") or material:find("brick") or material:find("concrete") then
        kind = "masonry"
    elseif material:find("wire") then
        return "wire"
    elseif material:find("metal") then
        kind = "metal"
    else
        kind = "timber"
    end
    return kind .. (full and "Full" or "Low")
end

-- Animals -------------------------------------------------------------------

local function definition(animal)
    local defs = AnimalDefinitions and AnimalDefinitions.animals
    return defs and defs[animal:getAnimalType()]
end

local function canThump(animal)
    local def = definition(animal)
    return not def or def.canThump ~= false
end

local function sizeClass(animal)
    local weight = animal:getData():getWeight()
    if weight >= option("HeavyWeight", 400) then return HEAVY end
    if weight >= option("MediumWeight", 50) then return MEDIUM end
    return LIGHT
end

local function isPanicOnly(animal)
    return animal:getAttackedBy() == nil and animal:getHunger() < 0.9 and animal:getThirst() < 0.9
end

local function isAgitated(animal)
    return animal:isAnimalAttacking()
        or animal:getStress() >= AGITATED_STRESS
        or animal:getHunger() >= AGITATED_NEED
        or animal:getThirst() >= AGITATED_NEED
        or animal:getAttackedBy() ~= nil
end

local function mayBreak(animal, category)
    local rule = option(category.option, category.default)
    if rule == ANYONE then return true end
    if rule == NOBODY then return false end
    local size = sizeClass(animal)
    if rule == HEAVY_ONLY then return size == HEAVY end
    return size >= MEDIUM
end

local function ramDamage(animal, categoryKey, obj)
    local category = CATEGORIES[categoryKey]
    if not mayBreak(animal, category) then return 0 end

    if category.hitsOption then
        local maxHealth = obj:getMaxHealth()
        if maxHealth and maxHealth > 0 then
            -- The extra half hit leaves a sliver after the last survived hit, so the next one breaks it.
            return maxHealth / (option(category.hitsOption, 10) + 0.5)
        end
    end

    local def = definition(animal)
    local gene = animal:calcDamage() / ((def and def.baseDmg) or DEFAULT_BASE_DMG)
    local strength = math.max(0.25, math.min(2.5, gene / AVERAGE_STRENGTH_GENE))
    local weight = math.max(1, animal:getData():getWeight())

    local damage = REFERENCE_FORCE * math.sqrt(weight / REFERENCE_WEIGHT) * strength * category.mult
    damage = damage * option("ForcePercent", 100) / 100
    if isPanicOnly(animal) then
        damage = damage * option("PanicForcePercent", 50) / 100
    end
    return damage
end

local function vanillaHit(animal, obj)
    local scale = instanceof(obj, "IsoDoor") and 100 or 1000
    return scale * animal:calcDamage()
end

-- Returns the animal whose vanilla hits best explain the lost health, how many hits that was,
-- and any remainder that came from something else (zombies, players).
local function findRammer(obj, lost)
    local square = obj:getSquare()
    local ox, oy, oz = square:getX() + 0.5, square:getY() + 0.5, square:getZ()
    local best, bestHits, bestHit, bestError
    for i = 1, #rammers do
        local animal = rammers[i]
        if math.floor(animal:getZ()) == oz
                and math.abs(animal:getX() - ox) <= RAM_RANGE
                and math.abs(animal:getY() - oy) <= RAM_RANGE then
            local hit = vanillaHit(animal, obj)
            local hits = hit > 0 and math.floor(lost / hit + 0.5) or 0
            if hits > 0 then
                local err = math.abs(lost - hits * hit)
                if not bestError or err < bestError then
                    best, bestHits, bestHit, bestError = animal, hits, hit, err
                end
            end
        end
    end
    if not best then return nil end
    local remainder = lost - bestHits * bestHit
    if remainder <= bestHits * MATCH_TOLERANCE then remainder = 0 end
    return best, bestHits, remainder
end

-- Giving up -----------------------------------------------------------------

local function backOff(animal, obj)
    local square = obj:getSquare()
    local props = obj:getProperties()
    local ex, ey = square:getX() + 0.5, square:getY() + 0.5
    if props and hasAny(props, NORTH_FLAGS) then
        ey = square:getY()
    elseif props and hasAny(props, WEST_FLAGS) then
        ex = square:getX()
    end

    local dx, dy = animal:getX() - ex, animal:getY() - ey
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.1 then
        dx, dy = ZombRandFloat(-1, 1), ZombRandFloat(-1, 1)
        len = math.max(0.1, math.sqrt(dx * dx + dy * dy))
    end
    animal:pathToLocation(
        math.floor(animal:getX() + dx / len * BACK_OFF_TILES),
        math.floor(animal:getY() + dy / len * BACK_OFF_TILES),
        math.floor(animal:getZ()))
end

-- A ramming animal ignores paths and leads until it is LOCK_RELEASE_DISTANCE from its target, and
-- Lua cannot clear the target, so giving up means stumbling back that far.

local STEPS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function canStep(from, to, dx, dy)
    return to:isFree(false)
        and not from:isBlockedTo(to)
        and from:getHoppableTo(to) == nil
        and from:testCollideSpecialObjects(to) == nil
        and not from:testCollideAdjacent(nil, dx, dy, 0)
end

local function pickGoal(goals, targetSquare, leader)
    local best, bestScore
    for i = 1, #goals do
        local sq = goals[i]
        local score
        if leader then
            local dx, dy = sq:getX() + 0.5 - leader:getX(), sq:getY() + 0.5 - leader:getY()
            score = -(dx * dx + dy * dy)
        else
            score = targetSquare:DistToProper(sq)
        end
        if not bestScore or score > bestScore then best, bestScore = sq, score end
    end
    return best
end

local function escapeRoute(animal, obj, leader)
    local start = animal:getCurrentSquare()
    local targetSquare = obj:getSquare()
    if not start or not targetSquare then return nil end

    local cell = getCell()
    local parent = { [start] = false }
    local frontier = { start }
    for _ = 1, ESCAPE_SEARCH_STEPS do
        local nextFrontier, goals = {}, {}
        for i = 1, #frontier do
            local from = frontier[i]
            for j = 1, #STEPS do
                local dx, dy = STEPS[j][1], STEPS[j][2]
                local to = cell:getGridSquare(from:getX() + dx, from:getY() + dy, from:getZ())
                if to and parent[to] == nil and canStep(from, to, dx, dy) then
                    parent[to] = from
                    nextFrontier[#nextFrontier + 1] = to
                    if targetSquare:DistToProper(to) >= LOCK_RELEASE_DISTANCE then
                        goals[#goals + 1] = to
                    end
                end
            end
        end
        if #goals > 0 then
            local reversed = {}
            local sq = pickGoal(goals, targetSquare, leader)
            while sq do
                reversed[#reversed + 1] = sq
                sq = parent[sq]
            end
            local route = {}
            for i = #reversed - 1, 1, -1 do route[#route + 1] = reversed[i] end
            return route
        end
        frontier = nextFrontier
    end
    return nil
end

local function breakFree(animal, obj, leader)
    if stumbles[animal] then return end
    local route = escapeRoute(animal, obj, leader)
    if route then
        stumbles[animal] = { route = route, step = 1, obj = obj, leader = leader, waited = 0 }
        stumbleCount = stumbleCount + 1
    end
end

local function endStumble(animal)
    if stumbles[animal] then
        stumbles[animal] = nil
        stumbleCount = stumbleCount - 1
    end
end

local function updateStumbles(units)
    local done = {}
    for animal, s in pairs(stumbles) do
        if animal:isDead() or not animal:getSquare() then
            done[#done + 1] = animal
        elseif s.step <= #s.route then
            local budget = units * STUMBLE_SPEED
            while budget > 0 and s.step <= #s.route do
                local sq = s.route[s.step]
                local tx, ty = sq:getX() + 0.5, sq:getY() + 0.5
                local dx, dy = tx - animal:getX(), ty - animal:getY()
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= budget then
                    animal:setX(tx)
                    animal:setY(ty)
                    budget = budget - dist
                    s.step = s.step + 1
                else
                    animal:setX(animal:getX() + dx / dist * budget)
                    animal:setY(animal:getY() + dy / dist * budget)
                    budget = 0
                end
            end
        else
            s.waited = s.waited + units
            if not animal:isAnimalAttacking() then
                done[#done + 1] = animal
                if not s.leader and not isGone(s.obj) then backOff(animal, s.obj) end
            elseif s.waited > STUMBLE_SETTLE_UNITS then
                done[#done + 1] = animal
            end
        end
    end
    for i = 1, #done do endStumble(done[i]) end
end

local function noteRams(animal, obj, perHit, hits)
    local leader = animal:getData():getAttachedPlayer()
    if leader then
        futile[animal] = nil
        breakFree(animal, obj, leader)
        return
    end

    local limit = option("GiveUpRams", 3)
    if limit <= 0 then return end
    if perHit > 0 then
        futile[animal] = nil
        return
    end

    local now = worldHours()
    local record = futile[animal]
    if not record or now - record.hours > FUTILE_MEMORY_HOURS then
        record = { count = 0 }
        futile[animal] = record
    end
    record.count = record.count + hits
    record.hours = now

    if record.count >= limit then
        futile[animal] = nil
        if isPanicOnly(animal) and animal:getStress() > CALM_STRESS then
            animal:setDebugStress(CALM_STRESS)
        end
        breakFree(animal, obj)
    end
end

-- Shields -------------------------------------------------------------------

local function shield(obj, hours)
    local entry = shields[obj]
    if entry then
        entry.untilHours = hours + SHIELD_HOURS
        return
    end
    local modData = obj:getModData()
    local real = modData[MOD_KEY] or obj:getHealth()
    modData[MOD_KEY] = real
    obj:setHealth(math.floor(real) + BUFFER)
    shields[obj] = { real = real, category = classify(obj), untilHours = hours + SHIELD_HOURS }
end

local function release(obj, entry)
    shields[obj] = nil
    obj:getModData()[MOD_KEY] = nil
    obj:setHealth(math.max(1, math.floor(entry.real)))
end

local function smash(obj)
    shields[obj] = nil
    obj:getModData()[MOD_KEY] = nil
    local square = obj:getSquare()
    local sound = instanceof(obj, "IsoThumpable") and obj:getBreakSound() or nil
    if sound then
        if SERVER then
            sendServerCommand(MODULE, "breakSound", { x = square:getX(), y = square:getY(), z = square:getZ(), sound = sound })
        else
            square:playSound(sound)
        end
    end
    addSound(nil, square:getX(), square:getY(), square:getZ(), 10, 20)
    obj:setHealth(0)
    obj:destroy()
end

local function settle(obj, entry)
    local health = obj:getHealth()
    local shielded = math.floor(entry.real) + BUFFER
    if health <= BUFFER / 2 then
        -- Something set the health outright (repair, another mod); adopt it as the real value.
        entry.real = health
    elseif health < shielded then
        local lost = shielded - health
        local damage = lost
        local animal, hits, remainder = findRammer(obj, lost)
        if animal then
            local perHit = ramDamage(animal, entry.category, obj)
            damage = perHit * hits + remainder
            noteRams(animal, obj, perHit, hits)
        end
        entry.real = entry.real - damage
    elseif health > shielded then
        entry.real = entry.real + (health - shielded)
    else
        return
    end
    if entry.real <= 0 then
        smash(obj)
        return
    end
    obj:getModData()[MOD_KEY] = entry.real
    obj:setHealth(math.floor(entry.real) + BUFFER)
end

-- Shields last SHIELD_HOURS, so an animal that hasn't left its square only needs a rescan to
-- refresh them and to catch objects built next to it since the last scan.
local function shieldAround(animal, hours)
    local x, y, z = math.floor(animal:getX()), math.floor(animal:getY()), math.floor(animal:getZ())
    local scan = scans[animal]
    if scan and not SERVER and scan.x == x and scan.y == y and scan.z == z
            and updateCount - scan.update < RESCAN_UPDATES and hours - scan.hours < SHIELD_HOURS / 2 then
        return
    end
    if not scan then
        scan = {}
        scans[animal] = scan
    end
    scan.x, scan.y, scan.z, scan.update, scan.hours = x, y, z, updateCount, hours

    local cell = getCell()
    for sx = x - SCAN_RADIUS, x + SCAN_RADIUS do
        for sy = y - SCAN_RADIUS, y + SCAN_RADIUS do
            local square = cell:getGridSquare(sx, sy, z)
            if square then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local obj = objects:get(i)
                    if isBreakable(obj) then shield(obj, hours) end
                end
            end
        end
    end
end

local function settleShields(hours)
    local done = {}
    for obj, entry in pairs(shields) do
        if isGone(obj) then
            done[#done + 1] = obj
        else
            settle(obj, entry)
            if shields[obj] and hours > entry.untilHours then done[#done + 1] = obj end
        end
    end
    for i = 1, #done do
        local obj = done[i]
        local entry = shields[obj]
        if entry then
            if isGone(obj) then shields[obj] = nil else release(obj, entry) end
        end
    end
end

-- Being spotted -------------------------------------------------------------
-- Vanilla's spotting has no line of sight: animals react to players and zombies within 10 tiles
-- on the same floor through any number of walls. Jogging players add stress regardless of trust;
-- sprinting players add none, because the game clears the running flag while sprinting. Zombies add
-- a trickle of stress and make the animal bolt within 6 tiles.
--
-- Small stress gains are undone while every jogger and zombie nearby is harmless (out of sight, or
-- a trusted jogger). Sprinting is a commotion heard through walls and always adds stress.

local function serverUnits()
    local now = getTimestampMs()
    local seconds = lastUpdateMs and math.min((now - lastUpdateMs) / 1000, MAX_SERVER_GAP_SECONDS) or 0
    lastUpdateMs = now
    return seconds * UNITS_PER_SECOND
end

local function within(a, b, radius)
    return math.floor(a:getZ()) == math.floor(b:getZ()) and a:DistTo(b) <= radius
end

-- On a server, updates are seconds apart, so someone who was moving fast last update still counts.
local function movingPlayers(people)
    local joggers, sprinters, jogging, sprinting = {}, {}, {}, {}
    for i = 1, #people do
        local p = people[i]
        if p:isSprinting() then
            sprinting[p] = true
        elseif p:isRunning() then
            jogging[p] = true
        end
        if jogging[p] or wasJogging[p] then joggers[#joggers + 1] = p end
        if sprinting[p] or wasSprinting[p] then sprinters[#sprinters + 1] = p end
    end
    wasJogging, wasSprinting = jogging, sprinting
    return joggers, sprinters
end

local function zombiesNear(animals)
    local result = {}
    if #animals == 0 then return result end
    local minX, minY = animals[1]:getX(), animals[1]:getY()
    local maxX, maxY = minX, minY
    for i = 2, #animals do
        local x, y = animals[i]:getX(), animals[i]:getY()
        minX, maxX = math.min(minX, x), math.max(maxX, x)
        minY, maxY = math.min(minY, y), math.max(maxY, y)
    end
    minX, maxX = minX - SPOT_RADIUS, maxX + SPOT_RADIUS
    minY, maxY = minY - SPOT_RADIUS, maxY + SPOT_RADIUS
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        local x = z:getX()
        if x >= minX and x <= maxX then
            local y = z:getY()
            if y >= minY and y <= maxY and not z:isDead() then
                result[#result + 1] = z
            end
        end
    end
    return result
end

-- Only animals whose stress just crept up, or that are bolting, look at zombies.
local function nearbyZombies()
    if not currentZombies then currentZombies = zombiesNear(currentAnimals) end
    return currentZombies
end

local function isHarmlessJogger(animal, p)
    if option("HiddenRunners", true) and not animal:CanSee(p) then return true end
    return option("FamiliarOwners", true)
        and animal:getAcceptanceLevel(p) >= option("FamiliarAcceptance", 50)
end

local function isHiddenZombie(animal, z)
    return option("HiddenZombies", true) and not animal:CanSee(z)
end

local function calm(animal, stress, joggers, cap)
    local before = lastStress[animal]
    if not before or stress <= before or stress - before > cap then return stress end

    local excused = false
    for i = 1, #joggers do
        if within(animal, joggers[i], SPOT_RADIUS) then
            if not isHarmlessJogger(animal, joggers[i]) then return stress end
            excused = true
        end
    end
    local zombies = nearbyZombies()
    for i = 1, #zombies do
        if within(animal, zombies[i], SPOT_RADIUS) then
            if not isHiddenZombie(animal, zombies[i]) then return stress end
            excused = true
        end
    end
    if not excused then return stress end
    animal:setDebugStress(before)
    return before
end

local function spookBySprinters(animal, sprinters, units)
    for i = 1, #sprinters do
        if within(animal, sprinters[i], SPOT_RADIUS) then
            animal:changeStress(units * VANILLA_RUN_STRESS * SPRINT_STRESS_FACTOR)
        end
    end
end

-- Vanilla makes the animal bolt (with a stressed call) from any zombie within 6 tiles. Stop the
-- bolt when every zombie that close is out of sight and nothing else nearby is visible to flee from.
local function cancelPhantomFlee(animal, people)
    if not option("HiddenZombies", true) then return end
    if not animal:getVariableBoolean("animalRunning") then return end
    if animal:isAnimalAttacking() or animal:getAttackedBy() then return end

    local zombies = nearbyZombies()
    local hiddenClose = false
    for i = 1, #zombies do
        local z = zombies[i]
        if within(animal, z, SPOT_RADIUS) then
            if animal:CanSee(z) then return end
            if within(animal, z, ZOMBIE_FLEE_RADIUS) then hiddenClose = true end
        end
    end
    if not hiddenClose then return end
    for i = 1, #people do
        if within(animal, people[i], SPOT_RADIUS) and animal:CanSee(people[i]) then return end
    end
    animal:stopAllMovementNow()
    animal:setVariable("animalRunning", false)
end

-- Events --------------------------------------------------------------------

local function update(units, moveStumbles)
    updateCount = updateCount + 1
    local hours = worldHours()

    local list = getCell():getAnimals()
    local animals = {}
    for i = 0, list:size() - 1 do
        local animal = list:get(i)
        if not animal:isDead() and animal:getSquare() and not animal:isWild() then
            animals[#animals + 1] = animal
        end
    end
    currentAnimals = animals
    currentZombies = nil

    local people = players()
    local joggers, sprinters = movingPlayers(people)
    local cap = units * MAX_SPOT_STRESS
    local seen = {}
    rammers = {}

    for i = 1, #animals do
        local animal = animals[i]
        calm(animal, animal:getStress(), joggers, cap)
        spookBySprinters(animal, sprinters, units)
        cancelPhantomFlee(animal, people)
        seen[animal] = animal:getStress()

        if canThump(animal) then
            local agitated = isAgitated(animal)
            -- An update can land after the ram (100 ms in single player, seconds on a server),
            -- when the animal may have stopped attacking.
            if agitated then
                rammers[#rammers + 1] = animal
            end
            if agitated then shieldAround(animal, hours) end
        end
    end
    lastStress = seen
    currentZombies = nil

    if moveStumbles then updateStumbles(units) end
    settleShields(hours)

    local gone = {}
    for animal in pairs(futile) do
        if not seen[animal] then gone[#gone + 1] = animal end
    end
    for animal in pairs(stumbles) do
        if not seen[animal] then gone[#gone + 1] = animal end
    end
    for animal in pairs(scans) do
        if not seen[animal] then gone[#gone + 1] = animal end
    end
    for i = 1, #gone do
        local animal = gone[i]
        futile[animal] = nil
        endStumble(animal)
        scans[animal] = nil
    end
end

-- Stress gains and stumbles are scaled by the GameTime multiplier, so it is summed over the
-- ticks between updates.
local function onTick()
    local multiplier = getGameTime():getMultiplier()
    pendingUnits = pendingUnits + multiplier
    if stumbleCount > 0 then updateStumbles(multiplier) end

    local now = getTimestampMs()
    if now < nextUpdateMs then return end
    nextUpdateMs = now + UPDATE_INTERVAL_MS
    local units = pendingUnits
    pendingUnits = 0
    update(units, false)
end

local function onEveryOneMinute()
    update(serverUnits(), true)
end

local function onSave()
    local list = {}
    for obj, entry in pairs(shields) do list[#list + 1] = { obj, entry } end
    for i = 1, #list do
        local obj, entry = list[i][1], list[i][2]
        if isGone(obj) then shields[obj] = nil else release(obj, entry) end
    end
    -- Released objects must be shielded again on the next update.
    scans = {}
end

local function onLoadGridsquare(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj:hasModData() and isBreakable(obj) and not shields[obj] then
            local modData = obj:getModData()
            local real = modData[MOD_KEY]
            if real then
                modData[MOD_KEY] = nil
                obj:setHealth(math.max(1, math.floor(real)))
            end
        end
    end
end

require "Moveables/ISMoveableSpriteProps"
if ISMoveableSpriteProps and not ISMoveableSpriteProps.SensibleLivestock_Hooked then
    ISMoveableSpriteProps.SensibleLivestock_Hooked = true
    local originalSave = ISMoveableSpriteProps.saveThumpableParameters
    ISMoveableSpriteProps.saveThumpableParameters = function(self, _table, _object)
        originalSave(self, _table, _object)
        local entry = shields[_object]
        local real = entry and entry.real
        if type(_table.modData) == "table" then
            real = real or _table.modData[MOD_KEY]
            _table.modData[MOD_KEY] = nil
        end
        if real then _table.health = math.max(1, math.floor(real)) end
    end
end

if SERVER then
    Events.EveryOneMinute.Add(onEveryOneMinute)
else
    Events.OnTick.Add(onTick)
end
Events.OnSave.Add(onSave)
Events.LoadGridsquare.Add(onLoadGridsquare)
