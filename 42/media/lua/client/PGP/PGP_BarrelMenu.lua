require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPage"
require "PGP/PGP_Barrels"

local B = PGP.Barrels

PGP.BarrelUI = PGP.BarrelUI or {}
local UI = PGP.BarrelUI

local function setTooltip(option, text, unavailable)
	local tooltip = ISWorldObjectContextMenu.addToolTip()
	tooltip.description = text
	option.toolTip = tooltip
	if unavailable then option.notAvailable = true end
end

local REASON_TEXT = {
	PumpNoPower = "ContextMenu_FuelPumpNoPower",
	PumpEmpty = "ContextMenu_FuelPumpEmpty",
}

local function reasonText(reason)
	return getText(REASON_TEXT[reason] or ("Tooltip_PGP_" .. tostring(reason)))
end

local function heldBarrel(playerObj)
	local item = playerObj:getPrimaryHandItem()
	if B.isBarrelItem(item) then return item end
	item = playerObj:getSecondaryHandItem()
	if B.isBarrelItem(item) then return item end
	return nil
end

local function inPlayerInventory(playerObj, item)
	return item:getContainer() == playerObj:getInventory()
end

---------------------------------------------------------------------------------------------------
-- Actions.
---------------------------------------------------------------------------------------------------

-- Quick drop: puts the carried barrel on the free square in front of the player. Never waits.
function UI.putDown(playerObj, item)
	if inPlayerInventory(playerObj, item) and not B.findPlaceSquare(playerObj, nil) then
		playerObj:setHaloNote(getText("IGUI_PGP_NoRoomForBarrel"), 255, 100, 100, 300)
		return
	end
	ISTimedActionQueue.add(PGP_PutDownBarrelAction:new(playerObj, item, nil))
end

-- Lets the player click the exact square (and facing) for the carried barrel.
function UI.choosePlace(playerObj, item)
	getCell():setDrag(PGP_BarrelCursor:new(playerObj, item), playerObj:getPlayerNum())
end

-- Takes a barrel item that is not carried yet: loose on the floor, or in a container.
function UI.take(playerObj, item)
	local worldItem = item:getWorldItem()
	if not worldItem then
		ISInventoryPaneContextMenu.equipHeavyItem(playerObj, item)
	elseif luautils.walkAdj(playerObj, worldItem:getSquare(), true) then
		ISTimedActionQueue.add(PGP_PickUpBarrelAction:new(playerObj, worldItem))
	end
end

function UI.onPutDown(worldobjects, playerObj, item)
	UI.choosePlace(playerObj, item)
end

function UI.onPickUp(worldobjects, playerObj, barrel)
	if luautils.walkAdj(playerObj, barrel:getSquare()) then
		ISTimedActionQueue.add(PGP_PickUpBarrelAction:new(playerObj, barrel))
	end
end

function UI.onFill(worldobjects, playerObj, pump, barrel)
	if not luautils.walkAdj(playerObj, pump:getSquare()) then return end
	local held = heldBarrel(playerObj)
	if held then ISTimedActionQueue.add(PGP_PutDownBarrelAction:new(playerObj, held, nil)) end
	ISTimedActionQueue.add(PGP_FillBarrelAction:new(playerObj, pump, barrel))
end

-- Takes the barrel into the hands first when it isn't carried yet.
function UI.load(playerObj, item, container)
	if inPlayerInventory(playerObj, item) then
		if not luautils.walkToContainer(container, playerObj:getPlayerNum()) then return end
	else
		UI.take(playerObj, item)
		local part = container:getVehiclePart()
		if part and part:getArea() then
			ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, part:getVehicle(), part:getArea()))
		end
	end
	ISTimedActionQueue.add(PGP_LoadBarrelAction:new(playerObj, item, container))
end

function UI.onLoad(playerObj, item, container)
	UI.load(playerObj, item, container)
end

function UI.onTake(playerObj, item)
	UI.take(playerObj, item)
end

---------------------------------------------------------------------------------------------------
-- World context menu.
---------------------------------------------------------------------------------------------------

local function findObjects(worldobjects)
	local barrel, loose, pump
	local seen = {}
	for _, obj in ipairs(worldobjects) do
		local sq = obj:getSquare()
		if sq and not seen[sq] then
			seen[sq] = true
			local objects = sq:getObjects()
			for i = 0, objects:size() - 1 do
				local o = objects:get(i)
				if not barrel and B.isBarrelObject(o) then barrel = o end
				if not loose and B.isLooseBarrel(o) then loose = o end
				if not pump and B.isPump(o) then pump = o end
			end
		end
	end
	return barrel, loose, pump
