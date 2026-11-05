-- Pooled Generator Power: authoritative logic (single player host or dedicated server).
require "PGP/PGP_Core"

if isClient() then return end

PGP.Server = PGP.Server or {}
local S = PGP.Server

S.live = {}         -- member key -> { gen, member } for loaded pool generators
S.loadedSince = {}  -- member key -> { gen, hour } when that generator object was first seen loaded
S.pendingAdopt = {}
S.scan = nil        -- in-progress load scan
S.needTransmit = false
S.needScan = true
S.needLive = true

local TOP_UP_BELOW = 0.25

function S.changed()
    PGP.markDirty()
    S.needTransmit = true
    S.needScan = true
    S.needLive = true
end

local function genKey(gen)
    local sq = gen and gen:getSquare()
    return sq and PGP.squareKey(sq) or nil
end

local function newMember(gen)
    local sq = gen:getSquare()
    return { x = sq:getX(), y = sq:getY(), z = sq:getZ(), running = gen:isActivated() }
end

---------------------------------------------------------------------------------------------------
-- Cable sprites
---------------------------------------------------------------------------------------------------

function S.refreshCableSprites(x, y, z)
    local cell = getCell()
    local spots = { { x, y } }
    for _, d in ipairs(PGP.DIRS) do table.insert(spots, { x + d.dx, y + d.dy }) end
    for _, s in ipairs(spots) do
        local obj = PGP.getCableObject(cell:getGridSquare(s[1], s[2], z))
        if obj then
            local want = PGP.cableSpriteName(PGP.cableMask(s[1], s[2], z))
            if obj:getSprite():getName() ~= want then
                obj:setSprite(getSprite(want))
                if isServer() then obj:transmitUpdatedSpriteToClients() end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------------------------------------

function S.createPool(gen)
    local k = genKey(gen)
    if not k or PGP.ensureState().memberPool[k] then return nil end
    local data = PGP.getData()
    local pid = "p" .. data.nextId
    data.nextId = data.nextId + 1
    data.pools[pid] = { id = pid, load = 0, members = { [k] = newMember(gen) } }
    S.changed()
    PGP.rebuild()
    local sq = gen:getSquare()
    S.refreshCableSprites(sq:getX(), sq:getY(), sq:getZ())
    S.topUpPool(pid)
    return pid
end

function S.addMember(pid, gen)
    local k = genKey(gen)
    local pool = PGP.getPool(pid)
    if not k or not pool then return false end
    pool.members[k] = newMember(gen)
    S.changed()
    PGP.rebuild()
    local sq = gen:getSquare()
    S.refreshCableSprites(sq:getX(), sq:getY(), sq:getZ())
    S.topUpPool(pid)
    return true
end

function S.removeMemberAt(k)
    local data = PGP.getData()
    for pid, pool in pairs(data.pools) do
        local m = pool.members[k]
        if m then
            pool.members[k] = nil
            if PGP.firstKey(pool.members) == nil then data.pools[pid] = nil end
            S.loadedSince[k] = nil
            S.changed()
            PGP.rebuild()
            S.refreshCableSprites(m.x, m.y, m.z)
            return true
        end
    end
    return false
end

function S.removeGenerator(gen)
    local k = genKey(gen)
    if k then S.removeMemberAt(k) end
end

-- Connected generators that predate the mod (or were connected without our hooks) join the single
-- pool they touch, otherwise they get their own pool.
function S.adopt(gen)
    if not gen or not gen:isConnected() or PGP.poolIdOfGenerator(gen) then return nil end
    local sq = gen:getSquare()
    local pools, n = PGP.touchingPools(sq:getX(), sq:getY(), sq:getZ())
    if n == 1 then
        local pid = PGP.firstKey(pools)
        S.addMember(pid, gen)
        return pid
    end
    return S.createPool(gen)
end

function S.onActivated(gen)
    if not gen then return end
    S.adopt(gen)
    local pid = PGP.poolIdOfGenerator(gen)
    local pool = PGP.getPool(pid)
    local m = pool and pool.members[genKey(gen)]
    if m and m.running ~= gen:isActivated() then
        m.running = gen:isActivated()
        S.changed()
    end
