import os
import sys

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "out")
names = sys.argv[2:] or ["coal_S", "coal_E", "tower_S", "tower_W"]
parts = []
for n in names:
    a = Image.open(os.path.join(OUT, n + ".png"))
    g = Image.open(os.path.join(OUT, n + "_glow.png"))
    print(n, "glow px", int((np.array(g)[..., 3] > 20).sum()))
    b = a.copy()
    b.alpha_composite(g)
    for im in (a, b):
        bg = Image.new("RGBA", im.size, (70, 70, 74, 255))
        bg.alpha_composite(im)
        parts.append(bg.crop((24, 90, 104, 250)))
out = Image.new("RGBA", (80 * len(parts), 160))
for k, p in enumerate(parts):
    out.paste(p, (80 * k, 0))
out.resize((out.width * 3 // 2, out.height * 3 // 2), Image.LANCZOS).save(os.path.join(OUT, sys.argv[1]))
