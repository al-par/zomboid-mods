# Mod structure, mod.info, translations, options, Workshop

## 1. Folder layout

```
MyMod/
  common/                  -- loads first; version-independent assets
  42/                      -- version folder
    mod.info
    media/
      registries.lua       -- 42.13+, custom tags and registries (see scripts.md)
      sandbox-options.txt
      scripts/*.txt
      textures/Item_*.png
      lua/
        shared/            -- loads first; timed actions, translations
          Translate/EN/*.json
        client/            -- second; UI, context menus (never run on a dedicated server)
        server/            -- third; also loads in SP and on MP clients
```

1. **A B42 mod is listed if `common/mod.info` or `<versionFolder>/mod.info` exists.**
   1. A root-level `mod.info` (the B41 location) is never read by B42.
   2. Metadata comes from the version folder's `mod.info`, with `common/mod.info` as the fallback. Keep the two identical, or ship only one.
   3. Only one of `common/` or a version folder is required (since 42.15). `SensibleRefrigeration` has only `42/` and loads.

   [A, C]
2. **Files load from `common/` first.** The version folder then overrides it file by file, by relative path. [A]
3. **The version folder is chosen by its name, not by `versionMin`/`versionMax`.**
   1. Folder names score `major*1000+minor`, and the patch digit is ignored: `42.13.2` counts as `42.13`.
   2. The game picks the highest folder from `42.0` up to the running version, so `42.22/` is ignored on 42.21.
   3. A Workshop item shipping `42`, `42.14`, `42.17` and `42.22` loads `42.17` on 42.21.

   [A]
4. **`versionMin`/`versionMax` only decide whether the mod is available.**
   1. The format is `42.0` or `42.21`. A bare `42` is invalid and drops the mod.
   2. Only major and minor are compared.

   [A]
5. **A top-level `media/` in a Workshop mod is the B41 copy.** Fix the folder that actually loads. [C]
6. **Folders named `examplemod` are skipped** ("refusing to list"). [A]

## 2. `mod.info`

```
name=My Mod
id=MyModID
description=First line.
description=Second line (repeated lines append).
modversion=1.0
versionMin=42.0
require=OtherModID
pack=MyModTiles
tiledef=MyModTiles 6143
```

1. **Keys parsed in 42.21:**
   1. `name`, `id`, `description` (repeatable), `author`, `modversion`.
   2. `poster` (repeatable; `../common/x.png` works), `icon`, `url`.
   3. `category` (`map`, `vehicle`, `features` or `modpack`).
   4. `require`, `incompatible`, `loadModAfter`, `loadModBefore` (comma lists).
   5. `pack=<name>[ type=ui]`, `tiledef=<name> <number>`.
   6. `versionMin`, `versionMax`.

   Keys like `lots`, `demoVideo` and `zoomX` belong to `map.info`, not `mod.info`. [A]
2. **`name=`, `poster=`, `description=`, `require=`, `pack=` and `tiledef=` are matched with "contains," and `name=` is checked first.** A description line containing the text `name=` (for example `filename=`) overwrites the mod name. [A]
3. **`tiledef=` takes exactly two space-separated tokens, and the number must be 100–8189.** Anything else invalidates the mod. Check pzwiki "Tiledefs used by mods" and every installed `mod.info` for collisions. [A]
4. **`require` is checked recursively.** A required mod that is missing, or out of its own version range, makes yours unavailable. `require=Base` breaks the mod, because `Base` is not a mod id. [A]
5. **Every `\` in mod ids is stripped** in `require`, `incompatible`, `loadModAfter`, `loadModBefore`, `mods.txt` and the server's `Mods=`. So `\ModId` equals `ModId`, but `WorkshopId\ModId` becomes `WorkshopIdModId` and breaks. Online claims that B42 servers *need* `\` are wrong for 42.21. [A]
6. **A mod id is not a Workshop id.** One Workshop item can hold several mod ids. [C]
7. **Duplicate mod ids:**
   1. The scan order is `Zomboid\Workshop` → subscribed Workshop items → `Zomboid\mods`, and the first copy found wins.
   2. A local copy with the same id as a subscribed Workshop mod is therefore ignored. A local patch mod needs its own id.
   3. `-modfolders mods,workshop,steam` changes the order.

   [A]
8. **Renaming a mod in a live save.** Change the folder, `id`, `name` and display strings, then swap the id in the save's `mods.txt`. Keep everything the save stores by name: sandbox option names (`map_sand.bin`), global ModData keys, item and recipe ids, and the `pack`/`tiledef` name and number (placed tiles). Renaming a sandbox option resets it to its default. [I, from section 4.5 and `world-objects.md`]

## 3. Translations (JSON since 42.15.0)

1. **Location.** UTF-8 JSON files in `media/lua/shared/Translate/<LANG>/`, with no language suffix in the file name. Each is a flat object: `{ "Base.MyItem": "My Item" }`. Old `*_EN.txt` Lua-table files are ignored, so raw keys show in game. [C]
2. **Only these file names load:** Tooltip, IG_UI, Recipes, RecipeGroups, Farming, ContextMenu, SurvivalGuide, UI, Items, ItemName, Moodles, Sandbox, Challenge, Stash, Moveables, MakeUp, GameSound, DynamicRadio, EvolvedRecipeName, Recorded_Media, SurvivorNames, Attributes, Fluids, Print_Media, Print_Text, Entity, RadioData, BodyParts, MapLabel, Credits. Also `Mod.json` (`name`, `description` for the mod manager) and `<mapFolder>.json`. **Any other file name is silently ignored.** [A]
3. **Key patterns:**

   | File | Key pattern |
   |---|---|
   | `ItemName.json` | `"Base.ItemId"` |
   | `Recipes.json` | bare recipe name |
   | `Tooltip.json` | `"Tooltip_..."` |
   | `ContextMenu.json` | `"ContextMenu_..."` |
   | `IG_UI.json` | `"IGUI_..."`, including `IGUI_CraftingCategories_<cat>` |
   | `Sandbox.json` | see section 4 |

   [C]
4. **Merge order.**
   1. EN loads first, then the selected language.
   2. Within each language, vanilla loads first, then mods in load order (each mod's `common/`, then its version folder).
   3. The later non-empty value wins per key. The log line `mod "X" overrides .../itemname.json` is normal.

   [A]
5. **Strings go through Java's formatter.** Placeholders are `%1`–`%9`. A literal `%` must be `%%`, or the log shows `UnknownFormatConversionException`. [C]
6. **Malformed JSON throws `JSON Error in: <file>`.** [A]
7. **Language folders carry `language.json`.** pzwiki's `language.txt` is outdated. [C]

## 4. Sandbox options

```
VERSION = 1,

