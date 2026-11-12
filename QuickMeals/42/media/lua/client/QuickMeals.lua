require "TimedActions/ISBaseTimedAction"

QuickMeals = QuickMeals or {}

-- Hard stop for one Quick Prepare chain, in case an add ever fails to change the meal.
local MAX_STEPS = 64
-- Food:getOffAgeMax() for items with no DaysTotallyRotten (canned, dried, oils): they never spoil.
local NEVER_ROTS = 1000000000

local function getExcluded()
    local raw = SandboxVars.QuickMeals and SandboxVars.QuickMeals.ExcludedItems or ""
    local set = {}
    for _, token in ipairs(string.split(raw, "[,;]")) do
        token = string.trim(token)
        if token ~= "" then
            set[token] = true
        end
    end
    return set
end

local function isSpice(item)
    if instanceof(item, "Food") then
        return item:isSpice()
    end
    return item:getScriptItem():isSpice()
end

-- Days left before the item is rotten; NEVER_ROTS for shelf-stable items.
local function daysLeft(item)
    if not instanceof(item, "Food") or item:getOffAgeMax() >= NEVER_ROTS then return NEVER_ROTS end
    return item:getOffAgeMax() - item:getAge()
end

local function isRotten(item)
    return instanceof(item, "Food") and item:isRotten()
end

-- True when a should be used before b: not rotten first, then the fewest days left.
local function usesSooner(a, b)
    local ra, rb = isRotten(a), isRotten(b)
    if ra ~= rb then return rb end
    return daysLeft(a) < daysLeft(b)
end

local function countExtraItems(base)
    local counts, total = {}, 0
    local extras = base:getExtraItems()
    if extras then
        for i = 0, extras:size() - 1 do
            local fullType = extras:get(i)
            counts[fullType] = (counts[fullType] or 0) + 1
            total = total + 1
        end
    end
    return counts, total
end

local function spiceLimitReached(base)
    local vars = SandboxVars.QuickMeals
    if not vars or not vars.SpiceLimitEnabled then return false end
    local spices = instanceof(base, "Food") and base:getSpices()
    local count = spices and spices:size() or 0
    return count >= vars.SpiceLimit
end

-- Groups what the recipe accepts right now by full type: ingredients and spices separately.
function QuickMeals.collect(playerObj, recipe, base, containers)
    local excluded = getExcluded()
    local ingredients, spices = {}, {}
    local _, extraCount = countExtraItems(base)
    local slotsLeft = recipe:getMaxItems() - extraCount
    local spicesAllowed = not spiceLimitReached(base)
    local seen = {}
    local candidates = recipe:getItemsCanBeUse(playerObj, base, containers)
    for i = 0, candidates:size() - 1 do
        local item = candidates:get(i)
        local id = item:getID()
        local fullType = item:getFullType()
        local itemRecipe = recipe:getItemRecipe(item)
        if not seen[id] and item ~= base
                and itemRecipe and itemRecipe:getUse() >= 0 and recipe:needToBeCooked(item)
                and not excluded[fullType] and not excluded[item:getType()] then
            seen[id] = true
            local bucket = nil
            if isSpice(item) then
                if spicesAllowed then bucket = spices end
            elseif slotsLeft > 0 then
                bucket = ingredients
            end
            if bucket then
                bucket[fullType] = bucket[fullType] or {}
                table.insert(bucket[fullType], item)
            end
        end
    end
    return ingredients, spices, slotsLeft
end

