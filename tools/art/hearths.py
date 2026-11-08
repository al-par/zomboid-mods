"""Home Heating hearths, built along a N wall (to_west() for W walls).

Frame: x along the wall (0..W), y out of the wall, z up in floors.

Families, each 2 or 3 tiles wide, in four looks (brick/stone, rough/neat):
1. hood:  a raised bed with a log store in its face, cheeks carrying a heavy beam, and a
          smoke hood narrowing into the stack.
2. range: a waist-high masonry cooking counter with the fire on top, wood stores below, and
          a straight chimney breast the full width.
3. oven:  a low fire with its own hood on one side, a domed bake oven on a plinth on the other.

The pot bar (bar across the opening, an S-hook pot and a cauldron on a chain) is an optional
add-on, drawn only when kit=True. lit=True adds the fire and firelight; that render is the lit
overlay, so the game's flame animation is not used.
"""
import copy

import numpy as np

from iso import Grid, value_noise
from models import Z_TO_TILE, rng_for, skin, tex_palette, noisy

IRON = [0.16, 0.15, 0.15]
TOP = 0.985
FAMILIES = ("hood", "range", "oven")
STYLES = ("brick_rough", "brick_neat", "stone_rough", "stone_neat")


def layout(family, W):
    """All dimensions of one hearth design."""
    P = {"family": family, "W": W}
    cw = 0.38 if W == 3 else 0.3
    x0, x1 = 0.06, W - 0.06
    if family == "hood":
        P.update(PLAT_Z=0.16, PLAT_Y=0.9, BACK_Y=0.14, CHEEK_Y=0.64, HOOD0=0.55, BEAM_H=0.065,
                 HOOD1=0.8, BEAM_FRONT=0.8, HOOD_FY=(0.8, 0.44), STACK_Y=0.44)
        fx0, fx1 = x0, x1
        P["HOOD_HX"] = ((fx1 - fx0) / 2, 0.78 if W == 3 else 0.5)
        P["CHEEK"] = ((fx0, fx0 + cw), (fx1 - cw, fx1))
        P["BED_X"] = (fx0, fx1)
    elif family == "range":
        P.update(PLAT_Z=0.3, PLAT_Y=0.8, BACK_Y=0.12, CHEEK_Y=0.62, HOOD0=0.69, BEAM_H=0.06,
                 HOOD1=TOP, BEAM_FRONT=0.74, HOOD_FY=(0.6, 0.6), STACK_Y=0.6)
        fx0, fx1 = x0, x1
        P["HOOD_HX"] = ((fx1 - fx0) / 2 - 0.06, (fx1 - fx0) / 2 - 0.06)
        P["CHEEK"] = ((fx0, fx0 + cw), (fx1 - cw, fx1))
        P["BED_X"] = (fx0, fx1)
    elif family == "oven":
        ow = 1.0 if W == 3 else 0.84
        fx0, fx1 = x0, W - ow
        P.update(PLAT_Z=0.1, PLAT_Y=0.86, BACK_Y=0.14, CHEEK_Y=0.62, HOOD0=0.52, BEAM_H=0.06,
                 HOOD1=0.78, BEAM_FRONT=0.76, HOOD_FY=(0.76, 0.42), STACK_Y=0.42)
        P["HOOD_HX"] = ((fx1 - fx0) / 2, 0.42 if W == 3 else 0.34)
        P["CHEEK"] = ((fx0, fx0 + cw * 0.9), (fx1 - 0.24, fx1))
        P["BED_X"] = (fx0, fx1)
        P["OVEN"] = (fx1, x1)
        P["OVEN_Z"] = 0.27
    else:
        raise ValueError(family)
    P["CX"] = (fx0 + fx1) / 2
    P["FIRE_X"] = (fx0, fx1)
    c0, c1 = P["CHEEK"][0][1], P["CHEEK"][1][0]
    P["OPEN"] = (c0, c1)
    P["BAR_Z"] = P["HOOD0"] - 0.11
    P["BAR_Y"] = P["BEAM_FRONT"] - 0.28
    P["POT_R"] = 0.19 if (c1 - c0) > 1.6 else 0.15
    P["POT"] = ((c0 + c1) / 2, P["BAR_Y"], P["BAR_Z"] - 0.13)
    P["FIRE"] = (P["POT"][0], P["BAR_Y"] - 0.04, P["PLAT_Z"] + 0.05)
    return P


def fire_tile(family, W):
    """Index of the square that holds the fire (the IsoFireplace), counted from the wall's start."""
    return int(layout(family, W)["FIRE"][0])


def box(g, a0, a1, b0, b1, z0, z1):
    return (g.X >= a0) & (g.X < a1) & (g.Y >= b0) & (g.Y < b1) & (g.Z >= z0) & (g.Z < z1)