end

function S.onPlumbed(gen)
    local pid = PGP.poolIdOfGenerator(gen)
    if pid then S.topUpPool(pid) end
    S.needTransmit = true
end

---------------------------------------------------------------------------------------------------
-- Cables
---------------------------------------------------------------------------------------------------

function S.placeCable(sq, itemType)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    if not PGP.checkCable(x, y, z) then return false end
    local data = PGP.getData()
    data.cables[PGP.key(x, y, z)] = { x = x, y = y, z = z, item = itemType }
    PGP.rebuild()
    local obj = IsoObject.new(sq, PGP.cableSpriteName(PGP.cableMask(x, y, z)), "PGP_ExtensionCable")
    sq:AddTileObject(obj)
    obj:transmitCompleteItemToClients()
    S.refreshCableSprites(x, y, z)
    S.changed()
    return true
end

-- Returns the full type of the item the cable was laid from.
function S.removeCable(sq, obj)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local k = PGP.key(x, y, z)
    local cable = PGP.getData().cables[k]
    local itemType = cable and PGP.CABLE_ITEMS[cable.item] and cable.item or PGP.CABLE_ITEM
    PGP.getData().cables[k] = nil
    if obj then
        sq:transmitRemoveItemFromSquare(obj)
        if obj:getObjectIndex() ~= -1 then sq:RemoveTileObject(obj) end
    end
    PGP.rebuild()
    S.refreshCableSprites(x, y, z)
    S.changed()
    return itemType
end

---------------------------------------------------------------------------------------------------
-- Cleanup of members and cables whose objects vanished (destroyed, burnt, unplugged elsewhere).
---------------------------------------------------------------------------------------------------

function S.validate()
    local data = PGP.getData()
    local cell = getCell()
    local staleMembers, staleCables = {}, {}
    for _, pool in pairs(data.pools) do
        for k, m in pairs(pool.members) do
            local sq = cell:getGridSquare(m.x, m.y, m.z)
            if sq then
                local gen = sq:getGenerator()
                if not gen or not gen:isConnected() then table.insert(staleMembers, k) end
            end
        end
    end
    for k, c in pairs(data.cables) do
        local sq = cell:getGridSquare(c.x, c.y, c.z)
        if sq and not PGP.getCableObject(sq) then table.insert(staleCables, c) end
    end
    for _, k in ipairs(staleMembers) do S.removeMemberAt(k) end
    for _, c in ipairs(staleCables) do
        data.cables[PGP.key(c.x, c.y, c.z)] = nil
        PGP.rebuild()
        S.refreshCableSprites(c.x, c.y, c.z)
        S.changed()
    end
end

function S.onChunkLoaded(chunk)
    local z0, z1 = chunk:getMinLevel(), chunk:getMaxLevel()
    for z = z0, z1 do
        for ly = 0, 7 do
            for lx = 0, 7 do
                local sq = chunk:getGridSquare(lx, ly, z)
                local gen = sq and sq:getGenerator()
                if gen and gen:isConnected() then table.insert(S.pendingAdopt, gen) end
            end
        end
    end
    S.needLive = true
end

function S.processPendingAdopt()
    local list = S.pendingAdopt
    S.pendingAdopt = {}
    for _, gen in ipairs(list) do
        if gen:getObjectIndex() ~= -1 then S.adopt(gen) end
    end
end

---------------------------------------------------------------------------------------------------
-- Load split: every powered appliance is billed once at its vanilla rate, divided evenly between
-- the pools covering it, then evenly between the running generators of each pool.
---------------------------------------------------------------------------------------------------

local function covered(runners, x, y, z, r2, v)
    for _, m in ipairs(runners) do
        if math.abs(z - m.z) <= v then
            local dx, dy = x - m.x, y - m.y
            if dx * dx + dy * dy <= r2 then return true end
        end
    end
    return false
end

