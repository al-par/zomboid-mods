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

local getRichText = ISGeneratorInfoWindow.getRichText
function ISGeneratorInfoWindow.getRichText(object, displayStats)
	local text = getRichText(object, displayStats)
	if displayStats and object then
		text = text .. poolText(object)
	end
	return text
end