def rod(g, p0, p1, r):
    """Round bar between two points (x, y in tiles, z in floors)."""
    p0 = np.array([p0[0], p0[1], p0[2] * Z_TO_TILE])
    p1 = np.array([p1[0], p1[1], p1[2] * Z_TO_TILE])
    d = p1 - p0
    L2 = max((d ** 2).sum(), 1e-9)
    px, py, pz = g.X - p0[0], g.Y - p0[1], g.Z * Z_TO_TILE - p0[2]
    t = np.clip((px * d[0] + py * d[1] + pz * d[2]) / L2, 0, 1)
    return (px - t * d[0]) ** 2 + (py - t * d[1]) ** 2 + (pz - t * d[2]) ** 2 < r * r


def ball(g, c, r, squash=1.0):
    return (g.X - c[0]) ** 2 + (g.Y - c[1]) ** 2 + ((g.Z - c[2]) * Z_TO_TILE * squash) ** 2 < r * r


def hood_mask(g, P):
    t = np.clip((g.Z - P["HOOD0"]) / max(P["HOOD1"] - P["HOOD0"], 1e-3), 0, 1)
    fy = P["HOOD_FY"][0] + (P["HOOD_FY"][1] - P["HOOD_FY"][0]) * t
    hx = P["HOOD_HX"][0] + (P["HOOD_HX"][1] - P["HOOD_HX"][0]) * t
    return (g.Y < fy) & (np.abs(g.X - P["CX"]) < hx) & (g.Z >= P["HOOD0"] + P["BEAM_H"]) & (g.Z < P["HOOD1"])


def beam_mask(g, P):
    hx = P["HOOD_HX"][0]
    return box(g, P["CX"] - hx, P["CX"] + hx, P["BEAM_FRONT"] - 0.24, P["BEAM_FRONT"], P["HOOD0"], P["HOOD0"] + P["BEAM_H"])


def oven_masks(g, P):
    """Plinth and dome of the bake oven, plus its mouth."""
    o0, o1 = P["OVEN"]
    ocx, oz = (o0 + o1) / 2, P["OVEN_Z"]
    plinth = box(g, o0, o1, 0, 0.74, 0, oz)
    rx, ry, rz = (o1 - o0) / 2 - 0.02, 0.5, 0.22
    dome = (((g.X - ocx) / rx) ** 2 + (g.Y / ry) ** 2 + ((g.Z - oz) / rz) ** 2 < 1) & (g.Z >= oz)
    mouth = box(g, ocx - 0.16, ocx + 0.16, 0.3, 0.6, oz, oz + 0.17)
    return plinth, dome, mouth


def masonry(g, P):
    """Bed, fireback, cheeks, throat, hood, stack (and the oven) as one solid."""
    bx0, bx1 = P["BED_X"]
    (a0, a1), (b0, b1) = P["CHEEK"]
    hx0, hx1 = P["HOOD_HX"]
    CX = P["CX"]
    bed = box(g, bx0, bx1, 0, P["PLAT_Y"], 0, P["PLAT_Z"])
    back = box(g, a0, b1, 0, P["BACK_Y"], 0, P["HOOD0"] + P["BEAM_H"])
    cheeks = box(g, a0, a1, 0, P["CHEEK_Y"], 0, P["HOOD0"]) | box(g, b0, b1, 0, P["CHEEK_Y"], 0, P["HOOD0"])
    throat = box(g, CX - hx0, CX + hx0, 0, P["BEAM_FRONT"] - 0.18, P["HOOD0"], P["HOOD0"] + P["BEAM_H"])
    stack = box(g, CX - hx1, CX + hx1, 0, P["STACK_Y"], P["HOOD1"], TOP)
    m = bed | back | cheeks | throat | hood_mask(g, P) | stack
    if "OVEN" in P:
        plinth, dome, mouth = oven_masks(g, P)
        m = m | plinth | dome | mouth
    return g.full(m)


def opening(g, P):
    o0, o1 = P["OPEN"]
    return g.full(box(g, o0, o1, P["BACK_Y"], 9, P["PLAT_Z"], P["HOOD0"]))