function S.scanPool(pid, consumers)
    local pool = PGP.getPool(pid)
    if not pool then return end
    local runners = PGP.runningMembers(pool)
    if #runners == 0 then return end
    local st = PGP.ensureState()
    local r = st.poolRadius[pid] or PGP.baseRadius()
    local r2, v = r * r, PGP.verticalRange()
    local allowExterior = SandboxVars.AllowExteriorGenerator
    local minX, minY, maxX, maxY, minZ, maxZ
    for _, m in ipairs(runners) do
        minX = math.min(minX or m.x, m.x - r); maxX = math.max(maxX or m.x, m.x + r)
        minY = math.min(minY or m.y, m.y - r); maxY = math.max(maxY or m.y, m.y + r)
        minZ = math.min(minZ or m.z, m.z - v); maxZ = math.max(maxZ or m.z, m.z + v)
    end
    for wy = math.floor(minY / 8), math.floor(maxY / 8) do
        for wx = math.floor(minX / 8), math.floor(maxX / 8) do
            local chunk = PGP.chunkAt(wx, wy)
            if chunk then
                for z = math.max(minZ, chunk:getMinLevel()), math.min(maxZ, chunk:getMaxLevel()) do
                    for ly = 0, 7 do
                        for lx = 0, 7 do
                            local sq = chunk:getGridSquare(lx, ly, z)
                            if sq then
                                local objects = sq:getObjects()
                                local n = objects:size()
                                local x, y = wx * 8 + lx, wy * 8 + ly
                                if n > 0 and covered(runners, x, y, z, r2, v)
                                        and not sq:hasGridPower()
                                        and (allowExterior or not sq:has(IsoFlagType.exterior)) then
                                    for i = 0, n - 1 do
                                        local c = objects:get(i):getGeneratorPowerConsumption()
                                        if c > 0 then
                                            local ck = x .. "," .. y .. "," .. z .. ":" .. i
                                            local e = consumers[ck]
                                            if not e then
                                                e = { c = c, n = 0, pools = {} }
                                                consumers[ck] = e
                                            end
                                            if not e.pools[pid] then
                                                e.pools[pid] = true
                                                e.n = e.n + 1
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function S.startScan()
    local queue = {}
    for pid, pool in pairs(PGP.getData().pools) do
        if #PGP.runningMembers(pool) > 0 then table.insert(queue, pid) end
    end
    S.scan = { queue = queue, i = 1, consumers = {} }
    S.needScan = false
end

function S.finishScan(scan)
    local share = {}
    for _, e in pairs(scan.consumers) do
        for pid in pairs(e.pools) do
            share[pid] = (share[pid] or 0) + e.c / e.n
        end
    end
    for pid, pool in pairs(PGP.getData().pools) do
        local load = share[pid] or 0
        local runners = #PGP.runningMembers(pool)
        pool.load = load
        for _, m in pairs(pool.members) do
            m.raw = (m.running and runners > 0) and (PGP.IDLE_DRAW + load / runners) or nil
        end
    end
    S.needTransmit = true
end

function S.stepScan()
    local scan = S.scan
    local pid = scan.queue[scan.i]
    if pid then
        S.scanPool(pid, scan.consumers)
        scan.i = scan.i + 1
    else
        S.finishScan(scan)
        S.scan = nil
    end
end

function S.rebuildLive()
    local now = getGameTime():getWorldAgeHours()
    local live, since = {}, {}
    for _, pool in pairs(PGP.getData().pools) do
        for k, m in pairs(pool.members) do
            local gen = PGP.getGeneratorAt(m.x, m.y, m.z)
            if gen then
                live[k] = { gen = gen, member = m }
                local prev = S.loadedSince[k]
                since[k] = (prev and prev.gen == gen) and prev or { gen = gen, hour = now }
            end
        end
    end
    S.live, S.loadedSince = live, since
    S.needLive = false
end

-- Vanilla bills the hours a generator missed while unloaded on its first update after loading;
-- fuel bookkeeping waits a game minute so it never runs before that.
function S.isSettled(key, now)
    local since = S.loadedSince[key]
    return since ~= nil and now - since.hour >= 1 / 60
end

