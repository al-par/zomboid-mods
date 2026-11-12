# Scripts: items, recipes, fixing, fluids, entities, loot

Copy syntax from `<install>\media\scripts\generated\`. Most online examples older than 42.13 are stale: they use bare tags, `+fluid` lines, and `Key : Value` syntax.

## 1. General syntax

1. **Always write `Key = Value,` with full `Base.` ids.** B41 `Key : Value` lines fail to parse, and a broken data script can break unrelated UI. CommonSense's B41-style fixing script killed every vehicle part menu (hood, trunk, repair). [C]
2. **Comments are `/* */`.** `//` doesn't work, and an apostrophe inside a comment can break loading. [O]
3. **Unknown item parameters end up in the item's ModData,** so a typo doesn't raise an error. [O]
4. **Script subfolder names don't matter.** Entity files load from any folder under `scripts/`. [C]
5. **A mod file at a vanilla relative path replaces the whole vanilla file.** A mod that shipped `scripts/generated/fixing.txt` and wiped vanilla's firearm self-repairs; the log says `mod "X" overrides media/scripts/generated/fixing.txt`. Give script files mod-specific names. [C]
6. **The script parser ignores quotes.** Commas split values even inside `"..."`, and a missing trailing comma swallows the next line's key. Put tooltip text in `Tooltip.json` and reference it as `Tooltip = Tooltip_X,`. [A]
7. **Redefining an existing object resets most of it.** A later block for the same model resets mesh, texture and scale but keeps attachments, so re-declaring a vanilla model to add attachments must not copy vanilla's attachment positions (they go stale on updates). [A]

## 2. Items

```
module Base
{
    item SLS_SaltLick
    {
        DisplayCategory = Material,
        ItemType = base:drainable,
        Weight = 15.0,
        Icon = SLS_SaltLick,
        UseDelta = 0.05,
        cantBeConsolided = true,
        Tooltip = Tooltip_SLS_SaltLick,
    }
}
```

1. **`ItemType` takes one of 15 script values:** `base:normal`, `food`, `clothing`, `weapon`, `literature`, `moveable`, `container`, `drainable`, `radio`, `map`, `weaponpart`, `key`, `alarmclock`, `alarmclockclothing`, `animal`. [C]
2. **`base:heavyitem` is a tag, not a type:** `Tags = base:hasmetal;base:heavyitem`. [C]
3. **Item tags are namespaced** (`base:hasmetal`). Custom tags must be registered (section 8). [C]
4. **Drainables:** `UseDelta = 0.05` gives 20 uses. `cantBeConsolided = true` blocks merging. [C]
5. **Icons:** `Icon = X` resolves to `media/textures/Item_X.png`. [C]
6. **`ReplaceOnCooked` can point at a non-food item,** and the replacement happens before the burn check. [A]
7. **Weight:** when changing an item's weight in Lua, also call `item:setCustomWeight(true)`, as vanilla does. `setEquippedWeight` doesn't exist. [C, A]
8. **Item names:** an item without an `ItemName.json` entry reports weight 0. [I]
9. **Don't change the `ItemType` of an existing vanilla item.** Saved copies are read back in the old format. Add a new item and convert. [A]
10. **Many vanilla ids were renamed in B42,** e.g. `TreeBranch2`, `PaperNapkins2`, `WoodenStick2`. Check every id against `generated/items/*.txt`. [C]
11. **Models:** `mesh` is relative to `media/models_X`, `.fbx` or `.glb` with the extension left off. `texture` is relative to `media/textures`. [O]

## 3. `craftRecipe`

```
craftRecipe SLS_MakeBrine
{
    timedAction = MixingBowl,
    time = 60,
    Tags = AnySurfaceCraft;Cooking,
    category = Cooking,
    inputs
    {
        item 1 [Base.Pot;Base.PotForged] mode:destroy flags[InheritCondition;ItemCount] mappers[potType],
        -fluid 1.5 categories[Water] mode:mixture,
        item 1 [Base.SLS_DirtySaltChunk],
    }
    outputs
    {
        item 1 mapper:potType,
    }
    itemMapper potType
    {
        Base.SLS_PotOfBrine = Base.Pot,
        Base.SLS_PotForgedOfBrine = Base.PotForged,
    }
}
```