def log_store(g, rng, P, spans, arched, top=None, y_front=None, depth=0.4):
    """Openings in a masonry face, stacked with split logs, end grain out."""
    hole = np.zeros(g.shape, bool)
    top = (P["PLAT_Z"] - 0.035) if top is None else top
    yf = P["PLAT_Y"] if y_front is None else y_front
    for x0, x1 in spans:
        m = box(g, x0, x1, yf - depth, yf + 0.01, 0, top)
        if arched:
            cx_, r = (x0 + x1) / 2, (x1 - x0) / 2
            m = m & ((g.Z < top - 0.04) | (((g.X - cx_) ** 2 + ((g.Z - (top - 0.04)) * Z_TO_TILE * 2.2) ** 2) < r * r))
        hole |= g.full(m)
    g.carve(hole)
    g.fill(hole & g.full(g.Y < yf - depth + 0.01), [0.1, 0.09, 0.08])
    for x0, x1 in spans:
        r = 0.038
        nrow = int((top - 0.005) * Z_TO_TILE / (2 * r * 0.95))
        for row in range(nrow):
            n = int((x1 - x0 - 0.01) / (2 * r))
            for k in range(n - row % 2):
                lx = x0 + r + 0.008 + k * 2 * r + (row % 2) * r + rng.uniform(-0.004, 0.004)
                lz = (r + row * 2 * r * 0.92) / Z_TO_TILE + 0.002
                rr = r * rng.uniform(0.85, 1.0)
                cyl = ((g.X - lx) ** 2 + ((g.Z - lz) * Z_TO_TILE) ** 2 < rr * rr) & (g.Y >= yf - depth + 0.02) & \
                    (g.Y < yf - rng.uniform(0.0, 0.03))
                m = g.full(cyl) & hole
                g.fill(m, [0.32, 0.22, 0.14])
                ends = m & g.full(g.Y >= yf - 0.06)
                ei, (ex, ey, ez) = g.coords(ends)
                d = np.sqrt((ex - lx) ** 2 + ((ez - lz) * Z_TO_TILE) ** 2)
                c = np.where((d > rr - 0.007)[:, None], np.float32([0.3, 0.2, 0.12]),
                             np.float32([0.68, 0.53, 0.35]) * (0.93 + 0.08 * np.sin(d * 320))[:, None])
                g.col[ei] = c


def soot(g, P, strength=1.0):
    X, Y, Z = g.X, g.Y, g.Z
    o0, o1 = P["OPEN"]
    FX = P["FIRE"][0]
    inner = (X > o0 - 0.02) & (X < o1 + 0.02) & (Y < P["CHEEK_Y"] + 0.02) & (Z >= P["PLAT_Z"] - 0.01) & (Z < P["HOOD0"] + 0.02)
    span = max(P["HOOD0"] - P["PLAT_Z"], 0.1)
    grade = (0.35 + 0.55 * np.exp(-((X - FX) / 0.75) ** 2)) * (0.55 + 0.45 * np.clip((Z - P["PLAT_Z"]) / span, 0, 1))
    f = g.full(inner * grade)
    plume = np.exp(-((X - FX) / 0.7) ** 2) * np.clip(1 - (Z - P["HOOD0"]) / 0.22, 0, 1) * (Z >= P["HOOD0"])
    f = np.maximum(f, g.full(plume) * 0.6)
    g.col *= (1 - f * strength)[..., None]
    ash = g.full((X > o0) & (X < o1) & (Y >= P["BACK_Y"]) & (Y < P["CHEEK_Y"]) & (Z >= P["PLAT_Z"]) & (Z < P["PLAT_Z"] + 0.008))
    g.fill(ash, [0.34, 0.32, 0.30])
    ai, (ax_, _, _) = g.coords(ash)
    rng = np.random.default_rng(3)
    fade = np.clip(1 - np.abs(ax_ - FX) / 1.0, 0, 1)
    g.col[ai] *= (0.6 + 0.5 * rng.random((len(ai[0]), 1)) * fade[:, None]).astype(np.float32)


def irons(g, rng, P):
    """Pieces every hearth has: a pair of low firedogs either side of the fire."""
    iron = lambda m, amt=0.12: noisy(g, m, IRON, rng, amt, 10)
    FX, Z0 = P["FIRE"][0], P["PLAT_Z"]
    fy = P["CHEEK_Y"] - 0.02
    half = min(0.44, (P["OPEN"][1] - P["OPEN"][0]) / 2 - 0.12)
    for fx in (FX - half, FX + half):
        iron(rod(g, (fx, fy, Z0 + 0.03), (fx, P["BACK_Y"] + 0.1, Z0 + 0.03), 0.013))
        iron(rod(g, (fx, fy, Z0), (fx, fy, Z0 + 0.09), 0.015))
        iron(ball(g, (fx, fy, Z0 + 0.1), 0.024))
        iron(rod(g, (fx - 0.05, fy + 0.02, Z0), (fx + 0.05, fy + 0.02, Z0 + 0.006), 0.01))


def oven_door(g, rng, P):
    if "OVEN" not in P:
        return
    iron = lambda m, amt=0.1: noisy(g, m, IRON, rng, amt, 10)
    o0, o1 = P["OVEN"]
    ox, oz = (o0 + o1) / 2, P["OVEN_Z"]
    ow, y = 0.11, 0.6
    z0, z1 = oz + 0.015, oz + 0.15
    door = (np.abs(g.X - ox) < ow) & (g.Y >= y - 0.004) & (g.Y < y + 0.012) & (g.Z >= z0) & \
        ((g.Z < z1 - 0.04) | ((g.X - ox) ** 2 + ((g.Z - z1 + 0.04) * Z_TO_TILE * 1.6) ** 2 < ow * ow))
    iron(door)
    for hz in (z0 + 0.025, z1 - 0.055):
        iron(box(g, ox - ow, ox + ow * 0.6, y + 0.012, y + 0.02, hz, hz + 0.012), 0.06)
    iron(rod(g, (ox + ow - 0.03, y + 0.03, z0 + 0.05), (ox + ow - 0.03, y + 0.03, z0 + 0.08), 0.008))


