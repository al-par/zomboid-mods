"""Generate Sensible Archery's meshes (DirectX .X text) and texture, plus a preview render.

Sizes and orientations match what the item scripts and the hand attachment expect:
held bow limbs on a diagonal in the XZ plane bending toward -Y, ground bow along Y bending
toward +Z, arrows along Y with the head at +Y.

Usage: python build_models.py   (paths are relative to this file)
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "..", "42", "media")
MESH_DIR = os.path.join(MEDIA, "models_X", "weapons", "sensiblearchery")
TEX_DIR = os.path.join(MEDIA, "textures", "weapons", "sensiblearchery")
TEX_NAME = "SA_Archery"
PREVIEW = os.path.join(HERE, "preview_models.png")

TEX = 128
# Texture columns (u ranges, in pixels). Each material spans the full height, so a flipped V still lands
# on the same material.
COLS = {
    "bow": (0, 32),
    "grip": (32, 48),
    "string": (48, 56),
    "shaft": (56, 80),
    "feather": (80, 104),
    "stone": (104, 128),
}


# ---------------------------------------------------------------------------------------------- texture

def paint_texture(seed=7):
    rng = np.random.default_rng(seed)
    img = np.zeros((TEX, TEX, 3), np.float32)
    ys = np.arange(TEX)[:, None]

    def wood(c0, c1, base, dark):
        w = c1 - c0
        xs = np.arange(w)[None, :]
        phase = rng.uniform(0, 6.28, size=4)
        grain = sum(np.sin(xs * f + ys * 0.05 * (k + 1) + phase[k]) for k, f in enumerate((0.9, 1.7, 2.9, 4.1)))
        grain = (grain / 4 + 1) / 2
        noise = rng.normal(0, 0.05, size=(TEX, w))
        t = np.clip(grain * 0.55 + noise, 0, 1)[..., None]
        img[:, c0:c1] = np.array(base) * (1 - t) + np.array(dark) * t

    wood(*COLS["bow"], base=(205, 170, 118), dark=(150, 108, 64))
    wood(*COLS["shaft"], base=(222, 196, 150), dark=(176, 140, 92))

    c0, c1 = COLS["grip"]
    band = ((ys // 5) % 2).astype(np.float32)
    grip = np.array((92, 60, 36)) * (1 - band[..., None] * 0.25)
    img[:, c0:c1] = grip + rng.normal(0, 6, size=(TEX, c1 - c0, 3))

    c0, c1 = COLS["string"]
    twist = (np.sin((np.arange(c1 - c0)[None, :] + ys) * 1.6) + 1) / 2
    img[:, c0:c1] = np.array((228, 218, 192)) - twist[..., None] * 30

    c0, c1 = COLS["feather"]
    bars = ((ys // 7) % 2).astype(np.float32)[..., None]
    img[:, c0:c1] = np.array((232, 230, 224)) * (1 - bars) + np.array((92, 88, 84)) * bars
    img[:, c0:c1] += rng.normal(0, 8, size=(TEX, c1 - c0, 3))

    c0, c1 = COLS["stone"]
    mottle = rng.normal(0, 1, size=(TEX // 4, (c1 - c0) // 4))
    mottle = np.kron(mottle, np.ones((4, 4)))
    img[:, c0:c1] = np.array((132, 134, 138))[None, None, :] + mottle[..., None] * 18

    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


# ---------------------------------------------------------------------------------------------- meshes

class Mesh:
    def __init__(self, name):
        self.name = name
        self.verts, self.uvs, self.faces = [], [], []

    def vert(self, p, uv):
        self.verts.append(np.asarray(p, np.float64))
        self.uvs.append(uv)
        return len(self.verts) - 1

    def tri(self, a, b, c, outward):
        """Add a triangle wound so cross(b-a, c-a) points along `outward`."""
        pa, pb, pc = self.verts[a], self.verts[b], self.verts[c]
        if np.dot(np.cross(pb - pa, pc - pa), outward) < 0:
            b, c = c, b
        self.faces.append((a, b, c))

    def normals(self):
        n = np.zeros((len(self.verts), 3))
        for a, b, c in self.faces:
            fn = np.cross(self.verts[b] - self.verts[a], self.verts[c] - self.verts[a])
            for i in (a, b, c):
                n[i] += fn
        lens = np.linalg.norm(n, axis=1, keepdims=True)
        lens[lens == 0] = 1
        return n / lens


def uv_in(col, u, v):
    c0, c1 = COLS[col]
    return ((c0 + 0.5 + u * (c1 - c0 - 1)) / TEX, 0.02 + v * 0.96)


def tube(mesh, spine, side, up, half_w, half_h, col, sides=6, caps=True, v_repeat=1.0):
    """A tube along `spine` (Nx3) with per-point half width/height and frames (side, up vectors)."""
    rings = []
    n = len(spine)
    for k in range(n):
        ring = []
        for i in range(sides + 1):
            t = 2 * math.pi * i / sides
            p = spine[k] + math.cos(t) * half_w[k] * side[k] + math.sin(t) * half_h[k] * up[k]
            ring.append(mesh.vert(p, uv_in(col, i / sides, (k / (n - 1)) * v_repeat % 1.0001)))
        rings.append(ring)
    for k in range(n - 1):
        mid = (spine[k] + spine[k + 1]) / 2
        for i in range(sides):
            a, b = rings[k][i], rings[k][i + 1]
            c, d = rings[k + 1][i + 1], rings[k + 1][i]
            centre = (mesh.verts[a] + mesh.verts[b] + mesh.verts[c] + mesh.verts[d]) / 4
            out = centre - mid
            mesh.tri(a, b, c, out)
            mesh.tri(a, c, d, out)
    if caps:
        for k, sign in ((0, -1), (n - 1, 1)):
            tangent = spine[min(k + 1, n - 1)] - spine[max(k - 1, 0)]
            centre = mesh.vert(spine[k], uv_in(col, 0.5, 0.5))
            for i in range(sides):
                mesh.tri(centre, rings[k][i], rings[k][i + 1], sign * tangent)


def frames_along(spine, plane_normal):
    """Side = plane normal (constant), up = perpendicular to tangent inside the bend plane."""
    side, up = [], []
    for k in range(len(spine)):
        t = spine[min(k + 1, len(spine) - 1)] - spine[max(k - 1, 0)]
        t = t / np.linalg.norm(t)
        s = plane_normal / np.linalg.norm(plane_normal)
        u = np.cross(t, s)
        side.append(s)
        up.append(u / np.linalg.norm(u))
    return side, up


def bow(mesh, centre, along, bend_dir, half_len, sag, strung=True, segs=24):
    """A self bow: tapered limbs, leather grip, optional string between the tips."""
    along = along / np.linalg.norm(along)
    bend_dir = bend_dir / np.linalg.norm(bend_dir)
    plane_normal = np.cross(along, bend_dir)
    s = np.linspace(-1, 1, segs + 1)
    spine = np.array([centre + along * half_len * x + bend_dir * sag * x * x for x in s])
    taper = 1 - 0.55 * np.abs(s)
    side, up = frames_along(spine, plane_normal)
    tube(mesh, spine, side, up, 0.012 * taper, 0.008 * taper, "bow", sides=6)

    if not strung:
        return
    g = np.linspace(-0.12, 0.12, 5)
    grip = np.array([centre + along * half_len * x + bend_dir * sag * x * x for x in g])
    gside, gup = frames_along(grip, plane_normal)
    tube(mesh, grip, gside, gup, np.full(5, 0.0145), np.full(5, 0.0105), "grip", sides=8)

    if strung:
        tip_a, tip_b = spine[0], spine[-1]
        line = np.array([tip_a + (tip_b - tip_a) * x for x in np.linspace(0, 1, 2)])
        sside, sup = frames_along(np.array([line[0], line[1]]), plane_normal)
        tube(mesh, line, sside, sup, np.full(2, 0.0016), np.full(2, 0.0016), "string", sides=4)


def arrow_shaft(mesh, y0, y1, radius, point_to=None, col="shaft"):
    spine = np.array([[0, y, 0] for y in np.linspace(y0, y1, 6)], np.float64)
    side = [np.array([1.0, 0, 0])] * len(spine)
    up = [np.array([0, 0, 1.0])] * len(spine)
    tube(mesh, spine, side, up, np.full(len(spine), radius), np.full(len(spine), radius), col,
         sides=6, caps=point_to is None)
    if point_to is not None:
        tip = mesh.vert((0, point_to, 0), uv_in(col, 0.5, 1.0))
        base = mesh.vert((0, y0, 0), uv_in(col, 0.5, 0.0))
        ring_top = [len(mesh.verts) - 2 - 7 + i for i in range(7)]
        first = len(mesh.verts) - 2 - 7 * len(spine)
        ring_bot = [first + i for i in range(7)]
        for i in range(6):
            mesh.tri(tip, ring_top[i], ring_top[i + 1], np.array([0, 1.0, 0]))
            mesh.tri(base, ring_bot[i], ring_bot[i + 1], np.array([0, -1.0, 0]))


def arrowhead(mesh, y_base, y_tip, half_w, half_t):
    """A flat knapped point: a double pyramid, wide in X and thin in Z."""
    tip = mesh.vert((0, y_tip, 0), uv_in("stone", 0.5, 1.0))
    back = mesh.vert((0, y_base - 0.012, 0), uv_in("stone", 0.5, 0.0))
    ring = [
        mesh.vert((half_w, y_base, 0), uv_in("stone", 0.0, 0.3)),
        mesh.vert((0, y_base, half_t), uv_in("stone", 0.33, 0.3)),
        mesh.vert((-half_w, y_base, 0), uv_in("stone", 0.66, 0.3)),
        mesh.vert((0, y_base, -half_t), uv_in("stone", 1.0, 0.3)),
    ]
    centre = np.array([0, y_base, 0.0])
    for i in range(4):
        a, b = ring[i], ring[(i + 1) % 4]
        for apex in (tip, back):
            out = (mesh.verts[a] + mesh.verts[b] + mesh.verts[apex]) / 3 - centre
            mesh.tri(apex, a, b, out)


def fletching(mesh, y0, y1, r_in, r_out):
    """Three double-sided feather vanes, tall at the back and tapering toward the front."""
    for k in range(3):
        ang = math.radians(90 + 120 * k)
        radial = np.array([math.cos(ang), 0, math.sin(ang)])
        normal = np.array([-math.sin(ang), 0, math.cos(ang)])
        corners = [
            (radial * r_in + [0, y0, 0], (0, 0)),
            (radial * r_out + [0, y0, 0], (1, 0)),
            (radial * (r_in + (r_out - r_in) * 0.35) + [0, y1, 0], (1, 1)),
            (radial * r_in + [0, y1, 0], (0, 1)),
        ]
        for facing in (normal, -normal):
            idx = [mesh.vert(p, uv_in("feather", u, v)) for p, (u, v) in corners]
            mesh.tri(idx[0], idx[1], idx[2], facing)
            mesh.tri(idx[0], idx[2], idx[3], facing)


def build_meshes():
    meshes = {}

    m = Mesh("SA_BowHeld")
    along = np.array([-0.4, 0, 0.7])
    bow(m, centre=np.array([0, 0.22, 0]), along=along, bend_dir=np.array([0, -1.0, 0]),
        half_len=0.403, sag=0.07)
    meshes[m.name] = m

    m = Mesh("SA_Bow")
    bow(m, centre=np.array([-0.01, 0.2, 0.01]), along=np.array([0, 1.0, 0]), bend_dir=np.array([0, 0, 1.0]),
        half_len=0.4, sag=0.07)
    meshes[m.name] = m

    m = Mesh("SA_BowStave")
    bow(m, centre=np.array([0, 0.22, 0]), along=along, bend_dir=np.array([0, -1.0, 0]),
        half_len=0.425, sag=0.0, strung=False)
    meshes[m.name] = m

    m = Mesh("SA_Arrow")
    arrow_shaft(m, -0.236, 0.168, 0.0035)
    arrowhead(m, y_base=0.168, y_tip=0.204, half_w=0.010, half_t=0.0025)
    fletching(m, y0=-0.226, y1=-0.168, r_in=0.0033, r_out=0.0125)
    meshes[m.name] = m

    m = Mesh("SA_ArrowShaft")
    arrow_shaft(m, -0.241, 0.178, 0.0035, point_to=0.193)
    meshes[m.name] = m
    return meshes


# ---------------------------------------------------------------------------------------------- .X writer

X_TEMPLATES = """xof 0303txt 0032
template ColorRGBA {
 <35ff44e0-6c7c-11cf-8f52-0040333594a3>
 FLOAT red;
 FLOAT green;
 FLOAT blue;
 FLOAT alpha;
}

