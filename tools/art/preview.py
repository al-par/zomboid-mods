"""Compose rendered sprites into a small vanilla-style room for review."""
import os
import sys

from PIL import Image, ImageDraw

REF = os.path.join(os.environ["TEMP"], "hh_sprites")


def ref(name):
    return Image.open(os.path.join(REF, name + ".png")).convert("RGBA")


class Scene:
    def __init__(self, w=8, h=6, margin=(0, 0)):
        self.w, self.h = w, h
        self.ox = h * 64 + 32
        self.oy = 120
        self.img = Image.new("RGBA", ((w + h) * 64 + 64, (w + h) * 32 + 340), (48, 48, 52, 255))
        self.items = []
        d = ImageDraw.Draw(self.img)
        for i in range(w):
            for j in range(h):
                x, y = self.pos(i, j)
                shade = 118 + ((i + j) % 2) * 8
                d.polygon([(x + 64, y + 192), (x + 128, y + 224), (x + 64, y + 256), (x, y + 224)],
                          fill=(shade, shade - 26, shade - 52, 255))

    def pos(self, i, j):
        return self.ox + (i - j) * 64, self.oy + (i + j) * 32

    def add(self, i, j, sprite, order=0):
        self.items.append((i + j, order, i, j, sprite))

    def save(self, path, zoom=2):
        for _, _, i, j, sp in sorted(self.items, key=lambda t: (t[0], t[1])):
            x, y = self.pos(i, j)
            self.img.alpha_composite(sp, (int(x), int(y)))
        im = self.img
        if zoom != 1:
            im = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
        im.save(path)


def flame(dir_):
    f = ref("Fire_01_12").resize((64, 128))
    c = Image.new("RGBA", (128, 256), (0, 0, 0, 0))
    c.alpha_composite(f, (54, 80) if dir_ == "N" else (2, 80))
    return c


def walls(sc, n_len, w_len):
    for i in range(n_len):
        sc.add(i, 0, ref("walls_interior_house_02_1"), -1)
    for j in range(w_len):
        sc.add(0, j, ref("walls_interior_house_02_0"), -1)
