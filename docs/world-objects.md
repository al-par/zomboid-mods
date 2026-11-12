# World objects: tiles, properties, collision, moveables

## 1. Sprite properties

1. **Flags and named properties are checked differently.**
   1. Wall, door, window and hoppable markers are `IsoFlagType` bits: `WallN`, `WallW`, `WallNW`, `WallNTrans`, `HoppableN`, `TallHoppableN`, `WindowN`, `DoorWallN`, `doorN`, `canBeCut`, and others. Check them with `props:has(IsoFlagType.WallN)`.
   2. `props:has("WallN")` only checks *named* properties, so it is **silently false** for flags. This bug broke all wall classification in SensibleLivestock and survived a "find all bugs" pass.
   3. Named properties use `props:has("Name")` / `props:get("Name")`, for example `Material`, `CustomItem`, `PickUpWeight`, `IsTrashCan`, `IsMoveAble`.
   4. 42.21 also has the `IsoPropertyType` enum, e.g. `square:has(IsoPropertyType.WALL_N)`.

   [C]
2. **B42 property methods are lowercase:** `set`, `get`, `has`, `unset`. B41 used `Set`, `Val`, `Is`. [C]
3. **Sprite properties are shared by every instance of a sprite.** Per-object state can't be changed through sprite properties. That includes `IsoThumpable` `north`, `isCorner`, `isThumpable`, `blockAllTheSquare`, `canPassThrough` and health, which are saved per object. [C]
4. **Edit sprite properties in `Events.OnLoadedTileDefinitions(manager)`** with `manager:getSprite(name):getProperties():set(...)`. [A]
5. **Property values go through `TilePropertyAliasMap`.** A value no tile definition ever used silently maps to index 0 (`getIDFromPropertyValue` is `idMap.getOrDefault(value, 0)`). For example, vanilla `MinimumCarSpeedDmg` only ever uses 5, 10, 15, 20 and 30. [A]
   1. So Lua can't introduce a new value. SensibleSalt set `CustomItem = Base.SLS_SaltLick` in `OnLoadedTileDefinitions`; it read back as the first known `CustomItem` value, `Base.HamRadio1`. A new value needs a `.patch.tiles` file (section 5.3), or convert the picked-up `Moveables.<sprite>` item in Lua afterwards. [A]
6. **The text dump `newtiledefinitions.tiles.txt` is incomplete.** The game loads the binary `.tiles` files plus patches such as `tiledefinitions_noiseworks.patch.tiles`, which override properties. Parse the binary (`tdef` format) when you need the truth. [C]
7. **Built walls don't always say what they're made of.** Brick walls (`walls_exterior_house_01_4`/`5`, `20`/`21`) have `MaterialType=Brick`, and stone walls (`walls_logs_96`/`97`) have `MaterialType=Stone`. Brick and stone door frames, window frames and the low brick fence (`BrickFenceLvl2`, `walls_exterior_house_01_36`/`37`) have no `Material` or `MaterialType`. Identify those by `obj:getEntityScript():getName()`. That survives save and load, because the `EntityScriptInfo` component saves `originalScript`. [A]

## 2. Collision

1. **What blocks a walking character:**
   1. Square flags `solid` and `solidtrans`.
   2. Edge flags `collideN` and `collideW`, which come from wall, window, hoppable and door properties.
   3. Special objects: `IsoGridSquare.getSpecialWall(north)` returns any `IsoThumpable` that is thumpable and isn't `isCorner()`, `isBlockAllTheSquare()` or stairs. That object blocks its north or west edge.

   Pathfinding (`zombie.pathfind.*`) has separate checks. [A]
2. **What blocks a vehicle:**
   1. Bullet colliders built in `IsoChunk.calcPhysics` from `solid`/`solidtrans`, `PhysicsShape`, `StopCar`, and hardcoded `lighting_outdoor_*` columns. `StopCar` makes the object `isMoveAbleObject` with a trunk collider.
   2. `PhysicsShape` is irrelevant to characters.
   3. Breakable props go through `IsoObject.HitByVehicle`, driven by `HitByCar`, `MinimumCarSpeedDmg` (150 when unset) and `DamagedSprite`.

   [A]
3. **The player-built Wooden Pole blocks one edge.**
   1. The entity `WoodenPole` (`entity_woodenpole.txt`, sprite `walls_exterior_wooden_01_27`, `isPole = true`) becomes an `IsoThumpable`.
   2. `buildUtil.setInfo` only calls `setCorner` when `ISItem.isCorner` is set, so the pole blocks one edge like a fence.

   [A]

