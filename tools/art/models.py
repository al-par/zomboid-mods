"""Home Heating models: hearths (4 looks), coal barrel heater, coil tower heater."""
import zlib

import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree

from iso import Grid, value_noise
from walltex import WallTexture

Z_TO_TILE = 2.45  # one floor is about 2.45 tiles of horizontal distance

# Hearth layout in the wall frame: a runs along the wall, b out of the wall, z up.
# The fire tile is a in [0, 1); the game's flame lands at a 0.5, b 0.09 on that tile.
D = 0.38                    # chimney breast depth
OPEN_A0 = D + 0.08          # opening, chosen so every flame frame shows inside it
OPEN_A1 = OPEN_A0 + 0.78
OPEN_TOP = 0.40
FIRE_FLOOR = 0.025
BACK = 0.05
WIDTH = 1.7


def rng_for(name):
    return np.random.default_rng(zlib.crc32(name.encode()))


def pick(palette, n, rng, jitter=0.05):
    pal = np.asarray(palette, np.float32)
    c = pal[rng.integers(0, len(pal), n)]
    return c * (1 + rng.normal(0, jitter, (n, 1))).astype(np.float32)


def dist_inside(g):
    """Distance to the nearest empty voxel; outside the grid counts as empty."""
    d = ndimage.distance_transform_edt(np.pad(g.occ, 1), sampling=(1 / g.res, 1 / g.res, Z_TO_TILE / g.zres))
    return d[1:-1, 1:-1, 1:-1]


def stones(g, solid, rng, palette, mortar, spacing, flat=1.6, joint=0.022, joint_depth=2,
           inset_max=2, bevel=1.7, mortar_jitter=0.04):
    """Fill solid with irregular stones (anisotropic Voronoi cells) and recessed joints."""
    g.fill(solid, mortar)
    vox = 1.0 / g.res
    dist = dist_inside(g)
    band = g.occ & (dist <= 6 * vox) & g.full(solid)
    idx, (x, y, z) = g.coords(band)
    lo = np.array([x.min(), y.min(), z.min() * Z_TO_TILE * flat]) - spacing
    hi = np.array([x.max(), y.max(), z.max() * Z_TO_TILE * flat]) + spacing
    n = [max(2, int((hi[i] - lo[i]) / spacing) + 1) for i in range(3)]
    gx, gy, gz = np.meshgrid(*[np.linspace(lo[i], hi[i], n[i]) for i in range(3)], indexing="ij")
    seeds = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], 1)
    seeds += rng.uniform(-0.45, 0.45, seeds.shape) * spacing
    tree = cKDTree(seeds)
    pts = np.stack([x, y, z * Z_TO_TILE * flat], 1)
    dd, ii = tree.query(pts, k=2)
    gap = dd[:, 1] - dd[:, 0]
    sid = ii[:, 0]
    cols = pick(palette, len(seeds), rng, 0.07)
    vn = value_noise(g.shape, 6, rng)[idx]
    c = cols[sid] * (1 + 0.06 * vn)[:, None]
    j = gap < joint
    mc = np.asarray(mortar, np.float32) * (1 + mortar_jitter * rng.normal(0, 1, (j.sum(), 1)))
    c[j] = mc
    g.col[idx] = c
    d = dist[idx]
    carve = (j & (d <= joint_depth * vox)) | ((gap < joint * bevel) & (d <= vox))
    inset = rng.integers(0, inset_max + 1, len(seeds))
    carve |= d <= inset[sid] * vox * 0.5
    sel = tuple(a[carve] for a in idx)
    g.occ[sel] = False


def bricks(g, solid, rng, palette, mortar, course=0.042, length=0.27, joint=0.018, jointz=0.008,
           rough=False, smear=0.0, joint_depth=1):
    g.fill(solid, mortar)
    vox = 1.0 / g.res
    dist = dist_inside(g)
    band = g.occ & (dist <= 4 * vox) & g.full(solid)
    idx, (x, y, z) = g.coords(band)
    nx, ny, nz = g.normals()
    side = np.abs(nx[idx]) > np.abs(ny[idx])
    u = np.where(side, y, x)
    if rough:
        cz = np.cumsum(rng.uniform(0.85, 1.2, 64)) * course
        crs = np.searchsorted(cz, z)
        cbot = np.where(crs > 0, cz[np.maximum(crs - 1, 0)], 0)
        fz = z - cbot
        off = rng.uniform(0, length, 64)[crs]
    else:
        crs = np.floor(z / course).astype(int)
        fz = z - crs * course
        off = (crs % 2) * length / 2
    bu = np.floor((u + off) / length).astype(int)
    fu = (u + off) - bu * length
    jt = (fu < joint) | (fz < jointz)
    key = (crs * 7919 + bu * 104729 + side * 15485863) % 1000003
    cols = pick(palette, 4096, rng, 0.06)
    c = cols[key % 4096].copy()
    vn = value_noise(g.shape, 5, rng)[idx]
    c *= (1 + 0.05 * vn)[:, None]
    if rough:
        dark = (key * 31 % 17) == 0
        c[dark] *= 0.72
    if smear > 0:
        sn = value_noise(g.shape, 14, rng, octaves=4)[idx]
        sm = sn > (1 - 2 * smear)
        c[sm] = np.asarray(mortar, np.float32) * (1 + 0.08 * sn[sm][:, None])
        jt = jt & ~sm
    c[jt] = mortar
    g.col[idx] = c
    d = dist[idx]
    carve = jt & (d <= joint_depth * vox)
    if rough:
        sink = (key * 13 % 7) == 0
        carve |= sink & (d <= vox)
    sel = tuple(a[carve] for a in idx)
    g.occ[sel] = False


_TEX = {}
SKIN_GAIN = 1.17  # offsets iso.py's ambient occlusion on a flat face, measured against the wall sprites


def wall_tex(key, face="N"):
    if (key, face) not in _TEX:
        _TEX[key, face] = WallTexture(key, face)
    return _TEX[key, face]


def tex_palette(t, n, rng):
    face = t.rgb[~t.joint]
    return face[rng.integers(0, len(face), n)]


