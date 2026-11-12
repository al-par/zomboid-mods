require "HomeHeating/HH_Shared"
require "HomeHeating/HH_Build"

local HH = HomeHeating
HH.World = HH.World or {}
local World = HH.World

local fires = {}     -- key -> IsoFireplace (hearth fire squares, coal heaters)
local electrics = {} -- key -> IsoThumpable
local shown = {}     -- key -> lit state the overlays were last drawn for
local heat = {}      -- key -> IsoHeatSource of a running electric heater
local genCache = {}  -- key -> generator square key, for heaters powered without SensiblePowerManagement

local function objKey(obj)
    local sq = obj:getSquare()
    return sq and HH.key(sq:getX(), sq:getY(), sq:getZ()) or nil
end

local function alive(obj)
    return obj ~= nil and obj:getSquare() ~= nil and obj:getObjectIndex() >= 0
end

local function binKind(obj)
    return obj:getModData().hhDesign and HH.BIN_WOOD or HH.BIN_COAL
end

-- Move fuel from the bin into the fire until it holds at least target minutes.
function World.feed(obj, target)
    local kind = binKind(obj)
    local bin = obj:getContainerByType(kind)
    if not bin then return end
    local cur = obj:getFuelAmount()
    if not target then
        if cur >= HH.FUEL_LOW then return end
        target = HH.FUEL_TARGET
    end
    local accept = kind == HH.BIN_COAL and HH.isCharcoal or HH.isWood
    local items = bin:getItems()
    local i, added = 0, 0
    while cur + added < target and i < items:size() do
        local item = items:get(i)
        local minutes = accept(item) and not item:IsDrainable() and HH.fuelMinutes(kind, item) or 0
        if minutes > 0 then
            bin:Remove(item)
            sendRemoveItemFromContainer(bin, item)
            added = added + minutes
        else
            i = i + 1
        end
    end
    if added > 0 then
        obj:setFuelAmount(cur + added)
        obj:sendObjectChange(IsoObjectChange.STATE)
    end
end

local function drawFire(key, obj, lit)
    local md = obj:getModData()
    if md.hhDesign then
        local z = obj:getSquare():getZ()
        for i, p in pairs(HH.hearthParts(md, z)) do
            local pmd = p:getModData()
            p:setOverlaySprite(lit and HH.hearthSprite(pmd.hhDesign, pmd.hhMat, pmd.hhQ, pmd.hhWest, pmd.hhKit, true, i) or "")
        end
        local cook = obj:getContainerByType(HH.COOKING)
        if lit and cook then cook:addItemsToProcessItems() end
    else
        local _, k = HH.heaterKind(HH.spriteName(obj))
        local glow = k and HH.glowSprite("coal", k)
        obj:setOverlaySprite(lit and glow or "")
    end
    shown[key] = lit
end

local function drawElectric(key, obj, on)
    local _, k = HH.heaterKind(HH.spriteName(obj))
    obj:setOverlaySprite(on and k and HH.glowSprite("electric", k) or "")
    shown[key] = on
end

local function stopHeat(key)
    local hs = heat[key]
    if hs then
        getCell():removeHeatSource(hs)
        heat[key] = nil
    end
end

function World.isPowered(sq)
    return sq ~= nil and (sq:haveElectricity() or sq:hasGridPower())
end

-- Containers keep their items and capacity in the save but not their accept function.
local function restore(obj)
    local md = obj:getModData()
    if md.hhDesign then
        local bin = obj:getContainerByType(HH.BIN_WOOD)
        if bin then
            bin:setAcceptItemFunction("HomeHeating_AcceptWood")
            bin:setCapacity(HH.binCapacity(HH.BIN_WOOD))
        end
        if md.hhKit and not obj:getContainerByType(HH.COOKING) then
            obj:addSecondaryContainer(HH.newContainer(obj, HH.COOKING, 20, nil))
        end
    elseif md.hhKind == "coal" or HH.heaterKind(HH.spriteName(obj)) == "coal" then
        md.hhKind = "coal"
        local bin = obj:getContainerByType(HH.BIN_COAL)
        if bin then
            bin:setAcceptItemFunction("HomeHeating_AcceptCharcoal")
            bin:setCapacity(HH.binCapacity(HH.BIN_COAL))
        else
            obj:addSecondaryContainer(HH.newContainer(obj, HH.BIN_COAL, HH.binCapacity(HH.BIN_COAL), "HomeHeating_AcceptCharcoal"))
        end
    end
end

function World.register(obj, redraw)
    local key = objKey(obj)
    if not key then return end
    if instanceof(obj, "IsoFireplace") then
        fires[key] = obj
    elseif obj:getModData().hhKind == "electric" then
        electrics[key] = obj
    end
    if redraw then shown[key] = nil end
end

-- At load the fire burns all the time its chunk was away in one go. Feed it for that time first,
-- as far as the bin allows, so a stocked fire is still going when the player comes back.
local function onLoadFire(obj)
    if not instanceof(obj, "IsoFireplace") then return end
    restore(obj)
    local md = obj:getModData()
    if obj:isLit() and md.hhT then
        local away = math.max(0, (getGameTime():getWorldAgeHours() - md.hhT) * 60)
        World.feed(obj, away + HH.FUEL_TARGET)
    end
    local key = objKey(obj)
    fires[key] = obj
    shown[key] = nil
end

local function onLoadElectric(obj)
    local md = obj:getModData()
    md.hhKind = "electric"
    local key = objKey(obj)
    electrics[key] = obj
    shown[key] = nil
