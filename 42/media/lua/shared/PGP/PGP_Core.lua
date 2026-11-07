-- Pooled Generator Power: shared data model, placement rules and extended power range.
--
-- Global ModData (server-authoritative, transmitted to clients):
--   pools[poolId]  = { id, load, members = { ["x,y,z"] = { x, y, z, running, raw, ... } } }
--   cables["x,y,z"] = { x, y, z, item }  (item: full type it was laid from)

PGP = PGP or {}

PGP.MODDATA_KEY = "PooledGeneratorPower"
PGP.TILESET = "pgp_extension_cable"
PGP.CABLE_ITEM = "Base.PGP_ExtensionCable"
-- Items that can be laid as an extension cable; picking the cable up gives the same item back.
PGP.CABLE_ITEMS = { [PGP.CABLE_ITEM] = true, ["Base.PowerBar"] = true }

function PGP.isCableItem(item)
    return item ~= nil and PGP.CABLE_ITEMS[item:getFullType()] == true
end

-- A makeshift cable lays this many tiles; anything else lays one.
PGP.CABLE_USES = 5

function PGP.cableUses(item)
    if item:getFullType() ~= PGP.CABLE_ITEM then return 1 end
    return item:getModData().pgpUses or PGP.CABLE_USES
end

function PGP.setCableUses(item, uses)
    item:getModData().pgpUses = uses
    local name = getItemNameFromFullType(item:getFullType())
    if uses < PGP.CABLE_USES then
        item:setName(getText("IGUI_PGP_CableUses", name, uses, PGP.CABLE_USES))
        item:setCustomName(true)
    else
        item:setName(name)
        item:setCustomName(false)
    end
end
PGP.IDLE_DRAW = 0.02

-- Orthogonal neighbours; bit values match the cable sprite index (N=1, E=2, S=4, W=8).
PGP.DIRS = {
    { dx = 0, dy = -1, bit = 1 },
    { dx = 1, dy = 0, bit = 2 },
    { dx = 0, dy = 1, bit = 4 },
    { dx = -1, dy = 0, bit = 8 },
}

PGP.dirty = true
PGP.powerDirty = false
PGP.state = { memberPool = {}, cablePool = {}, poolCables = {}, poolRadius = {} }

-- The game's Lua has no next().
function PGP.firstKey(t)
    for k in pairs(t) do return k end
    return nil
end

function PGP.key(x, y, z)
    return x .. "," .. y .. "," .. z
end

function PGP.squareKey(sq)
    return PGP.key(sq:getX(), sq:getY(), sq:getZ())
end

function PGP.baseRadius()
    return SandboxVars.GeneratorTileRange or 20
end

function PGP.verticalRange()
    return SandboxVars.GeneratorVerticalPowerRange or 3
end

function PGP.tilesPerCable()
    local o = SandboxVars.PooledGeneratorPower
    return (o and o.TilesPerCable) or 1
end

function PGP.maxCables()
    local o = SandboxVars.PooledGeneratorPower
    return (o and o.MaxCablesPerPool) or 40
end

function PGP.fuelMultiplier()
    return SandboxVars.GeneratorFuelConsumption or 1
end

function PGP.getData()
    local data = ModData.getOrCreate(PGP.MODDATA_KEY)
    data.pools = data.pools or {}
    data.cables = data.cables or {}
    data.nextId = data.nextId or 1
    return data
end

function PGP.markDirty()
    PGP.dirty = true
end

function PGP.isPlumbed(gen)
    return gen ~= nil and gen:getModData().pgpPlumbed == true
end

function PGP.getGeneratorAt(x, y, z)
    local cell = getCell()
    local sq = cell and cell:getGridSquare(x, y, z)
    return sq and sq:getGenerator() or nil
end

