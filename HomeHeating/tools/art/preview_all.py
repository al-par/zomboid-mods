"""Review sheets: every hearth look on both walls, and both heaters in every facing, next to vanilla."""
import os
import sys

from PIL import Image, ImageDraw

from iso import render_tile, render_tiles
from models import coal_heater, hearth, to_west, tower_heater, tower_heater_crafted
from preview import Scene, flame, ref, walls

OUT = os.path.join(os.path.dirname(__file__), "out")
STYLES = ["stone_rough", "stone_neat", "brick_rough", "brick_neat"]

want = sys.argv[1:] or ["hearths", "heaters"]

MATCH = {"stone_rough": ("walls_logs_97", "walls_logs_96"), "stone_neat": ("walls_logs_97", "walls_logs_96"),
         "brick_rough": ("walls_exterior_house_01_21", "walls_exterior_house_01_20"),
         "brick_neat": ("walls_exterior_house_01_5", "walls_exterior_house_01_4")}

sc = Scene(13, 13)
sc.add(0, 0, ref("walls_interior_house_02_1"), -1)
sc.add(0, 0, ref("walls_interior_house_02_0"), -1)
for k, st in enumerate(STYLES if "hearths" in want else []):
    for d in range(3):
        sc.add(1 + k * 3 + d, 0, ref(MATCH[st][0]), -1)
        sc.add(0, 1 + k * 3 + d, ref(MATCH[st][1]), -1)
    g = hearth(st)
    r = render_tiles(g, [(0, 0), (1, 0)])
    i = 1 + k * 3
    sc.add(i, 0, r[(0, 0)][0]); sc.add(i + 1, 0, r[(1, 0)][0])
    if k % 2:
        sc.add(i, 0, flame("N"), 1)
    r = render_tiles(to_west(hearth(st, west=True)), [(0, 0), (0, 1)])
    j = 1 + k * 3
    sc.add(0, j, r[(0, 0)][0]); sc.add(0, j + 1, r[(0, 1)][0])
    if not k % 2:
        sc.add(0, j, flame("W"), 1)
    print(st)
sc.add(11, 2, ref("appliances_cooking_01_16"))
sc.add(2, 11, ref("crafted_05_4"))
if "hearths" in want:
    sc.save(os.path.join(OUT, "sheet_hearths.png"), zoom=1)

def cell(sprite, label):
    c = Image.new("RGBA", (128, 256), (48, 48, 52, 255))
    d = ImageDraw.Draw(c)
    d.polygon([(64, 192), (128, 224), (64, 256), (0, 224)], fill=(122, 96, 70, 255))
    c.alpha_composite(sprite)
    d.text((4, 4), label, fill=(230, 230, 230, 255))
    return c


if "heaters" in want:
    cells = []
    for name, fn in (("coal", coal_heater), ("store", tower_heater), ("crafted", tower_heater_crafted)):
        row = []
        for f in ["S", "E", "N", "W"]:
            g = fn(f)
            img, _ = render_tile(g, 0, 0)
            glow, _ = render_tile(g, 0, 0, emissive_only=True)
            lit = img.copy()
            lit.alpha_composite(glow)
            row += [cell(img, f"{name} {f} off"), cell(lit, f"{name} {f} on")]
        cells.append(row)
        print(name)
    cells.append([cell(ref(n), lbl) for n, lbl in (
        ("crafted_01_26", "vanilla drum"), ("crafted_05_4", "barrel oven"),
        ("appliances_cooking_01_16", "antique stove"), ("appliances_refrigeration_01_0", "fridge"))])
    sheet = Image.new("RGBA", (128 * 8, 256 * len(cells)), (48, 48, 52, 255))
    for r, row in enumerate(cells):
        for c, im in enumerate(row):
            sheet.alpha_composite(im, (128 * c, 256 * r))
    sheet.save(os.path.join(OUT, "sheet_heaters.png"))
