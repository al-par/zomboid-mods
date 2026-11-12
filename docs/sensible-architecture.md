# The Sensible mods: how they're built

Rules for every published mod in the Sensible family, so players get low friction and no needless conflicts. Decided 2026-11-07. Read `environment.md` §5 for ZombieBuddy mechanics.

## 1. What earns the Sensible name

1. **Sensible mods are shareable, vanilla-adjacent fixes.** They make an existing game system behave the way a player would expect, in the game's own style. They're polished enough to publish.
2. **Mods that go well off the vanilla path aren't Sensible mods.** New systems, big content additions or overhauls get their own name and live outside the family. The same goes for personal tools (Error Monitor) and unfinished work (Walk Through Poles).
3. **Brand membership is decided per mod with the user,** not by default.

## 2. Branding

1. **Names.** Display name "Sensible <Topic>", mod id `Sensible<Topic>`, one topic per mod. A mod doesn't reach into another mod's topic.
2. **Prefixes.** Every global, ModData key, sandbox namespace, item id and translation key carries the mod's own prefix. Renamed mods keep their old save-stored names (`mod-structure.md` §8); new names use the new prefix.
3. **Java packages.** `sensiblemods.<topic>` (for example `sensiblemods.livestock`). Unique, short, and stable across renames.
4. **One signing identity.** All jars are signed with one ZombieBuddy author key, so players can tick "trust this author" once (`doc/ModSigning.md` upstream). Needs the user's Steam ID64 at first publish.
5. **Workshop presentation.** A shared poster style and description template, and a Workshop collection of the family. The description says plainly which features need ZombieBuddy.

## 3. Lua by default; Java once the mod needs it anyway

1. **A mod is Lua-only if it reasonably can be.** Lua-only mods need nothing extra from players, so that's the default. Java is never the starting point just because it's more powerful. A mod gets a Java part only when something in it can't be done in Lua, or only unreasonably: no hook exists, or the only Lua route can't be made correct. The first Java patch names that limitation in a comment.
2. **In for a penny, in for a pound.** Once a mod needs a Java part for one thing, players already have to run ZombieBuddy for it, so other parts of that mod may also be Java where Java is simpler or more reliable. Example: ReviveMe needed Java to let a dead player load at all, so the heal on load moved to Java too, at the exact point the game zeroes the health (2026-11-11).
3. **The mod still loads without ZombieBuddy.** Never `require=\ZombieBuddy` in `mod.info`. A Java-dependent feature turns off cleanly and says so; it never half-works. Keep an existing Lua approximation as the fallback only if it already works well.
   1. **Exception: an explicit "(ZombieBuddy)" add-on mod.** When the Lua mod already works on its own and Java only improves it, the Java part can ship as a second mod in the same Workshop item, with id `<Mod>ZB`, `require=<Mod>,ZombieBuddy` and only the jar plus `mod.info`. Players pick it in the Mods screen; the base mod is the no-ZombieBuddy option. The base mod's Lua detects the jar's global function and hands it the rules. First case: `SensibleRefrigerationZB` (2026-11-08).
4. **One source of truth for rules.** Gameplay rules (materials, thresholds, sandbox options) live in the mod's Lua. The Java side is a thin hook that asks Lua (or reads data Lua handed it) for the decision, then applies it. If ZombieBuddy is ever abandoned, only the hooks need rewriting.
5. **Nothing Java-only goes into the save.** No ModData, object fields or items that exist only when Java is loaded. Adding or removing ZombieBuddy mid-save must be harmless.

## 4. Compatibility

1. **Advice patches only.** Use `@Patch.OnEnter`/`OnExit`. Never `isAdvice = false` (method delegation): only one mod can delegate a method, so it guarantees conflicts.
2. **Don't skip the original method** (`skipOn`) when adjusting an argument would do. Skipping hides the call from every other mod's patches. Skip only for a true "this doesn't happen" (for example an immune wall).
3. **Patch the narrowest method** that sees the context needed. To scale damage, mark the context on entry to the specific action and adjust the argument of the generic call inside it, rather than replacing the generic call for everyone.
4. **Fail closed per patch.** If a game update removes or renames a target, that patch is dropped (`optional` handles, version checks in `Main`), the mod falls back to Lua, and the status panel says so. One broken patch never takes the mod or the game down.
5. **Lua overrides wrap and call the original** (as `SensibleWalls_WireFences.lua` does); never replace a vanilla function outright.
6. **Multiplayer.** Patches that change world state run where the world is simulated: the server, or the single-player game. Use `media/java/` for both sides; `media/java/client/` only for purely visual patches.