template ColorRGB {
 <d3e16e81-7835-11cf-8f52-0040333594a3>
 FLOAT red;
 FLOAT green;
 FLOAT blue;
}

template Material {
 <3d82ab4d-62da-11cf-ab39-0020af71e433>
 ColorRGBA faceColor;
 FLOAT power;
 ColorRGB specularColor;
 ColorRGB emissiveColor;
 [...]
}

template TextureFilename {
 <a42790e1-7810-11cf-8f52-0040333594a3>
 STRING filename;
}

template Frame {
 <3d82ab46-62da-11cf-ab39-0020af71e433>
 [...]
}

template Matrix4x4 {
 <f6f23f45-7686-11cf-8f52-0040333594a3>
 array FLOAT matrix[16];
}

template FrameTransformMatrix {
 <f6f23f41-7686-11cf-8f52-0040333594a3>
 Matrix4x4 frameMatrix;
}

template Vector {
 <3d82ab5e-62da-11cf-ab39-0020af71e433>
 FLOAT x;
 FLOAT y;
 FLOAT z;
}

template MeshFace {
 <3d82ab5f-62da-11cf-ab39-0020af71e433>
 DWORD nFaceVertexIndices;
 array DWORD faceVertexIndices[nFaceVertexIndices];
}

template Mesh {
 <3d82ab44-62da-11cf-ab39-0020af71e433>
 DWORD nVertices;
 array Vector vertices[nVertices];
 DWORD nFaces;
 array MeshFace faces[nFaces];
 [...]
}