def skin(g, solid, key, west, joint_depth=0, band_vox=4):
    """Cover solid with vanilla wall texture, built in the N-wall frame. A face takes its texture
    from the vanilla wall facing the same way once placed: the front (normal along y) looks like
    a N wall's face, or a W wall's once to_west() swaps the axes. Joint texels can be recessed."""
    front = wall_tex(key, "W" if west else "N")
    side_t = wall_tex(key, "N" if west else "W")
    g.fill(solid, front.joint_col)
    vox = 1.0 / g.res
    dist = dist_inside(g)
    band = g.occ & g.full(solid) & (dist <= band_vox * vox)
    idx, (x, y, z) = g.coords(band)
    nx, ny, nz = (c[idx] for c in g.normals(1.2 * g.res / 64))
    ax, ay, az = np.abs(nx), np.abs(ny), np.abs(nz)
    side = (ax > ay) & (ax >= az)
    top = (az > ax) & (az > ay) & (az > 0.85)  # slopes (a smoke hood) read as wall, not floor
    col = np.empty((len(x), 3), np.float32)
    jt = np.empty(len(x), bool)
    for t, sel, u, v in ((front, ~side, x, np.where(top, y * 0.6 + 0.11, z)), (side_t, side, y + 0.37, z)):
        iu, iv = t.sample(u[sel], v[sel])
        col[sel] = t.rgb[iv, iu]
        jt[sel] = t.joint[iv, iu]
    g.col[idx] = col * SKIN_GAIN
    carve = jt & (dist[idx] <= joint_depth * vox) & ~top
    g.occ[tuple(a[carve] for a in idx)] = False
    return front


def box(g, a0, a1, b0, b1, z0, z1):
    return (g.X >= a0) & (g.X < a1) & (g.Y >= b0) & (g.Y < b1) & (g.Z >= z0) & (g.Z < z1)


def opening_mask(g, top_extra=None):
    m = box(g, OPEN_A0, OPEN_A1, BACK, 9, FIRE_FLOOR, OPEN_TOP)
    if top_extra is not None:
        m = m | top_extra
    return m


def soot(g, strength=0.75, up=0.25, plume_strength=0.5):
    """Blacken the firebox and a smoke stain above the opening."""
    ac = (OPEN_A0 + OPEN_A1) / 2
    hw = (OPEN_A1 - OPEN_A0) / 2
    inside = (g.Y < D - 0.025) & (g.X > OPEN_A0 - 0.04) & (g.X < OPEN_A1 + 0.04) & (g.Z < OPEN_TOP + 0.03)
    plume = np.exp(-((g.X - ac) / (hw * 0.9)) ** 2) * np.clip(1 - (g.Z - OPEN_TOP) / up, 0, 1) * (g.Z >= OPEN_TOP - 0.01)
    f = np.maximum(inside * 1.0, plume * plume_strength)
    f = g.full(f).astype(np.float32) * strength
    k = 1 - f
    g.col *= k[..., None]
    floor = g.full(inside & (g.Z < FIRE_FLOOR + 0.012)) & g.occ
    ash = np.asarray([0.36, 0.34, 0.32], np.float32)
    rng = np.random.default_rng(7)
    g.col[floor] = ash * (0.8 + 0.4 * rng.random((floor.sum(), 1))).astype(np.float32)