def pot_bar(g, rng, P):
    """The add-on: an iron bar set into both cheeks, a cauldron on a chain and a pot on an S-hook."""
    iron = lambda m, amt=0.12: noisy(g, m, IRON, rng, amt, 10)
    az, BY = P["BAR_Z"], P["BAR_Y"]
    x0, x1 = P["OPEN"][0] - 0.04, P["OPEN"][1] + 0.04
    iron(box(g, x0, x1, BY - 0.016, BY + 0.016, az - 0.016 / Z_TO_TILE, az + 0.016 / Z_TO_TILE), 0.14)
    for sx in (P["OPEN"][0], P["OPEN"][1] - 0.03):
        iron(box(g, sx, sx + 0.03, BY - 0.026, BY + 0.026, az - 0.03 / Z_TO_TILE, az + 0.03 / Z_TO_TILE), 0.1)
        for dz in (-0.022, 0.022):
            iron(ball(g, (sx + 0.015, BY + 0.026, az + dz / Z_TO_TILE), 0.008))
    POT, R = P["POT"], P["POT_R"]
    # an S-hook with a smaller pot hanging to one side of the cauldron
    sh = POT[0] - R - 0.14
    if sh - 0.08 > P["OPEN"][0]:
        iron(rod(g, (sh, BY, az), (sh, BY, az - 0.07), 0.006))
        sp_z = az - 0.07
        sp = ((g.X - sh) ** 2 + (g.Y - BY) ** 2 < 0.075 ** 2) & (g.Z < sp_z - 0.005) & (g.Z >= sp_z - 0.09)
        iron(sp & ~(((g.X - sh) ** 2 + (g.Y - BY) ** 2 < 0.062 ** 2) & (g.Z > sp_z - 0.08)), 0.1)
        iron((np.abs(np.sqrt((g.X - sh) ** 2 + ((g.Z - sp_z + 0.005) * Z_TO_TILE) ** 2) - 0.072) < 0.006) &
             (np.abs(g.Y - BY) < 0.006) & (g.Z > sp_z - 0.005))
    # a long pot hook on the other side
    kh = POT[0] + R + 0.12
    if kh + 0.04 < P["OPEN"][1]:
        iron(rod(g, (kh, BY, az), (kh, BY, az - 0.12), 0.006))
        iron((np.abs(np.sqrt((g.X - kh - 0.018) ** 2 + ((g.Z - az + 0.12) * Z_TO_TILE) ** 2) - 0.018) < 0.005) &
             (np.abs(g.Y - BY) < 0.005) & (g.Z < az - 0.12))
    # chain and cauldron
    hook_z = POT[2] + 0.085
    nlink = max(1, int((az - hook_z) / 0.022))
    for k in range(nlink):
        z0 = az - k * 0.022
        if k % 2 == 0:
            m = (np.abs(np.sqrt((g.X - POT[0]) ** 2 + ((g.Z - z0 + 0.011) * Z_TO_TILE) ** 2) - 0.016) < 0.005) & \
                (np.abs(g.Y - POT[1]) < 0.005)
        else:
            m = (np.abs(np.sqrt((g.Y - POT[1]) ** 2 + ((g.Z - z0 + 0.011) * Z_TO_TILE) ** 2) - 0.016) < 0.005) & \
                (np.abs(g.X - POT[0]) < 0.005)
        iron(m, 0.05)
    depth = 0.13
    bowl = ((g.X - POT[0]) ** 2 + (g.Y - POT[1]) ** 2) / R ** 2 + ((g.Z - POT[2]) / depth) ** 2 < 1
    bowl &= g.Z < POT[2]
    inner = ((g.X - POT[0]) ** 2 + (g.Y - POT[1]) ** 2) / (R - 0.016) ** 2 + ((g.Z - POT[2]) / (depth - 0.01)) ** 2 < 1
    iron(bowl, 0.1)
    g.carve(g.full(inner & (g.Z > POT[2] - 0.025)))
    stew = g.full(inner & (g.Z <= POT[2] - 0.025) & (g.Z > POT[2] - 0.035))
    g.fill(stew, [0.32, 0.22, 0.12])
    si, _ = g.coords(stew)
    g.col[si] *= (0.8 + 0.4 * np.clip(value_noise(g.shape, 25, rng)[si] + 0.5, 0, 1))[:, None]
    rr = np.sqrt((g.X - POT[0]) ** 2 + (g.Y - POT[1]) ** 2)
    iron((rr < R + 0.012) & (rr > R - 0.016) & (g.Z >= POT[2] - 0.006) & (g.Z < POT[2] + 0.006), 0.06)
    iron((np.abs(np.sqrt((g.X - POT[0]) ** 2 + ((g.Z - POT[2]) * Z_TO_TILE) ** 2) - (R + 0.005)) < 0.007) &
         (np.abs(g.Y - POT[1]) < 0.007) & (g.Z > POT[2]), 0.06)
    for a in (0, 2.1, 4.2):
        lx_, ly_ = POT[0] + 0.62 * R * np.cos(a), POT[1] + 0.62 * R * np.sin(a)
        iron(rod(g, (lx_, ly_, POT[2] - depth * 0.75), (lx_ + 0.02 * np.cos(a), ly_ + 0.02 * np.sin(a),
                                                       max(POT[2] - depth - 0.02, P["PLAT_Z"])), 0.012))