end

local function everyMinute()
    local now = getGameTime():getWorldAgeHours()
    for key, obj in pairs(fires) do
        if not alive(obj) then
            fires[key], shown[key] = nil, nil
        else
            World.feed(obj)
            obj:getModData().hhT = now
            local lit = obj:isLit()
            if shown[key] ~= lit then drawFire(key, obj, lit) end
        end
    end
    for key, obj in pairs(electrics) do
        if not alive(obj) then
            stopHeat(key)
            electrics[key], shown[key], genCache[key] = nil, nil, nil
        else
            local sq = obj:getSquare()
            local on = obj:getModData().hhOn == true and World.isPowered(sq)
            if on and not heat[key] then
                local hs = IsoHeatSource.new(sq:getX(), sq:getY(), sq:getZ(), HH.HEAT_RADIUS, HH.HEAT_TEMP)
                getCell():addHeatSource(hs)
                heat[key] = hs
            elseif not on then
                stopHeat(key)
            end
            if shown[key] ~= on then drawElectric(key, obj, on) end
        end
    end
end

local function covers(m, x, y, z, r2, v)
    local dx, dy = m.x - x, m.y - y
    return dx * dx + dy * dy <= r2 and math.abs(m.z - z) <= v
end

-- SensiblePowerManagement pools every generator; bill the running members of the pool reaching sq.
local function billPool(sq, amount)
    if not (PGP and PGP.getData and PGP.runningMembers) then return false end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local st = PGP.ensureState and PGP.ensureState()
    local v = PGP.verticalRange()
    for pid, pool in pairs(PGP.getData().pools) do
        local runners = PGP.runningMembers(pool)
        if #runners > 0 then
            local r = (st and st.poolRadius and st.poolRadius[pid]) or PGP.baseRadius()
            local reached = false
            for _, m in ipairs(runners) do
                if covers(m, x, y, z, r * r, v) then reached = true break end
            end
            if reached then
                local share = amount / #runners
                for _, m in ipairs(runners) do
                    local gen = PGP.getGeneratorAt(m.x, m.y, m.z)
                    if gen and gen:isActivated() then gen:setFuel(math.max(0, gen:getFuel() - share)) end
                end
                return true
            end
        end
    end
    return false
end

local function generatorAtKey(k)
    if not k then return nil end
    local x, y, z = string.match(k, "^(-?%d+),(-?%d+),(-?%d+)$")
    local gsq = getCell():getGridSquare(tonumber(x), tonumber(y), tonumber(z))
    return gsq and gsq:getGenerator() or nil
end

local function findGenerator(sq)
    local r = SandboxVars.GeneratorTileRange or 20
    local v = SandboxVars.GeneratorVerticalPowerRange or 3
    local cell = getCell()
    local x0, y0, z0 = sq:getX(), sq:getY(), sq:getZ()
    for z = z0 - v, z0 + v do
        for y = y0 - r, y0 + r do
            for x = x0 - r, x0 + r do
                local gsq = cell:getGridSquare(x, y, z)
                local gen = gsq and gsq:getGenerator()
                if gen and gen:isActivated() and gen:isConnected() then return HH.key(x, y, z), gen end
            end
        end
    end
    return nil
end

-- A failed search scans thousands of squares, so it is retried at most once per game hour.
local searchAgainAt = {}

local function billGenerator(key, sq, amount)
    if billPool(sq, amount) then return end
    local gen = generatorAtKey(genCache[key])
    if not (gen and gen:isActivated()) then
        local now = getGameTime():getWorldAgeHours()
        if now < (searchAgainAt[key] or 0) then return end
        genCache[key], gen = findGenerator(sq)
        searchAgainAt[key] = gen == nil and now + 1 or nil
    end
    if gen then gen:setFuel(math.max(0, gen:getFuel() - amount)) end
end

local function everyTenMinutes()
    local amount = HH.ELEC_DRAW * (SandboxVars.GeneratorFuelConsumption or 1) / 6
    for key, obj in pairs(electrics) do
        if heat[key] and alive(obj) then
            local sq = obj:getSquare()
            if not sq:hasGridPower() then billGenerator(key, sq, amount) end
        end
    end
end

function World.setElectric(obj, on)
    obj:getModData().hhOn = on and true or false
    World.register(obj, true)
    everyMinute()
end

function World.refresh(obj)
    World.register(obj, true)
    everyMinute()
end

local function spriteLists()
    local fireSprites, elec = {}, {}
    for design, def in pairs(HH.DESIGNS) do
        for _, mat in ipairs({ "brick", "stone" }) do
            for _, q in ipairs({ "rough", "neat" }) do
                for _, west in ipairs({ false, true }) do
                    for _, kit in ipairs({ false, true }) do
                        table.insert(fireSprites, HH.hearthSprite(design, mat, q, west, kit, false, def.fire))
                    end
                end
            end
        end
    end
    for k = 0, 3 do
        table.insert(fireSprites, HH.MISC .. "_" .. (HH.COAL_FIRST + k))
        table.insert(elec, HH.MISC .. "_" .. (HH.ELEC_FIRST + k))
    end
    return fireSprites, elec
end

if not isClient() then
    local fireSprites, elec = spriteLists()
    MapObjects.OnLoadWithSprite(fireSprites, onLoadFire, 5)
    MapObjects.OnLoadWithSprite(elec, onLoadElectric, 5)
    Events.EveryOneMinute.Add(everyMinute)
    Events.EveryTenMinutes.Add(everyTenMinutes)
end