def hearth(style, west=False):
    """Return a Grid in the N-wall frame (x along the wall, y out of it), 2 tiles wide.
    west=True textures it for a W wall; pass the result through to_west()."""
    g = Grid(2, 1, 1.0, res=64, zres=192)  # one voxel per wall texel
    rng = rng_for("hearth_" + style)
    X, Y, Z = g.X, g.Y, g.Z
    top = 0.985

    if style == "brick_neat":
        body = box(g, 0, WIDTH, 0, D, 0, top)
        arch_c = (OPEN_A0 + OPEN_A1) / 2
        spring = OPEN_TOP - 0.03
        half = (OPEN_A1 - OPEN_A0) / 2
        rise = 0.055 * Z_TO_TILE
        r_in = (half ** 2 + rise ** 2) / (2 * rise)
        zc = (spring * Z_TO_TILE + rise - r_in) / Z_TO_TILE
        rr = np.sqrt((X - arch_c) ** 2 + ((Z - zc) * Z_TO_TILE) ** 2)
        hole = box(g, OPEN_A0, OPEN_A1, BACK, 9, FIRE_FLOOR, spring)
        under_arch = (rr < r_in) & (Z >= spring - 0.001) & (X > OPEN_A0) & (X < OPEN_A1) & (Y >= BACK)
        solid = body & ~hole & ~under_arch
        t = skin(g, solid, "brick_neat", west)
        # soldier-course arch over the opening
        band = solid & (rr >= r_in) & (rr < r_in + 0.12) & (Z > spring - 0.03)
        band = g.full(band) & g.occ
        idx, (x, y, z) = g.coords(band)
        ang = np.arctan2((z - zc) * Z_TO_TILE, x - arch_c)
        step = 0.085 / r_in
        k = np.floor(ang / step).astype(int)
        fa = ang / step - k
        cols = tex_palette(t, 64, rng)
        c = cols[k % 64] * (1 + 0.04 * value_noise(g.shape, 5, rng)[idx])[:, None]
        r = np.sqrt((x - arch_c) ** 2 + ((z - zc) * Z_TO_TILE) ** 2)
        jt = (fa < 0.14) | (r > r_in + 0.105)
        c[jt] = t.joint_col
        g.col[idx] = c
        # firebrick lining
        lining = g.full(box(g, OPEN_A0 - 0.03, OPEN_A1 + 0.03, BACK - 0.02, D, 0, OPEN_TOP + 0.04)) & g.occ & ~g.full(band)
        li, (lx, ly, lz) = g.coords(lining)
        crs = np.floor(lz / 0.03).astype(int)
        uu = np.where(np.abs(ly - BACK) < 0.03, lx, ly) + (crs % 2) * 0.09
        jt2 = ((uu % 0.18) < 0.012) | ((lz % 0.03) < 0.006)
        cc = np.where(jt2[:, None], np.float32([0.62, 0.58, 0.52]), np.float32([0.74, 0.62, 0.48]))
        g.col[li] = cc * (1 + 0.05 * rng.normal(0, 1, (len(cc), 1))).astype(np.float32)
        soot(g, 0.82, up=0.18)
        # quarry-tile hearth in front
        slab = box(g, OPEN_A0 - 0.12, OPEN_A1 + 0.12, D, D + 0.2, 0, 0.022)
        g.fill(slab, [0.55, 0.30, 0.24])
        si, (sx, sy, sz) = g.coords(g.full(slab))
        jt3 = ((sx % 0.15) < 0.01) | (((sy - D) % 0.1) < 0.01)
        tc = pick([[0.56, 0.31, 0.24], [0.50, 0.27, 0.22], [0.60, 0.35, 0.27]], 64, rng, 0.04)
        tid = (np.floor(sx / 0.15).astype(int) * 7 + np.floor((sy - D) / 0.1).astype(int)) % 64
        c3 = tc[tid]
        c3[jt3] = [0.40, 0.36, 0.33]
        g.col[si] = c3

    elif style == "brick_rough":
        lower = box(g, 0, WIDTH, 0, D, 0, 0.56)
        upper = box(g, 0, 1.12, 0, D - 0.03, 0.5, top)
        shoulder = (X >= 1.12) & (X < WIDTH) & (Y < D) & (Z >= 0.56) & (Z < 0.56 + (WIDTH - X) * 0.14 / (WIDTH - 1.12))
        body = lower | upper | shoulder
        sag = 0.018 * np.clip(1 - ((X - (OPEN_A0 + OPEN_A1) / 2) / ((OPEN_A1 - OPEN_A0) / 2)) ** 2, 0, 1)
        hole = box(g, OPEN_A0, OPEN_A1, BACK, 9, FIRE_FLOOR, 9) & (Z < OPEN_TOP - sag)
        solid = body & ~hole
        t = skin(g, solid, "brick_rough", west)
        # sagging iron lintel
        lint = (X > OPEN_A0 - 0.06) & (X < OPEN_A1 + 0.06) & (Y > D - 0.05) & (Y < D + 0.004) & \
               (Z >= OPEN_TOP - sag) & (Z < OPEN_TOP - sag + 0.02)
        g.fill(lint, [0.30, 0.22, 0.18])
        li, _ = g.coords(g.full(lint))
        g.col[li] *= (0.8 + 0.4 * rng.random((len(li[0]), 1))).astype(np.float32)
        soot(g, 0.85, up=0.3)
        for i in range(5):
            a0 = OPEN_A0 - 0.1 + rng.uniform(0, 0.9)
            b0 = D + rng.uniform(0, 0.12)
            g.fill(box(g, a0, a0 + 0.13, b0, b0 + 0.06, 0, 0.018), tex_palette(t, 1, rng)[0])

    elif style == "stone_rough":
        nz = value_noise(g.shape, 12, rng)
        lower = box(g, 0, WIDTH, 0, D + 0.04, 0, 0.62)
        upper = box(g, 0.12, WIDTH - 0.12, 0, D - 0.02, 0.55, top)
        body = g.full(lower | upper)
        body = body & ~(g.full((Y > D - 0.04)) & (nz > 0.55))
        hole = box(g, OPEN_A0, OPEN_A1, BACK, 9, FIRE_FLOOR, OPEN_TOP)
        solid = body & ~g.full(hole)
        t = skin(g, solid, "stone", west, joint_depth=2)
        lint = box(g, OPEN_A0 - 0.14, OPEN_A1 + 0.16, D - 0.12, D + 0.04, OPEN_TOP, OPEN_TOP + 0.05)
        g.fill(lint, t.face_col * 0.95)
        li, _ = g.coords(g.full(lint))
        g.col[li] *= (1 + 0.06 * value_noise(g.shape, 4, rng)[li])[:, None]
        soot(g, 0.7, up=0.2)
        for i in range(3):
            a0 = OPEN_A0 + rng.uniform(-0.05, 0.6)
            g.fill(box(g, a0, a0 + 0.2, D + 0.02, D + 0.12, 0, 0.015), tex_palette(t, 1, rng)[0])

    elif style == "stone_neat":
        LEDGE = 0.44
        lower = box(g, 0, WIDTH, 0, D, 0, LEDGE)
        upper = box(g, 0.14, WIDTH - 0.14, 0, D - 0.05, LEDGE, top)
        hole = box(g, OPEN_A0, OPEN_A1, BACK, 9, FIRE_FLOOR, OPEN_TOP)
        solid = (lower | upper) & ~hole
        t = skin(g, g.full(solid), "stone", west, joint_depth=1)
        ledge = box(g, -0.0, WIDTH, 0, D + 0.05, LEDGE, LEDGE + 0.024)
        g.fill(ledge, t.face_col * 1.1)
        li, (lx, ly, lz) = g.coords(g.full(ledge))
        g.col[li] *= (1 + 0.035 * value_noise(g.shape, 8, rng)[li])[:, None]
        seams = ((lx % 0.57) < 0.008)
        g.col[tuple(a[seams] for a in li)] *= 0.75
        lint = box(g, OPEN_A0 - 0.04, OPEN_A1 + 0.04, D - 0.03, D + 0.003, OPEN_TOP, OPEN_TOP + 0.016)
        g.fill(lint, [0.22, 0.21, 0.21])
        soot(g, 0.8, up=0.22)
        slab = box(g, OPEN_A0 - 0.1, OPEN_A1 + 0.1, D, D + 0.18, 0, 0.02)
        g.fill(slab, t.face_col * 1.05)
        si, _ = g.coords(g.full(slab))
        g.col[si] *= (1 + 0.05 * value_noise(g.shape, 6, rng)[si])[:, None]
    else:
        raise ValueError(style)
    return g


