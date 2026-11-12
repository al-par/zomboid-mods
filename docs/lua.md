# Lua in Project Zomboid B42

## 1. Kahlua is not standard Lua 5.1

1. **Missing:** `next`, `xpcall`, `io.*`, and `math.random`/`math.randomseed`. Calling `next` raises "tried to call nil". Iterate instead: `for k in pairs(t) do return k end`. For randomness use `ZombRand(n)` (0 to n-1), `ZombRand(a, b)` or `ZombRandFloat(a, b)`. Vanilla never calls `math.random`. [C]
2. **Partial:** `os` has only `os.date`, `os.difftime` and `os.time`. `loadstring` exists. [A]
3. **Where the basics come from:** `pairs`, `ipairs`, `assert`, `table.sort` and `coroutine.wrap` are defined in `<install>\stdlib.lua`. `table.sort` is a pure-Lua quicksort, so it is **not stable**, and it errors on inconsistent comparators. [C]
4. **PZ extras:** `string.trim`, `string.split`, `string.contains`, `table.newarray`, `table.isempty` and `table.wipe`. `string.split` takes a Java **regex**, so write `s:split("\\.")`, not `s:split(".")`. Tables from `table.newarray` can't be stored in modData or sent over the network. [A, O]
5. **`%` truncates toward zero.** `-1 % 3 == -1` (standard Lua gives 2), `x % 0` is NaN, and it misbehaves past the 32-bit range. [A]
6. **`rawget` isn't raw.** It falls back to the metatable's keys, so `rawget(obj, "method")` finds inherited methods of `derive()` classes. [A]
7. **Multiple returns leak into calls.** `math.min(x, f())` receives every value `f` returns; wrap it as `math.min(x, (f()))`. `ipairs({nil, item})` stops at once. (Standard Lua behaviour, but it caused real bugs.) [C]
8. **`pairs` copies the key list first.** Deleting keys during the loop is safe, but every `pairs` over a non-empty table allocates an array of all its keys, so avoid `pairs` over big tables in per-frame code. [A]
9. **`require "x"` never raises.** It adds `.lua`, searches loaded paths, returns nil with a `require("x") failed` WARN, and logs `recursive require()` on cycles. Vanilla itself emits dozens of these warnings. [C]

## 2. Load order

1. **Folders load in a fixed order.** `shared` loads, then `client`, then `server`. Within each folder, vanilla loads first, then each mod in load order (its `common/`, then its version folder). Files are sorted case-insensitively. A file with the same relative path replaces the earlier one, and the last mod wins. [A, C]
2. **Cross-folder references crash at load.** Code that runs at file load and touches a global from a later folder fails, with errors like `attempted index: derive of non-table: null`. `ISBuildingObject` and every build cursor live in `server/BuildingObjects/`, so put classes that derive from them in `server/`. Client menus may refer to them only inside callbacks. [C]
3. **Which folders run where.** `server/` also loads in SP and on MP clients, so guard server-only files with `if isClient() then return end`. On a dedicated server, `client/` is checksummed but never executed. [C, A]
4. **Quitting to the main menu resets Lua.** `shared` and `client` reload, and `OnGameBoot` fires again. [A]

## 3. Events

```lua
local function onEveryTenMinutes() ... end
Events.EveryTenMinutes.Add(onEveryTenMinutes)   -- keep the reference to Remove later
```

1. **Registration pitfalls.** `Events.X.Add` accepts only Lua functions. A `nil` from a typo is **silently ignored**. Handlers are not deduplicated, and `Remove` needs the same function reference. When one handler errors, the error is logged and the other handlers still run. [A]
2. **Custom events.** Create one with `LuaEventManager.AddEvent("MyMod_Event")`, then fire it with `triggerEvent("MyMod_Event", a, b, c, d)` (at most 4 arguments). Firing an unknown name auto-registers it and logs `adding unknown event`. [A]
3. **42.21 registers 262 events.** Lesser-known ones include `OnTickEvenPaused`, `OnServerStarted`, `OnGameTimeLoaded`, `OnPostSave`, `OnTileObjectAdded`, `OnObjectAboutToBeRemoved`, `OnPostDistributionMerge` and `LoadChunk`. For the full list, see `LuaEventManager` or the Umbrella typings (`sources.md`). [A]

Where events fire:

