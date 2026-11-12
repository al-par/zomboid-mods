require "HomeHeating/HH_Shared"
require "TimedActions/ISBaseTimedAction"

local HH = HomeHeating

-- Fuel goes into the bin; the fire takes it from there.
local vanillaAddFuel = ISCampingMenu.doAddFuelOption
function ISCampingMenu.doAddFuelOption(context, worldobjects, currentFuel, fuelInfo, target, ...)
    if instanceof(target, "IsoObject") and HH.isOurs(target) then return end
    return vanillaAddFuel(context, worldobjects, currentFuel, fuelInfo, target, ...)
end

HHToggleHeater = ISBaseTimedAction:derive("HHToggleHeater")

function HHToggleHeater:isValid()
    return self.heater:getObjectIndex() ~= -1
end

function HHToggleHeater:waitToStart()
    self.character:faceThisObject(self.heater)
    return self.character:shouldBeTurning()
end

function HHToggleHeater:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

function HHToggleHeater:update()
    self.character:faceThisObject(self.heater)
end

function HHToggleHeater:stop()
    ISBaseTimedAction.stop(self)
end

function HHToggleHeater:perform()
    ISBaseTimedAction.perform(self)
end

function HHToggleHeater:complete()
    HH.World.setElectric(self.heater, self.on)
    return true
end

function HHToggleHeater:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 30
end

function HHToggleHeater:new(character, heater, on)
    local o = ISBaseTimedAction.new(self, character)
    o.heater = heater
    o.on = on
    o.maxTime = o:getDuration()
    return o
end

local function onToggle(worldobjects, player, heater, on)
    local playerObj = getSpecificPlayer(player)
    if luautils.walkAdj(playerObj, heater:getSquare()) then
        ISTimedActionQueue.add(HHToggleHeater:new(playerObj, heater, on))
    end
end

local function onFill(player, context, worldobjects, test)
    local heater, fire, clickedFire
    local seen = {}
    for _, wo in ipairs(worldobjects) do
        local sq = wo:getSquare()
        if sq and not seen[sq] then
            seen[sq] = true
            local objects = sq:getObjects()
            for i = 0, objects:size() - 1 do
                local o = objects:get(i)
                if o:hasModData() and o:getModData().hhKind == "electric" then
                    heater = o
                elseif HH.hearthPart(o) then
                    if instanceof(o, "IsoFireplace") then clickedFire = o else fire = fire or HH.fireOf(o) end
                end
            end
        end
    end
    if heater then
        if test then return ISWorldObjectContextMenu.setTest() end
        local on = heater:getModData().hhOn == true
        local option = context:addOption(getText(on and "ContextMenu_HH_HeaterOff" or "ContextMenu_HH_HeaterOn"),
            worldobjects, onToggle, player, heater, not on)
        if not on and not HH.World.isPowered(heater:getSquare()) then
            option.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = getText("ContextMenu_HH_NoPower")
            option.toolTip = tip
        end
    end
    -- the vanilla fire menu only looks at the clicked square; open it from every square of the hearth
    if fire and not clickedFire then
        ISBBQMenu.OnFillWorldObjectContextMenu(player, context, { fire }, test)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFill)
