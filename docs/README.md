# Project Zomboid B42 modding docs

Documentation for AI agents working in `C:\Users\alpar\Zomboid\mods`, for game version **42.21.0**. Which mods are in scope: `save-manifest.md`.

## Status: read this first

1. **The local mods are not known-good.** Many bugs are still unfound and unfixed, and performance in the modded save is currently poor. Don't copy patterns from a local mod as if they were correct; check them against vanilla first.
2. **Nothing in these docs replaces testing in game.** Most Java-derived facts were read from bytecode, not exercised.
3. **Read ErrorMonitor's output before `console.txt`.** Each session writes `Zomboid\ErrorMonitor\<session>\errors.txt`, `session.log`, `perf.txt` and `performance.jfr` (`performance-debugging.md` §2.7). Read the SUMMARY and ERRORS sections of `errors.txt`; its WARNINGS section is thousands of lines of mostly vanilla noise. [C, 2026-11-07]
4. **The game is now 42.22.2 (installed 2026-11-09); most facts here were checked on 42.21.** Checked against 42.22.2 [A, 2026-11-09]:
    1. Only vanilla's `.tiles` files moved to `media/tile_definitions/`. Mod `tiledef=` files are still read from `media/<name>.tiles` (`ZomboidFileSystem.loadModTileDefs`), and `pack=` files from `media/texturepacks/`.
    2. Save format went from 249 to 251, so the game asks to convert older saves.
    3. `IsoThumpable.getNorth()` became `isNorth()`. `getNorth()` still works as a default method on the `GridSquareEdgeElement` interface, and vanilla Lua still calls it.
    4. `IsoGenerator` fires `OnElectricityChanged` when it is switched on or off. Its fuel logic is unchanged.
    5. `Core.tileScale` is gone; offsets are hard-coded for 2x tiles. `IsoFireplace` changed only its fire and fuel draw offsets. `IsoHeatSource` is unchanged, and so are `Food.isThawing`/`isFreezing`.
    6. `ItemContainer.removeItemOnServer` was removed; containers now stop nesting at 16 levels.
    7. All hooks of the ErrorMonitor and CutawayFix agents still apply [C].

## Confidence tags

1. **[C]** Confirmed by vanilla files, the game log, or in-game behaviour.
2. **[A]** Read from decompiled Java or bytecode, not exercised in game.
3. **[O]** Online source only, not checked locally.
4. **[I]** Inferred. Treat it as a hypothesis.

## Files

| File | Read it when |
|---|---|
| `save-manifest.md` | Starting any chat: the mods in the save and what each does |
| `workflow.md` | Starting any task. It is the working protocol and explains why each rule exists |
| `sensible-architecture.md` | You're designing, renaming, publishing or adding Java to a Sensible mod (branding, Lua-by-default rules, compatibility, ZombieBuddy hooks) |
| `environment.md` | You need a path, the decompiler, launch options, or how our mods use ZombieBuddy |
| `mod-structure.md` | Creating a mod, or touching `mod.info`, version folders, translations, sandbox options, ModOptions, or a Workshop upload |
| `lua.md` | Writing Lua: Kahlua quirks, load order, events, Java interop, B41→B42 renames, context menus |
| `multiplayer.md` | Timed actions, client/server commands, global ModData, side checks |
| `scripts.md` | Items, `craftRecipe`, fixing, fluids, entities, loot, registries |
| `world-objects.md` | Tiles, sprite properties, collision, moveables, depth maps, custom tiles |
| `performance-debugging.md` | Anything slow, any error hunt, profiling, logs |
| `game-mechanics.md` | Vanilla numbers (animals, food, generators) and known vanilla bugs |
| `sources.md` | Before trusting a web page: rated sources and known-wrong online claims |

Update the relevant file when you confirm or disprove something. Keep the confidence tag honest.
