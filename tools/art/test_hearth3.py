import os
import sys
import time

from PIL import Image, ImageDraw

from hearths import render
from preview import ref

OUT = os.path.join(os.path.dirname(__file__), "out")
WALL = {"stone_rough": ("walls_logs_97", "walls_logs_96"), "stone_neat": ("walls_logs_97", "walls_logs_96"),
        "brick_rough": ("walls_exterior_house_01_21", "walls_exterior_house_01_20"),
        "brick_neat": ("walls_exterior_house_01_5", "walls_exterior_house_01_4")}


def floor(d, x, y):
    d.polygon([(x + 64, y + 192), (x + 128, y + 224), (x + 64, y + 256), (x, y + 224)], fill=(122, 96, 70, 255))


def compose(tiles, wall, west):
    """Three squares of a hearth on the floor in front of five squares of matching wall."""
    im = Image.new("RGBA", (128 + 6 * 64, 256 + 6 * 32), (48, 48, 52, 255))
    d = ImageDraw.Draw(im)
    pos = []
    for k in range(-1, 4):
        if west:
            x, y = 64 * 2 - k * 64, 32 + k * 32
        else:
            x, y = 64 * 2 + k * 64, 32 + k * 32
        pos.append((k, x, y))
        for j in range(3):
            floor(d, x + (j * 64 if west else -j * 64), y + j * 32)
    for k, x, y in pos:
        im.alpha_composite(ref(wall), (x, y))
    for k, x, y in pos:
        if 0 <= k < 3:
            im.alpha_composite(tiles[k], (x, y))
    return im


styles = sys.argv[1:] or ["stone_rough", "stone_neat", "brick_rough", "brick_neat"]
tag = os.environ.get("TAG", "a")
for st in styles:
    t = time.time()
    row = []
    for west in (False, True):
        for lit in (False, True):
            tiles = render(st, west, lit)
            row.append(compose(tiles, WALL[st][1 if west else 0], west))
    sheet = Image.new("RGBA", (row[0].width * 4, row[0].height), (48, 48, 52, 255))
    for k, im in enumerate(row):
        sheet.alpha_composite(im, (k * row[0].width, 0))
    sheet.save(os.path.join(OUT, f"h3_{st}_{tag}.png"))
    print(st, round(time.time() - t, 1), "s")