## 3. Adding and removing objects

1. **Create and add:** `IsoObject.getNew(square, spriteName, nil, false)`, then `square:transmitAddObjectToSquare(obj, index)`. [C]
2. **Removal pitfalls:**
   1. `removeFromSquare()` doesn't clear `getSquare()`. Test for removal with `obj:getObjectIndex() < 0`.
   2. `transmitRemoveItemFromSquare` returns -1 when a multi-tile removal fails.
   3. `IsoObjectUtils.safelyRemoveTileObjectFromSquare` removes all pieces of a multi-tile object or none.

   [A]
3. **Debris:** broken fences leave `fencing_damaged_01_124`–`171`, which can be reused as debris sprites. [A]

## 4. Moveables (picking up and placing)

1. **What a pickup produces.** A placed tile picks up as `Moveables.<spriteName>`, not as the `Base.Mov_*` loot item, unless the tile has a `CustomItem` property. Recipes keyed to `Base.Mov_X` won't accept map pickups. [C]
2. **Pickup weight** is `PickUpWeight / 10` when there's no `CustomItem`. With `CustomItem`, it's the item's `Weight`. `IsMoveAble` is the pickup gate. [C, O for the CustomItem case]
3. **Placement must match the sprite exactly.** `ISMoveableSpriteProps:findInInventory` compares against `item:getWorldSprite()`. A wrong facing sprite means "not found", and placement silently does nothing. [C]
4. **Health and modData travel with the item.** `ISMoveableSpriteProps.saveThumpableParameters` copies the object's current health and modData into it, so a temporary health buffer is carried along. [C]
5. **A wall flag is a child sprite of the wall, and pickup must not treat the wall as the item.** South and east overlays are `AttachExistingAnim` on the wall in the same square (`ISMoveableSpriteProps:placeMoveableInternal`). A constructed wall is an `IsoThumpable` with entity components; a map wall is a plain `IsoObject`. Vanilla pickup passes that host into `GameEntityFactory.TransferComponents` and, for an `IsoThumpable`, `saveThumpableParameters`. `LuaTimedActionNew.complete` runs the Lua `complete()` through `pcall` and discards the result, so a failure there plays the whole animation, leaves the flag up, and puts nothing in the inventory. `WallN` / `WallW` / `WallNW` are flags: `props:has("WallN")` does not see them, and the cursor, `findOnSquare`, `getWallForFacing` and `ISMoveablesAction:new` all use that check. [A]
6. **Disassembly ("scrap") is driven by the tile's `CanScrap` and primary `Material`.**
   1. `ISMoveableDefinitions.load` (`OnGameBoot`) maps each material to a scrap definition: tools, second tools, perk, time, sound, return items. Only `Material` picks the tools, perk, time and sound; `Material2`/`Material3` only add return items.
   2. Every tool check goes through `ISMoveableSpriteProps:hasScrapTool(player, doSecond)` (context menu, cursor, `walkToAndEquip`, and `canScrapObject` on the server in `ISMoveablesAction:complete`). Wrapping it in `shared/` changes the tools everywhere. Changing the tile's `Material` instead would also change its repair definition.
   3. Chain link (`fencing_01_24`–`28` short, `56`–`60` tall) and its burnt and damaged variants are `MetalWire`, so in vanilla they need a blowtorch plus welding mask. Posts (`fencing_01_29`, `61`, `53`) are separate `MetalBars` objects. Player-built wire fences (`MetalSmallWireFence`, `MetalBigWireFence`) use the same sprites. Welded panel fences (`fencing_01_48`–`52`) and temporary construction panels (`80`–`92`) are also `MetalWire`, so material alone doesn't identify chain link.
   4. Other wire tiles: barbed-wire strands `fencing_01_20`/`21` (the player-built `BarbedWireFence`) are `MetalWire`. Razor-wire coils `fencing_01_108`–`111` are `MetalScrap` with `MetalWire` second. Every `fencing_*` tile with primary `MetalWire` is wire mesh, strands or wire debris. Chain-link gates `fixtures_doors_fences_01_64`–`79` are `MetalPipe` + `MetalWire`, and the wire-on-wooden-post tiles `fencing_01_16`–`18` are `Wood` + `MetalWire`, with the post drawn into the same sprite.
   5. Bolt cutters (`Base.BoltCutters`, tag `base:boltcutters`) aren't a scrap tool in vanilla; they're only used in a few craft recipes. Sensible Walls adds them for every `fencing_*` `MetalWire` tile plus the razor wire.
   6. Vanilla `ISMoveableSpriteProps:scrapObjectInternal` calls `UseAndSync()` on the blowtorch once per scrap (a full torch has 10 uses). That is far too harsh for bolt cutters (`ConditionMax = 15`, as common as crowbars). Vanilla tool wear in Lua is `item:damageCheck(skill, multiplier, false)`: 1 condition with chance 1 in (`ConditionLowerChanceOneIn` × multiplier + skill), then `ItemUtils.checkWeapon` if it returns true. The sledgehammer uses multiplier 2 per demolished object (`ISDestroyStuffAction`); recipe flags use `MayDegradeHeavy` 1, `MayDegrade` 2, `MayDegradeLight` 3 (every bolt cutter recipe), with the recipe skill plus Maintenance bonus (`CraftRecipeData.processKeepInputItem`). Sensible Walls uses the sledgehammer's `damageCheck(0, 2, false)`: 1 in 140 per cut, about 2,100 cuts per new pair. [A]

   [C]

