import os
import time

from PIL import Image

from iso import render_tile
from models import coal_heater, tower_heater
from preview import Scene, ref

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)

FACINGS = ["S", "E", "N", "W"]
sprites = {}
for name, fn in (("coal", coal_heater), ("tower", tower_heater)):
    for f in FACINGS:
        t = time.time()
        g = fn(f)
        img, _ = render_tile(g, 0, 0)
        glow, _ = render_tile(g, 0, 0, emissive_only=True)
        sprites[(name, f)] = (img, glow)
        img.save(os.path.join(OUT, f"{name}_{f}.png"))
        glow.save(os.path.join(OUT, f"{name}_{f}_glow.png"))
        print(name, f, round(time.time() - t, 1), "s")

for lit in (False, True):
    sc = Scene(9, 4)
    for k, f in enumerate(FACINGS):
        for row, name in enumerate(("coal", "tower")):
            img, glow = sprites[(name, f)]
            c = img.copy()
            if lit:
                c.alpha_composite(glow)
            sc.add(k * 2, row * 2 + 1, c)
    sc.add(8, 1, ref("appliances_cooking_01_16"))
    sc.add(8, 3, ref("appliances_refrigeration_01_0"))
    sc.save(os.path.join(OUT, f"test_heaters_{'lit' if lit else 'off'}.png"))
