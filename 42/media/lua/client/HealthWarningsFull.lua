local initialized             = false
local prevSickLevel           = 0
local prevHypoLevel           = 0
local prevHyperLevel          = 0
local criticalInjuryTriggered = false
local bulletTriggered         = false
local glassTriggered          = false
local burnsTriggered          = false
local foodPoisoningTriggered  = false
local poisoningTriggered      = false
local starvationTriggered     = false
local dehydrationTriggered    = false
local hypoTriggered           = false
local hyperTriggered          = false

local TEMP_DANGER_LEVEL       = 3
local FOOD_SICKNESS_THRESHOLD = 50
local STARVING_MOODLE_LEVEL   = 4

local CRITICAL_HEAD_PARTS  = nil
local CRITICAL_TORSO_PARTS = nil
local function initPartTables()
    if CRITICAL_HEAD_PARTS then return end
    CRITICAL_HEAD_PARTS  = { BodyPartType.Neck, BodyPartType.Head }
    CRITICAL_TORSO_PARTS = { BodyPartType.Torso_Upper, BodyPartType.Torso_Lower }
end

local sv = function() return SandboxVars.HealthWarningsFull end

local function pauseGame()
    local sc = UIManager.getSpeedControls()
    if sc and sc:getCurrentGameSpeed() ~= 0 then sc:SetCurrentGameSpeed(0) end
end

local function openHealthPanel()
    local infoPanel = getPlayerInfoPanel(0)
    if infoPanel and not infoPanel:isActive(xpSystemText.health) then
        infoPanel:toggleView(xpSystemText.health)
    end
end

local function showAlert(title, body)
    local w, h = 420, 320
    local x = getCore():getScreenWidth()  / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local modal = ISModalRichText:new(x, y, w, h, title .. "\n \n" .. body, false, nil, nil, 0)
    modal:initialise()
    modal:addToUIManager()
    -- Fix: override destroy so closing the dialog does not unpause the game
    modal.destroy = function(self)
        UIManager.setShowPausedMessage(true)
        self:setVisible(false)
        if self.destroyOnClick then self:removeFromUIManager() end
        if self.player and JoypadState.players[self.player + 1] then
            setJoypadFocus(self.player, self.prevFocus)
        elseif self.joyfocus and self.joyfocus.focus == self then
            self.joyfocus.focus = self.prevFocus
            updateJoypadFocus(self.joyfocus)
        end
    end
end

local function alert(key, pauseKey, title, body)
    if not (sv() and sv()[key]) then return end
    openHealthPanel()
    showAlert(title, body)
    if sv()[pauseKey] then pauseGame() end
end

-- Fix: check both ZOMBIE_INFECTION and ZOMBIE_FEVER so Knox is detected
-- even before fever symptoms fully develop
local function isKnoxInfected(player)
    local stats = player:getStats()
    return stats:get(CharacterStat.ZOMBIE_INFECTION) > 0
        or stats:get(CharacterStat.ZOMBIE_FEVER) > 0
end

local function checkSickness(player)
    local sickLevel = player:getMoodles():getMoodleLevel(MoodleType.SICK)
    local knox      = isKnoxInfected(player)

    if prevSickLevel < 3 and sickLevel >= 3 and sickLevel < 4 then
        alert("SickEnabled", "SickPause",
            "You are now Sick",
            "Your condition has worsened.\n" ..
            "\nTake antibiotics. Rest." ..
            "\nStay warm and dry. Avoid raw or rotten food." ..
            "\nMove away from corpses or equip a gas mask or respirator."
        )
    end

    if prevSickLevel < 4 and sickLevel >= 4 then
        local advice = knox
            and "Your skin feels like broken glass, and your head feels like it might explode. Your bones feel like they are on fire, but you shiver uncontrollably. Every step you take feels heavier and heavier still.\n\nYou need rest. Get inside. <RGB:0.5,0.5,0.5>Lock the door."
            or  "Take antibiotics. Rest in a warm, dry place."
        alert("FeverEnabled", "FeverPause", "You have a Fever", advice)
    end

    prevSickLevel = sickLevel
end

