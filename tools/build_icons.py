"""Cut the 3x3 icon sheet (flat magenta background) into 32x32 item icons and a preview image.

Usage: python build_icons.py   (run from anywhere; paths are relative to this file)
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.join(HERE, "icons_sheet.jpg")
OUT = os.path.join(HERE, "..", "42", "media", "textures")
PREVIEW = os.path.join(HERE, "preview_icons.png")
MOD_ICON = os.path.join(HERE, "..", "42", "icon.png")

# Grid order of the sheet, left to right, top to bottom.
NAMES = [
    "CA_Bow", "CA_BowStave", "CA_Bowstring",
    "CA_Arrow", "CA_ArrowShaft", "CA_ArrowheadFlint",
    "CA_ArrowheadBone", "CA_ArrowheadMetal", "CA_ArcheryMag",
]
SIZE = 32
MARGIN = 1
OUTLINE = (40, 28, 18)


def key_out(rgb):
    """Alpha from distance to magenta, then remove the magenta tint left on edge pixels."""
    rgb = rgb.astype(np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dist = np.sqrt((r - 255) ** 2 + g ** 2 + (b - 255) ** 2)
    alpha = np.clip((dist - 90) / 110, 0, 1)
    spill = np.clip(np.minimum(r, b) - g, 0, None)
    rgb[..., 0] -= spill
    rgb[..., 2] -= spill
    rgba = np.dstack([np.clip(rgb, 0, 255), alpha * 255])
    return rgba.astype(np.uint8)


def keep_main_shape(rgba):
    """Drop specks: keep pieces at least 5% the size of the largest one."""
    labels, n = ndimage.label(rgba[..., 3] > 40)
    if n > 1:
        sizes = ndimage.sum(np.ones_like(labels), labels, range(1, n + 1))
        keep = np.isin(labels, 1 + np.nonzero(sizes >= sizes.max() * 0.05)[0])
        grown = ndimage.binary_dilation(keep, iterations=3)
        rgba[..., 3] = np.where(grown, rgba[..., 3], 0)
    return rgba


def add_outline(icon):
    """A 1-pixel dark outline around the shape, like vanilla inventory icons."""
    a = np.asarray(icon).copy()
    solid = a[..., 3] >= 96
    ring = ndimage.binary_dilation(solid) & ~solid
    a[ring, :3] = OUTLINE
    a[ring, 3] = np.maximum(a[ring, 3], 200)
    return Image.fromarray(a, "RGBA")


def cut(cell, size=SIZE):
    rgba = keep_main_shape(key_out(np.asarray(cell.convert("RGB"))))
    ys, xs = np.nonzero(rgba[..., 3] > 40)
    rgba = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = rgba.shape[:2]
    side = max(h, w)
    square = np.zeros((side, side, 4), np.uint8)
    square[(side - h) // 2:(side - h) // 2 + h, (side - w) // 2:(side - w) // 2 + w] = rgba
    img = Image.fromarray(square, "RGBA")
    inner = size - 2 * MARGIN
    small = img.resize((inner, inner), Image.LANCZOS)
    icon = Image.new("RGBA", (size, size))
    icon.alpha_composite(small, (MARGIN, MARGIN))
    a = np.asarray(icon).copy()
    a[..., 3] = np.where(a[..., 3] < 24, 0, a[..., 3])
    return add_outline(Image.fromarray(a, "RGBA"))


def main():
    sheet = Image.open(SHEET)
    cw, ch = sheet.width // 3, sheet.height // 3
    icons = []
    for i, name in enumerate(NAMES):
        x, y = (i % 3) * cw, (i // 3) * ch
        icon = cut(sheet.crop((x, y, x + cw, y + ch)))
        icon.save(os.path.join(OUT, f"Item_{name}.png"))
        icons.append(icon)
        if name == "CA_Bow":
            cut(sheet.crop((x, y, x + cw, y + ch)), size=64).save(MOD_ICON)

    scale, pad = 4, 8
    tile = SIZE * scale + pad
    preview = Image.new("RGBA", (len(icons) * tile + pad, tile * 2 + pad), (64, 64, 64, 255))
    for i, icon in enumerate(icons):
        preview.alpha_composite(icon.resize((SIZE * scale, SIZE * scale), Image.NEAREST), (pad + i * tile, pad))
        preview.alpha_composite(icon, (pad + i * tile + (SIZE * scale - SIZE) // 2, tile + pad + 40))
    preview.save(PREVIEW)
    print("wrote", len(icons), "icons and", PREVIEW)


if __name__ == "__main__":
    main()