option MyModID.Strength
{
    type = enum,
    numValues = 3,
    default = 2,
    page = MyModID,
    translation = MyMod_Strength,
    valueTranslation = MyMod_StrengthValues,
}
```

1. **File and syntax.** The file is `42/media/sandbox-options.txt` and must start with `VERSION = 1,`. It isn't Lua, so `--` comments aren't allowed. [C]
2. **Option types:**
   1. All types take `type`, `default`, `page` and `translation`.
   2. `integer` and `double` add `min`/`max`.
   3. `enum` adds `numValues` and `valueTranslation`.
   4. `boolean` takes nothing more.
   5. `string` takes only `default`.
   6. A `string` default can't contain commas, because `ScriptParser` ends the value at the first one. Use `;` in the file and accept both separators when parsing (players may type commas in the sandbox screen). Vanilla's own comma lists (`WorldItemRemovalList`) are defined in Java, not in this file.

   [A]
3. **Translation keys in `Sandbox.json`:**
   1. Page: `Sandbox_<page>`.
   2. Name and tooltip: `Sandbox_<translation>` and `Sandbox_<translation>_tooltip`.
   3. Enum values: `Sandbox_<valueTranslation or translation>_option<N>`.

   [A]
4. **Reading values.** Read in Lua as `SandboxVars.MyModID.Strength`. At runtime, `getSandboxOptions():getOptionByName("MyModID.Strength"):getValue()` also works. [C, O]
5. **Editing one save's value without the sandbox screen.** `map_sand.bin` is `SAND`, int32 249, int32 version, int32 count, then count (name, value) string pairs, then the preset name. Strings are a big-endian uint16 byte length plus UTF-8; booleans are stored as `true`/`false`. `QuickMeals/tools/set_sandbox_option.py` sets or adds one option, refuses if the file doesn't round-trip, and writes a `.bak`. Run it only with the game closed, because the game rewrites the file. [A, format checked against a real save]
6. **Saved values.** A save stores the values when the mod is added (`map_sand.bin`). New options use their defaults, and changing a default doesn't change existing saves. Save-specific `SandboxVars` aren't loaded yet during the distribution-merge events or `OnInitWorld`. [A]

## 5. Mod Options (per-player client settings)

Use these for UI and keybind preferences. Use sandbox options for gameplay.

```lua
-- client/MyMod_Options.lua
local options = PZAPI.ModOptions:create("MyModID", "UI_MyMod_Title")
options:addTickBox("showHalo", "UI_MyMod_ShowHalo", true, "UI_MyMod_ShowHalo_tooltip")
options:addSlider("radius", "UI_MyMod_Radius", 1, 20, 1, 5, "UI_MyMod_Radius_tooltip")
options.apply = function(self) --[[ react to changes ]] end

-- elsewhere
local radius = PZAPI.ModOptions:getOptions("MyModID"):getOption("radius"):getValue()
```

1. **Where it lives.** It's defined in vanilla `client/PZAPI/ModOptions.lua` and saved to `Zomboid\Lua\ModOptions.ini`. [C]
2. **Builders:** `addTitle`, `addDescription`, `addSeparator`, `addTextEntry`, `addTickBox`, `addMultipleTickBox`, `addComboBox` (then `:addItem(name, selected)`), `addColorPicker`, `addKeyBind`, `addSlider`, `addButton`. Names and tooltips go through `getText`. [C]
3. **Timing.** Values load when the Options screen is built. Create the options at file load or on `OnGameBoot`, and read them later, not at file load. [C, I for the timing]

## 6. Workshop upload

1. **Layout:** `Zomboid\Workshop\<Item>\workshop.txt`, `preview.png`, and `Contents\mods\<ModFolder>\{common,42,...}`. [A]
2. **What `Contents\` may hold.** Only `mods\`, `buildings\` and `creative\`. Loose files directly in `Contents\mods\` are rejected. Anything beside `Contents\` isn't uploaded, so docs and raw art can live there. [A]
3. **`preview.png`** must be square, exactly 256×256 or 512×512, and at most 1,024,000 bytes. [A]
4. **`workshop.txt`:** `version=1`, `title=`, repeatable `description=`, `tags=` and `visibility=`. [C]
5. **The in-game uploader overwrites the Steam description** and appends `Workshop ID:`/`Mod ID:` lines. [O]