local function checkTemperature(player)
    local hypo  = player:getMoodles():getMoodleLevel(MoodleType.HYPOTHERMIA)
    local hyper = player:getMoodles():getMoodleLevel(MoodleType.HYPERTHERMIA)

    if hypo >= TEMP_DANGER_LEVEL and not hypoTriggered then
        hypoTriggered = true
        alert("TemperatureEnabled", "TemperaturePause",
            "Hypothermia Warning",
            "Your body temperature is dangerously low.\n" ..
            "\nPut on dry, warm clothing." ..
            "\nFind shelter or light a fire." ..
            "\nDrink warm liquids if available."
        )
    elseif hypo < TEMP_DANGER_LEVEL then
        hypoTriggered = false
    end

    if hyper >= TEMP_DANGER_LEVEL and not hyperTriggered then
        hyperTriggered = true
        alert("TemperatureEnabled", "TemperaturePause",
            "Overheating",
            "Your body temperature is dangerously high.\n" ..
            "\nRemove excess clothing." ..
            "\nFind shade or cool water." ..
            "\nRest and stay out of direct sunlight."
        )
    elseif hyper < TEMP_DANGER_LEVEL then
        hyperTriggered = false
    end

    prevHypoLevel  = hypo
    prevHyperLevel = hyper
end

local function isCriticalInjury(player)
    initPartTables()
    local bd = player:getBodyDamage()
    for _, partType in ipairs(CRITICAL_HEAD_PARTS) do
        local bp = bd:getBodyPart(partType)
        if bp:bitten() or bp:deepWounded() or bp:bleeding() then return true end
    end
    for _, partType in ipairs(CRITICAL_TORSO_PARTS) do
        local bp = bd:getBodyPart(partType)
        if bp:bitten() or bp:deepWounded() then return true end
    end
    return false
end

local function checkCriticalInjury(player)
    local critical = isCriticalInjury(player)
    if critical and not criticalInjuryTriggered then
        criticalInjuryTriggered = true
        alert("CriticalInjuryEnabled", "CriticalInjuryPause",
            "CRITICAL: Vital Area Injury",
            "You have a serious injury to a vital area (neck, head, or torso).\n" ..
            "\nBandage it immediately." ..
            "\nThese wounds bleed rapidly and are life-threatening."
        )
    elseif not critical then
        criticalInjuryTriggered = false
    end
end

local function hasLodgedBullet(player)
    local bodyParts = player:getBodyDamage():getBodyParts()
    for i = 0, bodyParts:size() - 1 do
        if bodyParts:get(i):haveBullet() then return true end
    end
    return false
end

local function checkLodgedBullet(player)
    local bullet = hasLodgedBullet(player)
    if bullet and not bulletTriggered then
        bulletTriggered = true
        alert("LodgedBulletEnabled", "LodgedBulletPause",
            "Lodged Bullet",
            "You have a bullet lodged in your body.\n" ..
            "\nYou need forceps to remove it." ..
            "\nIt will cause ongoing pain and damage until removed."
        )
    elseif not bullet then
        bulletTriggered = false
    end
end

local function hasLodgedGlass(player)
    local bodyParts = player:getBodyDamage():getBodyParts()
    for i = 0, bodyParts:size() - 1 do
        if bodyParts:get(i):haveGlass() then return true end
    end
    return false
end

local function checkLodgedGlass(player)
    local glass = hasLodgedGlass(player)
    if glass and not glassTriggered then
        glassTriggered = true
        alert("LodgedGlassEnabled", "LodgedGlassPause",
            "Lodged Glass",
            "You have glass shards lodged in your body.\n" ..
            "\nRemove them with tweezers or by hand." ..
            "\nLeaving them in will cause ongoing pain and damage."
        )
    elseif not glass then
        glassTriggered = false
    end
end

local function hasBurns(player)
    local bodyParts = player:getBodyDamage():getBodyParts()
    for i = 0, bodyParts:size() - 1 do
        local bp = bodyParts:get(i)
        if bp:getBurnTime() > 0 and not bp:bandaged() then return true end
    end
    return false
end

local function checkBurns(player)
    local burns = hasBurns(player)
    if burns and not burnsTriggered then
        burnsTriggered = true
        alert("BurnsEnabled", "BurnsPause",
            "Burn Injury",
            "You have sustained a burn injury.\n" ..
            "\nOpen the health panel to clean the burn, then bandage it." ..
            "\nBurns cause ongoing damage until treated."
        )
    elseif not burns then
        burnsTriggered = false
    end
