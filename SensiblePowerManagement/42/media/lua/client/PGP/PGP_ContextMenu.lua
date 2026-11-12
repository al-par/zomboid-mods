require "ISUI/ISWorldObjectContextMenu"
require "PGP/PGP_Core"

PGP.UI = PGP.UI or {}
local UI = PGP.UI

local function notBroken(item)
	return not item:isBroken()
end

local function findWrench(playerObj)
	local inv = playerObj:getInventory()
	return inv:getFirstTypeEvalRecurse("PipeWrench", notBroken) or inv:getFirstTagEvalRecurse(ItemTag.PIPE_WRENCH, notBroken)
end

local function setTooltip(option, text, unavailable)
	local tooltip = ISWorldObjectContextMenu.addToolTip()
	tooltip.description = text
	option.toolTip = tooltip
	if unavailable then option.notAvailable = true end
end

local function reasonText(reason)
	return getText("Tooltip_PGP_" .. tostring(reason))
end

function UI.onPlumb(worldobjects, generator, player)
	local playerObj = getSpecificPlayer(player)
	local wrench = findWrench(playerObj)
	if not wrench or not luautils.walkAdj(playerObj, generator:getSquare()) then return end
	ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
	ISTimedActionQueue.add(PGP_PlumbGeneratorAction:new(playerObj, generator, wrench))
end

function UI.onLink(worldobjects, generator, player)
	local playerObj = getSpecificPlayer(player)
	if not luautils.walkAdj(playerObj, generator:getSquare()) then return end
	local inv = playerObj:getInventory()
	for _, itemType in ipairs(PGP_LinkGeneratorAction.MATERIALS) do
		local item = inv:getFirstTypeRecurse(itemType)
		if item and luautils.haveToBeTransfered(playerObj, item) then
			ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, item:getContainer(), inv))
		end
	end
	ISTimedActionQueue.add(PGP_LinkGeneratorAction:new(playerObj, generator))
end

function UI.onPickupCable(worldobjects, cable, player)
	local playerObj = getSpecificPlayer(player)
	if luautils.walkAdj(playerObj, cable:getSquare(), true) then
		ISTimedActionQueue.add(PGP_PickupCableAction:new(playerObj, cable))
	end
end

function UI.onLayCable(item, player)
	local playerObj = getSpecificPlayer(player)
	local cursor = PGP_CableCursor:new(playerObj, item)
	getCell():setDrag(cursor, player)
end

local function findObjects(worldobjects)
	local generator, cable
	local seen = {}
	for _, obj in ipairs(worldobjects) do
		local sq = obj:getSquare()
		if sq and not seen[sq] then
			seen[sq] = true
			local objects = sq:getObjects()
			for i = 0, objects:size() - 1 do
				local o = objects:get(i)
				if not generator and instanceof(o, "IsoGenerator") then generator = o end
				if not cable and PGP.isCableObject(o) then cable = o end
			end
		end
	end
	return generator, cable
end

local function addGeneratorOptions(player, context, worldobjects, generator)
	local playerObj = getSpecificPlayer(player)
	local genOption = context:getOptionFromName(getText("ContextMenu_Generator"))
	local menu = genOption and genOption.subOption and context:getSubMenu(genOption.subOption)
	if not menu then return end

	if not generator:isConnected() then
		local plugOption = menu:getOptionFromName(getText("ContextMenu_GeneratorPlug"))
		local canConnect, connectReason = PGP.checkConnect(generator)
		if plugOption and not canConnect then
			setTooltip(plugOption, reasonText(connectReason), true)
		end

		local linkOption = menu:addGetUpOption(getText("ContextMenu_PGP_LinkToPool"), worldobjects, UI.onLink, generator, player)
		local pid, reason = PGP.checkLink(generator)
		if not pid then
			setTooltip(linkOption, reasonText(reason), true)
		elseif not PGP_LinkGeneratorAction.canOperate(playerObj) then
			setTooltip(linkOption, getText("ContextMenu_GeneratorPlugTT"), true)
		elseif not PGP_LinkGeneratorAction.hasMaterials(playerObj) then
			setTooltip(linkOption, getText("Tooltip_PGP_LinkDesc") .. " <LINE> <RED> " .. getText("Tooltip_PGP_LinkNeeds"), true)
		else
			setTooltip(linkOption, getText("Tooltip_PGP_LinkDesc") .. " <LINE> " .. getText("Tooltip_PGP_LinkNeeds"), false)
		end
	end

	if not PGP.isPlumbed(generator) then
		local plumbOption = menu:addGetUpOption(getText("ContextMenu_PGP_PlumbGenerator"), worldobjects, UI.onPlumb, generator, player)
		if findWrench(playerObj) then
			setTooltip(plumbOption, getText("Tooltip_PGP_PlumbDesc"), false)
		else
			setTooltip(plumbOption, getText("Tooltip_PGP_PlumbDesc") .. " <LINE> <RED> " .. getText("Tooltip_PGP_NeedWrench"), true)
		end
	end
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
	if test then return end
	local generator, cable = findObjects(worldobjects)
	if generator then addGeneratorOptions(player, context, worldobjects, generator) end
	if cable then
		context:addGetUpOption(getText("ContextMenu_PGP_PickUpCable"), worldobjects, UI.onPickupCable, cable, player)
	end
end

local function onFillInventoryObjectContextMenu(player, context, items)
	for _, entry in ipairs(items) do
		local item = entry
		if not instanceof(entry, "InventoryItem") then item = entry.items[1] end
		if PGP.isCableItem(item) then
			context:addOption(getText("ContextMenu_PGP_LayCable"), item, UI.onLayCable, player)
			return
		end
	end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
