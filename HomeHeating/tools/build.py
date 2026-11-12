"""Render every Home Heating sprite and write the .pack, .tiles, depth assignments and build icons.

Tile layout:
1. homeheating_<family><W>_<style>: index = ((wall * 2 + kit) * 2 + lit) * 4 + i, wall 0 = N, 1 = W,
   i = square along the wall. lit = 1 sprites are the lit overlays.
2. homeheating_misc: coal heater 0-3 (front S, E, N, W), its glow 4-7, electric heater 8-11,
   its glow 12-15, pot bar build cursor 16 (N) and 17 (W).
"""
import io
import os
import struct
import sys
from concurrent.futures import ProcessPoolExecutor

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "art"))
sys.path.insert(0, r"C:\Users\alpar\Zomboid\mods\SensibleLivestock\tools")

MOD = os.path.normpath(os.path.join(HERE, ".."))
MEDIA42 = os.path.join(MOD, "42", "media")
COMMON = os.path.join(MOD, "common", "media")
CACHE = os.path.join(HERE, "art", "out", "sprites")
PACK_NAME = "HomeHeating"
TILEDEF = "homeheating_tiles"

FAMILIES = ("hood", "range", "oven")
WIDTHS = (3, 2)
STYLES = ("brick_rough", "brick_neat", "stone_rough", "stone_neat")
FRONTS = ("S", "E", "N", "W")
MISC = "homeheating_misc"


def hearth_sheet(family, W, style):
    return f"homeheating_{family}{W}_{style}"


def hearth_index(west, kit, lit, i):
    return ((int(west) * 2 + int(kit)) * 2 + int(lit)) * 4 + i


def job_hearth(args):
    import hearths
    family, W, style, west = args
    r = hearths.render_all(family, W, style, west)
    out = {}
    for (kit, lit), tiles in r.items():
        for i, im in enumerate(tiles):
            out[f"{hearth_sheet(family, W, style)}_{hearth_index(west, kit, lit, i)}"] = im
    return out


def job_heater(args):
    from iso import render_tile
    from models import coal_heater, tower_heater_crafted
    kind, k = args
    front = FRONTS[k]
    fn, base = (coal_heater, 0) if kind == "coal" else (tower_heater_crafted, 8)
    g = fn(front)
    img, _ = render_tile(g, 0, 0)
    glow, _ = render_tile(g, 0, 0, emissive_only=True)
    return {f"{MISC}_{base + k}": img, f"{MISC}_{base + 4 + k}": glow}


def job_ghost(west):
    import hearths
    g, P = hearths.kit_only(3, "hood")
    tiles = hearths.render_grid(g, 3, west)
    return {f"{MISC}_{17 if west else 16}": tiles[hearths.fire_tile("hood", 3)]}


def render_everything():
    os.makedirs(CACHE, exist_ok=True)
    jobs = [(job_hearth, (f, W, s, w)) for f in FAMILIES for W in WIDTHS for s in STYLES for w in (False, True)]
    jobs += [(job_heater, (kind, k)) for kind in ("coal", "electric") for k in range(4)]
    jobs += [(job_ghost, w) for w in (False, True)]
    sprites = {}
    with ProcessPoolExecutor(min(30, os.cpu_count() or 4)) as ex:
        futs = [ex.submit(fn, a) for fn, a in jobs]
        for f in futs:
            sprites.update(f.result())
    for name, im in sprites.items():
        im.save(os.path.join(CACHE, name + ".png"))
    return sprites


def load_cached():
    return {os.path.splitext(n)[0]: Image.open(os.path.join(CACHE, n)).convert("RGBA")
            for n in os.listdir(CACHE) if n.endswith(".png")}