end

local function checkFoodPoisoning(player)
    local level = player:getStats():get(CharacterStat.FOOD_SICKNESS)
    if level >= FOOD_SICKNESS_THRESHOLD and not foodPoisoningTriggered then
        foodPoisoningTriggered = true
        alert("FoodPoisoningEnabled", "FoodPoisoningPause",
            "Food Poisoning",
            "You have significant food poisoning.\n" ..
            "\nTake charcoal tablets if available." ..
            "\nAvoid eating anything further until it passes." ..
            "\nRest and stay hydrated."
        )
    elseif level < FOOD_SICKNESS_THRESHOLD then
        foodPoisoningTriggered = false
    end
end

local function checkPoisoning(player)
    local level = player:getStats():get(CharacterStat.POISON)
    if level > 0 and not poisoningTriggered then
        poisoningTriggered = true
        alert("PoisoningEnabled", "PoisoningPause",
            "Poisoning Detected",
            "You have been poisoned.\n" ..
            "\nTake charcoal tablets immediately if available." ..
            "\nDo not eat or drink anything that may be tainted."
        )
    elseif level <= 0 then
        poisoningTriggered = false
    end
end

local function checkStarvation(player)
    local level = player:getMoodles():getMoodleLevel(MoodleType.HUNGRY)
    if level >= STARVING_MOODLE_LEVEL and not starvationTriggered then
        starvationTriggered = true
        alert("StarvationEnabled", "StarvationPause",
            "Critically Starving",
            "You are critically starving and losing health.\n" ..
            "\nEat any food you have immediately." ..
            "\nCheck your inventory and nearby containers." ..
            "\nForaging or hunting may be necessary."
        )
    elseif level < STARVING_MOODLE_LEVEL then
        starvationTriggered = false
    end
end

local function checkDehydration(player)
    local level = player:getMoodles():getMoodleLevel(MoodleType.THIRST)
    if level >= STARVING_MOODLE_LEVEL and not dehydrationTriggered then
        dehydrationTriggered = true
        alert("DehydrationEnabled", "DehydrationPause",
            "Critically Dehydrated",
            "You are critically dehydrated and losing health.\n" ..
            "\nCheck sinks, water bottles, or rain collectors." ..
            "\nDehydration will kill you faster than tainted water."
        )
    elseif level < STARVING_MOODLE_LEVEL then
        dehydrationTriggered = false
    end
end

local function onTick()
    if isClient() or isServer() then return end

    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end

    if not initialized then
        prevSickLevel           = player:getMoodles():getMoodleLevel(MoodleType.SICK)
        prevHypoLevel           = player:getMoodles():getMoodleLevel(MoodleType.HYPOTHERMIA)
        prevHyperLevel          = player:getMoodles():getMoodleLevel(MoodleType.HYPERTHERMIA)
        criticalInjuryTriggered = isCriticalInjury(player)
        bulletTriggered         = hasLodgedBullet(player)
        glassTriggered          = hasLodgedGlass(player)
        burnsTriggered          = hasBurns(player)
        foodPoisoningTriggered  = player:getStats():get(CharacterStat.FOOD_SICKNESS) >= FOOD_SICKNESS_THRESHOLD
        poisoningTriggered      = player:getStats():get(CharacterStat.POISON) > 0
        starvationTriggered     = player:getMoodles():getMoodleLevel(MoodleType.HUNGRY) >= STARVING_MOODLE_LEVEL
        dehydrationTriggered    = player:getMoodles():getMoodleLevel(MoodleType.THIRST) >= STARVING_MOODLE_LEVEL
        hypoTriggered           = player:getMoodles():getMoodleLevel(MoodleType.HYPOTHERMIA) >= TEMP_DANGER_LEVEL
        hyperTriggered          = player:getMoodles():getMoodleLevel(MoodleType.HYPERTHERMIA) >= TEMP_DANGER_LEVEL
        initialized             = true
        return
    end

    checkSickness(player)
    checkTemperature(player)
    checkCriticalInjury(player)
    checkLodgedBullet(player)
    checkLodgedGlass(player)
    checkBurns(player)
    checkFoodPoisoning(player)
    checkPoisoning(player)
    checkStarvation(player)
    checkDehydration(player)
end

Events.OnTick.Add(onTick)