1. **Keys** are case-insensitive:
   1. Core: `time`, `timedAction`, `category`, `Tags`.
   2. Skills and learning: `SkillRequired = Electricity:1`, `xpAward = Electricity:5`, `NeedToBeLearn`, `AutoLearnAll`/`AutoLearnAny`, `MetaRecipe`, `ResearchAny`/`ResearchAll`/`ResearchSkillLevel`.
   3. Misc: `AllowBatchCraft`, `Tooltip`, `icon`, `recipeGroup`.
   4. Callbacks: `OnTest`, `OnCreate`, `OnStart`, `OnUpdate`, `OnFailed`, `OnAddToMenu`.
   5. Mapper blocks: `itemMapper`, `fluidMapper`, `energyMapper`, `overlayMapper`.

   [A]
2. **`timedAction`** names must exist in `generated/timedactions.txt`. [C]
3. **Inputs** take the form `item N [A;B]` or `item N tags[base:hammer;...]`, optionally followed by:
   1. A mode. With no mode the input is **Normal** (consumed normally). `mode:keep` keeps it as a tool, and `mode:destroy` removes the whole item.
   2. `flags[...]`.
   3. `mappers[name]`.

   Other forms: `item variable[1:20] [X]` for a variable count, and `[*]` for any item. [A, C]
4. **Fluid inputs:**
   1. `-fluid 1.0 [Water]` or `-fluid 0.2 categories[Water] mode:mixture`, placed directly after an `item` line. The fluid is drawn from that container. A comment between the `item` line and the `-fluid` line is not safe: the fluid line has to stay the child of that item.
   2. Fluid modes (`InputScript.isFluidMatch`, default `exact`):
      1. `exact`: the container is not a mixture, and its primary fluid is in the list.
      2. `mixture`: every fluid in the container is in the list. One drop of water rejects the whole container.
      3. `primary`: the primary (largest) fluid is in the list. Other fluids may be present.
      4. `anything`: any non-empty fluid.
   3. Cow and sheep breeds milk as `CowMilk` and `SheepMilk`. Powder milk fills the container with `AnimalMilk` (`RecipeCodeOnCreate.makeMilkFromPowder`). Vanilla `churn_butter` is `-fluid 5.0 [CowMilk;SheepMilk] mode:mixture`, so a bucket of powder milk, or a milk bucket with any rain or leftover water, is rejected. SensibleCraft replaces that file with `mode:primary` and adds `AnimalMilk`.

   [A for the four modes and the churn line, C for the drawing rule]
5. **Common input flags:** `MayDegradeLight`, `Prop1`, `Prop2`, `IsNotDull`, `ItemCount` (a drainable or fluid container counts as one whole item), `InheritCondition`, `DontRecordInput` and `AllowDestroyedItem`. The full list is the Java enum `zombie.entity.components.crafting.InputFlag` (67 values). Output flags used by vanilla are `IsBlunt`, `HasOneUse`, `HasNoUses`, `DontInheritCondition`, `EquipSecondary` and `SetActivated` (enum `OutputFlag`). `FullOfWater` doesn't exist. [A]
6. **Recipe `Tags` are not namespaced:**
   1. Placement tags: `AnySurfaceCraft`, `InHandCraft`, `CanBeDoneInDark`, `CanBeDoneFromFloor`, `RightClickOnly`.
   2. A workstation name also works as a tag; it matches `component CraftBench { Recipes = X }`.
   3. A custom `category` needs an `IGUI_CraftingCategories_<cat>` key in `IG_UI.json`.

   [A, C]
7. **Hooks:**
   1. `OnTest(item, character)` returns a boolean.
   2. `OnCreate(craftRecipeData, character)` gets results through `craftRecipeData:getAllCreatedItems()`.
   3. The vanilla `RecipeCodeOnCreate.*` and `RecipeCodeOnTest.*` are **Java** (`zombie.scripting.logic`), so grepping Lua won't find them.

   [A]
8. **Overriding vanilla recipes:**
   1. Redeclaring a vanilla recipe name doesn't replace it; both load.
   2. An unknown item in an input list is silently dropped.
   3. An unknown fluid or invalid output throws.
   4. A file at the vanilla relative path replaces that whole file (section 1, item 5). Use that only when the vanilla file contains the one recipe being changed. SensibleCraft replaces `recipes_butter_churn.txt` this way, because that file is only `churn_butter`.

   [O, A for item 4]