def local(g, facing):
    """Coordinates around the square's centre with the object's front along local +y."""
    dx, dy = g.X - 0.5, g.Y - 0.5
    if facing == "S":
        return dx, dy
    if facing == "E":
        return -dy, dx
    if facing == "N":
        return -dx, -dy
    if facing == "W":
        return dy, -dx
    raise ValueError(facing)


def noisy(g, mask, color, rng, amount=0.05, scale=4):
    mask = g.full(mask)
    g.fill(mask, color)
    idx, _ = g.coords(mask)
    if len(idx[0]):
        g.col[idx] *= (1 + amount * value_noise(g.shape, scale, rng)[idx])[:, None]


def coal_heater(facing):
    g = Grid(1, 1, 1.0, res=128, zres=256)
    rng = rng_for("coal_" + facing)
    lx, ly = local(g, facing)
    # modelled small, then scaled so the body matches a vanilla 55-gallon drum
    lx, ly, Z = lx / 1.75, ly / 1.75, g.Z / 1.35
    r = np.sqrt(lx ** 2 + ly ** 2)
    paint = [0.30, 0.30, 0.31]
    dark = [0.15, 0.15, 0.16]
    steel = [0.52, 0.53, 0.54]

    def rsq(half, rad):
        qx = np.maximum(np.abs(lx) - (half - rad), 0)
        qy = np.maximum(np.abs(ly) - (half - rad), 0)
        return np.sqrt(qx ** 2 + qy ** 2) <= rad

    bead_col = [0.27, 0.25, 0.23]
    th_all = np.arctan2(lx, ly)

    def bead(mask, strength=1.0):
        """Weld bead: lumpy, darker, heat-tinted metal along a joint."""
        lump = value_noise(g.shape, 40, rng)
        m = g.full(mask) & (lump > -0.12)
        g.fill(m, bead_col)
        idx, _ = g.coords(m)
        g.col[idx] *= (1 + 0.25 * lump[idx])[:, None] * strength

    # legs: square bar stock splayed out, welded to foot plates
    for ang in (45, 135, 225, 315):
        a = np.radians(ang)
        t = np.clip(1 - Z / 0.06, 0, 1)
        rl = 0.13 + 0.04 * t
        cx, cy = rl * np.sin(a), rl * np.cos(a)
        ca, sa = np.cos(a), np.sin(a)
        u_, v_ = (lx - cx) * ca - (ly - cy) * sa, (lx - cx) * sa + (ly - cy) * ca
        leg = (np.abs(u_) < 0.013) & (np.abs(v_) < 0.013) & (Z < 0.06)
        noisy(g, leg, [0.26, 0.26, 0.27], rng, 0.1)
        fx, fy = 0.17 * sa, 0.17 * ca
        foot = (np.abs(lx - fx) < 0.024) & (np.abs(ly - fy) < 0.024) & (Z < 0.006)
        noisy(g, foot, [0.24, 0.24, 0.25], rng, 0.1)
        bead((np.abs(u_) < 0.018) & (np.abs(v_) < 0.018) & (Z >= 0.05) & (Z < 0.062))
    noisy(g, rsq(0.18, 0.012) & (Z >= 0.055) & (Z < 0.07), paint, rng)
    box_ = rsq(0.16, 0.012) & (Z >= 0.07) & (Z < 0.2)
    noisy(g, box_, paint, rng, 0.05)
    # weld beads up the firebox corners and along the plinth
    for sx in (-1, 1):
        for sy in (-1, 1):
            bead((np.sqrt((lx - sx * 0.158) ** 2 + (ly - sy * 0.158) ** 2) < 0.009) & (Z >= 0.07) & (Z < 0.2))
    bead(rsq(0.166, 0.014) & ~rsq(0.155, 0.012) & (Z >= 0.068) & (Z < 0.078))
    # fire door with vent slots, ash door with a round damper
    front = 0.16
    fdoor = (np.abs(lx) < 0.1) & (ly >= front - 0.005) & (ly < front + 0.01) & (Z >= 0.135) & (Z < 0.19)
    noisy(g, fdoor, [0.36, 0.36, 0.37], rng)
    slots = np.zeros(g.shape, bool)
    for k in range(4):
        sx = -0.045 + k * 0.03
        slots |= g.full((np.abs(lx - sx) < 0.0095) & (Z >= 0.143) & (Z < 0.183))
    g.carve(slots & g.full(ly >= front + 0.003))
    sback = slots & g.full((ly >= front - 0.01) & (ly < front + 0.003))
    g.fill(sback, [0.12, 0.10, 0.09])
    g.emit[sback] = 1.0
    adoor = (np.abs(lx) < 0.1) & (ly >= front - 0.005) & (ly < front + 0.008) & (Z >= 0.078) & (Z < 0.125)
    noisy(g, adoor, [0.36, 0.36, 0.37], rng)
    dcx, dcz = 0.035, 0.1
    dr = np.sqrt((lx - dcx) ** 2 + ((Z - dcz) * Z_TO_TILE) ** 2)
    disc = (dr < 0.032) & (ly >= front) & (ly < front + 0.016)
    noisy(g, disc, steel, rng)
    ang = np.arctan2(lx - dcx, (Z - dcz) * Z_TO_TILE)
    holes = g.full(disc & (dr > 0.008) & (dr < 0.024) & (np.cos(3 * ang) > 0.55) & (ly >= front + 0.008))
    g.carve(holes)
    hback = g.full((dr < 0.024) & (dr > 0.008) & (np.cos(3 * ang) > 0.55) & (ly >= front) & (ly < front + 0.008)) & g.occ
    g.paint(hback, [0.12, 0.10, 0.09])
    g.emit[hback] = 0.8
    # door plates cut from bare stock: tack welds at the corners, bent-bar handles
    dplate = g.full((np.abs(lx) < 0.1) & (ly >= front) & (Z >= 0.078) & (Z < 0.19)) & g.occ & ~g.full(disc) & ~sback & ~hback
    di, (dx_, dy_, dz_) = g.coords(dplate)
    g.col[di] = g.col[di] * 0.75 + 0.25 * np.float32(steel)
    grind = np.sin((dx_ * 0.8 + dz_ * 2.2) * 700) > 0.6
    g.col[tuple(a[grind] for a in di)] *= 1.12
    for zz in (0.187, 0.138, 0.122, 0.081):
        for sx in (-1, 1):
            bead((np.abs(lx - sx * 0.094) < 0.008) & (np.abs(Z - zz) < 0.005) & (ly >= front) & (ly < front + 0.014))
    for zz in (0.162, 0.1):
        hz = (Z - zz) * Z_TO_TILE
        loop = (np.abs(lx + 0.07) < 0.005) & (np.abs(hz) < 0.022) & (ly >= front + 0.008) & (ly < front + 0.03)
        ends = (np.abs(lx + 0.07) < 0.005) & (np.abs(np.abs(hz) - 0.018) < 0.005) & (ly >= front) & (ly < front + 0.03)
        noisy(g, (loop & (ly >= front + 0.022)) | ends, [0.2, 0.2, 0.21], rng)
    for zz in (0.17, 0.15, 0.11, 0.09):
        hinge = (np.sqrt((lx - 0.104) ** 2 + ((Z - zz) * Z_TO_TILE * 0.3) ** 2) < 0.009) & (np.abs(Z - zz) < 0.007) & \
                (ly >= front - 0.01) & (ly < front + 0.014)
        noisy(g, hinge, [0.33, 0.32, 0.31], rng)
    # flat plate flange where the drum is welded onto the firebox
    flange = (r < 0.168) & (Z >= 0.196) & (Z < 0.206)
    noisy(g, flange, paint, rng, 0.06)
    bead((r < 0.156) & (r >= 0.146) & (Z >= 0.205) & (Z < 0.215))
    body = (r < 0.15) & (Z >= 0.2) & (Z < 0.44)
    noisy(g, body, steel, rng, 0.07, 6)
    bi, (bx, by, bz) = g.coords(g.full(body) & g.occ)
    mz = bz / 1.35
    streak = value_noise(g.shape, 3, rng)[bi]
    # heat: scorched dark brown just above the fire, a faint straw band, then bare steel
    h = np.clip((0.33 - mz) / 0.12, 0, 1)
    scorch = np.float32([0.26, 0.21, 0.17])
    straw = np.float32([0.58, 0.49, 0.34])
    w_scorch = np.clip(h * 1.6 - 0.6, 0, 1) * 0.65
    w_straw = np.clip(1 - np.abs(h - 0.35) / 0.25, 0, 1) * 0.35
    c = g.col[bi] * (1 - 0.12 * np.clip(streak * 3, 0, 1))[:, None]
    c = c * (1 - w_straw[:, None]) + straw * w_straw[:, None]
    c = c * (1 - w_scorch[:, None]) + scorch * w_scorch[:, None]
    rust = np.clip((value_noise(g.shape, 8, rng, octaves=3)[bi] - 0.16) * 2.4, 0, 1) * (mz > 0.3)
    c = c * (1 - 0.5 * rust[:, None]) + (0.5 * rust)[:, None] * np.float32([0.42, 0.27, 0.17])
    g.col[bi] = c
    # the drum's own rolling hoops and its seam, now with a weld run over it
    for zb in (0.28, 0.36):
        hoop = (r < 0.156) & (np.abs(Z - zb) < 0.005)
        noisy(g, hoop, [0.46, 0.46, 0.47], rng)
    bead((np.abs(np.arctan2(lx, -ly)) < 0.06) & (r < 0.155) & (r > 0.14) & (Z >= 0.2) & (Z < 0.44))
    ring = (r < 0.175) & (Z >= 0.44) & (Z < 0.452)
    noisy(g, ring, paint, rng)
    bead((r < 0.156) & (r >= 0.146) & (Z >= 0.43) & (Z < 0.44))
    # rust creeping along the firebox and plinth edges
    fi, (fx_, fy_, fz_) = g.coords(g.full(box_ | rsq(0.18, 0.012)) & g.occ & ~dplate)
    fr = np.clip((value_noise(g.shape, 10, rng, octaves=3)[fi] - 0.1) * 3, 0, 1) * 0.45
    g.col[fi] = g.col[fi] * (1 - fr[:, None]) + fr[:, None] * np.float32([0.36, 0.22, 0.14])
    # upturned cooking pot as the loading cap
    pz0, ph = 0.452, 0.058
    potr = 0.118 - np.clip((Z - (pz0 + ph - 0.01)) / 0.01, 0, 1) * 0.012
    pot = (r < potr) & (Z >= pz0) & (Z < pz0 + ph)
    noisy(g, pot, [0.38, 0.39, 0.41], rng, 0.08, 5)
    ki, _ = g.coords(g.full(pot))
    pr_ = np.clip((value_noise(g.shape, 10, rng, octaves=3)[ki] - 0.12) * 2.5, 0, 1) * 0.45
    g.col[ki] = g.col[ki] * (1 - pr_[:, None]) + pr_[:, None] * np.float32([0.4, 0.26, 0.16])
    g.col[ki] *= (0.85 + 0.15 * np.clip(value_noise(g.shape, 4, rng)[ki] * 3 + 0.5, 0, 1))[:, None]
    lip = (r < 0.128) & (Z >= pz0) & (Z < pz0 + 0.008)
    noisy(g, lip, [0.34, 0.35, 0.37], rng)
    for side in (-1, 1):
        hx = side * 0.13
        loop = (np.abs(lx - hx) < 0.018) & (np.abs(ly) < 0.025) & (Z >= pz0 + 0.03) & (Z < pz0 + 0.045)
        hole = (np.abs(lx - hx) < 0.009) & (np.abs(ly) < 0.013)
        noisy(g, loop & ~hole, [0.30, 0.31, 0.33], rng)
    # flue out of the back, up to the ceiling
    pr = 0.038
    horiz = (np.sqrt(lx ** 2 + ((Z - 0.4) * Z_TO_TILE) ** 2) < pr) & (ly < -0.1) & (ly > -0.27)
    vert = (np.sqrt(lx ** 2 + (ly + 0.25) ** 2) < pr) & (Z >= 0.4) & (g.Z < 0.97)
    pipe = g.full(horiz | vert)
    noisy(g, pipe, [0.3, 0.29, 0.28], rng, 0.08)
    pi_, (px_, py_, pz_) = g.coords(pipe)
    pz_m = pz_ / 1.35
    # weathered like the drum: rust patches, soot run-off below each joint, heat browning low down
    rust = np.clip((value_noise(g.shape, 9, rng, octaves=3)[pi_] - 0.1) * 2.6, 0, 1)
    brown = np.clip((0.6 - pz_m) / 0.2, 0, 1) * 0.35
    c = g.col[pi_]
    c = c * (1 - brown[:, None]) + brown[:, None] * np.float32([0.34, 0.24, 0.16])
    c = c * (1 - 0.55 * rust[:, None]) + (0.55 * rust)[:, None] * np.float32([0.44, 0.27, 0.15])
    c *= (1 + 0.1 * value_noise(g.shape, 30, rng)[pi_])[:, None]
    g.col[pi_] = c
    # crimped joints every pipe section, with a soot drip under each, and a damper handle
    for zj in (0.56, 0.72, 0.88):
        joint = (np.sqrt(lx ** 2 + (ly + 0.25) ** 2) < pr + 0.006) & (np.abs(g.Z - zj) < 0.008)
        noisy(g, joint, [0.24, 0.23, 0.22], rng, 0.12)
        drip = g.full((np.sqrt(lx ** 2 + (ly + 0.25) ** 2) < pr + 0.001) & (g.Z < zj) & (g.Z > zj - 0.06)) & g.occ
        di, (dx2, dy2, dz2) = g.coords(drip)
        streak = np.clip(value_noise(g.shape, 25, rng)[di] * 3, 0, 1) * np.clip((dz2 - (zj - 0.06)) / 0.06, 0, 1)
        g.col[di] *= (1 - 0.5 * streak)[:, None]
    noisy(g, (np.abs(lx) < 0.006) & (np.abs(ly + 0.25) < pr + 0.03) & (np.abs(g.Z - 0.64) < 0.006), [0.2, 0.2, 0.2], rng)
    noisy(g, (np.abs(lx) < 0.014) & (np.abs(ly + 0.25 - pr - 0.03) < 0.006) & (np.abs(g.Z - 0.64) < 0.01), [0.15, 0.15, 0.15], rng)
    # weld bead where the pipe leaves the drum and at the elbow
    bead((np.sqrt(lx ** 2 + ((Z - 0.4) * Z_TO_TILE) ** 2) < pr + 0.007) & (ly < -0.135) & (ly > -0.15))
    bead((np.sqrt(lx ** 2 + (ly + 0.25) ** 2) < pr + 0.007) & (Z >= 0.4 + pr / Z_TO_TILE - 0.004) & (Z < 0.4 + pr / Z_TO_TILE + 0.006))
    collar2 = (np.sqrt(lx ** 2 + (ly + 0.25) ** 2) < pr + 0.008) & (g.Z >= 0.94) & (g.Z < 0.97)
    noisy(g, collar2, [0.3, 0.3, 0.31], rng)
    return g