def cold_ashes(g, rng, P):
    FX = P["FIRE"][0]
    for _ in range(10):
        cx_ = FX + rng.uniform(-0.4, 0.4)
        cy_ = rng.uniform(P["BACK_Y"] + 0.08, P["CHEEK_Y"] - 0.04)
        r = rng.uniform(0.02, 0.04)
        m = ball(g, (cx_, cy_, P["PLAT_Z"]), r, squash=2) & (g.Z >= P["PLAT_Z"])
        noisy(g, m, [0.11, 0.1, 0.1], rng, 0.2, 12)


def fire(g, rng, P, kit):
    """Logs on the bed, coals, flames (licking up the cauldron when the pot bar is fitted), firelight."""
    FX, FY, _ = P["FIRE"]
    fz = P["PLAT_Z"] + 0.02
    logs = [((FX - 0.34, FY - 0.12, fz + 0.015), (FX + 0.34, FY - 0.06, fz + 0.015), 0.045),
            ((FX - 0.3, FY + 0.1, fz + 0.015), (FX + 0.32, FY + 0.05, fz + 0.015), 0.042),
            ((FX - 0.12, FY - 0.17, fz + 0.03), (FX + 0.08, FY + 0.16, fz + 0.045), 0.038)]
    crack = value_noise(g.shape, 30, rng)
    for p0, p1, r in logs:
        m = g.full(rod(g, p0, p1, r)) & ~g.occ
        g.fill(m, [0.2, 0.13, 0.08])
        idx, _ = g.coords(m)
        g.col[idx] *= (0.7 + 0.6 * np.clip(value_noise(g.shape, 10, rng)[idx] + 0.5, 0, 1))[:, None]
        hot = m & (crack > 0.12)
        g.col[hot] = [1.0, 0.45, 0.1]
        g.selflit[hot] = 0.9
    bi, (bx, by, bz) = g.coords(g.full((np.abs(g.X - FX) < 0.6) & (g.Y > P["BACK_Y"]) & (g.Y < P["CHEEK_Y"] + 0.06) &
                                       (g.Z >= P["PLAT_Z"]) & (g.Z < P["PLAT_Z"] + 0.01)) & g.occ)
    heat = np.exp(-((bx - FX) / 0.36) ** 2 - ((by - FY) / 0.16) ** 2)
    speck = value_noise(g.shape, 90, rng)[bi]
    w = np.clip(heat * 1.4 + speck * 1.5 - 0.35, 0, 1)
    hot_c = np.float32([1.0, 0.5, 0.12]) * (0.75 + 0.25 * np.clip(speck * 3, -1, 1))[:, None]
    g.col[bi] = g.col[bi] * (1 - w[:, None]) + hot_c * w[:, None]
    g.selflit[bi] = w * 0.9
    X, Y, Zt = g.X, g.Y, g.Z * Z_TO_TILE
    wob = value_noise(g.shape, 14, rng)
    pot_bottom = (P["POT"][2] - 0.13) * Z_TO_TILE
    for k in range(24):
        ang = rng.uniform(0, 2 * np.pi)
        rad_ = rng.uniform(0.0, 0.2) ** 0.8
        fx = FX + rad_ * np.cos(ang) * 1.3
        fy = FY + rad_ * np.sin(ang) * 0.6
        z0 = (fz + rng.uniform(0.01, 0.03)) * Z_TO_TILE
        under = kit and rad_ < 0.16
        h = (pot_bottom - z0 + 0.03) if under else rng.uniform(0.1, 0.2) * Z_TO_TILE
        r0 = rng.uniform(0.07, 0.11)
        if fy > FY + 0.03:  # keep the flames in front low so the pot and firedogs stay readable
            h, r0 = min(h, rng.uniform(0.05, 0.09) * Z_TO_TILE), r0 * 0.75
        t = (Zt - z0) / max(h, 0.05)
        sway = 0.03 * np.sin(t * 4 + k) * t
        rad = r0 * np.clip(1 - t, 0, 1) ** 0.55 * (1 + 0.5 * wob)
        m = g.full((np.sqrt((X - fx - sway) ** 2 + (Y - fy) ** 2) < rad) & (t >= -0.15) & (t < 1)) & ~g.occ
        tt = np.broadcast_to(t, g.shape)[m]
        core = np.clip(1 - tt * 1.6, 0, 1)[:, None]
        tip = np.clip((tt - 0.55) / 0.45, 0, 1)[:, None]
        c = np.float32([1.0, 0.92, 0.55]) * core + np.float32([1.0, 0.55, 0.12]) * (1 - core)
        c = c * (1 - tip) + np.float32([0.85, 0.22, 0.06]) * tip
        g.occ[m] = True
        g.col[m] = c
        g.selflit[m] = 1.0
    d = np.sqrt((g.X - FX) ** 2 + (g.Y - FY) ** 2 + ((g.Z - P["FIRE"][2] - 0.05) * Z_TO_TILE) ** 2)
    L = g.full(1.8 * np.exp(-d / 0.55))
    lit = g.occ & (g.selflit < 0.5)
    g.col[lit] *= 1 + L[lit][:, None] * np.float32([1.0, 0.55, 0.2])


