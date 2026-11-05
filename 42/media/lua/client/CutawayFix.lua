-- Build 42.
-- The fixes live in the Java agent (java/CutawayFix-agent.jar, added to the game's launch options by
-- install.ps1). It writes Zomboid/Lua/CutawayFix_status.txt at launch and deletes it on exit; this file
-- only tells the player whether that agent is running.

local STATUS_FILE = "CutawayFix_status.txt"
local PATCHES = { "south_edge_invalidation", "occluded_rooms_recheck", "attached_room_roofs", "tree_room_crash" }
local REPORT_DELAY_TICKS = 120

local function readStatus()
    local reader = getFileReader(STATUS_FILE, false)
    if not reader then return nil end
    local status = {}
    local line = reader:readLine()
    while line do
        local key, value = string.match(line, "^([^=]+)=(.*)$")
        if key then
            status[key] = value
        end
        line = reader:readLine()
    end
    reader:close()
    return status
end

local function findProblem(status)
    if not status then
        return "Java patch not loaded", "Run install.ps1 in the CutawayFix mod folder, then restart the game."
    end
    if status.error then
        return "Java patch failed", status.error
    end
    local skipped = {}
    for i = 1, #PATCHES do
        if status[PATCHES[i]] ~= "applied" then
            skipped[#skipped + 1] = PATCHES[i]
        end
    end
    if #skipped > 0 then
        return "some fixes skipped", "A game update changed the code behind: " .. table.concat(skipped, ", ")
    end
    return nil
end

local ticks = 0

local function report()
    ticks = ticks + 1
    if ticks < REPORT_DELAY_TICKS then return end
    Events.OnTick.Remove(report)

    local summary, detail = findProblem(readStatus())
    if not summary then
        print("[CutawayFix] all " .. #PATCHES .. " fixes active")
        return
    end
    print("[CutawayFix] " .. summary .. ". " .. detail)
    local player = getSpecificPlayer(0)
    if player then
        HaloTextHelper.addBadText(player, "Cutaway Fix: " .. summary)
    end
end

Events.OnGameStart.Add(function()
    ticks = 0
    Events.OnTick.Add(report)
end)