9. **Recipes keyed to `Base.Mov_X` never see items picked up from the map.** Those become `Moveables.<sprite>` (`world-objects.md`). [C]

## 4. Fixing

1. **Vanilla `fixing.txt` in 42.21 holds only 29 firearm self-repairs:**
   ```
   fixing Fix Pistol
   {
       Require = Base.Pistol,
       Fixer = Base.Pistol; Aiming=3,
   }
   ```
2. **General repair is now craftRecipes** in `recipes_fixing.txt`: `tags[base:repairwithtape] mode:keep flags[Prop2;IsDamaged]`, `OnCreate = RecipeCodeOnCreate.genericFixing`, with empty `outputs`. Copy that pattern. [C]

## 5. Fluids

1. **Definitions** are in `generated/fluids*.txt` (61 fluids). Keys are `ColorReference`, `DisplayName` (translated in `Fluids.json`), `Categories`, `Properties`, `Poison` and `BlendWhiteList`. [C]
2. **Fluid categories:** Beverage, Alcoholic, Hazardous, Medical, Industrial, Colors, Dyes, HairDyes, Paint, Fuel, Poisons and Water. [C]
3. **`component FluidContainer` keys:**
   1. `ContainerName`: no spaces allowed; the log says "Sanitizing container name".
   2. `Capacity`, `RainFactor`, `TransferRate`, `InitialPercentMin`/`InitialPercentMax`, `PickRandomFluid`, `Opened`, `FillsWithCleanWater`, `HiddenAmount`.
   3. `Fluids { fluid = Water:1.0, }`, where the number is a fraction of capacity.
   4. `whitelist { fluid = Water, }`.

   [C, O for the fraction]
4. **In Lua,** use `item:getFluidContainer()` with `contains(Fluid.Petrol)`, `getAmount()`, `getCapacity()` and `getFreeCapacity()`. [C]

## 6. Entities (player-built objects)

1. **Shape:** `entity X { component UiConfig {...} component SpriteConfig {...} component CraftRecipe {...} }`. Vanilla entities are in `generated/entities/**`. They are built through `ISBuildIsoEntity` → `buildUtil.setInfo`. [C]
2. **`SpriteConfig` keys:**
   1. Layout: `face single|n|s|w|e|n_open|w_open`, then `layer`, then `row = a b`. Space-separated sprites make a multi-tile row.
   2. Health: `health`, `skillBaseHealth`, `bonusHealth`.
   3. Flags: `corner`, `isPole`, `isProp`, `isThumpable`, `needToBeAgainstWall`, `needWindowFrame`, `dontNeedFrame`, `canBePadlocked`.
   4. Callbacks and staging: `OnCreate`, `OnIsValid`, `previousStage`.

   [A]
3. **The `xuiSkin` style block** (`entity ES_X { DisplayName = ..., Icon = Build_X, }`) must be in `module Base`. A missing icon draws "?". [O]
4. **A sprite can belong to only one entity.** A duplicate errors and world load dies. [O]
5. **How `ISBuildIsoEntity` runs the callbacks** (`server/BuildingObjects/ISBuildIsoEntity.lua`):
   1. `OnIsValid(params)` runs per square of the cursor, every frame, with `square`, `tileInfo`, `north`, `facing`, `testCollisions` and `canBuildOverWater`. Setting `params.testCollisions = false` skips the free-square, wall and stair checks, so an add-on can be placed on a square something already occupies.
   2. Each square becomes its own `IsoThumpable`, which is added to the square before `OnCreate(params)` runs with `thumpable`, `craftRecipeData`, `character` and `facing`. A multi-tile entity calls `OnCreate` once per square.
   3. In `OnCreate`, return `{ replaceObject = true, object = o }` after swapping the thumpable for another class (the barrel oven pattern), or `{ objectAlreadyTransmitted = true }` after removing it yourself. Returning nothing transmits the thumpable.
   4. `previousStage` matches an `IsoThumpable` with that name and the same `north` on the same square, and replaces it. It can't upgrade one square of a multi-tile object without destroying that object.
   5. Faces don't map to the sprite's `Facing` property one to one. The barrel oven's face N is `crafted_05_7` (door facing S) and face S is `crafted_05_4` (door facing N); E and W match.

   [C]

## 7. Loot

