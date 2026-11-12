# Vanilla mechanics and known vanilla bugs (42.21)

Before you quote a number, check that it's here, or grep the definitions yourself.

## 1. Animals

Definitions: `media/lua/shared/Definitions/animal/*.lua` (`AnimalDefinitions.animals`, `.stages`, `.breeds`, `.genome`).

1. **Damage per hit** [C]:
   1. Thumpables: `1000 × baseDmg × strengthGene`.
   2. Doors: `100 × baseDmg × strength`.
   3. Cows and bulls have `baseDmg = 0.3`. Sheep and pigs fall back to the Java default of 0.5.
   4. Genes default to a random 0.2–0.6, so an average sheep does about 200 per hit and an average cow about 120.
2. **Player-built object health** [C]:
   1. Formula: base + bonus (`ConstructionBonusPoints`) + skill × `skillBaseHealth`, from `ISBuildIsoEntity.lua` (around line 657).
   2. `StoneWall` gets 400 per Masonry level, and `BrickFenceLvl2` gets 400 + 50 per level.
   3. Doors get 300 per skill level.
3. **What animals can damage** [C]:
   1. Only `IsoThumpable` and `IsoDoor`. Map walls and fences are plain `IsoObject`s and can't be damaged.
   2. Lambs, piglets and calves can't thump.
   3. Damage happens in Java (`AnimalAttackState` → `IsoThumpable.animalHit` → `destroy` in the same frame). There's no Lua event before the hit.
4. **When animals ram** [C]:
   1. When `attackedBy` is set, when hunger or thirst is high once `thumpDelay` has run out, or when stress is 80 or more.
   2. The lock releases only when the target breaks, a door opens, or the animal is 2 or more tiles away. Leashing doesn't release it.
