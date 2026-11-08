local CHECK_INTERVAL_MS       = 250
local TEMP_DANGER_LEVEL       = 3
local FOOD_SICKNESS_THRESHOLD = 50
local STARVING_MOODLE_LEVEL   = 4

local STYLE_NONE, STYLE_SIMPLIFIED, STYLE_FULL = 1, 2, 3

local CRITICAL_HEAD_PARTS  = { BodyPartType.Neck, BodyPartType.Head }
local CRITICAL_TORSO_PARTS = { BodyPartType.Torso_Upper, BodyPartType.Torso_Lower }

local TOAST_BACKGROUND = { r = 0.15, g = 0,   b = 0,   a = 0.92 }
local TOAST_BORDER     = { r = 0.8,  g = 0.2, b = 0.2, a = 1 }

local initialized             = false
local nextCheckMs             = 0
local prevSickLevel           = 0
local lowHealthTriggered      = false
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

local function sv() return SandboxVars.HealthWarnings end

local function style()
    local opts = sv()
    return (opts and opts.Style) or STYLE_FULL
end

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

-- ISModalRichText:destroy minus its SetCurrentGameSpeed(1), so closing the dialog does not unpause the game
local function destroyWithoutUnpause(self)
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

local function showAlert(title, body)
    local w, h = 420, 320
    local x = getCore():getScreenWidth()  / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local modal = ISModalRichText:new(x, y, w, h, title .. "\n \n" .. body, false, nil, nil, 0)
    modal:initialise()
    modal:addToUIManager()
    modal.destroy = destroyWithoutUnpause
end

local function toastOnMouseDown(self, mx, my)
    self:removeFromUIManager()
    return true
end

local function toastRender(self)
    ISPanel.render(self)
    self:drawTextCentre(self.msg, self.width / 2, 12, 1, 0.4, 0.4, 1, UIFont.Small)
end

-- A panel instead of HaloText so the message stays visible while paused
local function showToast(msg)
    local fh    = getTextManager():getFontHeight(UIFont.Small)
    local w     = math.max(300, getTextManager():MeasureStringX(UIFont.Small, msg) + 40)
    local h     = fh + 24
    local x     = getCore():getScreenWidth()  / 2 - w / 2
    local y     = 60
    local toast = ISPanel:new(x, y, w, h)
    toast.backgroundColor = TOAST_BACKGROUND
    toast.borderColor     = TOAST_BORDER
    toast.msg             = msg
    toast:initialise()
    toast:addToUIManager()
    toast.onMouseDown = toastOnMouseDown
    toast.render      = toastRender
end

local function alert(key, pauseKey, short, title, body)
    local opts = sv()
    local mode = style()
    if mode == STYLE_NONE or not (opts and opts[key]) then return end
    openHealthPanel()
    if mode == STYLE_SIMPLIFIED then
        showToast(short)
    else
        showAlert(title, body)
    end
    if opts[pauseKey] then pauseGame() end
end

-- Check both ZOMBIE_INFECTION and ZOMBIE_FEVER so Knox is detected
-- even before fever symptoms fully develop
local function isKnoxInfected(stats)
    return stats:get(CharacterStat.ZOMBIE_INFECTION) > 0
        or stats:get(CharacterStat.ZOMBIE_FEVER) > 0
end

local function checkLowHealth(health)
    local opts = sv()
    local threshold = (opts and opts.LowHealthThreshold) or 20
    if health <= threshold and not lowHealthTriggered then
        lowHealthTriggered = true
        if not opts or opts.LowHealthPause ~= false then pauseGame() end
    elseif health > threshold then
        lowHealthTriggered = false
    end
end

