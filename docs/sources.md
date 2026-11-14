# Online sources

Most Project Zomboid modding material online predates Build 42, or predates 42.13 and 42.15, which changed tags, registries, multiplayer and translations. Trust the local game files over any web page. When a page states a version, check it against 42.21.

## 1. Trusted sources

| Source | Covers | Notes |
|---|---|---|
| [PZ-API-Docs](https://pz-wiki-modding.github.io/PZ-API-Docs/) | `mod.info`, script parameters, translations, Java and Lua API | Generated from 42.21 game files. Good for names; descriptions are often empty |
| [pzwiki: Mod structure](https://pzwiki.net/wiki/Mod_structure) | `common/` and version folders, Workshop layout | Revised for 42.21 |
| [pzwiki: Load order](https://pzwiki.net/wiki/Load_order), [Lua (API)](https://pzwiki.net/wiki/Lua_(API)) | Lua folder load order and overrides | B42 |
| [pzwiki: Translation](https://pzwiki.net/wiki/Translation) | JSON translation types, `Mod.json` | It says `language.txt`; 42.21 ships `language.json` |
| [pzwiki: Sandbox options](https://pzwiki.net/wiki/Sandbox_options) | Option types and keys | Its enum key rule is incomplete (see `mod-structure.md`) |
| [pzwiki: ISBaseTimedAction](https://pzwiki.net/wiki/ISBaseTimedAction), [Networking](https://pzwiki.net/wiki/Networking) | B42 timed actions, commands | Networking says "plain data only", which is incomplete |
| [pzwiki: Debug mode](https://pzwiki.net/wiki/Debug_mode), [Startup parameters](https://pzwiki.net/wiki/Startup_parameters) | `-debug`, F-keys, launch flags | 42.20 |
| [pzwiki: Registries](https://pzwiki.net/wiki/Registries), [Fluid](https://pzwiki.net/wiki/Fluid), [AnimalDefinitions](https://pzwiki.net/wiki/AnimalDefinitions), [Tile depth](https://pzwiki.net/wiki/Tile_depth) | 42.13+ systems | |
| [pzwiki: Mod optimization](https://pzwiki.net/wiki/Mod_optimization), [Mod data](https://pzwiki.net/wiki/Mod_data) | Performance basics, ModData | Partly from the B41 era |
| [pzwiki: Uploading mods](https://pzwiki.net/wiki/Uploading_mods), [Build 42.15.0](https://pzwiki.net/wiki/Build_42.15.0) | Uploader, 42.15 changelog (JSON translations, folder rules) | |
| [TIS: Modding Migration Guide 42.13](https://theindiestone.com/forums/topic/88499-modding-migration-guide-4213/) | Registries, MP changes (official PDF) | Authoritative |
| [TIS: Modding Migration Guide 42.15](https://theindiestone.com/forums/topic/92433-modding-migration-guide-4215/) | Translation and folder changes | Authoritative |
| [TIS: Build 42.13 unstable MP released](https://theindiestone.com/forums/topic/88501-build-42130-unstable-multiplayer-released/) | Server-authoritative MP | Official |
| [TIS: Tidy Up Time](https://theindiestone.com/forums/topic/72103-tidy-up-time/) | Design intent of version folders | Background |
| [Umbrella](https://github.com/PZ-Umbrella/Umbrella) | EmmyLua/LuaLS typings for B42 | Good signatures; some event "side" tags are wrong |
| [Official JavaDocs](https://projectzomboid.com/modding/) | Java class signatures | No behaviour, no version stated |
| [Wenopal course and guides](https://wenopal.work/en/guides/migrate-b41-to-b42.html) | Bytecode-checked B42 course (mostly Spanish): Kahlua, Java interop, timed actions, MP, events | Best single source. Wrong that `\` is required on servers |
| [HydeCo B42 engine notes](https://hydecogames.com/tools/mapformats/) | Tiles, depth maps, moveables, entities, recipes | Dense and decompile-based; verify before relying on it |
| [demiurgeQuantified PZModdingGuides](https://github.com/demiurgeQuantified/PZModdingGuides) | `Optimisation.md` and other guides | Experienced author |
| [Unjammer/TileZed (B42)](https://github.com/Unjammer/TileZed) | Community B42 tile tools | TIS hasn't released B42 TileZed |
| [pzcodex.com](https://pzcodex.com) | Recipe and building database with raw scripts | 42.21 |

## 1a. Code to start from

Don't write boilerplate from scratch; start from these and adjust to our rules (`sensible-architecture.md`). Vanilla Lua and scripts stay the best example of any API call. All [O], found 2026-11-14, not yet used here.

1. [pzmc-template](https://github.com/Project-Zomboid-Community-Modding/pzmc-template) (community template, GPL-3, [wiki page](https://pzwiki.net/wiki/Project_Zomboid_Community_Modding_template/en)): Workshop item layout with `Contents/mods/<Mod>/`, `common/` and `42/`. Use it for structure; last revised for 42.12, so check translations and folders against `mod-structure.md`.
2. [ZBHelloWorld](https://github.com/zed-0xff/ZBHelloWorld) (ZombieBuddy's author): smallest patch-only Java mod, with Gradle build. It uses `require=\ZombieBuddy`; we don't (`sensible-architecture.md` §3 item 3).
3. [ZombieBuddy README](https://github.com/zed-0xff/ZombieBuddy) and `doc/ModdingGuide.md`: `mod.info` keys, `@Patch` examples, `ZBVersionMin`/`ZBVersionMax`. Other examples by the same author: [ZBLuaPerfMon](https://github.com/zed-0xff/ZBLuaPerfMon).
4. [zb-gradle-plugin](https://github.com/zed-0xff/zb-gradle-plugin): signs jars (`signJarZBS` writes `<Mod>.jar.zbs`; the public key goes in the Steam profile as `JavaModZBS:<hex>`). This is the signing route for Sensible Core's "trust once" goal; it would replace our hand-copied `build.ps1` scripts.
5. [Umbrella](https://github.com/PZ-Umbrella/Umbrella) (section 1): typings, so an editor or model sees real signatures.

## 2. Use with care

| Source | Problem |
|---|---|
| [Steam: "THE Ultimate Mod Guide And API For PZ Build 42"](https://steamcommunity.com/sharedfiles/filedetails/?id=3776551449) | Useful, but wrong on several points: `complete()` does run on the server; SP has `isServer()` false; instance fields aren't readable; its `tiledef` example is invalid; it lists map keys as `mod.info` keys; it ignores B42 depth maps |
| pzwiki craftRecipe / Inputs / Outputs pages | The flag list dates from 42.6; it says inputs default to `destroy` (they default to Normal) and that no vanilla recipe uses output flags (six are used) |
| pzwiki Fluids (craftRecipe), Tags (craftRecipe) | 42.5-era; documents `+fluid`, which vanilla no longer uses |
| pzwiki OnPreDistributionMerge | Says it fires after the merge; it fires before |
| pzwiki Adding new tiles | B41; gives the tiledef range as 0–999 (it's 100–8189) |
| [FWolfe Zomboid-Modding-Guide](https://github.com/FWolfe/Zomboid-Modding-Guide) | B41: says `os` is missing and reflection works; both are wrong for 42.21 |
| DeepWiki pages | AI summaries with wrong signatures, e.g. `syncItemModData(item)` |
| Server-hosting guides (e.g. WinterNode) | Say `\` is required before B42 server mod ids; it's stripped |
| Early-B42 Steam guides (e.g. `3391657438`) | Pre-42.15 folder advice |
| `<install>\Workshop\ModTemplate` | B41 layout |

## 3. Claims that are wrong for 42.21

1. "`common/` is mandatory." Since 42.15, `common/` or a version folder is enough.
2. "The version folder is picked by `versionMin`/`versionMax`." It is picked by folder name.
3. "Translations go in `*_EN.txt`." JSON only, since 42.15.
4. "`OnTick` doesn't run on servers." It does, unless the server is paused because it's empty.
5. "Timed actions in `client/` are SP-only." Only actions with `complete()` need to be in `shared/`.
6. "`base:heavyitem` is an `ItemType`." It is a tag.
7. "Kahlua has `next`/`math.random`." It doesn't.
