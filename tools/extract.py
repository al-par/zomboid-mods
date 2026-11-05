import io
import struct
import sys
from PIL import Image

import os; PACK = os.environ.get("PZPACK", r"C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\media\texturepacks\Tiles2x.pack")


def extract(names, outdir):
    d = open(PACK, "rb").read()
    p = 0

    def i32():
        nonlocal p
        v = struct.unpack_from("<i", d, p)[0]
        p += 4
        return v

    def s():
        nonlocal p
        n = i32()
        v = d[p:p + n].decode("latin1")
        p += n
        return v

    assert d[:4] == b"PZPK"
    p = 4
    i32()
    want = set(names)
    for _ in range(i32()):
        s()
        n = i32()
        i32()
        entries = []
        for _ in range(n):
            en = s()
            vals = struct.unpack_from("<8i", d, p)
            p += 32
            entries.append((en, vals))
        size = i32()
        start, end = p, p + size
        p = end
        hits = [(en, v) for en, v in entries if en in want]
        if hits:
            img = Image.open(io.BytesIO(d[start:end])).convert("RGBA")
            for en, (x, y, w, h, ox, oy, tw, th) in hits:
                canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
                canvas.paste(img.crop((x, y, x + w, y + h)), (ox, oy))
                canvas.save(f"{outdir}\\{en}.png")
                print(en, (x, y, w, h, ox, oy, tw, th))


extract(sys.argv[2:], sys.argv[1])