| Event | Fires on | Notes |
|---|---|---|
| `OnTick` | client, SP, **and servers** | Every frame, whatever the game speed. Stops when a server is paused because it's empty. [A] |
| `OnPlayerUpdate` | client, SP | Local players only. [A] |
| `OnRenderTick`, `OnSave` | client, SP | Fired from `GameWindow`. [A] |
| `OnPreUIDraw`, `OnPostUIDraw` | client, SP | Fired from `UIManager.render()` on every UI frame, **at the main menu as well as in game and while paused**. The only gate is the UI-FBO frame skip. ErrorMonitor polls from it behind a `getTimestampMs()` check. [A] |
| `OnGameStart`, `OnLoad` | client, SP | Never on a server. Server-side init uses `OnServerStarted`, `OnInitWorld`, `OnInitGlobalModData`. [A] |
| `OnGameBoot` | all | In SP and on clients it fires **before** `server/` loads, so `OnGameBoot` handlers in `server/` files never run there. [A] |
| `EveryOneMinute`, `EveryTenMinutes`, `EveryHours`, `EveryDays` | wherever game time runs | Real-time rate scales with game speed. All handlers fire on the same frame. [A] |
| `LoadGridsquare` | wherever squares load | Once for every loaded square. Expensive (`performance-debugging.md`). [A] |
| `OnLoadedTileDefinitions(manager)` | all | After tile definitions load, before chunks. Use it to edit sprite properties; `OnGameBoot` is too early. [A] |
| `OnObjectAdded` | | Fired when a moveable is placed. [C] |
| `OnHitZombie(zombie, attacker, bodyPartType, weapon)` | wherever `IsoZombie.Hit` runs | Fired at the start of `Hit`, before damage, melee and ranged alike. Shoves and stomps pass the `BareHands` weapon. Pair with `zombie:addItemToSpawnAtDeath(item)`: `DoZombieInventory` moves that list into the corpse on death; the list isn't saved, so a zombie that unloads alive loses it. [A] |

World initialisation order, from `IsoWorld.init`:

1. `OnPreDistributionMerge`
2. `OnDistributionMerge`
3. `OnPostDistributionMerge`
4. `OnInitWorld`
5. Sandbox options load
6. `ItemPickerJava.Parse`
7. `OnLoadedTileDefinitions`
8. `OnInitGlobalModData(isNewGame)`
9. `OnLoadMapZones`

[A]

## 4. Java interop

1. **Only public methods are callable.** Instance fields are never readable or writable (`obj.field` is nil). Static fields are snapshots taken when the class was exposed, so use getters. [A]
2. **Reflection is debug-only since 42.15.** `getClassField`, `getClassFieldVal`, `getNumClassFields`, `getClassFunction` and the rest throw `Not in debug` without `-debug`. Never use them in a shipped mod. [A, O]
3. **Java lists are 0-based.** Use `list:size()` and `list:get(i)` for `i = 0 .. size-1`; `#list` doesn't work. [C]
4. **Some Java getters have side effects.** For example, `animalShouldThump()` decrements a timer. Don't call Java decision functions just to read state. [A]
5. **Some lookups never return nil.** `IsoSpriteManager.getSprite(name)` creates a placeholder for unknown names, so a nil check validates nothing. [A]
6. **Squares are pooled and reused.** `IsoGridSquare.discard()` returns squares to a cache, so a stored square object can later point at a different location. Keep coordinates across frames, not square objects. [A]
7. **Hooking vanilla.** Wrap globals with `local orig = X.f; X.f = function(...) return orig(...) end`. Local functions and tables can't be hooked. Before wrapping, confirm the function still exists in 42.21; a wrapper on a removed function silently never runs. [C]

## 5. B41 → B42 renames that keep biting

| B41 (broken in 42.21) | B42 |
|---|---|
| `stats:getEndurance()` / `setEndurance` | `stats:get(CharacterStat.ENDURANCE)` / `stats:set(...)` [C] |
| `player:HasTrait("Burglar")` | `player:hasTrait(CharacterTrait.BURGLAR)` [C] |
| `props:Is("X")`, `props:Val("X")`, `props:Set(...)` | `props:has(...)`, `props:get(...)`, `props:set(...)` [C] |
| `props:has("WallN")` | `props:has(IsoFlagType.WallN)`, because walls, doors, windows and hoppables are flags (`world-objects.md`) [C] |
| `require "recipecode"`, `Recipe.OnCreate` | `craftRecipe` scripts; `OnCreate(craftRecipeData, character)` (`scripts.md`) [C] |
| string item tags | `ItemTag.X`; `getScriptManager():getItemsTag(ItemTag.get(ResourceLocation.of("X")))` [C] |
| `getUseDelta` petrol cans | `item:getFluidContainer():contains(Fluid.Petrol)`, `getAmount`, `getCapacity`, `getFreeCapacity` [C] |
| `ISWorldObjectContextMenu.doWashClothingMenu`, `handleInteraction`, `getSquaresInRadius`, `ISFireplaceMenu`, `ISBBQMenu.onAddAllFuel` | gone; the world menu is built in Java (section 6) [C] |
| campfire-only fuel functions | `ISCampingMenu.onAddAllFuel(playerObj, target, timedAction, currentFuel)`, shared by campfire, BBQ and fireplace [C] |
| `SRainBarrelSystem` tracking rain barrels | `SRainBarrelSystem:isValidIsoObject` returns `false`, so it tracks nothing [C] |
| `math.random` | `ZombRand` [C] |
| `getGameTime():setPaused(true)` (never existed) | `UIManager.getSpeedControls():SetCurrentGameSpeed(0)`. If the game is already paused, this stores 0 as the resume speed, so check `getCurrentGameSpeed() ~= 0` first [C] |

