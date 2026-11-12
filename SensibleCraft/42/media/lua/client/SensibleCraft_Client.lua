-- Left click and the interact key open the butcher UI the same way the
-- right-click menu does: walk next to the hook, then queue the open action.

local function onButcherHookLeftClick(object, x, y)
    if not instanceof(object, "IsoButcherHook") or not object:getSquare() or not object:getSquare():isSeen(0) then
        return
    end
    local playerObj = getSpecificPlayer(0)
    if not playerObj or not playerObj:isAlive() or playerObj:isAiming() or playerObj:isIgnoreContextKey()
            or playerObj:isClimbingLadder() or playerObj:isClimbingDownLadder() then
        return
    end
    -- Same reach as vanilla's light-switch click: a stray click across the room doesn't walk you over.
    local playerSq, hookSq = playerObj:getCurrentSquare(), object:getSquare()
    if not playerSq or hookSq:getZ() ~= playerSq:getZ() or hookSq:DistToProper(playerObj) >= 2
            or playerSq:isWallTo(hookSq) then
        return
    end
    if getCell():getDrag(0) then
        return
    end
    local speed = UIManager.getSpeedControls()
    if speed and speed:getCurrentGameSpeed() == 0 then
        return
    end
    ContextMenuCode.OnButcherHook(nil, object, playerObj, nil)
end

Events.OnObjectLeftMouseButtonUp.Add(onButcherHookLeftClick)

function ContextualActionHandlers.OpenButcherHook(action, playerObj, hook, arg2, arg3, arg4)
    if not playerObj:getVehicle() and luautils.walkAdj(playerObj, hook:getSquare(), false) then
        ISTimedActionQueue.add(ISOpenButcherHookUI:new(playerObj, hook))
    end
end
