import io
import os
import struct

from PIL import Image

import tiles

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
MOD = r"C:\Users\alpar\Zomboid\mods\SensibleLivestock\42\media"

SHEET = "sensiblelivestock_walls_01"
PACK_NAME = "SensibleLivestock"

# The vanilla short brick wall is the full wall with every column's top lowered by 88 px,
# and the stone wall's top edge is a 3 px dark cap that has to move down with it.
TILE_SHIFT = 88
TILE_CAP = 3
ICON_SHIFT = 16
ICON_CAP = 1

SOURCES = ["walls_logs_96", "walls_logs_97", "walls_logs_98", "walls_logs_99"]


def cut(img, shift, cap):
    img = img.convert("RGBA")
    w, h = img.size
    src = img.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst = out.load()
    for x in range(w):
        top = next((y for y in range(h) if src[x, y][3] > 0), None)
        if top is None:
            continue
        for y in range(top + shift, h):
            if y < top + shift + cap:
                dst[x, y] = src[x, y - shift]
            else:
                dst[x, y] = src[x, y]
    return out


def build_tiles():
    sprites = [cut(Image.open(os.path.join(SRC, n + ".png")), TILE_SHIFT, TILE_CAP) for n in SOURCES]
    for i, s in enumerate(sprites):
        s.save(os.path.join(HERE, f"out_{SHEET}_{i}.png"))
    return sprites


def build_icon():
    icon = cut(Image.open(os.path.join(SRC, "Build_WallStone.png")), ICON_SHIFT, ICON_CAP)
    left, top, right, bottom = icon.getbbox()
    centered = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    height = bottom - top
    centered.paste(icon.crop((left, top, right, bottom)), (left, (icon.height - height) // 2))
    path = os.path.join(MOD, "textures", "Build_SL_StoneWallLow.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    centered.save(path)
    return centered


def write_pack(sprites):
    page_w, page_h = 256, 512
    page = Image.new("RGBA", (page_w, page_h), (0, 0, 0, 0))
    entries = []
    x = y = row_h = 0
    for i, s in enumerate(sprites):
        left, top, right, bottom = s.getbbox()
        piece = s.crop((left, top, right, bottom))
        if x + piece.width > page_w:
            x, y, row_h = 0, y + row_h + 2, 0
        page.paste(piece, (x, y))
        entries.append((f"{SHEET}_{i}", x, y, piece.width, piece.height, left, top, s.width, s.height))
        x += piece.width + 2
        row_h = max(row_h, piece.height)
    assert y + row_h <= page_h

    png = io.BytesIO()
    page.save(png, "PNG")
    png = png.getvalue()

    def string(s):
        b = s.encode("latin-1")
        return struct.pack("<i", len(b)) + b

    out = bytearray(b"PZPK")
    out += struct.pack("<ii", 1, 1)
    out += string(PACK_NAME + "0")
    out += struct.pack("<ii", len(entries), 1)
    for name, *vals in entries:
        out += string(name)
        out += struct.pack("<8i", *vals)
    out += struct.pack("<i", len(png)) + png

    path = os.path.join(MOD, "texturepacks", PACK_NAME + ".pack")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(bytes(out))
    page.save(os.path.join(HERE, "out_page.png"))
    return entries


def write_tiledefs():
    stone = [("MaterialType", "Stone")]
    props = [
        [("HoppableW", ""), ("WallW", ""), ("wall", "")] + stone,
        [("HoppableN", ""), ("WallN", ""), ("wall", "")] + stone,
        [("CornerNorthWall", f"{SHEET}_1"), ("CornerWestWall", f"{SHEET}_0"),
         ("HoppableN", ""), ("HoppableW", ""), ("WallNW", ""), ("wall", "")] + stone,
        [("WallSE", ""), ("wall", "")] + stone,
    ]
    sheet = {"name": SHEET, "image": SHEET + ".png", "w": 4, "h": 1, "number": 1, "tiles": props}
    path = os.path.join(MOD, "sensiblelivestock_tiles.tiles")
    tiles.write(path, [sheet])
    _, check = tiles.read(path)
    assert check[0]["tiles"] == props
    return path


if __name__ == "__main__":
    sprites = build_tiles()
    build_icon()
    for e in write_pack(sprites):
        print(e)
    print(write_tiledefs())