1. **Order:** `OnPreDistributionMerge`, then `OnDistributionMerge` (where the vanilla merge happens), then `OnPostDistributionMerge`, then `ItemPickerJava.Parse()`. Edits made after `Parse` do nothing. [A]
2. **Edit `ProceduralDistributions.list[name].items`** (flat `"Module.Item", weight` pairs) and `VehicleDistributions` in the Pre or Post event. Check that the list exists first, and don't wrap the edit in `pcall`. [C]
3. **Vanilla reuses one table under several names** (e.g. `Bag_Sheriff = BagsAndContainers.Bag_Police`). Code that loops over every distribution can hit the same list 3–5 times; track visited tables. Collect your rules first and apply them in one pass, rather than rescanning all lists per rule (one mod went from about 1 s to 6 ms in native Lua). [C, measured off-engine]
4. **To spawn "as often as item X":** in `OnPostDistributionMerge`, walk `SuburbsDistributions`, `ProceduralDistributions.list`, `VehicleDistributions`, `ClutterTables` and `BagsAndContainers` with a visited set, and append your item with X's weight after every X entry. For foraging, copy `forageSystem.forageDefinitions.X` (with fresh `zones`/`categories` tables) into `forageSystem.addForageDef` at file load. `ElectronicsMag4` (generator magazine) has 73 container/vehicle entries, total weight 102.215, plus one Junk forage entry. SensibleArchery does this. [C, verified off-engine by running the vanilla distribution files under `lupa`; see `SensibleArchery/tools/test_distributions.py`]
5. **Recipe magazines:** `ItemType = base:literature`, `LearnedRecipes = a;b`, `OnCreate = ItemCodeOnCreate.onCreateRecipeMagazine`, `Tags = base:magazine`. Each recipe needs `NeedToBeLearn = true`; adding that to an existing save's recipes makes the player unlearn them until they read the magazine. [A]

## 8. Registries (42.13+)

1. **`media/registries.lua`** runs from each mod's version folder and its `common/` folder, before scripts load. [A]
2. **Register custom item tags** with `ItemTag.register("mymod:mytag")`. The `base:` namespace is rejected. An unregistered tag in `tags[...]` throws an NPE in `InputScript.OnPostWorldDictionaryInit`, and the error doesn't name the recipe. [O]
3. **Other registries:** CharacterTrait, CharacterProfession, ItemBodyLocation, ItemType, MoodleType, WeaponCategory, AmmoType, Brochure, Flier and Newspaper. See the TIS 42.13 migration guide (`sources.md`). [O]
4. **Custom ammo:** `AmmoType.register("mymod:arrow", "Base.MyArrow")` (id first, item key second), then `AmmoType = mymod:arrow,` on the weapon. Vanilla ids are `base:bullets_9mm`, `base:shotgun_shells`, etc. Reload, unload and the radial menu read `getAmmoType():getItemKey()`, so any `Ranged = true` weapon works without the `base:firearm` tag. No translation key is needed. [A; GunsOfMarz and Gunworks do the same]

## 9. Ranged weapons and crafting defaults

1. **Sounds a firearm script omits:** `ClickSound` defaults to `Stormy9mmClick` (`Item` constructor), so set it on non-guns. Rack, eject and shell-fall sounds are nil-checked in vanilla Lua and can be left out. [A]
2. **`WeaponReloadType = boltactionnomag` with `RackAfterShoot = true`** loads rounds one by one on R and auto-racks after each shot (`ISReloadWeaponAction.OnPlayerAttackFinished`), with no mod Lua. Types in 42.21: `boltaction`, `boltactionnomag`, `doublebarrelshotgun`, `doublebarrelshotgunsawn`, `handgun`, `leveraction`, `revolver`, `shotgun`. [C for the list, A for behaviour]
3. **`AllowBatchCraft` defaults to true**; the craft window's quantity box shows unless a recipe sets it false. [A]
4. **Drainable inputs count uses:** `item 2 [Base.DuctTape]` takes 2 uses (repair recipes), and Twine has 5 uses (`UseDelta = 0.2`). [C from vanilla patterns, I for exact rounding]
5. **Feathers** are `Base.ChickenFeather`/`Base.TurkeyFeather`, tag `base:feather`, `ItemType = base:food`, from plucking (`maxFeather` 100 chicken, 120 turkey). [C]