def dressed_blocks(g, mask, rng, base, edges_u, rows, joint=0.006, var=0.06):
    """Dressed stone: one shade per block, thin dark joints. u runs along x on faces that look
    along y and along y on faces that look along x."""
    m = g.full(mask) & g.occ
    idx, (x, y, z) = g.coords(m)
    if not len(x):
        return
    nx, ny, _ = (c[idx] for c in g.normals(1.0))
    side = np.abs(nx) > np.abs(ny)
    u = np.where(side, y + 5.0, x)
    edges = np.sort(np.asarray(edges_u))
    zr = np.asarray(rows)
    ri = np.clip(np.searchsorted(zr, z) - 1, 0, len(zr) - 2)
    ui = np.searchsorted(edges, u)
    shade = 1 + var * rng.normal(0, 1, 4096)
    c = np.float32(base) * shade[(ui * 31 + ri * 7 + side * 3) % 4096][:, None]
    c *= (1 + 0.035 * value_noise(g.shape, 9, rng)[idx])[:, None]
    jt = (np.min(np.abs(u[:, None] - edges[None, :]), axis=1) < joint) | (np.min(np.abs(z[:, None] - zr[None, :]), axis=1) < 0.004)
    c[jt] *= 0.6
    g.col[idx] = c


def oak_beam(g, rng, m, P):
    g.fill(m, [0.36, 0.25, 0.16])
    bi, (bx, by, bz) = g.coords(g.full(m))
    across = bz * Z_TO_TILE + (P["BEAM_FRONT"] - by) * 0.6 + 0.02 * np.sin(bx * 7) + 0.015 * value_noise(g.shape, 4, rng)[bi]
    grain = np.sin(across * 260) * 0.5 + 0.5
    char = np.clip(1 - (bz - P["HOOD0"]) / 0.04, 0, 1) * np.exp(-((bx - P["FIRE"][0]) / 1.0) ** 2)
    g.col[bi] *= (0.82 + 0.25 * grain)[:, None] * (1 - 0.7 * char)[:, None]
    checks = np.abs(np.sin(across * 41 + bx * 1.3)) > 0.985
    g.col[tuple(a[checks] for a in bi)] *= 0.5


def store_spans(P, arched):
    """Where the log stores go in the bed face."""
    W, fam = P["W"], P["family"]
    if fam == "oven":
        o0, o1 = P["OVEN"]
        return [(o0 + 0.14, o1 - 0.14)]
    b0, b1 = P["BED_X"]
    if not arched:
        return [(b0 + 0.44, b1 - 0.44)]
    mid = (b0 + b1) / 2
    return [(b0 + 0.39, mid - 0.2), (mid + 0.2, b1 - 0.39)]


def stores(g, rng, P, arched):
    if P["family"] == "oven":
        log_store(g, rng, P, store_spans(P, arched), arched, top=P["OVEN_Z"] - 0.04, y_front=0.74, depth=0.36)
    else:
        log_store(g, rng, P, store_spans(P, arched), arched)


def corbels(g, P, rng, t, steps, step_h, ext):
    for (c0, c1) in P["CHEEK"]:
        for k in range(steps):
            zc = P["HOOD0"] - (k + 1) * step_h
            g.fill(box(g, c0, c1, P["CHEEK_Y"], P["CHEEK_Y"] + ext * (steps - k), zc, zc + step_h), tex_palette(t, 1, rng)[0])