local function checkSickness(moodles, stats)
    local sickLevel = moodles:getMoodleLevel(MoodleType.SICK)

    if prevSickLevel < 3 and sickLevel >= 3 and sickLevel < 4 then
        alert("SickEnabled", "SickPause",
            "You are now Sick.",
            "You are now Sick",
            "Your condition has worsened.\n" ..
            "\nTake antibiotics. Rest." ..
            "\nStay warm and dry. Avoid raw or rotten food." ..
            "\nMove away from corpses or equip a gas mask or respirator."
        )
    end

    if prevSickLevel < 4 and sickLevel >= 4 then
        local advice = isKnoxInfected(stats)
            and "Your skin feels like broken glass, and your head feels like it might explode. Your bones feel like they are on fire, but you shiver uncontrollably. Every step you take feels heavier and heavier still.\n\nYou need rest. Get inside. <RGB:0.5,0.5,0.5>Lock the door."
            or  "Take antibiotics. Rest in a warm, dry place."
        alert("FeverEnabled", "FeverPause", "You have a Fever.", "You have a Fever", advice)
    end

    prevSickLevel = sickLevel
end

local function checkTemperature(moodles)
    local hypo  = moodles:getMoodleLevel(MoodleType.HYPOTHERMIA)
    local hyper = moodles:getMoodleLevel(MoodleType.HYPERTHERMIA)

    if hypo >= TEMP_DANGER_LEVEL and not hypoTriggered then
        hypoTriggered = true
        alert("TemperatureEnabled", "TemperaturePause",
            "Hypothermia — warm up now.",
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
            "Overheating — cool down now.",
            "Overheating",
            "Your body temperature is dangerously high.\n" ..
            "\nRemove excess clothing." ..
            "\nFind shade or cool water." ..
            "\nRest and stay out of direct sunlight."
        )
    elseif hyper < TEMP_DANGER_LEVEL then
        hyperTriggered = false
    end
end

local function isCriticalInjury(bodyDamage)
    for i = 1, #CRITICAL_HEAD_PARTS do
        local bp = bodyDamage:getBodyPart(CRITICAL_HEAD_PARTS[i])
        if bp:bitten() or bp:deepWounded() or bp:bleeding() then return true end
    end
    for i = 1, #CRITICAL_TORSO_PARTS do
        local bp = bodyDamage:getBodyPart(CRITICAL_TORSO_PARTS[i])
        if bp:bitten() or bp:deepWounded() then return true end
    end
    return false
end

-- One pass over all body parts: lodged bullet, lodged glass, unbandaged burn
local function scanBodyParts(bodyDamage)
    local bullet, glass, burns = false, false, false
    local bodyParts = bodyDamage:getBodyParts()
    for i = 0, bodyParts:size() - 1 do
        local bp = bodyParts:get(i)
        if not bullet and bp:haveBullet() then bullet = true end
        if not glass and bp:haveGlass() then glass = true end
        if not burns and bp:getBurnTime() > 0 and not bp:bandaged() then burns = true end
        if bullet and glass and burns then break end
    end
    return bullet, glass, burns
end

local function checkCriticalInjury(critical)
    if critical and not criticalInjuryTriggered then
        criticalInjuryTriggered = true
        alert("CriticalInjuryEnabled", "CriticalInjuryPause",
            "Critical injury — bandage immediately.",
            "CRITICAL: Vital Area Injury",
            "You have a serious injury to a vital area (neck, head, or torso).\n" ..
            "\nBandage it immediately." ..
            "\nThese wounds bleed rapidly and are life-threatening."
        )
    elseif not critical then
        criticalInjuryTriggered = false
    end
end

local function checkLodgedBullet(bullet)
    if bullet and not bulletTriggered then
        bulletTriggered = true
        alert("LodgedBulletEnabled", "LodgedBulletPause",
            "Lodged bullet — use forceps to remove.",
            "Lodged Bullet",
            "You have a bullet lodged in your body.\n" ..
            "\nYou need forceps to remove it." ..
            "\nIt will cause ongoing pain and damage until removed."
        )
    elseif not bullet then
        bulletTriggered = false
    end
end

local function checkLodgedGlass(glass)
    if glass and not glassTriggered then
        glassTriggered = true
        alert("LodgedGlassEnabled", "LodgedGlassPause",
            "Lodged glass — remove with tweezers or by hand.",
            "Lodged Glass",
            "You have glass shards lodged in your body.\n" ..
            "\nRemove them with tweezers or by hand." ..
            "\nLeaving them in will cause ongoing pain and damage."
        )
    elseif not glass then
        glassTriggered = false
    end
end