local function randomEntry(list)
    return list[ZombRand(#list) + 1]
end

-- The instance to use first; among equals, one already in the player's inventory.
local function chooseInstance(items, playerObj)
    local inv = playerObj:getInventory()
    local best = nil
    for _, item in ipairs(items) do
        if not best or usesSooner(item, best)
                or (not usesSooner(best, item) and inv:contains(item) and not inv:contains(best)) then
            best = item
        end
    end
    return best
end

-- The type whose best instance spoils soonest; random among ties (e.g. all shelf-stable).
local function chooseType(types, byType, playerObj)
    local soonest, soonestItem = {}, nil
    for _, fullType in ipairs(types) do
        local item = chooseInstance(byType[fullType], playerObj)
        if not soonestItem or usesSooner(item, soonestItem) then
            soonest, soonestItem = { fullType }, item
        elseif not usesSooner(soonestItem, item) then
            table.insert(soonest, fullType)
        end
    end
    return randomEntry(soonest)
end

function QuickMeals.pickNext(playerObj, recipe, base, containers, session)
    local ingredients, spices = QuickMeals.collect(playerObj, recipe, base, containers)

    local counts = countExtraItems(base)
    local leastUsed, leastCount = {}, nil
    for fullType in pairs(ingredients) do
        local c = counts[fullType] or 0
        if not leastCount or c < leastCount then
            leastUsed, leastCount = { fullType }, c
        elseif c == leastCount then
            table.insert(leastUsed, fullType)
        end
    end
    if #leastUsed > 0 then
        return chooseInstance(ingredients[chooseType(leastUsed, ingredients, playerObj)], playerObj)
    end

    local spiceTypes = {}
    for fullType in pairs(spices) do
        if not session.triedSpices[fullType] then
            table.insert(spiceTypes, fullType)
        end
    end
    if #spiceTypes > 0 then
        local fullType = chooseType(spiceTypes, spices, playerObj)
        session.triedSpices[fullType] = true
        return chooseInstance(spices[fullType], playerObj)
    end
    return nil
end

local function recipeApplies(playerObj, recipe, base, containers)
    local list = RecipeManager.getEvolvedRecipe(base, playerObj, containers, false)
    local name = recipe:getUntranslatedName()
    for i = 0, list:size() - 1 do
        if list:get(i):getUntranslatedName() == name then return true end
    end
    return false
end

-- Plans one ingredient (or spice) and queues the actions for it, then another step.
-- Called from QuickMealsStepAction:update(), so the previous add's complete() has run.
function QuickMeals.step(playerObj, session)
    if session.lastAction then
        session.baseItem = session.lastAction.baseItem
        session.lastAction = nil
    end
    session.steps = session.steps + 1
    if session.steps > MAX_STEPS then return end

    local base = session.baseItem
    local inv = playerObj:getInventory()
    if not base then return end
    local containers = ISInventoryPaneContextMenu.getContainers(playerObj)

    if not session.started then
        session.started = true
        if not recipeApplies(playerObj, session.recipe, base, containers) then return end
        if not inv:contains(base) then
            if not base:getContainer() then return end
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, base, base:getContainer(), inv, nil))
            if instanceof(base, "Food") then
                base:setChef(playerObj:getUsername())
            end
            ISTimedActionQueue.add(QuickMealsStepAction:new(playerObj, session))
            return
        end
    end
    if not inv:contains(base) then return end

    local _, extraTotal = countExtraItems(base)
    if session.expectExtraAbove and extraTotal <= session.expectExtraAbove then return end

    local usedItem = QuickMeals.pickNext(playerObj, session.recipe, base, containers, session)
    if not usedItem then return end
    session.expectExtraAbove = (not isSpice(usedItem)) and extraTotal or nil

    local transferred = false
    if not inv:contains(usedItem) then
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, usedItem, usedItem:getContainer(), inv, nil))
        transferred = true
        if instanceof(usedItem, "Food") then
            usedItem:setChef(playerObj:getUsername())
        end
    end
    local action = ISAddItemInRecipe:new(playerObj, session.recipe, base, usedItem)
    session.lastAction = action
    ISTimedActionQueue.add(action)
    if transferred then
        ISCraftingUI.ReturnItemToOriginalContainer(playerObj, usedItem)
    end
    ISTimedActionQueue.add(QuickMealsStepAction:new(playerObj, session))
end

-- Like ISQueueActionsAction, but plans in update() instead of start(). start() can run inside
-- the previous action's perform(), before its complete() has added the last ingredient.
-- It always finishes with forceComplete(): forceStop() would reset the whole queue, including
-- any other Quick Prepares queued behind this one.
QuickMealsStepAction = ISBaseTimedAction:derive("QuickMealsStepAction")

function QuickMealsStepAction:isValid()
    return true
