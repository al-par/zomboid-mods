"""Voxel model -> Project Zomboid 2x tile sprites (128x256 per square).

World units: x east and y south in tiles, z up in floors.
A square's sprite puts its north corner at z=0 on pixel (64, 192); one tile of (x - y)
is 64 px across, one tile of (x + y) is 32 px down, one floor is 192 px up.
"""
import numpy as np
from PIL import Image
from scipy import ndimage

TILE_W, TILE_H = 128, 256


class Grid:
    def __init__(self, nx, ny, nz=1.0, res=64, zres=128):
        self.res, self.zres = res, zres
        self.nx, self.ny, self.nz = nx, ny, nz
        self.shape = (int(nx * res), int(ny * res), int(round(nz * zres)))
        self.occ = np.zeros(self.shape, bool)
        self.col = np.zeros(self.shape + (3,), np.float32)
        self.emit = np.zeros(self.shape, np.float32)
        self.selflit = np.zeros(self.shape, np.float32)  # 1 = drawn unshaded (flames, embers)
        self.flat = False  # True = one shade per face, crisp edges like vanilla masonry
        self.smooth = None  # with flat: bool mask of voxels that keep smooth shading (curves, slopes)
        ix = (np.arange(self.shape[0]) + 0.5) / res
        iy = (np.arange(self.shape[1]) + 0.5) / res
        iz = (np.arange(self.shape[2]) + 0.5) / zres
        self.X, self.Y, self.Z = np.meshgrid(ix, iy, iz, indexing="ij", sparse=True)

    def full(self, m):
        return np.broadcast_to(m, self.shape)

    def fill(self, mask, color):
        mask = self.full(mask)
        self.occ |= mask
        self.col[mask] = np.asarray(color, np.float32)

    def paint(self, mask, color):
        mask = self.full(mask) & self.occ
        self.col[mask] = np.asarray(color, np.float32)

    def carve(self, mask):
        mask = self.full(mask)
        self.occ &= ~mask
        self.emit[mask] = 0

    def coords(self, mask):
        idx = np.nonzero(mask)
        return idx, ((idx[0] + 0.5) / self.res, (idx[1] + 0.5) / self.res, (idx[2] + 0.5) / self.zres)

    def surface(self):
        inner = ndimage.binary_erosion(self.occ, structure=np.ones((3, 3, 3), bool), border_value=0)
        return self.occ & ~inner

    def normals(self, sigma=1.5):
        d = ndimage.gaussian_filter(self.occ.astype(np.float32), sigma, mode="constant")
        gx, gy, gz = np.gradient(d)
        return -gx, -gy, -gz


FACE_SHADE = {"top": 1.0, "south": 0.86, "east": 0.68, "north": 0.6, "west": 0.6}


def render_tiles(g, squares, ss=2, ao_strength=1.0, emissive_only=False):
    """Render several squares of one object; outlines are computed on the combined image so
    the cut between two squares gets no seam. Returns {(i, j): (image, depth)}."""
    raws = {sq: _raw(g, sq[0], sq[1], ss, ao_strength, emissive_only) for sq in squares}
    offs = {sq: ((sq[0] - sq[1]) * 64 * ss, (sq[0] + sq[1]) * 32 * ss) for sq in squares}
    minx = min(o[0] for o in offs.values())
    miny = min(o[1] for o in offs.values())
    maxx = max(o[0] for o in offs.values()) + TILE_W * ss
    maxy = max(o[1] for o in offs.values()) + TILE_H * ss
    A = np.zeros((maxy - miny, maxx - minx), np.float32)
    S = np.full(A.shape, np.nan, np.float32)
    for sq in sorted(squares, key=lambda q: q[0] + q[1]):
        rgb, alpha, hs, hit = raws[sq]
        ox, oy = offs[sq][0] - minx, offs[sq][1] - miny
        win = (slice(oy, oy + TILE_H * ss), slice(ox, ox + TILE_W * ss))
        A[win] = np.maximum(A[win], alpha)
        S[win] = np.where(hit, hs, S[win])
    dark = np.ones(A.shape, np.float32)
    if not emissive_only:
        a = A > 0
        edge = a & ~ndimage.binary_erosion(a, iterations=ss)
        jump = np.zeros_like(a)
        for axis in (0, 1):
            dd = np.nan_to_num(np.abs(np.diff(S, axis=axis)), nan=0) > 0.06
            if axis == 0:
                jump[1:, :] |= dd
            else:
                jump[:, 1:] |= dd
        dark[jump & a] = 0.8
        dark[edge] = 0.62
    out = {}
    for sq in squares:
        rgb, alpha, hs, hit = raws[sq]
        ox, oy = offs[sq][0] - minx, offs[sq][1] - miny
        d = dark[oy:oy + TILE_H * ss, ox:ox + TILE_W * ss]
        out[sq] = _finish(rgb * d[..., None], alpha, hs, hit, ss, emissive_only)
    return out