local function checkBurns(burns)
    if burns and not burnsTriggered then
        burnsTriggered = true
        alert("BurnsEnabled", "BurnsPause",
            "Burn injury — clean and bandage the wound.",
            "Burn Injury",
            "You have sustained a burn injury.\n" ..
            "\nOpen the health panel to clean the burn, then bandage it." ..
            "\nBurns cause ongoing damage until treated."
        )
    elseif not burns then
        burnsTriggered = false
    end
end

local function checkFoodPoisoning(stats)
    local level = stats:get(CharacterStat.FOOD_SICKNESS)
    if level >= FOOD_SICKNESS_THRESHOLD and not foodPoisoningTriggered then
        foodPoisoningTriggered = true
        alert("FoodPoisoningEnabled", "FoodPoisoningPause",
            "Food poisoning — take charcoal tablets.",
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

local function checkPoisoning(stats)
    local level = stats:get(CharacterStat.POISON)
    if level > 0 and not poisoningTriggered then
        poisoningTriggered = true
        alert("PoisoningEnabled", "PoisoningPause",
            "You are poisoned — take charcoal tablets.",
            "Poisoning Detected",
            "You have been poisoned.\n" ..
            "\nTake charcoal tablets immediately if available." ..
            "\nDo not eat or drink anything that may be tainted."
        )
    elseif level <= 0 then
        poisoningTriggered = false
    end
end

local function checkStarvation(moodles)
    local level = moodles:getMoodleLevel(MoodleType.HUNGRY)
    if level >= STARVING_MOODLE_LEVEL and not starvationTriggered then
        starvationTriggered = true
        alert("StarvationEnabled", "StarvationPause",
            "Critically starving — eat food immediately.",
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

local function checkDehydration(moodles)
    local level = moodles:getMoodleLevel(MoodleType.THIRST)
    if level >= STARVING_MOODLE_LEVEL and not dehydrationTriggered then
        dehydrationTriggered = true
        alert("DehydrationEnabled", "DehydrationPause",
            "Critically dehydrated — drink water immediately.",
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
    local now = getTimestampMs()
    if now < nextCheckMs then return end
    nextCheckMs = now + CHECK_INTERVAL_MS

    if isClient() or isServer() then return end

    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end

    local moodles    = player:getMoodles()
    local stats      = player:getStats()
    local bodyDamage = player:getBodyDamage()
    local health     = bodyDamage:getOverallBodyHealth()
    local critical   = isCriticalInjury(bodyDamage)
    local bullet, glass, burns = scanBodyParts(bodyDamage)

    if not initialized then
        local opts = sv()
        prevSickLevel           = moodles:getMoodleLevel(MoodleType.SICK)
        lowHealthTriggered      = health <= ((opts and opts.LowHealthThreshold) or 20)
        criticalInjuryTriggered = critical
        bulletTriggered         = bullet
        glassTriggered          = glass
        burnsTriggered          = burns
        foodPoisoningTriggered  = stats:get(CharacterStat.FOOD_SICKNESS) >= FOOD_SICKNESS_THRESHOLD
        poisoningTriggered      = stats:get(CharacterStat.POISON) > 0
        starvationTriggered     = moodles:getMoodleLevel(MoodleType.HUNGRY) >= STARVING_MOODLE_LEVEL
        dehydrationTriggered    = moodles:getMoodleLevel(MoodleType.THIRST) >= STARVING_MOODLE_LEVEL
        hypoTriggered           = moodles:getMoodleLevel(MoodleType.HYPOTHERMIA) >= TEMP_DANGER_LEVEL
        hyperTriggered          = moodles:getMoodleLevel(MoodleType.HYPERTHERMIA) >= TEMP_DANGER_LEVEL
        initialized             = true
        return
    end

    checkLowHealth(health)
    checkSickness(moodles, stats)
    checkTemperature(moodles)
    checkCriticalInjury(critical)
    checkLodgedBullet(bullet)
    checkLodgedGlass(glass)
    checkBurns(burns)
    checkFoodPoisoning(stats)
    checkPoisoning(stats)
    checkStarvation(moodles)
    checkDehydration(moodles)
end

Events.OnTick.Add(onTick)