## 5. Custom tiles

1. **`mod.info` entries:** `pack=<name>` and `tiledef=<name> <100..8189>`. The number must be unique (`mod-structure.md`). [A]
2. **Tileset numbers** inside one `.tiles` file run 1–512. A bad one breaks every later mod's tiledef. [O]
3. **Patching existing sprites:** a `<name>.patch.tiles` file, declared as `tiledef=<name>.patch N`, adds properties to existing sprites. UsefulBarrelsMP uses this. [C]
4. **File formats:** `.tiles` is binary (`tdef` magic, version 1). `.pack` is `PZPK` atlases of PNG pages, with 128×256 tiles at 2x. [A]
5. **Build-menu icons** can be loose PNGs in `media/textures`. [A]
6. **Tile changes need a full game restart.** [A]
7. **B42 depth maps.**
   1. Ship `common/media/depthmaps/DEPTH_<sheet>.png` (8 columns, 1024 px wide) and/or `common/media/tileDepthTextureAssignments.txt` (`mytile = vanillatile,`).
   2. A mod's depth maps only load if `common/media/tileGeometry.txt` exists. A minimal one is `tileGeometry { VERSION = 2, }`.
   3. Without depth data, sprites fall back to a whole-tile depth and can draw over characters.
   4. SensibleLivestock and SensiblePowerManagement ship none. Check them in game.

   [O]