end

function QuickMealsStepAction:waitToStart()
    return false
end

function QuickMealsStepAction:start()
end

function QuickMealsStepAction:update()
    if self.planned then
        -- QuickMeals.step raised an error last frame; let the queue move on.
        self:endAddingActions()
        self:forceComplete()
        return
    end
    self.planned = true
    self:beginAddingActions()
    QuickMeals.step(self.character, self.session)
    self:endAddingActions()
    self:forceComplete()
end

function QuickMealsStepAction:stop()
    ISBaseTimedAction.stop(self)
end

function QuickMealsStepAction:perform()
    ISBaseTimedAction.perform(self)
end

function QuickMealsStepAction:new(character, session)
    local o = ISBaseTimedAction.new(self, character)
    o.session = session
    o.stopOnAim = false
    o.stopOnWalk = false
    o.stopOnRun = false
    o.maxTime = -1
    return o
end

function QuickMeals.onQuickPrepare(recipe, bases, player)
    local playerObj = getSpecificPlayer(player)
    for _, base in ipairs(bases) do
        local session = { recipe = recipe, baseItem = base, steps = 0, triedSpices = {} }
        ISTimedActionQueue.add(QuickMealsStepAction:new(playerObj, session))
    end
end

local function findUnusedOption(context, name, used)
    for _, option in ipairs(context.options) do
        if option.name == name and option.subOption and not used[option] then
            used[option] = true
            return option
        end
    end
    return nil
end

-- Mirrors how ISInventoryPaneContextMenu picks the base item and names each evolved recipe
-- submenu, then puts Quick Prepare at the top of that submenu.
function QuickMeals.onFillMenu(player, context, items)
    local playerObj = getSpecificPlayer(player)
    local containerList = ISInventoryPaneContextMenu.getContainers(playerObj)
    local baseItem, evorecipe = nil, nil
    for _, v in ipairs(items) do
        local testItem = v
        if not instanceof(v, "InventoryItem") then
            testItem = v.items[1]
        end
        if not testItem:isNoRecipes(playerObj) then
            evorecipe = RecipeManager.getEvolvedRecipe(testItem, playerObj, containerList, true)
            baseItem = testItem
        end
    end
    if not evorecipe or evorecipe:isEmpty() then return end

    local bases = {}
    local baseType = baseItem:getFullType()
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        if item:getFullType() == baseType and not item:isNoRecipes(playerObj) then
            table.insert(bases, item)
        end
    end
    if #bases == 0 then
        bases = { baseItem }
    end
    local label = getText("ContextMenu_QuickMeals_QuickPrepare")
    if #bases > 1 then
        label = getText("ContextMenu_QuickMeals_QuickPrepareCount", #bases)
    end

    local used = {}
    for i = 0, evorecipe:size() - 1 do
        local recipe = evorecipe:get(i)
        if recipe:getItemsCanBeUse(playerObj, baseItem, containerList):size() == 0 then
            break
        end
        local fromName = getText("ContextMenu_EvolvedRecipe_" .. recipe:getUntranslatedName())
        local menuName = fromName
        if not recipe:isResultItem(baseItem) then
            menuName = getText("ContextMenu_Create_From_Ingredient", fromName)
        end
        local option = findUnusedOption(context, menuName, used)
        local subMenu = option and context:getSubMenu(option.subOption)
        if subMenu then
            local ingredients, spices, slotsLeft = QuickMeals.collect(playerObj, recipe, baseItem, containerList)
            local typeCount, spiceCount = 0, 0
            for _ in pairs(ingredients) do typeCount = typeCount + 1 end
            for _ in pairs(spices) do spiceCount = spiceCount + 1 end
            if typeCount > 0 or spiceCount > 0 then
                local quick = subMenu:addOptionOnTop(label, recipe, QuickMeals.onQuickPrepare, bases, player)
                local tooltip = ISInventoryPaneContextMenu.addToolTip()
                tooltip.description = getText("Tooltip_QuickMeals_QuickPrepare", math.max(slotsLeft, 0), typeCount)
                quick.toolTip = tooltip
            end
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(QuickMeals.onFillMenu)
