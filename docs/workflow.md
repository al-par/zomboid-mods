# Working protocol

Each rule here exists because breaking it caused a real failure in a past chat. The table at the end maps the failures to the rules.

## 1. Before designing

1. **Identify the exact game object.** It could be any of these, and each is a different code path:
   1. A map tile: a plain `IsoObject` from the map.
   2. A player-built object: an `IsoThumpable` created from a B42 entity script.
   3. A moveable item.
   4. A script item.

   Example: "wooden pole" meant the Carpentry-built `WoodenPole` entity, not utility-pole map tiles. That misunderstanding cost a whole chat.
2. **Grep vanilla before claiming a mechanic exists or quoting a number.** Search `media/lua`, `media/scripts/generated`, and `shared/Definitions`. Never quote vanilla numbers from memory: animal damage quoted from memory was 2.5× too high.
3. **Find out whether the logic is Lua or Java.** If vanilla Lua doesn't contain it, it's Java (see `environment.md`). Lua can't change rendering and cutaways, collision, Bullet physics, animal attack logic, or most of the world context menu.
4. **When something is broken, read the log before theorising.** Use the newest `Zomboid\ErrorMonitor\<session>\errors.txt` (and `perf.txt` for slowness) when it exists, otherwise `console.txt`. Group exceptions by message and count them. A vanilla NPE that fired every frame went unnoticed for hours while an agent studied screenshots.
5. **Implement the user's spec literally.** No extra steps, immunities or categories. If the user says something breaks "too fast", change the number (hits or health), not the category.
6. **Clarify an ambiguous noun once, in plain text.** Then look things up instead of asking again.

## 2. While coding

1. **Copy a vanilla call site for every API.** That a signature exists doesn't prove you're using it correctly (see `props:has("WallN")` in `world-objects.md`).
2. **Search for both definition styles,** `function X.y` and `X.y = function`.
3. **Never edit Steam Workshop folders.** Steam overwrites them on update. Make a local patch mod with its **own** mod id: on a duplicate id the Workshop copy wins (`mod-structure.md`). Edit Workshop files only on explicit request, with a warning.
4. **Never rewrite files with PowerShell `Get-Content | Set-Content`.** Windows PowerShell 5.1 corrupts BOM-less UTF-8. Use the editor tools. If a shell write is unavoidable, use `[IO.File]::WriteAllText(path, text, [Text.UTF8Encoding]::new($false))`.
5. **Pick a `tiledef` number only after scanning every installed `mod.info`,** local and Workshop. Never change the number after release.
6. **No `pcall` to silence errors.** It hides bugs, so a clean log no longer proves anything. It is also slow in hot paths.
7. **Commit side effects only after the destination accepts.** Example: remove pump fuel only after `addFluid` succeeds.
8. **Think about cost before you register a frequent event** (`performance-debugging.md`).

## 3. Verifying

