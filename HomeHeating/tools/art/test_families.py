"""Review sheet: each family x width for given styles, N wall, (no kit, unlit) and (kit, lit)."""
import sys
from concurrent.futures import ProcessPoolExecutor

from PIL import Image, ImageDraw

import hearths


def job(args):
    family, W, style, west = args
    r = hearths.render_all(family, W, style, west)
    return args, {k: [im.copy() for im in v] for k, v in r.items()}


def strip(tiles, west):
    n = len(tiles)
    im = Image.new("RGBA", (64 * n + 64, 256 + 32 * (n - 1)), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        if west:
            im.alpha_composite(t, (64 * (n - 1) - 64 * i, 32 * i))
        else:
            im.alpha_composite(t, (64 * i, 32 * i))
    return im


if __name__ == "__main__":
    styles = sys.argv[1].split(",")
    tag = sys.argv[2]
    west = len(sys.argv) > 3 and sys.argv[3] == "W"
    jobs = [(f, W, s, west) for s in styles for f in hearths.FAMILIES for W in (3, 2)]
    with ProcessPoolExecutor(min(len(jobs), 24)) as ex:
        res = dict(ex.map(job, jobs))
    cols = [(False, False), (False, True), (True, False), (True, True)]
    cw, ch = 64 * 4 + 20, 256 + 64 + 30
    sheet = Image.new("RGBA", (cw * len(cols), ch * len(jobs)), (58, 62, 58, 255))
    d = ImageDraw.Draw(sheet)
    for r, j in enumerate(jobs):
        for c, k in enumerate(cols):
            sheet.alpha_composite(strip(res[j][k], west), (c * cw + 4, r * ch + 20))
            d.text((c * cw + 4, r * ch + 4), f"{j[0]} {j[1]}w {j[2]} kit={k[0]} lit={k[1]}", fill=(255, 255, 255, 255))
    sheet.save(f"out/fam_{tag}.png")