function PGP.isCableObject(obj)
    local sprite = obj and obj:getSprite()
    local name = sprite and sprite:getName()
    return name ~= nil and string.sub(name, 1, #PGP.TILESET) == PGP.TILESET
end

function PGP.getCableObject(sq)
    if not sq then return nil end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if PGP.isCableObject(obj) then return obj end
    end
    return nil
end

function PGP.cableSpriteName(mask)
    return PGP.TILESET .. "_" .. mask
end

---------------------------------------------------------------------------------------------------
-- Derived state: which pool owns each generator and cable, cable counts and pool radius.
---------------------------------------------------------------------------------------------------

function PGP.rebuild()
    local data = PGP.getData()
    local memberPool, cablePool, poolCables, poolRadius = {}, {}, {}, {}

    for pid, pool in pairs(data.pools) do
        for k, _ in pairs(pool.members) do
            memberPool[k] = pid
        end
    end

    for pid, pool in pairs(data.pools) do
        local queue = {}
        local function visit(x, y, z)
            local k = PGP.key(x, y, z)
            local cable = data.cables[k]
            if cable and cablePool[k] == nil then
                cablePool[k] = pid
                table.insert(queue, cable)
            end
        end
        for _, m in pairs(pool.members) do
            for _, d in ipairs(PGP.DIRS) do
                visit(m.x + d.dx, m.y + d.dy, m.z)
            end
        end
        local i = 1
        while i <= #queue do
            local c = queue[i]
            i = i + 1
            for _, d in ipairs(PGP.DIRS) do
                visit(c.x + d.dx, c.y + d.dy, c.z)
            end
        end
        poolCables[pid] = #queue
    end

    local base, perCable, maxCables = PGP.baseRadius(), PGP.tilesPerCable(), PGP.maxCables()
    for pid, n in pairs(poolCables) do
        local counted = n
        if maxCables > 0 and counted > maxCables then counted = maxCables end
        poolRadius[pid] = base + counted * perCable
    end

    PGP.state = { memberPool = memberPool, cablePool = cablePool, poolCables = poolCables, poolRadius = poolRadius }
    PGP.dirty = false
    PGP.powerDirty = true
end

function PGP.ensureState()
    if PGP.dirty then PGP.rebuild() end
    return PGP.state
end

function PGP.poolIdOfGenerator(gen)
    local sq = gen and gen:getSquare()
    if not sq then return nil end
    return PGP.ensureState().memberPool[PGP.squareKey(sq)]
end

function PGP.getPool(pid)
    return pid and PGP.getData().pools[pid] or nil
end

function PGP.runningMembers(pool)
    local list = {}
    for _, m in pairs(pool.members) do
        if m.running then table.insert(list, m) end
    end
    return list
end

function PGP.memberCount(pool)
    local n = 0
    for _ in pairs(pool.members) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------------------------------
-- Placement rules.
---------------------------------------------------------------------------------------------------

-- A generator's 3x3 fuel area overlaps another pool's area, or it would touch another pool's cables.
function PGP.overlapsOtherPool(x, y, z, allowedPid)
    local data = PGP.getData()
    local st = PGP.ensureState()
    for pid, pool in pairs(data.pools) do
        if pid ~= allowedPid then
            for _, m in pairs(pool.members) do
                if m.z == z and math.abs(m.x - x) <= 2 and math.abs(m.y - y) <= 2 then
                    return true
                end
            end
        end
    end
    for _, d in ipairs(PGP.DIRS) do
        local cablePid = st.cablePool[PGP.key(x + d.dx, y + d.dy, z)]
        if cablePid and cablePid ~= allowedPid then return true end
    end
    return false
end

-- Pools with a member touching (x,y,z), diagonals included.
function PGP.touchingPools(x, y, z)
    local data = PGP.getData()
    local found, n = {}, 0
    for pid, pool in pairs(data.pools) do
        for _, m in pairs(pool.members) do
            if m.z == z and math.abs(m.x - x) <= 1 and math.abs(m.y - y) <= 1 and not (m.x == x and m.y == y) then
                if not found[pid] then
                    found[pid] = true
                    n = n + 1
                end
            end
        end
    end
    return found, n
end

-- Returns the pool id the generator can link to, or nil and a reason key.
function PGP.checkLink(gen)
    local sq = gen and gen:getSquare()
    if not sq then return nil, "Invalid" end
    if gen:isConnected() then return nil, "AlreadyConnected" end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local k = PGP.key(x, y, z)
    if PGP.ensureState().memberPool[k] then return nil, "AlreadyPooled" end
    if PGP.getData().cables[k] then return nil, "CableHere" end
    local pools, n = PGP.touchingPools(x, y, z)
    if n == 0 then return nil, "NotTouching" end
    if n > 1 then return nil, "TooClose" end
    local pid = PGP.firstKey(pools)
    if PGP.overlapsOtherPool(x, y, z, pid) then return nil, "TooClose" end
    return pid
end

-- Vanilla "Connect Generator" starts a new pool, so it must not overlap any existing one.
function PGP.checkConnect(gen)
    local sq = gen and gen:getSquare()
    if not sq then return false, "Invalid" end
    if PGP.getData().cables[PGP.squareKey(sq)] then return false, "CableHere" end
    if PGP.overlapsOtherPool(sq:getX(), sq:getY(), sq:getZ(), nil) then return false, "TooClose" end
    return true
end

function PGP.cableMask(x, y, z)
    local data = PGP.getData()
    local st = PGP.ensureState()
    local mask = 0
    for _, d in ipairs(PGP.DIRS) do
        local k = PGP.key(x + d.dx, y + d.dy, z)
        if data.cables[k] or st.memberPool[k] then mask = mask + d.bit end
    end
    return mask
end

-- Returns the pool id a cable at (x,y,z) would extend, or nil and a reason key.
function PGP.checkCable(x, y, z)
    local data = PGP.getData()
    local st = PGP.ensureState()
    local k = PGP.key(x, y, z)
    if data.cables[k] then return nil, "CableHere" end
    if st.memberPool[k] then return nil, "GeneratorHere" end
    local pools, n = {}, 0
    for _, d in ipairs(PGP.DIRS) do
        local nk = PGP.key(x + d.dx, y + d.dy, z)
        local pid = st.memberPool[nk] or st.cablePool[nk]
        if pid and not pools[pid] then
            pools[pid] = true
            n = n + 1
        end
    end
    if n == 0 then return nil, "CableNotConnected" end
    if n > 1 then return nil, "CableTwoPools" end
    local pid = PGP.firstKey(pools)
    local maxCables = PGP.maxCables()
    if maxCables > 0 and (st.poolCables[pid] or 0) >= maxCables then return nil, "CableLimit" end
    return pid
end

---------------------------------------------------------------------------------------------------
-- Fuel area: barrels on the floor above plumbed members (vanilla FindExternalWaterSource order).
---------------------------------------------------------------------------------------------------

function PGP.sortedMemberKeys(pool)
    local keys = {}
    for k in pairs(pool.members) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

function PGP.plumbedGenerators(pool)
    local list = {}
    for _, k in ipairs(PGP.sortedMemberKeys(pool)) do
        local m = pool.members[k]
        local gen = PGP.getGeneratorAt(m.x, m.y, m.z)
        if gen and PGP.isPlumbed(gen) then
            table.insert(list, { gen = gen, member = m, key = k })
        end
    end
    return list
end

local function petrolContainerOf(obj)
    if instanceof(obj, "IsoWorldInventoryObject") or instanceof(obj, "IsoGenerator") then return nil end
    local fc = obj:getComponent(ComponentType.FluidContainer)
    if fc and fc:getAmount() > 0.001 and fc:isPureFluid(Fluid.Petrol) then return fc end
    return nil
end

-- Ordered list of { obj, fc } petrol barrels feeding the given plumbed generators.
function PGP.collectBarrels(plumbed)
    local list, seen = {}, {}
    local cell = getCell()
    local function addSquare(x, y, z)
        local k = PGP.key(x, y, z)
        if seen[k] then return end
        seen[k] = true
        local sq = cell:getGridSquare(x, y, z)
        if not sq then return end
        local objects = sq:getObjects()
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            local fc = petrolContainerOf(obj)
            if fc then table.insert(list, { obj = obj, fc = fc }) end
        end
    end
    for _, p in ipairs(plumbed) do
        local m = p.member
        addSquare(m.x, m.y, m.z + 1)
        for dy = -1, 1 do
            for dx = -1, 1 do
                addSquare(m.x + dx, m.y + dy, m.z + 1)
            end
        end
    end
    return list
end

function PGP.barrelPetrol(barrels)
    local total = 0
    for _, b in ipairs(barrels) do total = total + b.fc:getAmount() end
    return total
end

---------------------------------------------------------------------------------------------------
-- Extended range: extra generator positions on rings around running members.
-- Each position powers the vanilla radius around itself, so a ring at distance d reaches base + d.
---------------------------------------------------------------------------------------------------

PGP.Power = PGP.Power or { applied = {} }
local Power = PGP.Power

function PGP.chunkAt(wx, wy)
    local cell = getCell()
    if not cell then return nil end
    local sq = cell:getGridSquare(wx * 8, wy * 8, 0) or cell:getGridSquare(wx * 8 + 4, wy * 8 + 4, 0)
    return sq and sq:getChunk() or nil
end

function PGP.chunkCoords(chunk)
    for ly = 0, 7, 7 do
        for lx = 0, 7, 7 do
            local sq = chunk:getGridSquare(lx, ly, 0)
            if sq then return math.floor(sq:getX() / 8), math.floor(sq:getY() / 8) end
        end
    end
    return nil
end

local REAPPLY_PER_TICK = 4
local REFRESH_CHUNKS_PER_TICK = 4

local function positionChunkRange(p)
    if not p.ax then
        local r = PGP.baseRadius()
        p.ax, p.ay = math.floor((p.x - r) / 8), math.floor((p.y - r) / 8)
        p.bx, p.by = math.floor((p.x + r) / 8), math.floor((p.y + r) / 8)
    end
    return p.ax, p.ay, p.bx, p.by
end

local function addToLoadedChunks(p, ax, ay, bx, by)
    for wy = ay, by do
        for wx = ax, bx do
            local chunk = PGP.chunkAt(wx, wy)
            if chunk then chunk:addGeneratorPos(p.x, p.y, p.z) end
        end
    end
end

local function forEachLoadedChunk(p, fn, wx0, wy0, wx1, wy1)
    local ax, ay, bx, by = positionChunkRange(p)
    if wx0 then
        ax, ay, bx, by = math.max(ax, wx0), math.max(ay, wy0), math.min(bx, wx1), math.min(by, wy1)
    end
    for wy = ay, by do
        for wx = ax, bx do
            local chunk = PGP.chunkAt(wx, wy)
            if chunk then fn(chunk) end
        end
    end
end

function Power.desired()
    local data = PGP.getData()
    local st = PGP.ensureState()
    local base = PGP.baseRadius()
    local out = {}
    for pid, pool in pairs(data.pools) do
        local extra = (st.poolRadius[pid] or base) - base
        if extra > 0 then
            for _, m in pairs(pool.members) do
                if m.running then
                    local d = extra
                    while d > 0 do
                        local count = math.max(8, math.ceil(2 * math.pi * d / 6))
                        for i = 0, count - 1 do
                            local a = (i / count) * 2 * math.pi
                            local px = m.x + math.floor(d * math.cos(a) + 0.5)
                            local py = m.y + math.floor(d * math.sin(a) + 0.5)
                            local k = PGP.key(px, py, m.z)
                            if not st.memberPool[k] then out[k] = { x = px, y = py, z = m.z, k = k } end
                        end
                        local inner = d - base
                        if inner <= base - 2 then break end
                        d = math.max(1, inner - base + 2)
                    end
                end
            end
        end
    end
    return out
end

function Power.apply()
    local want = Power.desired()
    local have = Power.applied
    local changed = {}
    for k, p in pairs(have) do
        if not want[k] then
            forEachLoadedChunk(p, function(chunk) chunk:removeGeneratorPos(p.x, p.y, p.z) end)
            table.insert(changed, p)
        end
    end
    for k, p in pairs(want) do
        if not have[k] then
            forEachLoadedChunk(p, function(chunk) chunk:addGeneratorPos(p.x, p.y, p.z) end)
            table.insert(changed, p)
        end
    end
    Power.applied = want
    if #changed > 0 and not isServer() then
        Power.refreshArea(changed)
    end
end

-- Vanilla drops positions without a running generator whenever a nearby chunk loads; put ours back.
function Power.reapplyNear(wx, wy)
    local r = math.floor(PGP.baseRadius() / 8) + 1
    local x0, y0, x1, y1 = wx - r, wy - r, wx + r, wy + r
    for _, p in pairs(Power.applied) do
        local ax, ay, bx, by = positionChunkRange(p)
        if bx >= x0 and ax <= x1 and by >= y0 and ay <= y1 then
            addToLoadedChunks(p, math.max(ax, x0), math.max(ay, y0), math.min(bx, x1), math.min(by, y1))
        end
    end
end

function Power.reapplyAll()
    for _, p in pairs(Power.applied) do
        addToLoadedChunks(p, positionChunkRange(p))
    end
end

-- Same as reapplyAll, spread over ticks by stepReapply.
function Power.startReapply()
    if Power.reapplyList then return end
    local list = {}
    for _, p in pairs(Power.applied) do list[#list + 1] = p end
    if #list > 0 then Power.reapplyList, Power.reapplyIndex = list, 1 end
end

function Power.stepReapply()
    local list, applied = Power.reapplyList, Power.applied
    local i = Power.reapplyIndex
    local last = math.min(#list, i + REAPPLY_PER_TICK - 1)
    for j = i, last do
        local p = list[j]
        if applied[p.k] then addToLoadedChunks(p, positionChunkRange(p)) end
    end
    if last >= #list then Power.reapplyList = nil else Power.reapplyIndex = last + 1 end
end

local function refreshChunkObjects(chunk, zmin, zmax)
    local z0 = math.max(zmin, chunk:getMinLevel())
    local z1 = math.min(zmax, chunk:getMaxLevel())
    for z = z0, z1 do
        for ly = 0, 7 do
            for lx = 0, 7 do
                local sq = chunk:getGridSquare(lx, ly, z)
                if sq then
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        if instanceof(obj, "IsoLightSwitch") or obj:getGeneratorPowerConsumption() > 0 then
                            obj:checkHaveElectricity()
                        end
                    end
                end
            end
        end
    end
end

-- Chunks waiting for a refresh, REFRESH_CHUNKS_PER_TICK per tick; refreshSeen[wx][wy] merges repeats.
Power.refreshList, Power.refreshIndex, Power.refreshSeen = {}, 1, {}

local function queueRefresh(wx, wy, zmin, zmax)
    local row = Power.refreshSeen[wx]
    if not row then
        row = {}
        Power.refreshSeen[wx] = row
    end
    local e = row[wy]
    if e then
        if zmin < e.zmin then e.zmin = zmin end
        if zmax > e.zmax then e.zmax = zmax end
    else
        e = { wx = wx, wy = wy, zmin = zmin, zmax = zmax }
        row[wy] = e
        table.insert(Power.refreshList, e)
    end
end

local function stepRefresh()
    local list, seen = Power.refreshList, Power.refreshSeen
    local i = Power.refreshIndex
    local last = math.min(#list, i + REFRESH_CHUNKS_PER_TICK - 1)
    for j = i, last do
        local e = list[j]
        seen[e.wx][e.wy] = nil
        local chunk = PGP.chunkAt(e.wx, e.wy)
        if chunk then refreshChunkObjects(chunk, e.zmin, e.zmax) end
    end
    if last >= #list then
        Power.refreshList, Power.refreshIndex, Power.refreshSeen = {}, 1, {}
    else
        Power.refreshIndex = last + 1
    end
end

-- Lets lights and appliances notice power appearing or disappearing at the changed positions.
function Power.refreshArea(positions)
    local v = PGP.verticalRange()
    for _, p in ipairs(positions) do
        local ax, ay, bx, by = positionChunkRange(p)
        for wy = ay, by do
            for wx = ax, bx do
                queueRefresh(wx, wy, p.z - v, p.z + v)
            end
        end
    end
end

local function onLoadChunk(chunk)
    local wx, wy = PGP.chunkCoords(chunk)
    if not wx then return end
    if PGP.firstKey(Power.applied) ~= nil then
        Power.reapplyNear(wx, wy)
        if not isServer() then
            local v = PGP.verticalRange()
            for _, p in pairs(Power.applied) do
                local ax, ay, bx, by = positionChunkRange(p)
                if wx >= ax and wx <= bx and wy >= ay and wy <= by then
                    queueRefresh(wx, wy, p.z - v, p.z + v)
                    break
                end
            end
        end
    end
    if PGP.Server then PGP.Server.onChunkLoaded(chunk, wx, wy) end
end

local function onTick()
    if PGP.dirty then PGP.rebuild() end
    if PGP.powerDirty then
        PGP.powerDirty = false
        Power.apply()
    end
    if Power.reapplyList then Power.stepReapply() end
    if Power.refreshIndex <= #Power.refreshList then stepRefresh() end
end

local function onInitGlobalModData()
    PGP.getData()
    PGP.markDirty()
    if isClient() then ModData.request(PGP.MODDATA_KEY) end
end

local function onReceiveGlobalModData(key, data)
    if key ~= PGP.MODDATA_KEY or type(data) ~= "table" then return end
    if isClient() then
        ModData.add(PGP.MODDATA_KEY, data)
        PGP.markDirty()
    end
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)
Events.OnTick.Add(onTick)
Events.LoadChunk.Add(onLoadChunk)
Events.EveryOneMinute.Add(function() Power.startReapply() end)
