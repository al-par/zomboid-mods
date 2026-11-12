# Environment, tools, and the Java side

## 1. Paths on this machine (42.21)

| What | Path |
|---|---|
| Game install (`<install>`) | `C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid` |
| Vanilla Lua | `<install>\media\lua\{shared,client,server}` |
| Kahlua standard library in Lua | `<install>\stdlib.lua` (`pairs`, `ipairs`, `assert`, `table.sort`, ...) |
| Vanilla scripts | `<install>\media\scripts\generated\{items,recipes,entities}\...`, `fixing.txt`, `timedactions.txt`, `fluids*.txt` |
| Vanilla translations | `<install>\media\lua\shared\Translate\<LANG>\*.json` |
| Tile definitions | `<install>\media\newtiledefinitions.tiles` (binary), `.tiles.txt` (text, incomplete), `tiledefinitions_*.tiles` (moves to `media\tile_definitions` in 42.22) |
| Texture packs | `<install>\media\texturepacks\Tiles2x.pack`, `UI2.pack` |
| Game Java | `<install>\projectzomboid.jar` (Java 25 bytecode, class version 69; there are no loose classes) |
| Bundled JRE | `<install>\jre64` (Azul Zulu 25.0.1; no `javap`, no `jdk.attach`; has `java.instrument`) |
| Launch config | `<install>\ProjectZomboid64.json` (used by the exe), `ProjectZomboid64*.bat` (use `jre64\bin\java.exe`, don't read the JSON) |
| Official mod template | `<install>\Workshop\ModTemplate` (B41 layout; use it only as a `workshop.txt` example) |
| Local mods | `C:\Users\alpar\Zomboid\mods\<Folder>` |
| Global mod list | `C:\Users\alpar\Zomboid\mods\default.txt` (main menu and new games only) |
| Workshop mods | `C:\Program Files (x86)\Steam\steamapps\workshop\content\108600\<workshopId>\mods\<Folder>` (read-only, see `workflow.md`) |
| Workshop upload staging | `C:\Users\alpar\Zomboid\Workshop\<Item>\` |
| Saves | `C:\Users\alpar\Zomboid\Saves\<Mode>\<save>\` (`mods.txt`, `map_sand.bin`, `players.db`); the save in use is in `save-manifest.md` |
| Retired mods | `C:\Users\alpar\Zomboid\mods-archive\<Folder>` (out of scope, not loaded) |
| Logs | `C:\Users\alpar\Zomboid\console.txt` (current session, overwritten on every launch), `Logs\<date>_DebugLog.txt`, `Logs\logs_<date>\` |
| Lua file I/O root | `C:\Users\alpar\Zomboid\Lua\` (`getFileReader`/`getFileWriter`, `ModOptions.ini`) |
| Debug options | `C:\Users\alpar\Zomboid\debug-options.ini` |
| Version | `C:\Users\alpar\Zomboid\version.txt` |

Git: `mods\` is one public monorepo, [al-par/zomboid-mods](https://github.com/al-par/zomboid-mods) (branch `main`, `gh` is signed in as `al-par`). Each of our mods is a folder in it; their earlier per-mod histories were merged in with `git subtree add` on 2026-11-11, and the old per-mod `.git` folders are in `C:\Users\alpar\Zomboid\git-backups\`. Forks and `SensibleWalls` (until its crack repair is rewritten) are listed in the root `.gitignore` and keep their own repos. Each fork has its own private GitHub repo, named after the folder in kebab case (`CommonSenseFork` is `al-par/common-sense-fork`; remote `origin`; the stale Origin copy is remote `cursor`), holding `main`, `upstream` and the `upstream-2026-11-07` tag. `SensibleWalls` stays local only. Commit before and after every change, using the noreply email `47093296+JonTronsLongJon@users.noreply.github.com` so commits count for `al-par`. Release a mod by pushing a tag `<ModFolder>-v<version>` (for example `ReviveMe-v1.0`): `.github/workflows/release.yml` zips that folder and attaches it to a GitHub release.

Forked Workshop mods. The save loads the fork ids, not the Workshop ids. Edit only the fork. Each fork repo has an `upstream` branch and an `upstream-2026-11-07` tag holding the untouched download; `git diff upstream main` shows every local change. To take a Workshop update, copy the new download onto `upstream`, commit, then merge into `main`.

| Fork folder | Fork mod id | Workshop ID | Upstream id and notes |
|---|---|---|---|
| CommonSenseFork | `BB_CommonSense_Fork` | `2875848298` | `BB_CommonSense`, folder `42.0` |
| SensibleWalls | `SensibleWalls` | `3684808606` | `RepairWallCracks_B42`; extended with bolt cutters for wire fences |
| PlaceAnywhereFork | `PlaceAnywhereMod_Fork` | `3613917826` | `PlaceAnywhereMod` |
| ProximityInventoryFork | `ProximityInventory_Fork` | `2847184718` | `ProximityInventory`, folder `common` |
| DrawOnMapFork | `DRAW_ON_MAP_Fork` | `2804531012` | `DRAW_ON_MAP`, folder `42.13` |
| CarryVisibleGeneratorsFork | `DEON_CVG_Fork` | `3390487814` | `DEON_CVG` |
## 2. Inspecting the game's Java

1. **Signatures.** Run `javap -p -classpath "<install>\projectzomboid.jar" zombie.iso.IsoGridSquare` using the JDK 17 at `C:\Program Files\Eclipse Adoptium\jdk-17.0.13.11-hotspot\bin`, which is on PATH. Add `-c -constants` to see bytecode and string constants. JDK 17's `javap` reads the jar fine.
2. **Decompiling.** Extract the classes from the jar, then run Vineflower or CFR (both in `C:\Users\alpar\Zomboid\pzdecomp\tools\`) with `<install>\jre64\bin\java.exe`. CFR fails on some methods, for example `ChooseGameInfo.readModInfoAux`; fall back to `javap -c` for those.
3. **Keep the decompile somewhere persistent,** e.g. `C:\Users\alpar\Zomboid\pzdecomp\<gameVersion>\`. Earlier sessions used `%TEMP%\pzdecomp`, which lost files between turns and filled up with confusing `src`…`src24` folders. Keep one full decompile per game version.
4. **No Lua interpreter is installed.** Use Python `luaparser` (`pip install luaparser`) for syntax only. Standard Lua isn't Kahlua (`lua.md`).
5. **What Lua can see.** Check `zombie.Lua.LuaManager$Exposer`. Many rendering classes aren't exposed, including `FBORenderCutaways`, `FBORenderCell` and `ChunkLevelData`. [A]

## 3. Launch options

1. **Steam launch options** go after `--`, e.g. `-Xmx4g -- -debug`. [O]
2. **Flags confirmed in `MainScreenState`:** `-debug`, `-debuglog=`, `-debugcfg=`, `-debugLogFile=`, `-console_dot_txt_size_kb=`, `-imgui`, `-cachedir=`, `-modfolders`, `-nosound`, `-nosteam`, `-novoip`, `-useTimeStampedLogFileNames=`, `-debugtranslation`. [A]
3. **The user's Steam launch passes `-debug` on purpose,** as a safety net against game bugs. It adds per-instruction Lua overhead (`performance-debugging.md`), but don't ask them to drop it. [C, 2026-11-01]

## 4. Former standalone Java agents (CutawayFix, ErrorMonitor)

Until 2026-11-11 these two were standalone `-javaagent`s with ASM transformers, wired into `ProjectZomboid64.json` by `install.ps1`. Both are now ZombieBuddy plugins (section 5). Their agent lines were removed with each mod's `uninstall.ps1` (backup `save-backups\ProjectZomboid64.json.before-zb-migration_2026-11-11`); the old agent code is in git history. The notes below are kept in case a standalone agent is ever needed again.

0. **JDK.** Temurin JDK 25 is at `C:\Users\alpar\scoop\apps\temurin25-jdk\current` (`JAVA_HOME`, installed 2026-11-07 via scoop bucket `java`). Every `build.ps1` picks it up through `JAVA_HOME` or `-JdkBin`. The older JDK 17 is still on PATH. [C]

1. **The exe and the `.bat` files start the JVM differently.**
   1. `ProjectZomboid64.exe` embeds the JVM, so `-javaagent` in `ProjectZomboid64.json` fails on its own. The JDK 17 on PATH supplies incompatible `jli.dll`/`java.dll`. Fix: list a native `-agentpath:<preload>.dll` first; its `Agent_OnLoad` loads `java.dll` and `jli.dll` from `jre64\bin` by full path. [C]
   2. The `.bat` launchers run `jre64\bin\java.exe` and don't read the JSON, so vmArgs must be added to both.
   3. Test the launch path the user actually uses: Steam → exe.
2. **Build with JDK 25 using `--release 17`.** JDK 17 `javac` can't read the jar. ASM 9.9 reads Java 25 classes, and the patcher must bundle it. [C]
3. **Output from `premain` never reaches `console.txt`,** because it runs before the game redirects stdout. Write a status file to `Zomboid\Lua\` instead. [C]
4. **Absolute agent paths in `ProjectZomboid64.json` stop the game from launching** if the mod folder moves or is deleted. Say so to the user. [I]
5. **Hooks that call game methods directly** throw `NoSuchMethodError` inside the game loop after an update renames something. Make the transformer skip a patch when its bytecode pattern doesn't match. [A]
6. **Steam updates can overwrite `ProjectZomboid64.json`.** The exe also reads `ProjectZomboid64.site.json`, which may survive updates (untested). [I]
7. **Java hooks add cost** that the Lua tools can't see. For example, CutawayFix forces a cutaway recheck about every 6 frames. Profile with JFR (`performance-debugging.md`).
8. **Testing game logging without launching the game** (worked 2026-11-04; the harness was `ErrorMonitor/java/test/Harness.java`, now in git history). [C]
   1. Call `RandStandard.INSTANCE.init()` and `RandLua.INSTANCE.init()` before anything logs; otherwise `GameClient`'s static init fails with `NoClassDefFoundError`. Then call `DebugLog.getInstance().init()`.
   2. For Lua, create `new KahluaThread(J2SEPlatform.getInstance(), env)`, set `thread.debugOwnerThread = Thread.currentThread()` (otherwise `pcall` throws an NPE), assign it to `LuaManager.thread`, and load code with `LuaCompiler.loadstring(src, name, env)`.
   3. `-Ddeployment.user.cachedir=<temp>` moves the game's `Zomboid` folder, so the test doesn't write into the real one.

## 5. ZombieBuddy: the Java layer for our mods

Decision (2026-11-07): new Java code in our mods is a ZombieBuddy plugin, not another standalone agent. ZombieBuddy (Workshop `3619862853`, [GitHub](https://github.com/zed-0xff/ZombieBuddy), MIT) is a Java agent with about 1 million Workshop subscribers, mostly because Project Viewpoint requires it. It is maintained (commits weekly as of November 2026) and supports B41 and B42.12–42.21. Facts below are from its docs (`doc/ModdingGuide.md`, `LuaAPI.md`, `Installation.md`), not yet tested here. [O]

1. **Layout.** The jar ships inside the normal Workshop mod: `42/media/java/<Mod>.jar`. `mod.info` gets `javaJarFile=media/java/<Mod>.jar` and `javaPkgName=<package>`. A path containing `media/java/client/` or `media/java/server/` restricts it to that side.
2. **Soft dependency.** Don't add `require=\ZombieBuddy`, so the mod still loads (Lua-only) without it. ZombieBuddy reads `javaJarFile` itself; only vanilla's launcher reads `require=`. The Lugli mods do the same.
3. **Detection from Lua.** `ZombieBuddy` is a global only when the agent is running. `ZombieBuddy.getJavaModStatus(modId)` returns `{loaded, reason, sha256, decision, persisted}` or nil; `loaded = false` with a `reason` covers a denied or blocked jar.
4. **Patches.** `@Patch(className, methodName)` classes in the package, with `@Patch.OnEnter` (`skipOn = true` + `boolean` return skips the original) and `@Patch.OnExit`. Bindings: `@Patch.This`, `@Patch.Argument(n)`, `@Patch.Return(readOnly = false)`, `@Patch.Field`, `@Patch.Local`. Optional `Main.main` runs at load. Keep each patch a thin hook into our own code, so the loader can be swapped if ZombieBuddy is abandoned.
5. **Lua bindings.** `@Exposer.LuaClass` on a class, or `@LuaMethod(name, global = true)` on static methods.
6. **Players.** One-time setup: subscribe, then the Windows installer or copy `ZombieBuddy.jar` and `zbNative.dll` from the Workshop `libs\` into `<install>` and add `-agentlib:zbNative` (Steam launch options: `-agentlib:zbNative --`). Each new or changed jar asks for approval once; signed authors can be trusted wholesale (`doc/ModSigning.md`). Its own Lua shows install instructions at the main menu when the agent is missing.
7. **On this machine the installer's JSON change is just `-agentlib:zbNative` at the top of `vmArgs`,** and `SET _JAVA_OPTIONS=-agentlib:zbNative` in the `.bat` (from its `installer/testdata/launchers/42.17/patched`). Since 2026-11-11 it is the only agent in `vmArgs`. Installed by hand on 2026-11-07: v2.3.4 `ZombieBuddy.jar` and `zbNative.dll` copied from the Workshop `libs\` into `<install>`, `-agentlib:zbNative` added to `vmArgs`, and `SET _JAVA_OPTIONS=-agentlib:zbNative` in `ProjectZomboid64.bat`. Backups: `Zomboid\save-backups\ProjectZomboid64.{json,bat}.before-zombiebuddy_2026-11-07`. Not yet confirmed in game.
8. **Debugging.** Start with `-agentlib:zbNative=experimental` for `ZombieBuddy.Watches.Add(class, method)` (logs every call with arguments) and `zbinspect`/`zbmethods`/`zbget`; `verbosity=1` logs patch transformations.
9. **Confirmed from the 2.3.4 bytecode (2026-11-08)** [A]:
   1. Mod jars are added with `Instrumentation.appendToSystemClassLoaderSearch`, so inlined advice inside game classes can call our classes. Methods the advice calls must be `public`, because the advice runs inside the patched class's package.
   2. `PatchEngine.collectPatches` scans the whole `javaPkgName` package with ClassGraph (nested classes included), applies every `@Patch` class, and registers every class with a `@LuaMethod(global = true)` static method.
   3. `mod.info` keys are matched lower-cased: `javajarfile=`, `javapkgname=`, `javapreload=`, `zbversionmin=`, `zbversionmax=`.
   4. New jars go through an approval prompt (`JarDecisionTable`, `ModApprovalsStore`) the first time they load.
   5. Jars load on every `ZomboidFileSystem.loadMods`, from that call's mod list: at the main menu that is `mods\default.txt`, at save load the save's `mods.txt`. Classes already loaded are retransformed. So a patch that must affect main-menu code (the load screen's `getSaveInfo`) needs its mod in `default.txt` too. [C: console.txt 2026-11-11, menu `loadMods(8 mods)` listed no jars, save `loadMods(21 mods)` loaded both and retransformed `Food`]
10. **Building plugin jars.** The `javac` on PATH is JDK 17, which can't read the game's Java 25 class files. Use `build.ps1 -JdkBin C:\Users\alpar\scoop\apps\temurin25-jdk\current\bin`. Wrap the source list in `@(...)`: with one source file, `@sources` splats the path as single characters. ZombieBuddy 2.3.4 patches fine on 42.22.2; it applied SensibleRefrigerationZB's two `Food` patches on 2026-11-09. [C]
11. **Porting bytecode patches to ZombieBuddy** (CutawayFix and ErrorMonitor, 2026-11-11, from the decompiled 2.3.4 `PatchEngine`). [A, not yet confirmed in game]
   1. Overloads are chosen by the advice's `@Patch.Argument` types: a target matches when it has enough parameters and each bound one is assignable to the advice's type. `Object` matches anything, so bind the real game types (`DebugLogStream.printException` has 3 overloads).
   2. There is no raw bytecode access. A fix that changed one instruction inside a vanilla method becomes `@Patch.OnExit` advice that recomputes the right value from public members and corrects the stored field or the `@Patch.Return`.
   3. `javaPreload=true` (load at JVM start) needs a signed jar (`doc/ModdingGuide.md` "Preload Mods"). Without it, a plugin starts at the first `loadMods` that lists it, so ErrorMonitor is in `default.txt` to record from the main menu on.
12. **Contributing upstream.** Small single-purpose PRs get merged within days; large bundled ones get closed or sit. No contributing guide. Only send fixes for bugs we actually hit; build everything else in our own mods.