end

local function addFillOption(context, worldobjects, playerObj, pumps, barrel, text)
	local pump, reason = B.choosePump(pumps)
	local option = context:addGetUpOption(text, worldobjects, UI.onFill, playerObj, pump, barrel)
	local space, spaceReason = B.petrolSpace(barrel)
	if not pump then
		setTooltip(option, reasonText(reason), true)
	elseif space <= 0 then
		setTooltip(option, reasonText(spaceReason), true)
	end
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
	if test then return end
	local playerObj = getSpecificPlayer(player)
	if not playerObj or playerObj:getVehicle() then return end

	local held = heldBarrel(playerObj)
	if held then
		local text = getText("ContextMenu_PGP_PutDownBarrel", held:getDisplayName())
		local vanilla = context:getOptionFromName(getText("ContextMenu_DropNamedItem", held:getDisplayName()))
		if vanilla then
			vanilla.name = text
			vanilla.target = worldobjects
			vanilla.onSelect = UI.onPutDown
			vanilla.param1 = playerObj
			vanilla.param2 = held
			vanilla.param3 = nil
		else
			context:addOptionOnTop(text, worldobjects, UI.onPutDown, playerObj, held)
		end
	end

	local barrel, loose, pump = findObjects(worldobjects)
	if barrel then
		local label = B.objectLabel(barrel)
		context:addGetUpOption(getText("ContextMenu_PGP_PickUpBarrel", label), worldobjects, UI.onPickUp, playerObj, barrel)
		local pumps = B.pumpsNear(barrel:getSquare())
		if #pumps > 0 then
			addFillOption(context, worldobjects, playerObj, pumps, barrel, getText("ContextMenu_PGP_FillBarrelFromPump", label))
		end
	elseif pump then
		for _, near in ipairs(B.barrelsNear(pump:getSquare())) do
			addFillOption(context, worldobjects, playerObj, { pump }, near,
				getText("ContextMenu_PGP_FillBarrelFromPump", B.objectLabel(near)))
		end
	end
	if loose then
		context:addGetUpOption(getText("ContextMenu_PGP_PickUpBarrel", B.objectLabel(loose)), worldobjects, UI.onPickUp, playerObj, loose)
	end
end

---------------------------------------------------------------------------------------------------
-- Inventory context menu.
---------------------------------------------------------------------------------------------------

local function onFillInventoryObjectContextMenu(player, context, items)
	local playerObj = getSpecificPlayer(player)
	local item
	for _, entry in ipairs(items) do
		local it = entry
		if not instanceof(entry, "InventoryItem") then it = entry.items[1] end
		if B.isBarrelItem(it) then item = it break end
	end
	if not item or playerObj:getVehicle() then return end

	if not inPlayerInventory(playerObj, item) then
		context:addOptionOnTop(getText("ContextMenu_PGP_PickUpBarrel", item:getDisplayName()), playerObj, UI.onTake, item)
		return
	end

	if playerObj:isEquipped(item) then
		context:addOptionOnTop(getText("ContextMenu_PGP_PutDownBarrel", item:getDisplayName()), playerObj, UI.choosePlace, item)
	end

	local containers = ISInventoryPaneContextMenu.getContainers(playerObj)
	for i = 0, containers:size() - 1 do
		local container = containers:get(i)
		if B.trunkPart(container) then
			local text = getText("ContextMenu_PGP_LoadBarrelInto", getText("IGUI_VehiclePart" .. container:getType()))
			local option = context:addOption(text, playerObj, UI.onLoad, item, container)
			local reason = B.trunkReason(playerObj, container)
			if reason then setTooltip(option, reasonText(reason), true) end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Dropping, taking and dragging.
---------------------------------------------------------------------------------------------------

-- Vanilla heavy-item pickup leaves the floor object behind for items that are loose on the floor.
local vanillaEquipHeavyItem = ISInventoryPaneContextMenu.equipHeavyItem
ISInventoryPaneContextMenu.equipHeavyItem = function(playerObj, item)
	if B.isBarrelItem(item) and item:getWorldItem() then
		UI.take(playerObj, item)
		return
	end
	return vanillaEquipHeavyItem(playerObj, item)
