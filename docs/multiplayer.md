# Multiplayer, timed actions, ModData

B42 multiplayer (42.13+) is server-authoritative. Single player runs the same server-side code paths locally, so code that only works in SP usually breaks in MP.

## 1. Side checks

| Situation | `isClient()` | `isServer()` | Notes |
|---|---|---|---|
| Single player | false | false | `getOnlinePlayers()` is empty |
| MP client | true | false | |
| Co-op host's own game | true | false | `isCoopHost()` is true; server code runs in the separate co-op server |
| Dedicated or co-op server | false | true | `client/` is never executed |

[A]

1. **"Works for the co-op host" is not the same as "works in SP."** [A]
2. **Player loop:** `isServer() and getOnlinePlayers() or getSpecificPlayer(0 .. getNumActivePlayers()-1)`. [C]

## 2. Timed actions

```lua
-- shared/TimedActions/MyMod_DoThing.lua
require "TimedActions/ISBaseTimedAction"
MyMod_DoThing = ISBaseTimedAction:derive("MyMod_DoThing")   -- string must equal the global name

function MyMod_DoThing:new(character, item)                 -- every param stored under the same name
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.maxTime = o:getDuration()
    return o
end
function MyMod_DoThing:getDuration() return 100 end
function MyMod_DoThing:isValid() return self.character:getInventory():contains(self.item) end  -- must return true
function MyMod_DoThing:perform() ISBaseTimedAction.perform(self) end   -- client side
function MyMod_DoThing:complete()                                       -- server/SP side
    -- authoritative state change here
    return true                                                          -- must return true
end
```

1. **Networked or client-only is decided at construction.** If the action class, or any parent, has `complete`, the action is networked. Without `complete` it runs client-only the old way, which is fine for UI, walking and local transfers. Vanilla has many client-only actions in `client/`. [A]
2. **Networked actions:**
   1. The file must be in `shared/`.
   2. The `derive("X")` name must equal the global name (or set `_G[X.Type] = X`; required since 42.13).
   3. Every `new()` parameter must be stored as `o.<sameName>`. The server rebuilds the action as `_G[Type].new(Type, ...)` from those fields.

   [A, O]
3. **Where each method runs:**
   1. The client runs `start`, `update` and `perform`.
   2. The server runs `serverStart`, `serverStop`, `complete` and `animEvent`, and **never runs `update()`**.
   3. `complete()` never runs on an MP client. In SP it runs locally.

   [A]
4. **Return values:** `isValid()` must return true (the base returns nothing, which counts as invalid), `complete()` must return true, and `waitToStart()` returning false means proceed. [A]
5. **Duration:** the server calls `getDuration()`. `-1` means indefinite. [A]
6. **Allowed action argument types:**
   1. Engine types: `IsoPlayer`, `IsoObject`, `IsoGridSquare`, `InventoryItem`, `ItemContainer`, `BaseVehicle`, `VehiclePart`, `IsoZombie`, `IsoAnimal`, `CraftRecipe`, `FluidContainer`.
   2. Plain values: numbers, strings and tables.
   3. Positional `nil` arguments keep their slot.

   [A]
7. **Order when one action finishes (SP).** `IsoGameCharacter` calls the Lua `perform()` first, then `complete()`. `ISBaseTimedAction.perform` calls the queue's `onCompleted`, which runs the **next** action's `isValidStart()` and `begin()` right there. `begin()` calls `StartAction`, which calls `waitToStart()`, and that calls `start()` **immediately** unless `shouldWaitToStartTimedAction()` is true (only while sitting on the ground mid-animation). So the next action's `isValidStart()` and usually its `start()` run before the previous `complete()` has changed anything. `update()` runs on a later frame, after it. `ISInventoryTransferAction` moves the item in `perform()`, which is why "transfer, then act on the item" queues work. [A, and confirmed in game: Quick Meals chains stopped after one ingredient because they planned in `start()`]
8. **`forceStop()` clears the whole queue.** It leads to `ISBaseTimedAction:stop()`, which calls `resetQueue()`. Vanilla `ISQueueActionsAction` does this when its function adds nothing, so it cancels everything queued behind it. To end a step quietly, use `forceComplete()`. [A]
9. **Chains that must re-plan after each step:** don't use `ISTimedActionQueue.queueActions`, because its function runs in `start()` (rule 7). Plan in `update()` instead, wrap it in `beginAddingActions()`/`endAddingActions()` so added actions go right after the current one, and always finish with `forceComplete()`. `QuickMealsStepAction` in `QuickMeals.lua` is an example. [A]

