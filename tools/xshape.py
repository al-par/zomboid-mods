"""Print a mesh's vertices sorted along its longest axis, to see its shape."""
import re
import sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"Mesh (\S+) \{\s*(\d+);", text)
n = int(m.group(2))
pts = [tuple(map(float, p)) for p in re.findall(r"(-?\d+\.\d+);(-?\d+\.\d+);(-?\d+\.\d+);[,;]", text[m.end():])[:n]]
axis = max(range(3), key=lambda i: max(p[i] for p in pts) - min(p[i] for p in pts))
for p in sorted(pts, key=lambda p: p[axis])[::max(1, n // 24)]:
    print(" ".join(f"{v:7.3f}" for v in p))