end

-- The world "Grab" menu would put a loose barrel in the inventory instead of the hands.
local function grabWithoutBarrels(vanilla)
	return function(worldobjects, wItems, player)
		local list = type(wItems) == "table" and wItems or { wItems }
		for _, wItem in ipairs(list) do
			if B.isLooseBarrel(wItem) then
				UI.take(getSpecificPlayer(player), wItem:getItem())
				return
			end
		end
		return vanilla(worldobjects, wItems, player)
	end
end

ISWorldObjectContextMenu.onGrabWItem = grabWithoutBarrels(ISWorldObjectContextMenu.onGrabWItem)
ISWorldObjectContextMenu.onGrabHalfWItems = grabWithoutBarrels(ISWorldObjectContextMenu.onGrabHalfWItems)
ISWorldObjectContextMenu.onGrabAllWItems = grabWithoutBarrels(ISWorldObjectContextMenu.onGrabAllWItems)

local vanillaDropItem = ISInventoryPaneContextMenu.dropItem
ISInventoryPaneContextMenu.dropItem = function(item, player)
	local playerObj = getSpecificPlayer(player)
	if B.isBarrelItem(item) and not playerObj:getVehicle() then
		if item:getWorldItem() then return end
		if not inPlayerInventory(playerObj, item) then UI.take(playerObj, item) end
		UI.putDown(playerObj, item)
		return
	end
	return vanillaDropItem(item, player)
end

local vanillaUnequipItem = ISInventoryPaneContextMenu.unequipItem
ISInventoryPaneContextMenu.unequipItem = function(item, player)
	local playerObj = getSpecificPlayer(player)
	if B.isBarrelItem(item) and playerObj:isEquipped(item) and not playerObj:getVehicle() then
		UI.putDown(playerObj, item)
		return
	end
	return vanillaUnequipItem(item, player)
end

-- Whether a dragged barrel may go into container even though vanilla's weight check says no.
local function barrelMayGo(playerObj, item, container)
	if not container or not B.isBarrelItem(item) or item:getContainer() == container then return false end
	if container:isInCharacterInventory(playerObj) then
		return not inPlayerInventory(playerObj, item)
	end
	return B.trunkReason(playerObj, container) == nil
end

local function draggingBarrelInto(playerObj, container)
	if not ISMouseDrag.dragging then return false end
	for _, item in ipairs(ISInventoryPane.getActualItems(ISMouseDrag.dragging)) do
		if barrelMayGo(playerObj, item, container) then return true end
	end
	return false
end

local vanillaPaneCanPutIn = ISInventoryPane.canPutIn
function ISInventoryPane:canPutIn()
	if vanillaPaneCanPutIn(self) then return true end
	return draggingBarrelInto(getSpecificPlayer(self.player), self.inventory)
end

local vanillaPageCanPutIn = ISInventoryPage.canPutIn
function ISInventoryPage:canPutIn()
	if vanillaPageCanPutIn(self) then return true end
	return draggingBarrelInto(getSpecificPlayer(self.player), self.mouseOverButton and self.mouseOverButton.inventory)
end

local vanillaDraggedUpdate = ISInventoryPaneDraggedItems.update
function ISInventoryPaneDraggedItems:update()
	vanillaDraggedUpdate(self)
	local container = self.mouseOverContainer
	if not container or not self.items then return end
	local playerObj = getSpecificPlayer(self.playerNum)
	for _, item in ipairs(self.items) do
		if self.itemNotOK[item] and barrelMayGo(playerObj, item, container) then
			self.itemNotOK[item] = nil
		end
	end
end

local vanillaTransferItemsByWeight = ISInventoryPane.transferItemsByWeight
function ISInventoryPane:transferItemsByWeight(items, container)
	local playerObj = getSpecificPlayer(self.player)
	local rest = {}
	for _, item in ipairs(items) do
		if not B.isBarrelItem(item) or container:getType() == "floor" then
			table.insert(rest, item)
		elseif container:isInCharacterInventory(playerObj) then
			if not inPlayerInventory(playerObj, item) then UI.take(playerObj, item) end
		elseif B.trunkReason(playerObj, container) == nil then
			UI.load(playerObj, item, container)
		else
			table.insert(rest, item)
		end
	end
	if #rest > 0 then vanillaTransferItemsByWeight(self, rest, container) end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