def render_tile(g, ti, tj, ss=2, ao_strength=1.0, emissive_only=False):
    return render_tiles(g, [(ti, tj)], ss, ao_strength, emissive_only)[(ti, tj)]


def _raw(g, ti, tj, ss, ao_strength, emissive_only, glow=(1.0, 0.55, 0.15)):
    """Ray-cast the voxels inside square (ti, tj) as that square's sprite."""
    W, H = TILE_W * ss, TILE_H * ss
    SX, SY = np.meshgrid((np.arange(W) + 0.5) / ss, (np.arange(H) + 0.5) / ss)
    u = (SX - 64.0) / 64.0
    v = (SY - 192.0) / 32.0
    x0 = (u + v) / 2 + ti
    y0 = (v - u) / 2 + tj
    s_lo = np.maximum(np.maximum(ti - x0, tj - y0), 0.0)
    s_hi = np.minimum(np.minimum(ti + 1 - x0, tj + 1 - y0), 3.0 * g.nz)
    ds = min(0.4 / g.res, 1.2 / g.zres)
    nsteps = int(np.ceil(1.0 / ds)) + 2

    hit = np.zeros(SX.shape, bool)
    hidx = np.zeros(SX.shape + (3,), np.int32)
    pidx = np.full(SX.shape + (3,), -1, np.int32)
    hs = np.zeros(SX.shape, np.float32)
    prev = np.full(SX.shape + (3,), -1, np.int32)
    sx_, sy_, sz_ = g.shape
    for k in range(nsteps):
        s = s_hi - k * ds
        valid = (s >= s_lo) & ~hit
        if not valid.any():
            break
        x = x0 + s
        y = y0 + s
        z = s / 3.0
        ix = np.floor(x * g.res).astype(np.int32)
        iy = np.floor(y * g.res).astype(np.int32)
        iz = np.floor(z * g.zres).astype(np.int32)
        inb = valid & (ix >= 0) & (ix < sx_) & (iy >= 0) & (iy < sy_) & (iz >= 0) & (iz < sz_)
        occ = np.zeros(SX.shape, bool)
        occ[inb] = g.occ[ix[inb], iy[inb], iz[inb]]
        new = occ & inb
        if new.any():
            hit |= new
            hidx[new, 0] = ix[new]
            hidx[new, 1] = iy[new]
            hidx[new, 2] = iz[new]
            pidx[new] = prev[new]
            hs[new] = s[new]
        prev[..., 0] = ix
        prev[..., 1] = iy
        prev[..., 2] = iz

    face = np.full(SX.shape, "", object)
    rgb = np.zeros(SX.shape + (3,), np.float32)
    alpha = np.zeros(SX.shape, np.float32)
    if hit.any():
        if not hasattr(g, "_dens"):
            g._dens = ndimage.uniform_filter(g.occ.astype(np.float32), size=int(9 * g.res / 64) | 1, mode="constant")
        dens = g._dens
        h = hit
        hi = hidx[h]
        pi = pidx[h]
        first = pi[:, 0] < 0
        # the face we entered through is the boundary crossed last, i.e. at the smallest s
        inf = np.float32(1e9)
        sbx = np.where(pi[:, 0] != hi[:, 0], (hi[:, 0] + 1) / g.res - x0[h], inf)
        sby = np.where(pi[:, 1] != hi[:, 1], (hi[:, 1] + 1) / g.res - y0[h], inf)
        sbz = np.where(pi[:, 2] != hi[:, 2], 3.0 * (hi[:, 2] + 1) / g.zres, inf)
        sb = np.stack([sbx, sby, sbz], 1)
        ax = np.argmin(sb, 1)
        f = np.array(["east", "south", "top"], object)[ax]
        if first.any():
            cut = np.stack([ti + 1 - x0[h], tj + 1 - y0[h], np.full(h.sum(), 3.0 * g.nz)], 1)
            f[first] = np.array(["east", "south", "top"], object)[np.argmin(cut[first], 1)]
        if not hasattr(g, "_n"):
            g._n = g.normals(1.2 * g.res / 64)
        n = np.stack([c[hi[:, 0], hi[:, 1], hi[:, 2]] for c in g._n], 1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-6)
        if g.flat:
            nf = np.zeros_like(n)
            nf[f == "east", 0] = 1
            nf[f == "south", 1] = 1
            nf[f == "top", 2] = 1
            if g.smooth is not None:
                keep = g.smooth[hi[:, 0], hi[:, 1], hi[:, 2]]
                nf[keep] = n[keep]
            n = nf
        # linear light reproducing vanilla's top 1.0 / south 0.86 / east 0.68 faces
        shade = np.clip(0.5 + 0.18 * n[:, 0] + 0.36 * n[:, 1] + 0.5 * n[:, 2], 0.3, 1.05).astype(np.float32)
        base = g.col[hi[:, 0], hi[:, 1], hi[:, 2]]
        reach = 1.5 * g.res / 64
        pc = np.clip(np.rint(hi + n * reach).astype(int), 0, np.array(g.shape) - 1)
        d = dens[pc[:, 0], pc[:, 1], pc[:, 2]]
        ao = np.clip(1.0 - ao_strength * 1.25 * (d - 0.32), 0.3, 1.05)
        em = g.emit[hi[:, 0], hi[:, 1], hi[:, 2]]
        if emissive_only:
            c = np.asarray(glow, np.float32)[None, :] * np.clip(em, 0, 1)[:, None]
            a = np.clip(em, 0, 1)
            rgb[h] = c
            alpha[h] = a
        else:
            sl = g.selflit[hi[:, 0], hi[:, 1], hi[:, 2]][:, None]
            c = base * (shade * ao)[:, None] * (1 - sl) + base * sl
            rgb[h] = c
            alpha[h] = 1.0
        face[h] = f
    return rgb, alpha, hs, hit


