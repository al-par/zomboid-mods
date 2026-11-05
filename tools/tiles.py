import struct
import sys

MEDIA = r"C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\media"


def read(path):
    d = open(path, "rb").read()
    p = 0

    def i32():
        nonlocal p
        v = struct.unpack_from("<i", d, p)[0]
        p += 4
        return v

    def line():
        nonlocal p
        e = d.index(b"\n", p)
        v = d[p:e].decode("latin-1")
        p = e + 1
        return v

    assert d[:4] == b"tdef", d[:4]
    p = 4
    version = i32()
    sheets = []
    for _ in range(i32()):
        name = line().strip()
        image = line()
        w, h, number, n = i32(), i32(), i32(), i32()
        tiles = []
        for _ in range(n):
            props = [(line(), line()) for _ in range(i32())]
            tiles.append(props)
        sheets.append({"name": name, "image": image, "w": w, "h": h, "number": number, "tiles": tiles})
    assert p == len(d), (p, len(d))
    return version, sheets


def write(path, sheets):
    out = bytearray(b"tdef")
    out += struct.pack("<ii", 1, len(sheets))
    for s in sheets:
        out += (s["name"] + "\n").encode("latin-1")
        out += (s["image"] + "\n").encode("latin-1")
        out += struct.pack("<iiii", s["w"], s["h"], s["number"], len(s["tiles"]))
        for props in s["tiles"]:
            out += struct.pack("<i", len(props))
            for k, v in props:
                out += (k + "\n").encode("latin-1")
                out += (v + "\n").encode("latin-1")
    open(path, "wb").write(bytes(out))


if __name__ == "__main__":
    wanted = sys.argv[1:]
    for f in ["newtiledefinitions.tiles", "tiledefinitions_b42chunkcaching.tiles"]:
        _, sheets = read(MEDIA + "\\" + f)
        for s in sheets:
            for i, props in enumerate(s["tiles"]):
                tn = f"{s['name']}_{i}"
                if tn in wanted:
                    print(f, tn, s["image"], s["w"], s["h"], s["number"])
                    for k, v in props:
                        print("   ", repr(k), repr(v))