def write_pack(sprites, page_size=2048):
    pieces = []
    for name in sorted(sprites):
        s = sprites[name]
        bb = s.getbbox()
        if bb is None:
            continue
        pieces.append((name, s.crop(bb), bb[0], bb[1], s.width, s.height))
    pieces.sort(key=lambda p: -p[1].height)
    pages, cur = [], None
    x = y = row_h = 0
    for name, piece, ox, oy, w, h in pieces:
        if cur is None or x + piece.width > page_size:
            x, y, row_h = 0, (y + row_h + 2) if cur is not None else 0, 0
        if cur is None or y + piece.height > page_size:
            cur = (Image.new("RGBA", (page_size, page_size), (0, 0, 0, 0)), [])
            pages.append(cur)
            x = y = row_h = 0
        cur[0].paste(piece, (x, y))
        cur[1].append((name, x, y, piece.width, piece.height, ox, oy, w, h))
        x += piece.width + 2
        row_h = max(row_h, piece.height)

    def string(s):
        b = s.encode("latin-1")
        return struct.pack("<i", len(b)) + b

    out = bytearray(b"PZPK")
    out += struct.pack("<ii", 1, len(pages))
    for n, (page, entries) in enumerate(pages):
        out += string(f"{PACK_NAME}{n}")
        out += struct.pack("<ii", len(entries), 1)
        for name, *vals in entries:
            out += string(name)
            out += struct.pack("<8i", *vals)
        png = io.BytesIO()
        page.save(png, "PNG", optimize=True)
        png = png.getvalue()
        out += struct.pack("<i", len(png)) + png
    path = os.path.join(MEDIA42, "texturepacks", PACK_NAME + ".pack")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(bytes(out))
    return path, len(pages), len(pieces)