def tower_heater(facing):
    g = Grid(1, 1, 1.0, res=128, zres=256)
    rng = rng_for("tower_" + facing)
    lx, ly = local(g, facing)
    squash = 0.5
    lx, ly, Z = lx / 1.3, ly / 1.3, g.Z / (1.35 * squash)
    paint = [0.50, 0.53, 0.57]
    hx, hy, z0, z1 = 0.13, 0.105, 0.03, 0.36
    for sx in (-1, 1):
        for sy in (-1, 1):
            foot = (np.abs(lx - sx * (hx - 0.025)) < 0.014) & (np.abs(ly - sy * (hy - 0.025)) < 0.014) & (Z < z0)
            noisy(g, foot, [0.2, 0.2, 0.21], rng)
    cab = (np.abs(lx) < hx) & (np.abs(ly) < hy) & (Z >= z0) & (Z < z1)
    noisy(g, cab, paint, rng, 0.05, 6)
    ci, (cx_, cy_, cz_) = g.coords(g.full(cab))
    g.col[ci] *= (1 - 0.05 * np.clip(value_noise(g.shape, 3, rng)[ci], 0, 1))[:, None]
    # front grille: vertical slots into a cavity holding a ceramic core wound with coil
    gx0, gx1, gz0, gz1 = -0.092, 0.092, 0.075, 0.315
    cavity = (np.abs(lx) < 0.095) & (ly > -0.06) & (ly < hy - 0.012) & (Z >= gz0 - 0.005) & (Z < gz1 + 0.005)
    g.carve(cavity)
    slot = np.zeros(g.shape, bool)
    for k in range(9):
        sx = gx0 + 0.01 + k * (gx1 - gx0 - 0.02) / 8
        slot |= g.full((np.abs(lx - sx) < 0.0095) & (Z >= gz0) & (Z < gz1))
    bars = g.full((np.abs(lx) < 0.095) & (ly >= hy - 0.012) & (ly < hy) & (Z >= gz0 - 0.005) & (Z < gz1 + 0.005))
    g.carve(bars & slot)
    frame = (np.abs(lx) < 0.105) & (np.abs(np.abs(lx) - 0.1) < 0.006) & (ly >= hy - 0.004) & (ly < hy + 0.004) & (Z >= gz0 - 0.012) & (Z < gz1 + 0.012)
    noisy(g, frame, [0.42, 0.45, 0.49], rng)
    inside = (np.abs(lx) < 0.095) & (ly >= -0.066) & (ly < -0.06) & (Z >= gz0 - 0.005) & (Z < gz1 + 0.005)
    g.fill(inside, [0.16, 0.16, 0.17])
    ccy = 0.01
    cr = np.sqrt(lx ** 2 + (ly - ccy) ** 2)
    core = (cr < 0.042) & (Z >= gz0) & (Z < gz1)
    noisy(g, core, [0.84, 0.81, 0.71], rng, 0.05)
    th = np.arctan2(lx, ly - ccy)
    helix = ((Z * 160 * squash + th / (2 * np.pi)) % 1.0) < 0.42
    coil = (cr >= 0.042) & (cr < 0.05) & helix & (Z >= gz0 + 0.005) & (Z < gz1 - 0.005)
    noisy(g, coil, [0.42, 0.36, 0.32], rng, 0.08)
    g.emit[g.full(coil) & g.occ] = 1.0
    g.emit[g.full(core) & g.occ] = 0.35
    for zz in (gz0 - 0.004, gz1 + 0.002):
        clamp = (cr < 0.05) & (Z >= zz) & (Z < zz + 0.006)
        noisy(g, clamp, [0.55, 0.55, 0.56], rng)
    # top: louvres, thermostat knob, pilot lamp
    for k in range(4):
        lz = (np.abs(lx + 0.03) < 0.075) & (np.abs(ly + 0.055 - k * 0.025) < 0.006) & (Z >= z1 - 0.008)
        g.paint(g.full(lz), [0.25, 0.26, 0.28])
    knob = (np.sqrt((lx - 0.075) ** 2 + (ly - 0.05) ** 2) < 0.022) & (Z >= z1) & (Z < z1 + 0.016)
    noisy(g, knob, [0.16, 0.16, 0.17], rng)
    lamp = (np.sqrt((lx - 0.075) ** 2 + (ly + 0.045) ** 2) < 0.009) & (Z >= z1) & (Z < z1 + 0.012)
    g.fill(lamp, [0.45, 0.12, 0.1])
    g.emit[g.full(lamp)] = 1.0
    # blower housing on the back
    br = np.sqrt(lx ** 2 + ((Z - 0.17) * Z_TO_TILE * squash) ** 2)
    blower = (br < 0.085) & (ly <= -hy + 0.002) & (ly > -hy - 0.045)
    noisy(g, blower, [0.36, 0.38, 0.40], rng)
    g.carve(g.full((br < 0.06) & (ly <= -hy - 0.03) & ((np.round(br * 120) % 2) == 0)))
    # screws along the cabinet edges
    for zz in np.linspace(z0 + 0.03, z1 - 0.03, 3):
        for sx in (-1, 1):
            for sy in (-1, 1):
                s = (np.abs(lx - sx * (hx - 0.012)) < 0.005) & (np.abs(ly - sy * hy) < 0.004) & (np.abs(Z - zz) < 0.008)
                g.paint(g.full(s | ((np.abs(lx - sx * hx) < 0.004) & (np.abs(ly - sy * (hy - 0.012)) < 0.005) & (np.abs(Z - zz) < 0.008))),
                        [0.3, 0.31, 0.33])
    return g