8. **Tools.**
   1. The Indie Stone hasn't released TileZed for B42. The community fork is Unjammer/TileZed (branch B42).
   2. Depth maps can be edited with z3r0x92 PZ_Mapping_Tools or guspuffygit/project-zomboid-tile-cli.
   3. Local Python helpers in `SensibleLivestock\tools\` (`build.py`, `tiles.py`, `extract.py`) read and write `.tiles` and `.pack` files.

   [O, C]
9. **Matching vanilla masonry.**
   1. Player-built walls use these sprites (from `scripts/generated/entities/walls`):
      1. BrickWallLvl1: `walls_exterior_house_01_20` (W) and `_21` (N).
      2. BrickWallLvl2: `_4` (W) and `_5` (N).
      3. StoneWall: `walls_logs_96` (W) and `_97` (N).
   2. The W sprites are painted separately from the N ones, not just darker. Their brick is browner, so a W-facing face needs the W texture to match.
   3. One seamless horizontal period of a N wall face is sprite x 60–123. For a W face it is x 65 down to 2. The vertical scale is 192 px per floor.
   4. `HomeHeating\tools\art\walltex.py` unskews these sprites into flat textures.

   [C]
10. **A `.pack` can hold several pages.** `TexturePackDevice` reads `PZPK`, version 1, a page count, then per page: name, entry count, mask flag, the entries (`name`, then x, y, w, h, offX, offY, origW, origH as int32), and the PNG's length and bytes. `HomeHeating\tools\build.py` writes 2048 px pages. [C]

## 6. Containers on world objects

1. **An object saves every container it has.** `getContainerCount()` is the primary `container` plus `secondaryContainers`. On load the first becomes the primary, so an object that only had secondaries gets one promoted. Use `setContainer`, `addSecondaryContainer` and `getContainerByType(type)`. [C]
2. **Type, items and capacity are saved; the accept function is not.** Reapply `setAcceptItemFunction("GlobalFnName")` at load (for example from `MapObjects.OnLoadWithSprite`). The function gets `(container, item)` and must return `true`. Capacity is capped at 100 for world containers. [C]
3. **A container's temperature comes from its parent.** `ItemContainer.getTemperature` returns the `IsoFireplace`'s 1.8 while lit for every container of that object, secondary ones included. Food cooks above 1.6. The loot window title is `IGUI_ContainerTitle_<type>`. [C]
4. **`IsoFireplace` only gives itself a container if its sprite has `ContainerCapacity`.** The type is the sprite's `container` property, default `fireplace`. `addToWorld` and `turnOn` only queue the primary container's items for processing, so cooking in a secondary container needs `container:addItemsToProcessItems()` after load and when the fire is lit. [C]

   Used by HomeHeating. Not yet tested in game.

## 7. Butcher hook

1. **The placed hook is `IsoButcherHook`, not the thumpable the build recipe created.** `BuildRecipeCode.butcheringHook.OnCreate` and `MOButcherHook.lua` (`crafted_04_120`) replace the `IsoThumpable` with `IsoButcherHook.new(sq)`. The build inputs (2 planks, 2 nails, 1 large hook, hammer kept) are not stored on the replacement. [A]
2. **The sprite only has `BlocksPlacement`.** No `IsMoveAble`, so furniture pickup refuses it. No `CanScrap` or `Material`, and it is not an `IsoThumpable`, so the disassemble menu never sees `craftValid`. [A]
3. **Right-click is the vanilla open path.** `ContextMenuCode.OnButcherHook` walks adjacent and queues `ISOpenButcherHookUI`. Left click opens an entity window only when `getSpriteConfig():getMultiSquareMaster()` is set, which a single-tile hook is not. The interact-key handler `ContextualActionHandlers.OpenButcherHook` queues the same action and only walks when the player is in a vehicle. [A]
4. **SensibleCraft** sets `IsMoveAble`, `PickUpWeight` 50, `CanScrap` and `Material` Wood on that sprite in `OnLoadedTileDefinitions` (those values already exist in the property map), names the picked-up item in Lua, returns the build materials on disassemble, and opens the hook UI from left click and the interact key. Pickup and disassemble are refused while `getAnimal()` is set. Wood scrap still asks for a hammer and a saw. Not yet tested in game.

5. **A hook placed as furniture is a plain `IsoObject`.** `MapObjects.OnNewWithSprite` only runs for newly generated squares and `OnLoadWithSprite` on chunk load, so `MOButcherHook` does not convert a placed hook until the chunk reloads. SensibleCraft wraps `placeMoveableInternal` and swaps in `IsoButcherHook` right away. `PlaceAnywhereFork` (earlier in load order) replaces `placeMoveableInternal` and `pickUpMoveableInternal` wholesale; SensibleCraft wraps whichever version is installed. [A]

## 8. Electric blower forge

1. **It is an unfinished forge tier.** The art (`crafted_02_52`, other facing `crafted_02_54`) is a steel coal-forge table with a blower fan; `_53` and `_55` are its glowing-coal overlays. Vanilla ships names (`Recipes.json`: "Forge (Electric Blower)", "Makeshift Electric Blower Forge", "Advanced Makeshift Electric Blower Forge") and window skins (`ES_Electric_Blower_Forge` and two makeshift ones in `x_entity_blacksmithfurnace.txt`), but no entity script, no build recipe and no Lua. Nothing crafts at it. [A]
2. **What it does in vanilla.** Both sprites are `IsoType = IsoBarbecue`, so it is a fuel burner: right-click shows the fire submenu (add fuel, light, put out) and while lit it is a heat source of radius 3. No `ContainerCapacity`, so no grill. The primitive forge's `crafted_01_45`/`46` are also `IsoBarbecue` tiles. [A]
3. **Collision.** Both sprites have `solidtrans`, which blocks walking, and no mod in this save unsets it on `crafted_02`. A dropped (not placed) moveable renders as its inventory icon, not the full sprite (`IsoWorldInventoryObject.updateSprite`). A full-size forge you can walk through is therefore unexplained. [A for the flags, open for the in-game report]
4. **Vanilla oddities.** `crafted_02_54` has no `IsMoveAble`. `Base.Mov_ElectricBlowerForge` weighs 0.5, and with `CustomItem` the item weight is used, so a picked-up forge weighs 0.5 instead of the tile's 40. [A]
