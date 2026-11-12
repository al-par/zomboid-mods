local CHECK_INTERVAL_MS       = 250
-- A warning fires again only after its condition has been gone this long, so values
-- hovering at a threshold don't pause the game over and over.
local REARM_MS                = 60000
local TEMP_DANGER_LEVEL       = 3
local FOOD_SICKNESS_THRESHOLD = 50
local STARVING_MOODLE_LEVEL   = 4

local STYLE_NONE, STYLE_SIMPLIFIED, STYLE_FULL = 1, 2, 3

local CRITICAL_HEAD_PARTS  = { BodyPartType.Neck, BodyPartType.Head }
local CRITICAL_TORSO_PARTS = { BodyPartType.Torso_Upper, BodyPartType.Torso_Lower }

local TOAST_BACKGROUND = { r = 0.15, g = 0,   b = 0,   a = 0.92 }
local TOAST_BORDER     = { r = 0.8,  g = 0.2, b = 0.2, a = 1 }
local TOAST_TOP, TOAST_GAP = 60, 6

local initialized = false
local nextCheckMs = 0
local states      = {}
local toasts      = {}

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
    local modal = ISModalRichText:new(x, y, w, h, title .. " <LINE> <LINE> " .. body, false, nil, nil, 0)
    modal:initialise()
    modal:addToUIManager()
    modal.destroy = destroyWithoutUnpause
end

local function layoutToasts()
    local y = TOAST_TOP
    for i = 1, #toasts do
        toasts[i]:setY(y)
        y = y + toasts[i]:getHeight() + TOAST_GAP
    end
end

local function toastOnMouseDown(self, mx, my)
    self:removeFromUIManager()
    for i = #toasts, 1, -1 do
        if toasts[i] == self then table.remove(toasts, i) end
    end
    layoutToasts()
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
    local x     = getCore():getScreenWidth() / 2 - w / 2
    local toast = ISPanel:new(x, TOAST_TOP, w, h)
    toast.backgroundColor = TOAST_BACKGROUND
    toast.borderColor     = TOAST_BORDER
    toast.msg             = msg
    toast:initialise()
    toast:addToUIManager()
    toast.onMouseDown = toastOnMouseDown
    toast.render      = toastRender
    table.insert(toasts, toast)
    layoutToasts()
end

local function show(name, bodyKey)
    local mode = style()
    if mode == STYLE_NONE then return end
    openHealthPanel()
    if mode == STYLE_SIMPLIFIED then
        showToast(getText("IGUI_HW_" .. name .. "_Short"))
    else
        showAlert(getText("IGUI_HW_" .. name .. "_Title"), getText(bodyKey or ("IGUI_HW_" .. name .. "_Body")))
    end
end

-- option: sandbox prefix (<option>Enabled, <option>Pause); name: text prefix (IGUI_HW_<name>_...)
local function alert(option, name, bodyKey)
    local opts = sv()
    if not (opts and opts[option .. "Enabled"]) then return end
    show(name or option, bodyKey)
    if opts[option .. "Pause"] then pauseGame() end
end

-- Fires once when the condition becomes true; re-arms after it has been false for REARM_MS.
-- Returns true when the warning fires.
local function edge(id, active, now)
    local s = states[id]
    if not s then
        s = {}
        states[id] = s
    end
    if active then
        s.clearSince = nil
        if s.triggered then return false end
        s.triggered = true
        return initialized
    end
    if s.triggered then
        s.clearSince = s.clearSince or now
        if now - s.clearSince >= REARM_MS then s.triggered = false end
    end
    return false
end

-- Check both ZOMBIE_INFECTION and ZOMBIE_FEVER so Knox is detected
-- even before fever symptoms fully develop
local function isKnoxInfected(stats)
    return stats:get(CharacterStat.ZOMBIE_INFECTION) > 0
        or stats:get(CharacterStat.ZOMBIE_FEVER) > 0
end

local function isCriticalInjury(bodyDamage)
    for i = 1, #CRITICAL_HEAD_PARTS do
        local bp = bodyDamage:getBodyPart(CRITICAL_HEAD_PARTS[i])
        if bp:bitten() or bp:deepWounded() or (bp:isCut() and bp:bleeding()) then return true end
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

local function onTick()
    local now = getTimestampMs()
    if now < nextCheckMs then return end
    nextCheckMs = now + CHECK_INTERVAL_MS

    if isClient() or isServer() then return end

    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end

    local opts       = sv()
    local moodles    = player:getMoodles()
    local stats      = player:getStats()
    local bodyDamage = player:getBodyDamage()
    local bullet, glass, burns = scanBodyParts(bodyDamage)
    local sickLevel  = moodles:getMoodleLevel(MoodleType.SICK)

    local threshold = (opts and opts.LowHealthThreshold) or 20
    if edge("LowHealth", bodyDamage:getOverallBodyHealth() <= threshold, now)
            and (not opts or opts.LowHealthPause ~= false) then
        show("LowHealth")
        pauseGame()
    end

    -- Jumping straight to Fever skips the Sick warning.
    local fever = edge("Fever", sickLevel >= 4, now)
    if edge("Sick", sickLevel >= 3, now) and not fever then alert("Sick") end
    if fever then alert("Fever", nil, isKnoxInfected(stats) and "IGUI_HW_Fever_Knox" or nil) end

    if edge("Hypothermia", moodles:getMoodleLevel(MoodleType.HYPOTHERMIA) >= TEMP_DANGER_LEVEL, now) then
        alert("Temperature", "Hypothermia")
    end
    if edge("Overheating", moodles:getMoodleLevel(MoodleType.HYPERTHERMIA) >= TEMP_DANGER_LEVEL, now) then
        alert("Temperature", "Overheating")
    end
    if edge("CriticalInjury", isCriticalInjury(bodyDamage), now) then alert("CriticalInjury") end
    if edge("LodgedBullet", bullet, now) then alert("LodgedBullet") end
    if edge("LodgedGlass", glass, now) then alert("LodgedGlass") end
    if edge("Burns", burns, now) then alert("Burns") end
    if edge("FoodPoisoning", stats:get(CharacterStat.FOOD_SICKNESS) >= FOOD_SICKNESS_THRESHOLD, now) then
        alert("FoodPoisoning")
    end
    if edge("Poisoning", stats:get(CharacterStat.POISON) > 0, now) then alert("Poisoning") end
    if edge("Starvation", moodles:getMoodleLevel(MoodleType.HUNGRY) >= STARVING_MOODLE_LEVEL, now) then
        alert("Starvation")
    end
    if edge("Dehydration", moodles:getMoodleLevel(MoodleType.THIRST) >= STARVING_MOODLE_LEVEL, now) then
        alert("Dehydration")
    end

    initialized = true
end

Events.OnTick.Add(onTick)
