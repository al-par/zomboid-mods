# Performance, debugging, profiling

## 1. Performance rules

Measure before optimising (section 3). Costs below come from reading code unless tagged otherwise.

### Event cost

1. **Registered handlers cost; empty events don't.** An event with no handlers costs almost nothing, while every registered handler is a protected Lua call on every fire. Don't register frequent events you don't need. [A]
2. **Per-frame events run every frame regardless of game speed:** `OnTick`, `OnPlayerUpdate`, `OnRenderTick`, and UI `prerender`/`render`. Keep them to a few dozen Java calls, and throttle with a frame counter or a `getTimestampMs()` gate. [A, O]
3. **`LoadGridsquare` fires for every loaded square,** and driving loads thousands per second. Reject cheaply first (sprite name, `hasModData`), and build no string keys and no `pcall` per square. Several mods in the current save each add a handler, and their costs stack. [A, O]
4. **Timed events bunch up.** `EveryOneMinute`/`EveryTenMinutes` scale with game speed, and every handler fires on the same frame.
   1. The current save uses DayLength option 4 ("1 Hour, 30 Minutes"), so one game minute is about 3.75 real seconds at 1×, and fast-forward multiplies the rate.
   2. Vanilla `SFarmingSystem:EveryTenMinutes` already iterates every plant on that frame (5,960 in the current save).
   3. A heavy scan here causes a periodic stutter. Use a cursor that processes N items per tick instead.
   4. Pattern: the timed event only queues the work and adds a temporary `OnTick` worker, which processes a fixed budget per tick and calls `Events.OnTick.Remove(itself)` when the queue is empty. Vanilla removes tick handlers from inside themselves the same way (`ISButtonPrompt.lua:241`). SensibleRefrigeration (about 240 squares per tick) and SensiblePowerManagement (4 chunk levels per tick) use this.

   [C, I]
5. **`triggerEvent("OnContainerUpdate")` rebuilds both inventory pages** and runs every `OnRefreshInventoryWindowContainers` handler, ProximityInventory's included. Fire it once per batch, never per item. The loot page also rebuilds on every player step or turn. [C]
6. **Never send network traffic per tick.** Batch `sendClientCommand` (0.5 s or slower). `ModData.transmit` sends the whole table. [O]
7. **Polling checks rarely need every frame.** Health and moodle warnings poll at 4–10 Hz behind a `getTimestampMs()` gate (vanilla `ISHorn.lua` throttles the same way). When a throttled update scales by `getGameTime():getMultiplier()`, sum the multiplier over the skipped ticks so totals don't change. [C for the vanilla pattern, I for the rest]

### Not yet measured in game

The stutter every 10 game minutes, frame time while driving, and the forked mods (ProximityInventory rebuilds the loot list on every step). `perf.txt` has Lua time by mod for each session.

### Code

1. **Java calls are the main cost.** Cache `getSpecificPlayer`, `getCell()` and repeated getters in locals once per pass. [O]
2. **Don't walk whole-world lists every tick.** That includes `getCell():getZombieList()`, `getAnimals()` and `getObjectList()`. Use a radius around the player, or throttle. [I]
3. **Square scans cost (2r+1)² × levels × objects.** At r=30 over 3 levels that's about 11,000 `getGridSquare` calls before any per-object work. Spread scans over ticks. [A]
4. **Avoid allocation in hot paths.** No tables or string building (`x..","..y`) per tick or per square; reuse tables and use numeric keys. [O, I]
5. **No `print` in hot paths.** Every line goes to both `console.txt` and the DebugLog. [O]
6. **Cache `getText` results and colour tables** when the UI element is created, not in `render`. [I]
7. **Repeated exceptions are lag.** An error thrown every frame or on every chunk load costs far more than the code around it. Fix log spam first. [C]

## 2. Logs and errors