## 6. Context menus

1. **The world menu is built mostly in Java** (`ISWorldObjectContextMenuLogic`).
   1. It returns early while the game is paused, the world map is open, or the player is asleep.
   2. `OnPreFillWorldObjectContextMenu(playerNum, context, worldobjects, test)` fires before Java adds its entries.
   3. `OnFillWorldObjectContextMenu` fires afterwards, and only if safehouse rules allow interaction.

   [C, A]
2. **To change a vanilla option,** find it with `context:getOptionFromName(getText("ContextMenu_..."))` and edit it. Don't re-implement the vanilla builder. [C]
3. **`ISContextMenu` API:**
   1. `addOption(name, target, fn, p1..p10)` calls `fn(target, p1..p10)`.
   2. Also available: `addOptionOnTop`, `insertOptionAfter`/`insertOptionBefore(existingName, ...)`, `removeOptionByName`, `getOptionFromName`, `addSubMenu(option, ISContextMenu:getNew(context))` and `addDebugOption` (hidden unless in debug).

   [C]
4. **`addGetUpOption(text, target, onSelect, p2, ...)` shifts the parameters.** It calls `addOption(text, self, self.onGetUpAndThen, onSelect, target, p2, ...)`, so `option.param1` is the callback, `param2` is the original target, and `param3` is your first extra argument. [C]
5. **`addActionsOption(text, fn, a1, ...)`** is `addOption(text, character, ISTimedActionQueue.queueActions, fn, a1, ...)`. [C]
6. **Inventory menus.** The `items` argument of `OnFillInventoryObjectContextMenu(playerNum, context, items)` mixes items and stack tables. Flatten it with `ISInventoryPane.getActualItems(items)`. [A]
7. **Check helper signatures against vanilla.** For example, `ISInventoryPaneContextMenu.onDumpContents(items, item, player)` takes three arguments. [C]
8. **Gardening options sit in a submenu in 42.21.** [A]

## 7. UI notes

Items 2 and 3 come from an older guide and haven't been re-verified on 42.21.

1. **`ISModalRichText:destroy` calls `SetCurrentGameSpeed(1)`** (`ISModalRichText.lua:76-78`); `initialise` doesn't. To keep the game paused after the dialog closes, override `destroy` on the instance with a copy minus that call (HealthWarnings does this). [C]
2. **`HaloTextHelper.addBadText`/`addGoodText` are tick-driven,** so they may not render while the game is paused.
3. **For "critical injury" checks on the torso, `bleeding()` is too broad.** Use `bitten() or deepWounded()`.
4. **`ISRichTextPanel` splits text on spaces, and any word containing both `<` and `>` is run as a command.** Put spaces around tags (` <LINE> `, ` <RGB:1,0.4,0.4> `) and replace `<`/`>` in text you don't control, such as error messages or item names. Tags read in 42.21: `LINE`, `BR`, `H1`, `H2`, `TEXT`, `CENTRE`, `LEFT`, `RIGHT`, `RGB:r,g,b`, `PUSHRGB`/`POPRGB`, `RED`, `ORANGE`, `GREEN`, `GHC`, `BHC`, `SIZE:small|medium|large`, `IMAGE:`, `IMAGECENTRE:`, `INDENT:n`, `SETX:n`, `SPACE`. [A]
5. **Container capacity in the UI is `getEffectiveCapacity(player)`, not `getCapacity()`.** Organized multiplies it by 1.3 and Disorganized by 0.7 for world and vehicle containers. A damaged pickup bed read `getCapacity() = 90` while the loot window showed 116. Compare against `getEffectiveCapacity` when a rule refers to the number the player sees. [C]
6. **Don't pass arbitrary text through `getText`.** Translations go through Java's formatter (`mod-structure.md`), so a `%` inside an argument could throw. Vanilla debug windows hardcode English; do the same for text that carries log or user content. [I]