def tower_heater_crafted(facing):
    """The same heater as built from the recipe: sheet-metal panels screwed together, a salvaged
    blower fan on the back, bare coils strung between ceramic posts behind a woven wire guard."""
    g = Grid(1, 1, 1.0, res=128, zres=256)
    rng = rng_for("towerc_" + facing)
    lx, ly = local(g, facing)
    squash = 0.5
    zt = Z_TO_TILE * squash
    lx, ly, Z = lx / 1.3, ly / 1.3, g.Z / (1.35 * squash)
    galv = [0.56, 0.57, 0.58]
    hx, hy, z0, z1 = 0.135, 0.105, 0.035, 0.35
    # bent-strip skids running front to back
    for sx in (-1, 1):
        skid = (np.abs(lx - sx * (hx - 0.03)) < 0.018) & (np.abs(ly) < hy + 0.02) & (Z < z0)
        noisy(g, skid & ~((np.abs(lx - sx * (hx - 0.03)) < 0.01) & (Z < z0 - 0.012)), [0.24, 0.23, 0.22], rng, 0.1)
    # body: one panel per side, each cut from different stock
    cab = (np.abs(lx) < hx) & (np.abs(ly) < hy) & (Z >= z0) & (Z < z1)
    noisy(g, cab, galv, rng, 0.07, 5)
    ci, (cx_, cy_, cz_) = g.coords(g.full(cab))
    ux, uy = np.abs(cx_ - 0.5), np.abs(cy_ - 0.5)
    tint = np.ones((len(cx_), 3), np.float32)
    tint[(ux > uy) & (cx_ > 0.5)] = [0.82, 0.83, 0.86]
    tint[(ux > uy) & (cx_ < 0.5)] = [1.05, 1.0, 0.92]
    tint[(ux <= uy) & (cy_ < 0.5)] = [0.9, 0.9, 0.9]
    g.col[ci] *= tint
    rust = np.clip((value_noise(g.shape, 9, rng, octaves=3)[ci] - 0.08) * 3.5, 0, 1)
    streak = np.clip(value_noise(g.shape, 3, rng)[ci] * 3, 0, 1) * np.clip((0.2 - cz_) / 0.15, 0, 1)
    rust = np.clip(np.maximum(rust, streak), 0, 1)
    g.col[ci] = g.col[ci] * (1 - 0.6 * rust[:, None]) + (0.6 * rust)[:, None] * np.float32([0.42, 0.27, 0.17])
    # scuffs and dents
    sc_ = value_noise(g.shape, 20, rng)[ci]
    g.col[ci] *= (1 + 0.1 * np.sign(sc_) * (np.abs(sc_) > 0.2))[:, None]
    # lapped vertical seam on each side panel, top lid overhanging
    for sx in (-1, 1):
        seam = (np.abs(ly + 0.01) < 0.008) & (np.abs(lx - sx * hx) < 0.006) & (Z >= z0) & (Z < z1)
        noisy(g, seam, [0.5, 0.5, 0.51], rng)
    lid = (np.abs(lx) < hx + 0.008) & (np.abs(ly) < hy + 0.008) & (Z >= z1) & (Z < z1 + 0.014)
    noisy(g, lid, [0.5, 0.51, 0.52], rng, 0.08)
    # front window: coils between ceramic posts, woven wire guard
    gz0, gz1 = 0.08, 0.31
    cavity = (np.abs(lx) < 0.1) & (ly > -0.055) & (ly < hy) & (Z >= gz0) & (Z < gz1)
    g.carve(cavity)
    back = (np.abs(lx) < 0.1) & (ly >= -0.062) & (ly < -0.055) & (Z >= gz0) & (Z < gz1)
    g.fill(back, [0.2, 0.19, 0.18])
    cy = 0.06
    for sx in (-1, 1):
        post = (np.sqrt((lx - sx * 0.088) ** 2 + (ly - cy) ** 2) < 0.011) & (Z >= gz0) & (Z < gz1)
        noisy(g, post, [0.82, 0.79, 0.7], rng)
    coil = np.zeros(g.shape, bool)
    for k in range(3):
        zc = gz0 + 0.045 + k * 0.07
        dz = (Z - zc) * zt
        rr = np.sqrt((ly - cy) ** 2 + dz ** 2)
        th = np.arctan2(dz, ly - cy)
        turns = ((lx * 50 + th / (2 * np.pi)) % 1.0) < 0.5
        coil |= g.full((np.abs(rr - 0.02) < 0.007) & turns & (np.abs(lx) < 0.082))
    g.fill(coil, [0.45, 0.37, 0.32])
    g.emit[coil] = 1.0
    guard = np.zeros(g.shape, bool)
    for k in range(5):
        guard |= g.full(np.abs(lx - (-0.08 + k * 0.04)) < 0.0045)
    for k in range(3):
        guard |= g.full(np.abs(Z - (gz0 + 0.04 + k * 0.075)) < 0.006)
    guard &= g.full((np.abs(lx) < 0.1) & (ly >= hy - 0.008) & (ly < hy + 0.004) & (Z >= gz0) & (Z < gz1))
    g.fill(guard, [0.36, 0.36, 0.37])
    # rough edge where the window was cut: a bent-out lip
    lip = (np.abs(lx) < 0.11) & (ly >= hy) & (ly < hy + 0.009) & (Z >= gz0 - 0.008) & (Z < gz1 + 0.008) & \
          ~((np.abs(lx) < 0.1) & (Z >= gz0) & (Z < gz1))
    noisy(g, lip, [0.5, 0.5, 0.5], rng, 0.1)
    # screws: rows along every panel edge and the lip
    sc = np.zeros(g.shape, bool)
    for zz in np.linspace(z0 + 0.025, z1 - 0.025, 4):
        for sx in (-1, 1):
            for sy in (-1, 1):
                sc |= g.full((np.abs(lx - sx * (hx - 0.012)) < 0.005) & (np.abs(ly - sy * hy) < 0.004) & (np.abs(Z - zz) < 0.008))
                sc |= g.full((np.abs(lx - sx * hx) < 0.004) & (np.abs(ly - sy * (hy - 0.012)) < 0.005) & (np.abs(Z - zz) < 0.008))
            sc |= g.full((np.abs(lx - sx * hx) < 0.007) & (np.abs(ly + 0.01) < 0.004) & (np.abs(Z - zz) < 0.008))
    for xx in (-0.07, 0.0, 0.07):
        for zz in (gz0 - 0.004, gz1 + 0.004):
            sc |= g.full((np.abs(lx - xx) < 0.005) & (ly >= hy) & (ly < hy + 0.009) & (np.abs(Z - zz) < 0.006))
    g.paint(sc, [0.26, 0.26, 0.27])
    g.fill(sc & g.full(ly >= hy), [0.26, 0.26, 0.27])
    # top: toggle switch in a bent bracket and a lamp in a bolt-on bezel
    zt0 = z1 + 0.014
    bracket = (np.abs(lx - 0.06) < 0.028) & (np.abs(ly + 0.02) < 0.022) & (Z >= zt0) & (Z < zt0 + 0.035)
    noisy(g, bracket, [0.22, 0.22, 0.23], rng)
    lever = (np.abs(lx - 0.06) < 0.005) & (np.abs(ly + 0.02 - (Z - zt0 - 0.035) * 0.5) < 0.005) & \
            (Z >= zt0 + 0.035) & (Z < zt0 + 0.07)
    noisy(g, lever, [0.7, 0.7, 0.7], rng)
    bezel = (np.sqrt((lx + 0.06) ** 2 + (ly - 0.03) ** 2) < 0.018) & (Z >= zt0) & (Z < zt0 + 0.014)
    noisy(g, bezel, [0.3, 0.3, 0.31], rng)
    lamp = (np.sqrt((lx + 0.06) ** 2 + (ly - 0.03) ** 2) < 0.011) & (Z >= zt0 + 0.014) & (Z < zt0 + 0.03)
    g.fill(lamp, [0.5, 0.14, 0.1])
    g.emit[g.full(lamp)] = 1.0
    # salvaged blower fan on the back, still in its appliance paint, held by two straps
    br = np.sqrt(lx ** 2 + ((Z - 0.19) * zt) ** 2)
    blower = (br < 0.09) & (ly <= -hy) & (ly > -hy - 0.05)
    noisy(g, blower, [0.74, 0.71, 0.62], rng, 0.06)
    g.carve(g.full((br < 0.065) & (ly <= -hy - 0.035) & ((np.round(br * 120) % 2) == 0)))
    for sx in (-1, 1):
        strap = (np.abs(lx - sx * 0.05) < 0.008) & (ly <= -hy + 0.002) & (ly > -hy - 0.054) & (br < 0.096)
        noisy(g, strap, [0.3, 0.3, 0.31], rng)
    return g


def to_west(g):
    """N-wall hearth -> W-wall hearth by swapping x and y (a mirror image on screen)."""
    w = Grid(g.ny, g.nx, g.nz, g.res, g.zres)
    w.occ = np.ascontiguousarray(g.occ.transpose(1, 0, 2))
    w.col = np.ascontiguousarray(g.col.transpose(1, 0, 2, 3))
    w.emit = np.ascontiguousarray(g.emit.transpose(1, 0, 2))
    w.selflit = np.ascontiguousarray(g.selflit.transpose(1, 0, 2))
    w.flat = g.flat
    w.smooth = None if g.smooth is None else np.ascontiguousarray(g.smooth.transpose(1, 0, 2))
    return w