def build_base(family, W, style, west):
    """Masonry, trim, soot and firedogs; the add-on and fire go on afterwards."""
    P = layout(family, W)
    g = Grid(W, 1, 1.0, res=64, zres=192)
    g.flat = True
    rng = rng_for(f"hearth_{family}_{W}_{style}")
    X, Y, Z = g.X, g.Y, g.Z
    body = masonry(g, P)
    open_ = opening(g, P)
    solid = body & ~open_
    beam = beam_mask(g, P)
    CX = P["CX"]
    hx0, hx1 = P["HOOD_HX"]
    HOOD0, BEAM_H, CHEEK_Y, PLAT_Y, PLAT_Z = P["HOOD0"], P["BEAM_H"], P["CHEEK_Y"], P["PLAT_Y"], P["PLAT_Z"]
    b0, b1 = P["BED_X"]
    BF = P["BEAM_FRONT"]

    if style == "brick_rough":
        t = skin(g, solid & ~g.full(beam), "brick_rough", west)
        lump = value_noise(g.shape, 7, rng)
        g.occ &= ~(g.full(Y >= CHEEK_Y - 0.016) & (lump > 0.25) & g.full((Z > 0.02) & (Z < HOOD0)) & ~open_)
        proud = g.full((Y >= PLAT_Y) & (Y < PLAT_Y + 0.016) & (Z < PLAT_Z - 0.01) & (X >= b0) & (X < b1)) & (lump < -0.3)
        g.fill(proud, t.face_col)
        pi, _ = g.coords(proud)
        g.col[pi] = tex_palette(t, len(pi[0]), rng)
        oak_beam(g, rng, beam, P)
        stores(g, rng, P, arched=False)
        corbels(g, P, rng, t, 2, 0.03, 0.06)
    elif style == "brick_neat":
        t = skin(g, solid, "brick_neat", west)
        bi, (bx, by, bz) = g.coords(g.full(beam) & g.occ)
        k = np.floor(bx / 0.07).astype(int)
        cols = tex_palette(t, 97, rng) * np.float32([0.9, 0.85, 0.85])
        c = cols[k % 97]
        jt = ((bx % 0.07) < 0.009) | ((bz - HOOD0) > BEAM_H - 0.006)
        c[jt] = t.joint_col
        g.col[bi] = c
        noisy(g, box(g, CX - hx0 + 0.02, CX + hx0 - 0.02, BF - 0.3, BF + 0.008, HOOD0 - 0.008, HOOD0 + 0.004),
              [0.18, 0.17, 0.17], rng, 0.1)
        band = box(g, CX - hx0, CX + hx0, BF - 0.3, BF + 0.03, HOOD0 + BEAM_H, HOOD0 + BEAM_H + 0.028)
        g.fill(band, t.face_col)
        skin(g, band, "brick_neat", west)
        for k2 in range(int(2 * hx0 / 0.11)):
            dx = CX - hx0 + 0.03 + k2 * 0.11
            g.fill(box(g, dx, dx + 0.055, BF, BF + 0.02, HOOD0 + BEAM_H - 0.028, HOOD0 + BEAM_H), tex_palette(t, 1, rng)[0])
        corbels(g, P, rng, t, 3, 0.028, 0.05)
        stores(g, rng, P, arched=True)
        kerb = box(g, b0, b1, PLAT_Y - 0.06, PLAT_Y + 0.012, PLAT_Z - 0.03, PLAT_Z + 0.012)
        g.fill(kerb, t.face_col)
        ki, (kx, ky, kz) = g.coords(g.full(kerb))
        c = tex_palette(t, 97, rng)[np.floor(kx / 0.07).astype(int) % 97]
        c[(kx % 0.07) < 0.009] = t.joint_col
        g.col[ki] = c
    elif style == "stone_rough":
        lump = value_noise(g.shape, 5, rng)
        rough = solid & ~(g.full((Y > CHEEK_Y - 0.05) & (Z < HOOD0) | (Y > PLAT_Y - 0.05) & (Z < PLAT_Z)) & (lump > 0.2))
        rough |= g.full(box(g, b0, b1, 0, PLAT_Y + 0.03, 0, PLAT_Z - 0.01)) & (lump < -0.22)
        t = skin(g, rough & ~g.full(beam), "stone", west, joint_depth=2)
        g.occ &= ~(solid & ~rough)
        ln = value_noise(g.shape, 9, rng)
        lint = g.full(beam) & ~(g.full(Z > HOOD0 + BEAM_H - 0.015) & (ln > 0.12))
        g.fill(lint, t.face_col * 0.95)
        li, (lx_, ly_, lz_) = g.coords(lint)
        g.col[li] *= (1 + value_noise(g.shape, 5, rng, octaves=3)[li] * 0.2 + value_noise(g.shape, 28, rng)[li] * 0.12)[:, None]
        crack = np.abs(lx_ - (CX + 0.4) - (lz_ - HOOD0) * 1.5 + 0.02 * np.sin(lz_ * 300)) < 0.006
        g.col[tuple(a[crack] for a in li)] *= 0.45
        stores(g, rng, P, arched=False)
    elif style == "stone_neat":
        t = skin(g, solid & ~g.full(beam), "stone", west, joint_depth=1)
        ash = np.clip(t.face_col * 1.22, 0, 1)
        rows = list(np.arange(0, TOP + 0.08, 0.075))
        q = np.zeros(g.shape, bool)
        for ri in range(len(rows) - 1):
            z0, z1 = rows[ri], rows[ri + 1]
            w = 0.17 if ri % 2 == 0 else 0.1
            for (c0, c1) in P["CHEEK"]:
                if z1 <= HOOD0:
                    q |= g.full(box(g, c0, c1, CHEEK_Y - w, CHEEK_Y + 0.01, z0, z1))
            if z0 >= P["HOOD1"]:
                for sx in (CX - hx1, CX + hx1 - w):
                    q |= g.full(box(g, sx, sx + w, P["STACK_Y"] - 0.2, P["STACK_Y"] + 0.01, z0, z1))
        g.fill(q & g.full(Z < TOP), ash)
        edges = [c for ch in P["CHEEK"] for c in ch] + [CX - hx1 + 0.17, CX + hx1 - 0.17,
                                                        5 + CHEEK_Y - 0.17, 5 + CHEEK_Y - 0.1]
        dressed_blocks(g, q, rng, ash, edges, rows)
        g.fill(beam, ash)
        g.carve(g.full(beam & (Y - (BF - 0.03) > (Z - HOOD0) * Z_TO_TILE) & (Z < HOOD0 + 0.02)))
        dressed_blocks(g, beam, rng, ash, list(np.linspace(CX - hx0, CX + hx0, 6)), [HOOD0, HOOD0 + BEAM_H])
        for (c0, c1) in P["CHEEK"]:
            for k in range(3):
                zc = HOOD0 - (k + 1) * 0.026
                cm = box(g, c0 + 0.02, c1 - 0.02, CHEEK_Y, CHEEK_Y + 0.055 * (3 - k) - 0.01, zc, zc + 0.026)
                g.fill(cm, np.float32(ash) * (1.0 - 0.04 * k))
        kerb = box(g, b0, b1, PLAT_Y - 0.08, PLAT_Y + 0.014, PLAT_Z - 0.035, PLAT_Z + 0.014)
        g.fill(kerb, ash)
        dressed_blocks(g, kerb, rng, ash, list(np.arange(b0, b1, 0.46)), [PLAT_Z - 0.035, PLAT_Z + 0.014])
        stores(g, rng, P, arched=True)
    else:
        raise ValueError(style)

    if family == "oven":
        # the oven's dome has a dark baked crown and a smoke-stained mouth
        o0, o1 = P["OVEN"]
        _, dome, mouth = oven_masks(g, P)
        crown = g.full(dome) & g.occ & g.full(g.Z > P["OVEN_Z"] + 0.17)
        g.col[crown] *= 0.85
        stain = g.full(mouth | dome) & g.occ & g.full((np.abs(g.X - (o0 + o1) / 2) < 0.2) & (g.Z > P["OVEN_Z"] + 0.12) & (g.Y > 0.45))
        g.col[stain] *= 0.7
    soot(g, P)
    irons(g, rng, P)
    oven_door(g, rng, P)
    g.smooth = g.full((g.Z >= HOOD0 + BEAM_H + 0.01) & (g.Z < P["HOOD1"]) & (g.Y > P["STACK_Y"] - 0.02)) & \
        g.full(P["HOOD_FY"][0] != P["HOOD_FY"][1])
    if family == "oven":
        g.smooth = g.smooth | oven_masks(g, P)[1]
    return g, P


