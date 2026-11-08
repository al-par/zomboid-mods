"""Print the frame matrix, vertex count and bounding box of each mesh in DirectX .X text files."""
import re
import sys


def bounds(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    frames = re.findall(r"FrameTransformMatrix \{\s*([^;]+);;", text)
    for m in re.finditer(r"Mesh (\S+) \{\s*(\d+);", text):
        name, n = m.group(1), int(m.group(2))
        body = text[m.end():]
        pts = re.findall(r"(-?\d+\.\d+);(-?\d+\.\d+);(-?\d+\.\d+);[,;]", body)[:n]
        xs, ys, zs = ([float(p[i]) for p in pts] for i in range(3))
        print(f"{path.split(chr(92))[-1]}  mesh={name} verts={n}")
        print(f"  x {min(xs):.3f}..{max(xs):.3f}  y {min(ys):.3f}..{max(ys):.3f}  z {min(zs):.3f}..{max(zs):.3f}")
    for f in frames:
        print("  frame", ",".join(f"{float(v):.3f}" for v in f.split(",")))
    tex = re.findall(r'TextureFilename \{\s*"([^"]+)"', text)
    print("  textures", tex)


for p in sys.argv[1:]:
    bounds(p)
