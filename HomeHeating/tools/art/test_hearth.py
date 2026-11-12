import os
import sys
import time

from iso import render_tiles
from models import hearth, to_west
from preview import Scene, walls, flame

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)

styles = sys.argv[1:] or ["brick_neat", "brick_rough", "stone_neat", "stone_rough"]
for st in styles:
    t = time.time()
    g = hearth(st)
    r = render_tiles(g, [(0, 0), (1, 0)])
    tiles = [r[(i, 0)][0] for i in range(2)]
    w = to_west(hearth(st, west=True))
    r = render_tiles(w, [(0, 0), (0, 1)])
    wt = [r[(0, j)][0] for j in range(2)]
    sc = Scene(5, 5)
    walls(sc, 5, 5)
    sc.add(2, 0, tiles[0]); sc.add(3, 0, tiles[1]); sc.add(2, 0, flame("N"), 1)
    sc.add(0, 2, wt[0]); sc.add(0, 3, wt[1]); sc.add(0, 2, flame("W"), 1)
    sc.save(os.path.join(OUT, f"test_{st}.png"))
    for i, im in enumerate(tiles):
        im.save(os.path.join(OUT, f"{st}_N_{i}.png"))
    print(st, round(time.time() - t, 1), "s")