def variant(base, P, rng_name, kit, lit):
    g = copy.copy(base)
    g.occ = base.occ.copy()
    g.col = base.col.copy()
    g.emit = base.emit.copy()
    g.selflit = base.selflit.copy()
    for a in ("_dens", "_n"):
        if hasattr(g, a):
            delattr(g, a)
    rng = rng_for(rng_name)
    mason = g.occ.copy()
    if kit:
        pot_bar(g, rng, P)
    if lit:
        fire(g, rng, P, kit)
    else:
        cold_ashes(g, rng, P)
    g.smooth = (g.occ & ~mason) | (base.smooth if base.smooth is not None else False)
    return g


def kit_only(W=3, family="hood"):
    """The pot bar by itself, for the build cursor."""
    P = layout(family, W)
    g = Grid(W, 1, 1.0, res=64, zres=192)
    g.flat = True
    pot_bar(g, rng_for("kit"), P)
    g.smooth = g.occ.copy()
    return g, P


def render_grid(g, W, west):
    from iso import render_tiles
    from models import to_west
    if west:
        g = to_west(g)
        sq = [(0, j) for j in range(W)]
    else:
        sq = [(i, 0) for i in range(W)]
    r = render_tiles(g, sq)
    return [r[s][0] for s in sq]


def render_all(family, W, style, west):
    """{(kit, lit): [tile images along the wall]} for one design and facing."""
    base, P = build_base(family, W, style, west)
    out = {}
    for kit in (False, True):
        for lit in (False, True):
            g = variant(base, P, f"v_{family}_{W}_{style}_{kit}_{lit}", kit, lit)
            out[kit, lit] = render_grid(g, W, west)
    return out