template MeshNormals {
 <f6f23f43-7686-11cf-8f52-0040333594a3>
 DWORD nNormals;
 array Vector normals[nNormals];
 DWORD nFaceNormals;
 array MeshFace faceNormals[nFaceNormals];
}

template MeshMaterialList {
 <f6f23f42-7686-11cf-8f52-0040333594a3>
 DWORD nMaterials;
 DWORD nFaceIndexes;
 array DWORD faceIndexes[nFaceIndexes];
 [Material <3d82ab4d-62da-11cf-ab39-0020af71e433>]
}

template Coords2d {
 <f6f23f44-7686-11cf-8f52-0040333594a3>
 FLOAT u;
 FLOAT v;
}

template MeshTextureCoords {
 <f6f23f40-7686-11cf-8f52-0040333594a3>
 DWORD nTextureCoords;
 array Coords2d textureCoords[nTextureCoords];
}

"""


def write_x(mesh, path):
    vs = [f"  {p[0]:.6f};{p[1]:.6f};{p[2]:.6f};;" for p in mesh.verts]
    fs = [f"  3;{a},{b},{c};;" for a, b, c in mesh.faces]
    ns = [f"   {n[0]:.6f};{n[1]:.6f};{n[2]:.6f};;" for n in mesh.normals()]
    nfs = [f"   3;{a},{b},{c};;" for a, b, c in mesh.faces]
    uvs = [f"   {u:.6f};{v:.6f};;" for u, v in mesh.uvs]
    mats = ["   0,"] * len(mesh.faces)
    mats[-1] = "   0;"

    def block(lines):
        return ",\n".join(line[:-1] for line in lines[:-1]) + (",\n" if len(lines) > 1 else "") + lines[-1][:-1] + ";"

    out = [X_TEMPLATES]
    out.append("Material SA_Material {\n 1.000000;1.000000;1.000000;1.000000;;\n 10.000000;\n"
               " 0.000000;0.000000;0.000000;;\n 0.000000;0.000000;0.000000;;\n\n"
               f" TextureFilename {{\n  \"{TEX_NAME}.png\";\n }}\n}}\n")
    out.append(f"Frame {mesh.name} {{\n\n FrameTransformMatrix {{\n"
               "  1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,"
               "0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000;;\n }\n\n")
    out.append(f" Mesh {mesh.name} {{\n  {len(vs)};\n{block(vs)}\n  {len(fs)};\n{block(fs)}\n\n")
    out.append(f"  MeshNormals {{\n   {len(ns)};\n{block(ns)}\n   {len(nfs)};\n{block(nfs)}\n  }}\n\n")
    out.append(f"  MeshMaterialList {{\n   1;\n   {len(mats)};\n" + "\n".join(mats) + "\n   { SA_Material }\n  }\n\n")
    out.append(f"  MeshTextureCoords c1 {{\n   {len(uvs)};\n{block(uvs)}\n  }}\n }}\n}}\n")
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write("".join(out))


# ---------------------------------------------------------------------------------------------- preview

def render(mesh, tex, size=900, tilt=0.35):
    """Flat-shaded, painter's-algorithm render with each face coloured from the texture.
    The camera looks along the model's flattest axis (tilted a little) so curves are visible."""
    raw = np.array(mesh.verts)
    centred = raw - raw.mean(0)
    _, _, axes = np.linalg.svd(centred, full_matrices=False)
    rx = np.array([[1, 0, 0], [0, math.cos(tilt), -math.sin(tilt)], [0, math.sin(tilt), math.cos(tilt)]])
    rot = rx @ np.array([axes[0], axes[1], axes[2]])
    pts = centred @ rot.T
    lo, hi = pts[:, :2].min(0), pts[:, :2].max(0)
    scale = (size * 0.94) / max(hi - lo)
    height = int((hi[1] - lo[1]) * scale + size * 0.06)
    off = ((size - (hi[0] - lo[0]) * scale) / 2, (height - (hi[1] - lo[1]) * scale) / 2)
    img = Image.new("RGB", (size, height), (70, 70, 70))
    draw = ImageDraw.Draw(img)
    light = np.array([0.3, 0.6, 0.75])
    light /= np.linalg.norm(light)
    texarr = np.asarray(tex)
    order = sorted(mesh.faces, key=lambda f: pts[list(f), 2].mean())
    for a, b, c in order:
        n = np.cross(pts[b] - pts[a], pts[c] - pts[a])
        ln = np.linalg.norm(n)
        if ln == 0:
            continue
        shade = 0.45 + 0.55 * abs(np.dot(n / ln, light))
        u = np.mean([mesh.uvs[i][0] for i in (a, b, c)])
        v = np.mean([mesh.uvs[i][1] for i in (a, b, c)])
        col = texarr[min(TEX - 1, int(v * TEX)), min(TEX - 1, int(u * TEX))] * shade
        poly = [((pts[i, 0] - lo[0]) * scale + off[0], height - ((pts[i, 1] - lo[1]) * scale + off[1])) for i in (a, b, c)]
        draw.polygon(poly, fill=tuple(int(x) for x in col))
    return img


def main():
    os.makedirs(MESH_DIR, exist_ok=True)
    os.makedirs(TEX_DIR, exist_ok=True)
    tex = paint_texture()
    tex.save(os.path.join(TEX_DIR, f"{TEX_NAME}.png"))
    meshes = build_meshes()
    for name, mesh in meshes.items():
        write_x(mesh, os.path.join(MESH_DIR, f"{name}.X"))
        print(f"{name}: {len(mesh.verts)} verts, {len(mesh.faces)} faces")

    rows = [render(m, tex) for m in meshes.values()]
    arrow = render(meshes["SA_Arrow"], tex, size=4000)
    h = arrow.height
    rows.append(Image.fromarray(np.hstack([
        np.asarray(arrow.crop((0, 0, 440, h))),
        np.full((h, 20, 3), 40, np.uint8),
        np.asarray(arrow.crop((4000 - 440, 0, 4000, h))),
    ])))
    rows.append(tex.resize((256, 256), Image.NEAREST))
    gap = 12
    sheet = Image.new("RGB", (900, sum(r.height for r in rows) + gap * len(rows)), (40, 40, 40))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height + gap
    sheet.save(PREVIEW)
    print("wrote", PREVIEW)


if __name__ == "__main__":
    main()