| Check | Proves | Does not prove |
|---|---|---|
| `javap` signature exists | the method is callable | correct usage |
| Lua parse (`luaparser`) | the syntax is valid | engine behaviour |
| Off-engine mock or simulation | your algorithm | the engine (it copies your assumptions; real Lua has `next`, Kahlua doesn't) |
| `loading <ModId>` in the log | the mod is enabled | that its files loaded |
| No mod errors in a **full** log | the files loaded | that the feature works |
| The user exercised the feature | it works in SP | multiplayer, or performance |

Before saying "done":

1. **Load order.** Every top-level `require`, `derive` or global resolves in the same or an earlier folder (`shared` → `client` → `server`).
2. **IDs.** Every `Base.X` exists in `scripts/generated/items` or in the mod's own scripts.
3. **Translations.** Every key exists in a loaded `.json` file name, and every literal `%` is written `%%`.
4. **Events.** Every `Events.X.Add(fn)` gets a real function. A typo that passes `nil` is silently ignored.
5. **Diagnostics.** For anything uncertain, add a debug-only print or context option that dumps the object's class, sprite, flags and state. One dump replaces several round trips with the user.

## 4. Enabling and testing

1. **Continue loads `Saves\<Mode>\<save>\mods.txt`.** The main-menu Mods screen and `mods\default.txt` don't change existing saves. Add new mods to the save's `mods.txt`. [C]
2. **Edit `mods.txt` only with the game closed, and back it up first.** `Get-Process ProjectZomboid64 -ErrorAction SilentlyContinue` must return nothing, so test the result explicitly. `Get-Process | Format-Table` has returned empty output here before.
3. **Don't launch the game yourself.** Ask the user. Steam may open a chooser, and the user may already be playing.
4. **Read the full log after the user tests.**
   1. Line 1's timestamp must be newer than your edits.
   2. `loading <ModId>` must appear.
   3. Your files must raise no errors.

   A log that starts mid-session or predates your edit is not "clean".
5. **Know what each change needs to take effect.**
   1. Tiles, `tiledef` or `.pack` changes need a full game restart.
   2. Lua or script changes need a quit to the main menu and a reload. Quitting to the menu resets Lua.
   3. `reloadLuaFile` doesn't install newly added event handlers (`performance-debugging.md`).
6. **When removing or merging a mod:**
   1. Swap the ids in the save's `mods.txt` and in `default.txt`.
   2. Migrate its modData keys.
   3. Warn the user about the harmless `ERROR unknown SandboxOption "<OldMod>.*"` lines that follow. [C]
7. **Ask before touching save data beyond `mods.txt`.** That includes `map_sand.bin`, `players.db`, and any binary patch.

## 5. Reporting

1. **Separate "checked statically" from "tested in game."** Never write "confirmed working" for code that hasn't run.
2. **When the user says it doesn't work, your model is wrong.** Gather evidence; don't argue from code reading.
3. **The thing the user asked for stays first,** even when the scope widens.
4. **Reconcile numbers before stating them,** and flag revisions explicitly.
5. **If another agent fixed your bug, diff the files to learn what was wrong,** then update these docs.
6. **Don't use the multiple-choice question popup with this user.** Ask in plain text.

## 6. Failure log

| Chat | What went wrong | Rules |
|---|---|---|
| WalkThroughPoles | Fixed the wrong kind of "pole" for a whole session; argued with the user's bug report; fixed 12 other mods first; picked the wrong mod and restructured the save without asking | 1.1, 5.2, 5.3, 4.7 |
| SensibleLivestock | The `has("WallN")` string-vs-flag bug survived an "all bugs fixed" pass; vanilla numbers quoted from memory; over-indexed after the user said not to; edited `mods.txt` while the user was in game; an unrequested `map_sand.bin` patch | 2.1, 1.2, 1.5, 4.2, 4.7 |
| SensiblePowerManagement | `next()` crashed every chunk load yet passed the mock tests; a client-folder cursor derived from a server class; declared clean from a partial log | 3, 4.4 |
| CutawayFix | Ignored a per-frame NPE in the log; claimed a launch config "will work" without testing the exe path; launched the game itself | 1.4, 4.3 |
| CommonSense | "Fix everything" scoped to the log's crashes only; B41 script syntax broke the vehicle menus; edited Workshop files in place; PowerShell encoding corruption; guessed the `addGetUpOption` parameters | 2.1, 2.3, 2.4 |
| SensibleSalt | Invented a salt-lick mechanic; unrealistic yields; the recipe used `Base.Mov_SaltLick`, which map pickups never produce; built the mod but never enabled it in the save | 1.2, 4.1 |
| SensibleRefrigeration | Misread a decompiled thaw rule (÷6 read as slower); left stale sandbox options; wrote redundant `.txt` translations; a 61×61-square scan every 10 game minutes; five `pcall`s hid errors; stored pooled square objects across frames | 4.6, 2.8, 2.6 |
| SensibleSalt (2nd) | Set a new `CustomItem` value from Lua, which the alias map turns into `Base.HamRadio1` (`world-objects.md` 1.5) | 2.1 |
| A firearms mod (archived) | `scripts/generated/fixing.txt` replaced vanilla's file; tooltips with commas and `%` broke item scripts; the local copy had the same id as a subscribed Workshop item, so it never loaded | 2.1, 2.3 |
| A plumbing mod (archived) | Passed the wrong arguments to `ISWorldObjectContextMenu.onPlumbItem` and called a Java field name as a method; it never worked | 2.1 |

"Fix everything" means auditing every Lua file, every `media/scripts/*.txt`, every item id, every sandbox option, and every translation, not only the crashes in the log.