def _finish(rgb, alpha, hs, hit, ss, emissive_only):
    rgba = np.concatenate([np.clip(rgb, 0, 1) * alpha[..., None], alpha[..., None]], axis=-1)
    rgba = rgba.reshape(TILE_H, ss, TILE_W, ss, 4).mean(axis=(1, 3))
    a = rgba[..., 3:4]
    col = np.where(a > 0, rgba[..., :3] / np.maximum(a, 1e-6), 0)
    out = np.concatenate([col, a], axis=-1)
    if emissive_only:
        out = soft_glow(out)
    img = Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    depth = np.where(hit, hs, np.nan).reshape(TILE_H, ss, TILE_W, ss).mean(axis=(1, 3))
    return img, depth


def soft_glow(rgba):
    a = rgba[..., 3]
    halo = ndimage.gaussian_filter(a, 2.0) * 0.55
    na = np.clip(np.maximum(a, halo), 0, 1)
    col = rgba[..., :3].copy()
    glow = np.array([1.0, 0.5, 0.12], np.float32)
    m = a < 1e-3
    col[m] = glow
    return np.concatenate([col, na[..., None]], axis=-1)


def value_noise(shape3, scale, rng, octaves=3):
    """Smooth 3D noise in [-1, 1] on a voxel grid; scale is the coarse cell size in voxels."""
    out = np.zeros(shape3, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cs = max(1, int(scale / (2 ** o)))
        small = rng.uniform(-1, 1, tuple(max(2, s // cs + 2) for s in shape3)).astype(np.float32)
        big = ndimage.zoom(small, [shape3[i] / small.shape[i] for i in range(3)], order=1)
        big = big[: shape3[0], : shape3[1], : shape3[2]]
        pad = [(0, shape3[i] - big.shape[i]) for i in range(3)]
        big = np.pad(big, pad, mode="edge")
        out += amp * big
        tot += amp
        amp *= 0.5
    return out / tot
