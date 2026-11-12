-- Build 42.
-- The fixes live in the Java part (media/java/CutawayFix.jar, loaded by ZombieBuddy). This file only tells
-- the player when that part isn't running. CutawayFix_active is defined by the jar.

local REPORT_DELAY_TICKS = 120

local ticks = 0

local function report()
    ticks = ticks + 1
    if ticks < REPORT_DELAY_TICKS then return end
    Events.OnTick.Remove(report)

    if CutawayFix_active and CutawayFix_active() then
        print("[CutawayFix] Java fixes active")
        return
    end
    print("[CutawayFix] Java part not loaded. It needs the ZombieBuddy Java mod loader, and its Java must be approved when ZombieBuddy asks.")
    local player = getSpecificPlayer(0)
    if player then
        HaloTextHelper.addBadText(player, "Cutaway Fix: needs ZombieBuddy")
    end
end

Events.OnGameStart.Add(function()
    ticks = 0
    Events.OnTick.Add(report)
end)