## 5. Separation of concerns

1. **Each mod owns its Java.** One jar per mod, inside that mod (`42/media/java/Sensible<Topic>.jar`). A broken or denied jar affects only its own mod. With author trust, extra jars cost the player nothing.
2. **No shared Java library.** Tiny helpers are copied rather than shared, so mods update independently.
3. **Sensible Core: one-time Java setup, then every mod is one-click subscribe** (decided 2026-11-12; supersedes "Core comes later").
   1. **Goal.** The least friction possible for players. They do one setup for Sensible Core; after that, any of our mods, Java or not, works by subscribing on the Workshop. No manual copying of jars.
   2. **Leverage ZombieBuddy, never replace it.** We push the existing standard forward (upstream PRs, `environment.md` §5 item 12) instead of competing with it. The one-time setup is ZombieBuddy's install; Core guides it. If an installer reduces effort further, prefer improving ZombieBuddy's own installer upstream.
   3. **Jars already arrive with the mod.** Each jar ships inside its own Workshop item (section 5 item 1) and ZombieBuddy loads it, so Core downloads nothing. Runtime downloads from GitHub or elsewhere are out: Lua can't, and Java would bypass Workshop delivery and ZombieBuddy's approval.
   4. **Jobs.** One pop-up when ZombieBuddy isn't running, with the setup steps; a status panel of every active mod's Java part (`ZombieBuddy.getJavaModStatus`) and which features are off; guidance to trust our signing author once (section 2 item 4) so new jars don't prompt; a small Lua API each mod uses to turn its Java features on or off.
   5. **Scope.** Every mod of ours with a Java part requires Core, Sensible-branded or not (ErrorMonitor, CutawayFix, ReviveMe, DebugHotkeysFix too). Lua-only mods never do. Core itself is Lua-only.
   6. **Status.** Not built yet. Five mods carry jars, and four of them have their own detection Lua to move into Core.

## 6. Developing while the user plays

1. The game reads mod files from `Zomboid\mods\<Folder>`, so editing a loaded mod's folder changes the next load. While the game runs, develop in a git worktree outside `mods\`: `git -C mods\<Mod> worktree add C:\Users\alpar\Zomboid\mods-dev\<Mod> -b <branch>`. Merge into `main` only when the user is ready to test.
2. Never touch the save, `mods.txt` or `ProjectZomboid64.json` while `ProjectZomboid64` is running.

## 7. Candidate Java feature: animal damage to built objects (Sensible Livestock)

Not approved yet: the Lua health-buffer workaround already works, so this only qualifies if the user agrees it counts as "can't be made correct in Lua" (section 3).

Confirmed from bytecode (42.21) [A]:

1. Animals damage built objects only in `zombie.ai.states.animals.AnimalAttackState.animEvent`. When `animal.thumpTarget` is an `IsoThumpable`, it calls `IsoThumpable.animalHit(IsoAnimal)`, plays the fence sound, and calls `destroy()` when `health` reaches 0.
2. `IsoThumpable.animalHit` computes `1000 * animal.calcDamage()` and passes it to `this.Damage(float)`; material and animal size don't enter into it. Map-placed walls aren't `IsoThumpable`, so animals can't hurt them at all.
3. **Planned hook:**
   1. `@Patch.OnEnter` on `IsoThumpable.animalHit` with `@Patch.This` and `@Patch.Argument(0)`: ask Sensible Livestock's Lua rules for a multiplier for this object and animal. A multiplier of 0 skips the hit (`skipOn`). Otherwise store it for the current call.
   2. `@Patch.OnEnter` on `IsoThumpable.Damage(float)` with `@Patch.Argument(value = 0, readOnly = false)`: when a multiplier is stored, scale the damage.
   3. `@Patch.OnExit` on `animalHit` clears the stored multiplier, even when the call throws.
4. **Fallback:** without ZombieBuddy, keep today's health-buffer approach unchanged.
5. **Still to check before building:** how map doors (`IsoDoor`) take animal damage, since `animEvent` only handles `IsoThumpable`; and how Java calls a Lua function safely on the game thread.