-- Vanilla recomputes a generator's draw whenever nearby chunks or objects change, so the pool
-- share is re-applied every tick; vanilla bills it on the hour.
function S.applyShares()
    for k, e in pairs(S.live) do
        local gen = e.gen
        if gen:getObjectIndex() == -1 then
            S.live[k] = nil
            S.needLive = true
        else
            local running = gen:isActivated()
            if running ~= e.member.running then
                e.member.running = running
                S.changed()
            end
            if running and e.member.raw then
                gen:setTotalPowerUsing(e.member.raw)
            end
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Fuel: plumbed generators are topped up from petrol barrels in the pool's fuel area.
---------------------------------------------------------------------------------------------------

local function drain(barrels, amount)
    local got = 0
    for _, b in ipairs(barrels) do
        if got >= amount - 0.0001 then break end
        local have = b.fc:getAmount()
        if have > 0.0001 then
            local take = math.min(have, amount - got)
            b.fc:adjustAmount(have - take)
            b.obj:sync()
            triggerEvent("OnWaterAmountChange", b.obj, have)
            got = got + take
        end
    end
    return got
end

local function fillTank(gen, barrels)
    local need = gen:getMaxFuel() - gen:getFuel()
    if need <= TOP_UP_BELOW then return end
    local got = drain(barrels, need)
    if got > 0 then
        gen:setFuel(gen:getFuel() + got)
        gen:sync()
    end
end

function S.topUpPool(pid)
    local pool = PGP.getPool(pid)
    if not pool then return end
    local plumbed = PGP.plumbedGenerators(pool)
    if #plumbed == 0 then return end
    local barrels = PGP.collectBarrels(plumbed)
    if #barrels == 0 then return end
    for _, p in ipairs(plumbed) do fillTank(p.gen, barrels) end
end

-- A plumbed generator that ran dry while its chunk was unloaded is billed to the barrels for the
-- hours it missed and restarted, if the barrels hold enough. One that ran dry while watched had
-- already emptied the barrels, so it is only marked as stopped.
local function catchUp(gen, m, barrels, now)
    if m.wasRunning and m.lastSeenHour and gen:isConnected() and gen:getCondition() > 0 and gen:getFuel() <= 0.01 then
        local perHour = (m.raw or PGP.IDLE_DRAW) * PGP.fuelMultiplier()
        local owed = math.max(0, (now - m.lastSeenHour) * perHour - (m.lastFuel or 0))
        if PGP.barrelPetrol(barrels) > owed + 0.1 then
            drain(barrels, owed)
            fillTank(gen, barrels)
            gen:setActivated(true)
            m.running = true
            S.changed()
        else
            drain(barrels, owed)
        end
    end
    m.wasRunning = gen:isActivated()
end

function S.fuelPass()
    local now = getGameTime():getWorldAgeHours()
    for _, pool in pairs(PGP.getData().pools) do
        local settled = {}
        for _, p in ipairs(PGP.plumbedGenerators(pool)) do
            if S.isSettled(p.key, now) then table.insert(settled, p) end
        end
        if #settled > 0 then
            local barrels = PGP.collectBarrels(settled)
            for _, p in ipairs(settled) do
                if not p.gen:isActivated() then catchUp(p.gen, p.member, barrels, now) end
            end
            for _, p in ipairs(settled) do fillTank(p.gen, barrels) end
            for _, p in ipairs(settled) do
                if p.gen:isActivated() then
                    p.member.wasRunning = true
                    p.member.lastSeenHour = now
                    p.member.lastFuel = p.gen:getFuel()
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local function onTick()
    if #S.pendingAdopt > 0 then S.processPendingAdopt() end
    if S.needLive then S.rebuildLive() end
    S.applyShares()
    if S.needScan and not S.scan then S.startScan() end
    if S.scan then S.stepScan() end
    if S.needTransmit then
        S.needTransmit = false
        if isServer() then ModData.transmit(PGP.MODDATA_KEY) end
    end
end

local function everyTenMinutes()
    S.validate()
    S.fuelPass()
    S.needScan = true
    S.needTransmit = true
end

Events.OnTick.Add(onTick)
Events.EveryTenMinutes.Add(everyTenMinutes)
Events.EveryOneMinute.Add(function() S.needLive = true end)