5. **Stress** [A]:
   1. Spotting is distance-only: 10 tiles, same floor, no line of sight.
   2. Jogging stresses animals; sprinting doesn't, because sprinting clears `isRunning()`.
   3. Stress decays about 10–20 points per in-game day.
   4. Decay stops while hunger or thirst is above 0.8, while the animal is in rain without a roof over its tile (`stressUnderRain`, and the square's `haveRoof` is false), or while it's on an upper floor (`stressAboveGround` and `z > 0`).
   5. Petting removes 7–11.
   6. A heard sound flagged `stressAnimals` or `stresshumans` makes them run and adds `radius × 0.05` stress. Zombie thumps use radius 20, animal rams 10.
   7. Animal calls become world sounds only when sandbox `AnimalSoundAttractZombies` is on. Those sounds set `stressZombies` only, so the herd does not panic from its own calls. Pigs and sheep use radius 40.
   8. At stress 80 an animal that can thump rams. A ram also has `attackIfStressed`: within 10 tiles, acceptance under 30, it can charge the player. Boars set `dontAttackOtherMale`. Rams do not, so two adult rams fight during mating season (September through February).
   9. Zone corpses are animal bodies (`IsoDeadBody.isAnimal`). They are not a stress source.
6. **Enclosures** [C]:
   1. `minEnclosureSize` is 80 for a cow, 40 for adult females, and 20 for young. Males have no minimum (the field stays 0).
   2. Each hour, `AnimalData` compares the connected zone's `getFullZoneSize()` (sum of width × height) with that animal's own minimum. Headcount does not divide it. Below the minimum, `smallEnclosure` is set and that hour's size and weight gain are divided by 8.
   3. Hutches hold 20.

## 2. Food and cold

1. **Vanilla spoilage ignores the outdoor air temperature.** It depends on the outermost container. [A]
2. **Container temperature isn't °C.** `ItemContainer:getTemperature()` returns 0.2 for a powered fridge or freezer, the heat value for a stove, and otherwise about 1.0. [A]
3. **Freezing and thawing** [A]:
   1. Food freezes only in a powered freezer, over 4 hours.
   2. Thawing takes 1.5 hours, doubles in a powered fridge, and is 6× **faster** when the container temperature is above 1.0.
   3. `setFreezingTime` only flips the frozen flag at 100 or above, or 0 or below.
4. **Spoilage sandbox values** [A]:
   1. Fridge Factor 1–6 → 0.4, 0.3, 0.2, 0.1, 0.03, 0.
   2. Food Rot Speed 1–5 → 1.7, 1.4, 1.0, 0.7, 0.4.
5. **`OnContainerUpdate`** fires with the food item when it crosses the stale or rotten threshold (client and SP). [A]
6. **Air temperature** in °C comes from `getClimateManager():getTemperature()`. [C]
   1. **"Outside" has two meanings** [A]:
      1. `IsoGridSquare:isOutside()` is the `exterior` flag. `RecalcProperties` and `setRoomID` clear it when the square has a room id **or `haveRoof`** (any tile overhead: porch roofs, eaves, balconies). It decides rain, snow and light.
      2. `isInARoom()` is true for a map room or a player-built room (`getIsoWorldRegion():isPlayerRoom()`).
      3. `ClimateManager:getAirTemperatureForSquare` uses only `isInARoom()`: rooms get indoor temperature (22 °C with hydro power, otherwise a blend), and every other square gets outdoor air, wind chill and heat sources.
      4. Food under an overhang therefore sits in outdoor air even though `isOutside()` is false. Use `isInARoom()` for temperature logic.
   2. **Room formula** (`getAirTemperatureForSquare`, outdoor T ≤ 22) [A]:
      1. Grid power (`IsoWorld.isHydroPowerOn`, generators don't count) makes a room 22 °C.
      2. Otherwise ground floor = T + (22 − T) × (0.4 + 0.2 × `dayLightLagged`), and upper floors use 0.85 × the gap.
      3. An unpowered ground-floor room is therefore about 8.5 °C at −5 °C outside, below 4 °C only when T < about −8, and below 0 °C only when T < about −15.
      4. Heat sources (`IsoCell.getHeatSourceHighestTemperature`) raise any square.
      5. `dayLightLagged` has no getter, so Lua can't recompute it exactly; `getDayLightStrength()` is the closest stand-in.
      6. Lua checks grid power with the sandbox formula (`ISButtonPrompt.lua:520`).
7. **A shown container ages every frame.** `ISInventoryPane` calls `item:updateAge()` on every item it draws (`ISInventoryPane.lua:2266`, and 2573 for collapsed food stacks). A mod that corrects food on a timer will see the open container drift visibly between passes; re-apply to `getPlayerLoot(p).inventoryPane.inventory` more often (skip when `isCollapsed`). [A]
8. **Outdoors, vanilla thaws everything.** Outside a powered freezer, `updateFreezing` thaws frozen food in 1.5 hours and `updateAge` then ages it at full rate. Any outdoor-freezing mod has to re-apply its frozen state and cap the age itself. The frozen flag stays set while thawing is partway done, so "Frozen" in the tooltip doesn't mean freezing progress is at 100. [A]
9. **Lesson from Sensible Refrigeration (2026-11-08)** [B]:
   1. Thawing food in the 0–4 °C band, at the fridge rate, let frozen food outside partly thaw and spoil on every day the air rose above 0 °C, even though it never got warm.
   2. The user's rule: frozen food left outside stays frozen until the air reaches the "Refrigerate Below" temperature.
   3. `SensibleRefrigeration/tools/simulate_aging.py` runs the mod against a bytecode transcription of vanilla `Food.updateAge`/`updateFreezing`. Use it before changing the model.
10. **Spoil times.** `Food:getOffAgeMax()` is `DaysTotallyRotten`; items without it (dried herbs, oils, tinned food) report 1000000000 and never spoil. Days left before rotten = `getOffAgeMax() - getAge()`. Jarred preserves do spoil, just slowly: `CannedCarrots`/`CannedTomato` are 30 days fresh, 60 rotten, against `Tomato` 4/12 and `Onion` 14/28. An opened jar (`CannedTomatoOpen`) is 2/4. [C, from `scripts/generated/items`]
11. **Evolved recipes (stew, soup, salad, sandwich, pie...)** are `evolvedrecipe` blocks in `scripts/generated/evolvedrecipes.txt`; items join them through their `EvolvedRecipe = Name:use;...` line. The logic is Java `zombie.scripting.objects.EvolvedRecipe` [A]:
   1. `getItemsCanBeUse(chr, base, containers)` lists every usable item instance. Non-spices stop once `base.extraItems` reaches `MaxItems`. A spice is allowed once per full type, and only when the base is already the result item (or the recipe has `CanAddSpicesEmpty`). Frozen items are left out unless `AllowFrozenItem`; burnt ones always, rotten ones below Cooking 7.
   2. It does **not** check `needToBeCooked`; the vanilla menu greys those options out instead. Once the base has 3+ extra items it also appends known poisons that aren't in the recipe's item list (`getItemRecipe(item)` is nil for them).
   3. Spice-ness is per item (`Spice = true`), not per recipe. 109 vanilla foods are spices, including butter, lard, margarine, the oils, sugar, flour, cornmeal and many sauces.
   4. `addItem(base, used, chr)` returns the new base. When the base isn't the result yet (a pot of water), it creates the result item, removes the old base from the player's inventory and adds the new one, so anything still holding the old base is stale.
   5. Vanilla's menu (`ISInventoryPaneContextMenu.doEvorecipeMenu`) names each submenu `ContextMenu_EvolvedRecipe_<script name>`, wrapped in `ContextMenu_Create_From_Ingredient` when the base isn't the result, and stops at the first recipe with no usable items.

## 3. Generators, fuel, plumbing

1. **Plumbing is Java.** `IsoObject.FindExternalWaterSource` checks the square above, then the 3×3 around it. It takes the first source that has fluid and ignores the fluid type. [A]
2. **The generator context menu is built in Java** (`ISWorldObjectContextMenuLogic`). [A]
3. **Generator numbers** [A]:
   1. 10 L tank (`getMaxFuel` returns 10). Base draw 0.02.
   2. Per appliance draw: fridge-freezer 0.13, single fridge or freezer 0.08, light 0.002, stove or washer 0.09, TV 0.03.
   3. These draws are not litres per hour. `IsoGenerator.update` burns `totalPowerUsing × SandboxVars.GeneratorFuelConsumption` litres each game hour, and every vanilla preset sets that option to 0.1. A generator running three fridge-freezers burns (0.02 + 3 × 0.13) × 0.1 = 0.041 L/h, so a full tank lasts about 10 days.
   4. Billing is cached hourly per generator. Overlapping generators each bill the same appliance.
4. **There's no vanilla extension-cable item.** [I]
5. **Barrel moveables (`Mov_*Barrel`)** have no `EquipBothHands` and no fluid container. [C]

## 4. Player

1. **Main inventory capacity** is about 50. Moveable pickup requires `hasRoomFor` the tile's weight. [A]
2. **Hunger and thirst health drain** starts at moodle level 4: hunger above 0.7, thirst above 0.84. [A]
3. **Moodle level thresholds** (`MoodleStat`, bytecode). Compare with `moodles:getMoodleLevel(MoodleType.X)` rather than raw stats. [A]

   | Moodle | Level 1 | Level 2 | Level 3 | Level 4 |
   |---|---|---|---|---|
   | Hunger | 0.15 | 0.25 | 0.45 | 0.70 |
   | Thirst | 0.12 | 0.25 | 0.70 | 0.84 |
   | Sick | 0.25 | 0.50 | 0.75 | 0.90 |

4. **Death and reviving a single-player character** (42.21 decompile, `pzdecomp\42.21\revive\`). [A]
   1. Death is the `isDead` column of `localPlayers` in the save's `players.db`. The load screen (`LoadGameScreen.lua`, `getSaveInfo().players[i].isDead`) hides dead players, so a dead character is never loaded and no Lua runs for him. Reviving needs Java that makes row 1 read as alive (`ReviveMe`), or the column set to 0 by hand with the game closed.
   2. `PlayerDB.loadPlayer` forces body health and `health` to 0 when `isDead` is set. With it cleared, health comes from the saved per-part `BodyPart` health. Overall body health, `IsoGameCharacter.health` (default 1.0) and the `dead`/`kill` flags aren't saved; `isDead()` is `health <= 0 or bodyDamage:getHealth() <= 0`.
   3. `OnCreatePlayer` fires from `GameLoadingState.exit()`, after the load and before the first player update, so `getBodyDamage():RestoreToFullHealth()` there keeps a character saved at death from dying again (`ReviveMe`).
   4. Readers of the flag: `PlayerDBHelper.isPlayerAlive(saveDir, sqlId)` (used by `IsoWorld.init` to choose loading vs character creation, by the `checkSavePlayerExists()` Lua global behind Continue/Load in `MainScreen.continueLatestSaveAux`, and by `getSaveInfo().playerAlive`), `PlayerDBHelper.getPlayers` (the load screen's player list, flat triples of id/name/isDead), and `PlayerDB.loadPlayer`. Single player always plays row 1: "New player" (`setSavefilePlayer1(..., -1)`) moves the old row 1 to `maxID + 1`. Saving writes `isDead = player:isDead()`, so a healed player saves as alive. `IsoPlayer.removeSaveFile` on death only force-saves; nothing is deleted.
   5. The blob saved at death is smaller (41 KB alive vs 25 KB dead for the same character): `new IsoDeadBody(player)` takes the player's inventory container, worn items and attached items and gives the player an empty container. `IsoPlayer.OnDeath` first drops hand items to the floor (`dropHandItems`), then exits the vehicle. The corpse saves its `SurvivorDesc` (name), the container, and worn (`ItemBodyLocation`) and attached (string) locations as indexes into the container; hand items and `isPlayer()` aren't saved. It also copies the player's ModData.

## 5. Harvest yield

`getVegetablesNumber` in `farming_vegetableconf.lua`. The growth stage is not an input. [C]

1. **Pick at the first harvestable phase for the same vegetable count.** `hasVegetable` turns on when a growth tick starts at `nbOfGrow >= harvestLevel`. The info line is then "Ready to harvest". The next tick, at `nbOfGrow == fullGrown`, sets `hasSeed` ("In bloom") and adds seeds: `floor(vegetables × 0.5)`, at least 1. The tick after that (`nbOfGrow > fullGrown`) rots the plant. [C]
2. **Some crops skip the food-only phase.** `harvestLevel == fullGrown` for barley, flax, hemp, hops, rye, wheat, tomato, and strawberry. The first time Harvest appears, the plant is already in bloom, and the following growth tick rots it. Most other vegetables use 5 then 6. Herbs use 3 then 4. [C]
3. **The roll** is `ZombRand` from `minVeg` to `maxVeg`, each shifted by `floor((health − 50) / 10)` and capped at `minVegAutorized` / `maxVegAutorized`. Aphids and slugs each subtract `floor(level / 10)`. If `ZombRand(10) < Farming`, the skill level is added after that cap. Below 1 becomes 1. [C]
4. **`bonusYield`** raises both caps by 1 and keeps the better of two rolls. Seasons on: planting in `bestMonth` rolls it (`ZombRand(20) < 9 + skill`). A wrong month sets `cursed`, which blocks it. Fertilizer before `nbOfGrow` 4 can also set it (`ZombRand(20) < 9 + skill`), and adds 10 health if still below `harvestLevel`. With seasons on, fertilizer does nothing in winter. [C]
5. **Plants with `growBack`** (kale, strawberry, and most herbs) return to stage 2 after a harvest instead of being removed. Rotting still ends them. [C]
6. **`FarmingAmountNew` is computed and discarded.** The function writes `floor(count × sandbox)` into a global and returns the unscaled count. [C]
7. **No crop sows in November, December, or January.** The next `sowMonth` is February. Best that month: carrots (`bestMonth` 2 and 6) and onions (`bestMonth` 2, `riskMonth` 3). Also in season then: broccoli, cabbage, cauliflower, green peas, kale, lettuce, potatoes, radishes, spinach, strawberry, sugar beet, mint, oregano, parsley, sage, thyme. [C]

## 6. Known vanilla bugs

1. **`IsoTree.isPlayerInsideARoom` NPE.** It throws when the room is null, which aborts the translucent render pass, so containers in the room vanish. CutawayFix patches it. [C]
2. **`FBORenderCutaways` copy-paste error** (around line 403). It assigns the north-edge value to `hasCutawayWestWallsOnSouthEdge`. [C]
3. **`ISTakeFuel` double-counts pump fuel.** `updateUse` subtracts it, then `complete` adds the remainder back. [C]
4. **`SetCurrentGameSpeed(0)` while paused** stores 0 as the resume speed. [C]
5. **Invalid `SpriteConfig` warnings at load** for several vanilla entities, e.g. `Wooden_Windows` and `MetalSmallWireFence`. These are vanilla noise, not mod errors. [C]
6. **Mildew spray cursor cures flies.** `ISFarmingMenu.onMildewCure` queues the opened plant with cure `"Mildew"`. `onMildewCureSquareSelected` (the cursor it then arms, and the only path for a joypad) passes `"Flies"` with `GardeningSprayMilk`. `ISCurePlantAction:complete` switches on that string, so the click calls `cureFlies` and `UseAndSync` still spends the milk. Flies, slugs and aphids pass their own cure on both paths. MildewCure replaces the cursor callback. [C]
7. **42.22.2: debug-mode hotkeys crash single player.** With `-debug`, `NetworkPlayerAI.checkDebugInput` runs every tick. While Left Ctrl is held, these keys act even in single player:
    1. Ctrl+A sends a "spawn bull" command; Ctrl+R sends "repair vehicle" when near a vehicle.
    2. Ctrl+V and Ctrl+Z send the "add vehicle" and "spawn horde" commands.
    3. Ctrl+D sets the player's health to 0, which kills them.
    4. Ctrl+S resets the network AI state.

    The command sends throw an NPE in single player because `GameClient.connection` is null. Left Ctrl is the default Aim key, and A, S and D are the default movement keys, so aiming while moving triggers these. The exception escapes `IngameState.updateInternal`, which copies the whole world to `<save>_crash` before saving. On a 150k-file save that copy freezes for minutes. Seen 2026-11-09. The keys are read from the raw keyboard state each frame (`KeyboardState.poll` → `Keyboard.isKeyDown`), so a stuck key or software that sends Ctrl triggers them as well. `DebugHotkeysFix` skips the method when `GameClient.client` is false. [C]

## 7. Farming diseases

1. **Milk spray** (`Base.GardeningSprayMilk`) is a drainable with `UseDelta = 0.1` (10 charges) and `ReplaceOnDeplete = Base.GardeningSprayEmpty`. The mildew menu entry always passes `uses = 1`. Aphids is the entry with a count submenu. [C]
2. **`cureMildew` has no cooldown.** Each use subtracts `10 + Farming level` from `mildewLvl`, clamped at 0, then saves. The action passes `nil` as the spray source and spends charges itself with `UseAndSync`. [C]
3. **Existing mildew grows on the water tick.** `upDisease` adds 0.5 when `calcWater` is at least 0, otherwise 1, capped at 100. That tick is every 5 in-game hours at normal Plant Resilience (12 / 8 / 3 / 2 for very high / high / low / very low), once per hour change inside `EveryTenMinutes`. [C]
4. **A new infection** starts only while `mildewLvl == 0`. `mildew()` sets it to 1 after `defaultDiseaseCheck()`. [C]
5. **Growth only consults mildew.** `farming_vegetableconf.grow` passes `mildewLvl` alone to `calcDisease`. Under 10 that returns 0 extra hours; under 30 it returns the level, added to the grow time; under 60 it returns -1; 60 or more returns -2. Once the plant has left stage 0, -1 delays the next growth 30 hours and drops a stage, and -2 calls `killThis()`. A stage-0 seedling still calls `growNext` with that number and does not die there. The disease words are Light under 10, Moderate under 30, otherwise Heavy. The unhealthy sprite also counts aphids and slugs (30 dying, 10 unhealthy); flies are not in that max. [C]

## 8. Drying racks

Plant, herb, and leather racks all use `DryingCraftLogic`. Recipe `time` is game seconds at a drying factor of 1. [A]

1. **Base times** at 20°C: herbs 86400 s (24 h), large plants (grain, flax, tobacco, hemp) 172800 s (48 h), leather 604800 s (7 days). [A]
2. **Factor** is the tile air temperature in °C, clamped to 0–40, divided by 20. Below 20°C that result is squared. 0°C or below is factor 0 and the tooltip says Frozen. 20°C is 1×. 40°C is 2× (Hot). [A]
3. **Any wetness above 0 pauses progress.** Rain or snow adds wetness only when `GameEntity.isOutside()` is true (`IsoGridSquare` has the `exterior` flag). Snow adds half as fast (`0.001 × intensity × 0.5` per game second, capped at 1). Wetness then falls at `0.0002 × factor` per game second, so a frozen rack stays wet. [A]
4. **Temperature** is `ClimateManager.getAirTemperatureForSquare` (no windchill). A room — `getRoom()` or a player room region — is pulled toward 22°C by `0.4 + 0.2 × dayLightLagged` of the gap. Ground floors use the full gap; upper floors multiply the cold gap by 0.85 first. With hydropower on, a room is set to 22°C (factor 1.1) before that. A heat source replaces the air temperature when it is hotter. [A]
5. **A fire heats tiles, not the whole room.** `IsoCell.getHeatSourceHighestTemperature` keeps the hottest source on the same floor, inside its radius, with clear line of sight (an open door counts). Temperature is lerped from the tile air at the edge to the source temperature at the fire. The source gets `air − 30`, clamped to −7..7 indoors and −15..5 outdoors, added to its base temperature. [A]
6. **Fireplace, wood stove, and metal drum** are `IsoFireplace`. The crafted barrel oven is one too (`BuildRecipeCode.barrelOven` replaces the thumpable with `IsoFireplace`). Lit temperature is 35. Radius is `lerp(1, 8, min(fuelMinutes, 60) / 60)`, so one hour of fuel is the widest circle and more fuel only lasts longer. Fuel burns 1 minute per game minute, including up to 10 minutes of smoulder after it is put out. A log is 6 hours (`min(6, weight × 2/3)`), a plank 2 hours. Adding fuel is refused past sandbox **Maximum Fire Fuel Hours** (`getCampingFuelMax()`, in minutes). Campfire, charcoal barbecue, and fireplace add-fuel all use that check. Apocalypse, Rising, and Extinction set it to 8; Outbreak sets it to 12. The option accepts 1–168. [C for the Lua cap and presets; A for the burn rate and the 1–168 range]
   1. **Sprites.** `IsoFireplace.updateFireSprite` only adds the flame animation and log sprite for named vanilla sprites or tiles with `collideN`/`collideW`. For any other sprite it draws nothing and only calls `setOverlaySprite(null)` when a fire that was lit while loaded goes out, so a mod can draw its own lit overlay. [C]
   2. **Away time burns in one go.** `update()` burns all the minutes since `lastUpdateTime` (saved) at once, so a chunk that was unloaded for hours comes back with the fire out unless its fuel already covered that time. The heat source and light are not saved; they're rebuilt on the first update. [C]
7. **A campfire** uses the same 35° heat via `IsoFire` and burns 1 minute of fuel per game minute. Indoors, every 10 minutes there is a 1-in-5 chance it ignites an adjacent wood or carpet floor. Its light radius (and the zombie-attracting sound) is up to 18 indoors and 10 outside once it holds 6 hours of fuel. [A]
8. **A propane barbecue** is heat 25, radius 3, and burns 1 minute of fuel per game minute. Inserting a tank sets fuel minutes to `round(currentUses × 0.24)` and does not check the sandbox cap. A full `Base.PropaneTank` (`UseDelta` 0.0002, 5000 uses) is 1200 minutes, 20 hours. A partial tank lasts that fraction of 20 hours. An electric stove has no heat source. [A]
9. **Farmed garlic (`Base.Garlic`) has no drying recipe.** The herb rack's `DryWildGarlic` accepts only `Base.WildGarlic2` and makes `WildGarlicDried` in 86400 s. Powdered garlic is a separate loot item. [C]

## 9. Sinew

`MakeSinewThread` turns 1 `Base.AnimalSinew` into `Base.Thread_Sinew` with `HasOneUse`, which sets `currentUses` to 1. The item's `UseDelta` is 0.1, so a crafted piece is 1 use and a looted spool is 10. It has tags `thread` and `heavythread`. `CraftTwine` takes 25 uses of it for 1 twine. Bone armor recipes take `Base.Twine` specifically. [C]
