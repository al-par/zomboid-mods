require "ISUI/ISGeneratorInfoWindow"
require "PGP/PGP_Core"

local function fmt(value)
	return string.format("%.2f", value)
end

local function poolText(generator)
	local text = " <LINE> "
	text = text .. getText(PGP.isPlumbed(generator) and "IGUI_PGP_Plumbed" or "IGUI_PGP_NotPlumbed") .. " <LINE> "
	local pid = PGP.poolIdOfGenerator(generator)
	local pool = PGP.getPool(pid)
	if not pool then
		return text .. getText("IGUI_PGP_NoPool") .. " <LINE> "
	end
	local st = PGP.ensureState()
	text = text .. getText("IGUI_PGP_Pool", PGP.memberCount(pool), #PGP.runningMembers(pool)) .. " <LINE> "
	text = text .. getText("IGUI_PGP_Range", st.poolRadius[pid] or PGP.baseRadius(), st.poolCables[pid] or 0) .. " <LINE> "
	text = text .. getText("IGUI_PGP_PoolLoad", fmt((pool.load or 0) * PGP.fuelMultiplier())) .. " <LINE> "
	local plumbed = PGP.plumbedGenerators(pool)
	if #plumbed > 0 then
		text = text .. getText("IGUI_PGP_Barrels", fmt(PGP.barrelPetrol(PGP.collectBarrels(plumbed)))) .. " <LINE> "
	end
	return text
end

-- getRichText runs every frame while the window is open; the pool text is rebuilt at most once per CACHE_MS.
local CACHE_MS = 1000
local MAX_CACHED = 8
local cache, cached = {}, 0

local function cachedPoolText(generator)
	local now = getTimestampMs()
	local e = cache[generator]
	if not e then
		if cached >= MAX_CACHED then cache, cached = {}, 0 end
		e = { at = now, text = poolText(generator) }
		cache[generator] = e
		cached = cached + 1
	elseif now - e.at >= CACHE_MS then
		e.at, e.text = now, poolText(generator)
	end
	return e.text
end

local getRichText = ISGeneratorInfoWindow.getRichText
function ISGeneratorInfoWindow.getRichText(object, displayStats)
	local text = getRichText(object, displayStats)
	if displayStats and object then
		text = text .. cachedPoolText(object)
	end
	return text
end