def tile_props():
    import tiles
    sheets = []
    for f in FAMILIES:
        for W in WIDTHS:
            for s in STYLES:
                props = []
                for idx in range(32):
                    i = idx % 4
                    lit = (idx // 4) % 2
                    if i >= W or lit:
                        props.append([])
                        continue
                    props.append([("BlocksPlacement", ""), ("CustomName", "Hearth"), ("MaterialType", "Stone"),
                                  ("solidtrans", "")])
                sheets.append({"name": hearth_sheet(f, W, s), "image": hearth_sheet(f, W, s) + ".png",
                               "w": 8, "h": 4, "number": 1, "tiles": props})
    misc = []
    for k, front in enumerate(FRONTS):
        misc.append([("BlocksPlacement", ""), ("ContainerCapacity", "15"), ("ContainerCloseSound", "BBQDoorClose"),
                     ("ContainerOpenSound", "BBQDoorOpen"), ("ContainerPosition", "Low"),
                     ("ContainerPutSound", "BBQTransferItem"), ("ContainerTakeSound", "BBQTransferItem"),
                     ("CustomName", "Coal Heater"), ("Facing", front), ("IsoType", "IsoFireplace"),
                     ("Material", "MetalPlates"), ("MaterialType", "Metal_Light"), ("container", "woodstove"),
                     ("solidtrans", "")])
    misc += [[] for _ in range(4)]
    for k, front in enumerate(FRONTS):
        misc.append([("BlocksPlacement", ""), ("CustomName", "Electric Heater"), ("Facing", front),
                     ("Material", "MetalPlates"), ("MaterialType", "Metal_Light"), ("solidtrans", "")])
    misc += [[] for _ in range(4)]
    misc += [[], []]
    misc += [[] for _ in range(6)]
    sheets.append({"name": MISC, "image": MISC + ".png", "w": 8, "h": 3, "number": 1, "tiles": misc})
    path = os.path.join(MEDIA42, TILEDEF + ".tiles")
    tiles.write(path, sheets)
    _, check = tiles.read(path)
    assert [c["tiles"] for c in check] == [s["tiles"] for s in sheets]
    return path


def write_depth():
    os.makedirs(COMMON, exist_ok=True)
    open(os.path.join(COMMON, "tileGeometry.txt"), "w", newline="\n").write("tileGeometry\n{\n    VERSION = 2,\n}\n")
    lines = []
    for f in FAMILIES:
        for W in WIDTHS:
            for s in STYLES:
                for west in (False, True):
                    for kit in (0, 1):
                        for lit in (0, 1):
                            for i in range(W):
                                src = "fixtures_fireplaces_01_5" if west else "fixtures_fireplaces_01_0"
                                lines.append(f"{hearth_sheet(f, W, s)}_{hearth_index(west, kit, lit, i)} = {src}")
    barrel = {"S": "crafted_05_7", "E": "crafted_05_6", "N": "crafted_05_4", "W": "crafted_05_5"}
    for k, front in enumerate(FRONTS):
        for base in (0, 4, 8, 12):
            lines.append(f"{MISC}_{base + k} = {barrel[front]}")
    lines.append(f"{MISC}_16 = fixtures_fireplaces_01_0")
    lines.append(f"{MISC}_17 = fixtures_fireplaces_01_5")
    body = "tileDepthTextureAssignments\n{\n    VERSION = 1,\n" + "".join(f"    {l},\n" for l in lines) + "}\n"
    open(os.path.join(COMMON, "tileDepthTextureAssignments.txt"), "w", newline="\n").write(body)


def icon_from(tiles, west=False):
    n = len(tiles)
    im = Image.new("RGBA", (64 * n + 64, 256 + 32 * (n - 1)), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        im.alpha_composite(t, ((64 * (n - 1) - 64 * i) if west else 64 * i, 32 * i))
    im = im.crop(im.getbbox())
    s = 120 / max(im.size)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    out.alpha_composite(im, ((128 - im.width) // 2, (128 - im.height) // 2))
    return out


def write_icons(sprites):
    d = os.path.join(MEDIA42, "textures")
    os.makedirs(d, exist_ok=True)
    for f in FAMILIES:
        for W in WIDTHS:
            for mat in ("brick", "stone"):
                sheet = hearth_sheet(f, W, mat + "_rough")
                tiles = [sprites[f"{sheet}_{hearth_index(False, False, False, i)}"] for i in range(W)]
                icon_from(tiles).save(os.path.join(d, f"Build_HH_{f.capitalize()}{W}_{mat.capitalize()}.png"))
    icon_from([sprites[f"{MISC}_0"]]).save(os.path.join(d, "Build_HH_CoalHeater.png"))
    icon_from([sprites[f"{MISC}_8"]]).save(os.path.join(d, "Build_HH_ElectricHeater.png"))
    sheet = hearth_sheet("hood", 3, "brick_rough")
    icon_from([sprites[f"{sheet}_{hearth_index(False, True, False, i)}"] for i in range(3)]).save(
        os.path.join(d, "Build_HH_PotBar.png"))


TITLES = {"hood": "Hooded Hearth", "range": "Raised Hearth", "oven": "Bake-Oven Hearth"}


def entity(name, display, icon, faces, recipe, on_create=None, on_is_valid=None):
    """faces: {face: [row, ...]}, each row a list of sprites along x."""
    sc = ["        component SpriteConfig", "        {"]
    if on_is_valid:
        sc.append(f"            OnIsValid = {on_is_valid},")
    if on_create:
        sc.append(f"            OnCreate = {on_create},")
    for face, rows in faces.items():
        sc += [f"            face {face}", "            {", "                layer", "                {"]
        sc += [f"                    row = {' '.join(r)}," for r in rows]
        sc += ["                }", "            }"]
    sc.append("        }")
    skin = [f"        entity ES_{name}", "        {", "            LuaWindowClass = ISEntityWindow,",
            f"            DisplayName = {display},", f"            Icon = {icon},", "        }"]
    body = [f"    entity {name}", "    {", "        component UiConfig", "        {", "            xuiSkin = default,",
            f"            entityStyle = ES_{name},", "            uiEnabled = false,", "        }"] + sc + \
        ["        component CraftRecipe", "        {"] + [f"            {l}" for l in recipe] + ["        }", "    }"]
    return skin, body


def write_scripts():
    skins, bodies = [], []
    for f in FAMILIES:
        for W in WIDTHS:
            for mat in ("brick", "stone"):
                s = hearth_sheet(f, W, mat + "_rough")
                n = [f"{s}_{hearth_index(False, 0, 0, i)}" for i in range(W)]
                w = [f"{s}_{hearth_index(True, 0, 0, i)}" for i in range(W)]
                block = ("item 18 [Base.ClayBrick]," if W == 3 else "item 12 [Base.ClayBrick],") if mat == "brick" else \
                    ("item 15 [Base.StoneBlock]," if W == 3 else "item 10 [Base.StoneBlock],")
                recipe = ["timedAction = BuildWallNoTool,", f"time = {400 if W == 3 else 300},", "category = Masonry,",
                          "SkillRequired = Masonry:4,", "xpAward = Masonry:40,", f"Tooltip = Tooltip_craft_HH_{f}Desc,",
                          "inputs", "{",
                          "    item 1 tags[base:masonstrowel] mode:keep flags[Prop1;MayDegradeLight],",
                          f"    item {6 if W == 3 else 4} tags[base:concrete] flags[DontRecordInput],",
                          "    " + block, "    item 1 [Base.MetalBar],", "}"]
                name = f"HH_{f.capitalize()}{W}_{mat.capitalize()}"
                display = f"{TITLES[f]}, {W} Wide ({mat.capitalize()})"
                sk, bd = entity(name, display, f"Build_{name}", {"N": [n], "W": [[x] for x in w]}, recipe,
                                on_create="HomeHeating.Build.hearthOnCreate")
                skins += sk
                bodies += bd
    # entity face -> sprite front, copied from the barrel oven: faces N and S show the opposite front
    coal = {"W": f"{MISC}_3", "N": f"{MISC}_0", "E": f"{MISC}_1", "S": f"{MISC}_2"}
    sk, bd = entity("HH_CoalHeater", "Coal Heater", "Build_HH_CoalHeater", {k: [[v]] for k, v in coal.items()}, [
        "timedAction = BuildMetalStructureMedium,", "time = 300,", "SkillRequired = MetalWelding:6,",
        "xpAward = MetalWelding:40,", "category = Welding,", "Tags = Welding,", "Tooltip = Tooltip_craft_HH_coalHeaterDesc,",
        "inputs", "{",
        "    item 6 [Base.BlowTorch] flags[DontRecordInput],",
        "    item 1 tags[base:weldingmask] mode:keep,",
        "    item 1 [Base.MetalDrum],",
        "    item 1 [Base.Pot;Base.PotForged;Base.Saucepan;Base.SaucepanCopper;Base.Kettle;Base.BucketEmpty;Base.BucketForged],",
        "    item 1 [Base.SheetMetal],", "    item 2 [Base.SmallSheetMetal],", "    item 2 [Base.Hinge],",
        "    item 2 [Base.MetalBar],", "    item 1 [Base.MetalPipe],",
        "    item 6 [Base.WeldingRods] flags[DontRecordInput],", "}"], on_create="HomeHeating.Build.coalOnCreate")
    skins += sk
    bodies += bd
    elec = {"W": f"{MISC}_11", "N": f"{MISC}_8", "E": f"{MISC}_9", "S": f"{MISC}_10"}
    sk, bd = entity("HH_ElectricHeater", "Electric Heater", "Build_HH_ElectricHeater", {k: [[v]] for k, v in elec.items()}, [
        "timedAction = BuildLowNoTool,", "time = 250,", "SkillRequired = Electricity:5,", "xpAward = Electricity:40,",
        "category = Miscellaneous,", "Tooltip = Tooltip_craft_HH_electricHeaterDesc,",
        "inputs", "{",
        "    item 1 tags[base:screwdriver] mode:keep flags[MayDegradeLight],",
        "    item 1 tags[base:pliers] mode:keep flags[MayDegradeLight],",
        "    item 1 [Base.BlowerFan],", "    item 2 [Base.SheetMetal],", "    item 2 [Base.SmallSheetMetal],",
        "    item 5 [Base.Wire],", "    item 6 [Base.ElectricWire],", "    item 6 [Base.ElectronicsScrap],",
        "    item 10 [Base.Screws],", "}"], on_create="HomeHeating.Build.electricOnCreate")
    skins += sk
    bodies += bd
    sk, bd = entity("HH_PotBar", "Hearth Pot Bar", "Build_HH_PotBar", {"N": [[f"{MISC}_16"]], "W": [[f"{MISC}_17"]]}, [
        "timedAction = BuildWallNoTool,", "time = 120,", "category = Masonry,", "Tooltip = Tooltip_craft_HH_potBarDesc,",
        "inputs", "{", "    item 2 [Base.SteelBar],", "    item 1 [Base.LargeHook],", "}"],
        on_create="HomeHeating.Build.potBarOnCreate", on_is_valid="HomeHeating.Build.potBarOnIsValid")
    skins += sk
    bodies += bd
    text = "module Base\n{\n    xuiSkin default\n    {\n" + "\n".join(skins) + "\n    }\n\n" + "\n".join(bodies) + "\n}\n"
    d = os.path.join(MEDIA42, "scripts", "entities")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "HH_entities.txt")
    open(path, "w", newline="\n").write(text)
    return path


if __name__ == "__main__":
    if "--scripts" in sys.argv:
        print(write_scripts())
        sys.exit()
    sprites = load_cached() if "--cached" in sys.argv else render_everything()
    print("sprites", len(sprites))
    print(write_pack(sprites))
    print(tile_props())
    write_depth()
    write_icons(sprites)