1. **Where logs live.** `console.txt` holds the current session only and is overwritten on launch. `Logs\<date>_DebugLog.txt` and `Logs\logs_<date>\` keep older sessions. Error Monitor keeps only its 3 newest session folders (`keepSessions=3` in `Zomboid\ErrorMonitor\config.properties`); copy a folder out before it ages off if it's evidence for an open bug. [C]
2. **Line format:** `LEVEL : Category f:<n>> Source> message`. `f:` is the world update counter (`IsoWorld.getFrameNo`), which stops while paused. Frames divided by the seconds between two lines gives a rough update rate, but it can't show render-only FPS loss or short stutters. [A]
3. **Mod errors name the mod:** `Lua((MOD:<name>)).<file or function>> Exception thrown`. Group errors by that string and count them. `DEBUG-MODE STACK TRACE` blocks only appear with `-debug`. [C]
4. **Expected noise, not mod errors:**
   1. `require("...") failed` warnings from vanilla.
   2. `mod "X" overrides .../<file>.json`.
   3. Thousands of global-object load lines at `f:0`, such as farming plants and feeding troughs.

   [C]
5. **Log levels.** Set them with `-debuglog=Lua,Mod` or `debuglog.cfg`. With `-debug`, every category logs at General. [A, C]
6. **Crash or forced exit.** A `console.txt` with no shutdown lines at the end means the game crashed or was killed. [I]
7. **ErrorMonitor (`mods\ErrorMonitor`).** It's a Java agent plus a small Lua mod, confirmed working in game since 2026-11-04. Prefer its output to `console.txt`. [C]
   1. **Output:** one folder per launch, `Zomboid\ErrorMonitor\<yyyy-MM-dd_HH-mm-ss>\`, holding four files.
      1. `errors.txt` lists each distinct error and warning once, with a count, the mod, the Lua stack, the call paths, and the log lines before the first occurrence.
      2. `session.log` is the whole session in order, with repeated lines collapsed into counts.
      3. `perf.txt` has frame times, hitches, freezes, and Lua time by mod and function.
      4. `performance.jfr` is a JDK Flight Recorder recording.
   2. **Settings:** `Zomboid\ErrorMonitor\config.properties`. The status files the Lua side reads are in `Zomboid\Lua\ErrorMonitor_*.txt`.
   3. **Replay an old log:** `jre64\bin\java.exe -jar ErrorMonitor-agent.jar <console.txt or DebugLog> [outDir]` builds `errors.txt` and `session.log` from any saved log, without the game. [C]
   4. **Grouping:** by exception class, normalised message, top Lua frame, first mod frame and root cause. One bug reached from several callers is a single problem with a "Called from" list. [C on replayed logs]
8. **Why `console.txt` loses things.** [A]
   1. It is written through `LimitSizeFileOutputStream`, which **wipes the file when it reaches its size limit** (`-console_dot_txt_size_kb=`). Old 10 MB `DebugLog.txt` files in `Logs\` start mid-session for this reason.
   2. Lines from subsystems switched off in `debuglog.ini` are dropped before they are written. ErrorMonitor still records them.
   3. `DebugLogStream.printException(Throwable, String, String, LogSeverity)` writes the whole exception, with its merged Lua and Java stack, as one multi-line record. Every log line reaches the files through `DebugLog.echoToLogFiles` / `echoExceptionLineToLogFiles`, after the `isLogEnabled` gate.
9. **Built-in Grafana Loki output.** `DebugLog.init()` reads `-DlokiUrl=<url>`, plus optional `-DlokiUser` and `-DlokiPass`. If set, every log-file line is also pushed through the bundled `pl.mjaron.tinyloki` client, labelled `service_name=pz.client` or `pz.server`. It goes through the same gate, so it has no deduplication and no mod attribution. Not tested. [A]

## 3. Profiling and debug tools

1. **`-debug` adds overhead to every Lua instruction.** With `Core.debug` on, `KahluaThread.luaMainloop` tracks the current line for the debugger on every instruction (breakpoint and step checks) and copies locals for the variable view on every local write. With it off, each check is a single boolean test. Debug mode also logs every category at General. The size of the slowdown hasn't been measured; it scales with how much Lua the mods run. [A]
   1. The user plays with `-debug` deliberately, as a safety net against game bugs. Don't tell them to stop.
   2. To find out whether it matters, A/B test: play the same few minutes with and without `-debug` and compare. Fixing heavy mods helps either way.
   3. Debug mode provides F11 (the Lua debugger), the debug menu and full stack traces.
2. **The debug option `Checks.SlowLuaEvents`** (debug menu or `Zomboid\debug-options.ini`) logs `SLOW Lua event callback <file> <closure> <ms>ms` for any handler over 250 ms. It catches only big hitches. [A]
3. **The debug option `GameProfiler.Enabled`,** together with the trigger file `Zomboid\messaging\Trigger_PerformanceProfiler.xml`, writes `*_GameProfiler_*` CSV span recordings. Untested here. [A]
4. **Live reload.** `reloadLuaFile(path)`, and the server admin commands `reloadlua <file>` and `reloadalllua`, re-run files while ignoring `Events.Add`/`Remove`. Existing handlers with the same file and function name are swapped in place. **Newly added handlers are not installed**; restart for those. [A]
5. **Java-side cost** (rendering, Java agents such as CutawayFix): use JFR.
   1. With ErrorMonitor installed, every session already has `performance.jfr`: the "default" settings, the last 30 minutes, at most 200 MB, written when the game closes. On a JVM crash the JVM writes `hs_err_pid<pid>.jfr`, which ErrorMonitor copies into the session folder as `jvm-crash.jfr`. Open either in JDK Mission Control or VisualVM. [A; the recording API was exercised outside the game]
   2. Without ErrorMonitor, add `-XX:StartFlightRecording=duration=120s,filename=C:/Users/alpar/Zomboid/pz.jfr,settings=profile` to `vmArgs` in `ProjectZomboid64.json`, after backing it up. [O]
   3. The game JRE (Zulu 25.0.1) includes `jdk.jfr`, `jdk.management` and `jdk.management.jfr`. `ProjectZomboid64.json` selects ZGC. ZGC's "Cycles"/"Concurrent" collector beans are not pauses; only the "Pauses" bean is. [C for the modules, A for the beans]
6. **Workshop profilers** (untested):
   1. ZProfiler `3801641988` ranks handlers per minute on a dedicated server.
   2. Lua Profiler `3712367847` and ZBLuaPerfMon need the ZombieBuddy Java agent.
   3. Viewpoint Smooth Frames `3816784011` reports handlers slower than 8 ms.

   [O]
7. **Find the slow mod by bisection.** With the game closed, back up the save's `mods.txt`, remove half the mods, then repeat the same activity and compare. Steam's performance overlay is reported to serialize the render thread, so keep it off while measuring. [C procedure, O for the overlay]
8. **Kahlua's own profiler is compiled out** in 42.21, so Lua time per mod has to be measured from outside. [A]
   1. ErrorMonitor's `perf.txt` does it with a sampler thread that reads `LuaManager.thread.currentCoroutine` every 5 ms.
   2. The frame stack comes from `Coroutine.getCallframeStack()`, `getCallframeTop()` and `getParent()`. Each `LuaCallFrame.closure.prototype` names its mod through `LuaClosure.toStackTraceElement(pc)`, which gives `Lua((MOD:Name))` or `Lua(Vanilla)`.
   3. The game thread only adds one clock read per frame, through a hook at the start of `GameWindow.frameStep()`.
   4. The reads are racy by design, so attribution is statistical.
   5. The sampler was verified outside the game with a standalone KahluaThread, not with real mod files.
   6. Check `perf.txt` before bisecting. Its "LUA TIME BY MOD" and "HITCHES" sections are meant to name the culprit, or to show that the time is in the engine rather than Lua. This is unproven in game until a real session's `perf.txt` has been checked against a known slow mod.
9. **Long freezes in FMOD on animal emitters (sessions of 2026-11-04 23:12 and 2026-11-05 01:53).** `perf.txt` said "Mostly the engine (Java), not Lua". To find the stuck call, dump `jfr print --stack-depth 64 --events jdk.NativeMethodSample performance.jfr` and count samples per second for each top frame.
   1. **Where it hung:**
      1. `AnimalEatState.exit` → `CharacterSoundEmitter.stopOrTriggerSoundByName("AnimalFoleyEatGrass")` → `EventSound.triggerCue` → `FMOD_Studio_EventInstance_KeyOff`.
      2. `IsoAnimal.update` → `FMODSoundEmitter.tick` → `FMOD_Studio_EventInstance3D`.
   2. **How it developed:** nothing for the first 20 minutes. Short stalls started at 02:14:51, between two sleeps, and grew to freezes of 3.9 s, 5.5 s, 9.4 s, 10.8 s and 13.9 s. FPS fell from 58 to 22 by the end. The older session hung for good. [C]
   3. **The game's own code:** `AnimalEatState.enter` plays `AnimalFoleyEatGrass` (or `AnimalFoleyFeedFromMother`). `exit` only calls `stopOrTriggerSoundByName`. That loops over the emitter's `toStart` and `instances` lists. Clips with sustain points get a KeyOff and **stay in `instances`**; the rest are released and removed. `stopSoundByName` stops, releases and removes every match, but always returns 0. No mod plays or stops these sounds. [A]
   4. **Not proven:** that the animal emitters' `instances` lists grow. Lua can't read their size. Forum reports describe the same vanilla B42 pattern: animal sounds in FMOD, worse in rain and with many animals, and only a restart helps. [O]
   5. **Prime suspect:** SensibleLivestock's `cancelPhantomFlee`, added 2026-11-03 15:49. It stops an animal that vanilla has just made bolt from an unseen zombie within 6 tiles. If vanilla bolts it again every tick, the animal keeps leaving and re-entering eating. Its `HiddenZombies` option turns this off. [Hypothesis] Evidence for it:
      1. The user reports the freezes started with the last day's changes.
      2. Of everything that changed in that window (SensibleLivestock, SensiblePowerManagement, SensibleRefrigeration, ErrorMonitor), only SensibleLivestock touches animals. SensiblePowerManagement never plays sounds or re-creates generators. ErrorMonitor hooks only logging and `frameStep`. Neither the game nor any Workshop item in the save updated. [C]
      3. In the 23:12 session, which ran per-tick SensibleLivestock, `cancelPhantomFlee` spent its time in the zombie loop, which runs only while an animal is bolting. That session froze 6 minutes after load. The 01:53 session, with 100 ms updates, took about 20 minutes. [C]
      4. FMOD wasn't jammed globally. All stalls were on character emitters, while generator, ambience and `FMOD_System_Update` calls stayed fast. [C]