## 3. Commands

```lua
-- client
sendClientCommand(player, "MyMod", "doThing", { x = sq:getX(), y = sq:getY(), z = sq:getZ() })
-- server/MyMod_Server.lua
if isClient() then return end
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "MyMod" then return end
    -- validate args; never trust the client
end)
```

1. **In SP, `sendClientCommand` goes through a loopback.** `OnClientCommand` fires later with serialized copies of the arguments. `sendServerCommand` does nothing unless `isServer()`, so it is a no-op in SP. [A]
2. **Argument types:**
   1. Keys must be strings or numbers.
   2. Values may be strings, numbers, booleans, tables, `InventoryItem`, `IsoDirections` or `IsoDeadBody`. Anything else is dropped with `can't save key,value=`.
   3. Send coordinates and IDs rather than objects.

   [A]
3. **Rate limits.** Never send per tick; batch at 0.5 s or slower. The server rate-limits command spam (`PacketsCache.isLimitExceeded`). [O]
4. **Sounds triggered on the server don't play on clients.** Send a command to a client file that plays them. [C]
5. **Item identity.** Items sent across the network arrive as new objects, so `container:contains(item)` fails. Use `container:getItemWithID(id)`. [A]

## 4. Sync helpers

1. **Server-only helpers** (no-ops elsewhere, so they're safe to call unconditionally):
   1. `sendAddItemToContainer(c, item)` and `sendAddItemsToContainer(c, list)`.
   2. `sendReplaceItemInContainer(c, old, new)`.
   3. `syncItemModData(player, item)` and `syncHandWeaponFields(player, item)`.

   [A]
2. **Helpers that work on both sides:** `syncItemFields(player, item)` and `sendRemoveItemFromContainer(c, item)`. [A]
3. **Floor items.** Only the server should add or remove them (`AddWorldInventoryItem`, `transmitRemoveItemFromSquare`). If a client does it, ghost duplicates appear. [O]
4. **Map objects that gain a `FluidContainer`** need `obj:sync()` before clients see it. [A]
5. **`IsoGenerator:setFuel`, `setActivated` and `setConnected` call `sync()` themselves.** An extra `gen:sync()` after them only doubles the packet. [A]
6. **`MapObjects.OnNewWithSprite` hooks are server-side.** A second registration at the same priority for the same sprite *replaces* the first. [A]
7. **Vehicle impulses** (`applyImpulseFromHitObject` and similar) only work on the machine simulating the car: SP, or the driver's client. `setSpeedKmHour` only changes the displayed speed. [A]

## 5. ModData

1. **Object ModData** (`obj:getModData()`) is saved with the object. On map objects, call `obj:transmitModData()` after changing it in MP. [C, I]
2. **Global ModData:**
   1. Call `ModData.getOrCreate(tag)` in `OnInitGlobalModData(isNewGame)`, which fires after `global_mod_data.bin` loads. `ModData.create(tag)` returns nil if the tag already exists.
   2. `ModData.transmit(tag)` sends from client to server, or from server to all clients, and does nothing in SP. It sends the **whole table**, so keep tables small. `ModData.request(tag)` is client-only.
   3. The receiver gets `OnReceiveGlobalModData(tag, tbl or false)` and must call `ModData.add(tag, tbl)` itself.
   4. The server also receives client transmits, so validate them.

   [A]
3. **`getGameTime():getModData()`** is synced from the server, which overwrites client writes. [O]
