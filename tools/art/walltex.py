"""Vanilla wall sprites unskewed into flat textures, so hearths use the same brick and stone as the walls.

The game's W-wall sprites are painted separately from the N ones (browner brick, not just darker),
so each hearth face takes its texture from the vanilla wall that faces the same way."""
import os

import numpy as np
from PIL import Image

REF = os.path.join(os.environ["TEMP"], "hh_sprites")
# iso.py shade of the face each wall shows: a N wall shows its south face, a W wall its east face
SHADE = {"N": 0.86, "W": 0.68}

WALLS = {  # (face N, face W) from the vanilla entity scripts
    "brick_rough": ("walls_exterior_house_01_21", "walls_exterior_house_01_20"),  # BrickWallLvl1
    "brick_neat": ("walls_exterior_house_01_5", "walls_exterior_house_01_4"),     # BrickWallLvl2
    "stone": ("walls_logs_97", "walls_logs_96"),                                  # StoneWall
}


def unskew(name, face, v0=0.03, v1=0.97):
    """Wall sprite -> texture[v, u, rgba], u along the wall away from the north corner
    (64 texels per tile), v up the wall (192 texels per floor)."""
    s = np.asarray(Image.open(os.path.join(REF, name + ".png")).convert("RGBA"), np.float32) / 255
    # a N face starts 4 px left of the north corner and the next wall covers its last 4 columns,
    # so x 60..123 is one seamless period; a W sprite is drawn x 0..65, so its period is x 65 down to 2
    nv = int(192 * (v1 - v0))
    if face == "N":
        px = np.arange(60, 124)
        along = px - 64
    else:
        px = np.arange(65, 1, -1)
        along = 64 - px
    v = v0 + (np.arange(nv) + 0.5) / 192
    py = np.rint(192 + along[None, :] / 2 - 192 * v[:, None]).astype(int)
    tex = s[py, px[None, :]]
    return tex[::-1]  # row 0 at the bottom


class WallTexture:
    def __init__(self, key, face="N"):
        t = unskew(WALLS[key][0 if face == "N" else 1], face)
        rgb = t[..., :3] / SHADE[face]
        self.rgb = rgb.astype(np.float32)
        self.nv, self.nu = rgb.shape[:2]
        self.lum = rgb.mean(-1)
        self.sat = rgb.max(-1) - rgb.min(-1)
        if key.startswith("brick"):
            # mortar is the pale, unsaturated part
            score = self.lum - self.sat
            self.joint = score > np.percentile(score, 80)
        else:
            # stone joints are the dark outlines
            self.joint = self.lum < np.percentile(self.lum, 22)
        self.face_col = np.median(rgb[~self.joint], 0)
        self.joint_col = np.median(rgb[self.joint], 0)

    def sample(self, u, v):
        """u in tiles along the face, v in floors up it; both wrap."""
        iu = np.floor(np.mod(u, 1.0) * self.nu).astype(int) % self.nu
        iv = np.floor(np.mod(v * 192, self.nv)).astype(int) % self.nv
        return iu, iv


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "out")
    ims = []
    for k in WALLS:
        for f in "NW":
            w = WallTexture(k, f)
            t = unskew(WALLS[k][0 if f == "N" else 1], f)
            print(k, f, "alpha<1", int((t[..., 3] < 1).sum()), "white", int((t[..., :3].min(-1) > 0.97).sum()),
                  "face", w.face_col.round(3), "joint", w.joint_col.round(3))
            ims.append(Image.fromarray((t[::-1] * 255).astype(np.uint8), "RGBA").resize((64 * 4, t.shape[0] * 4), Image.NEAREST))
    sheet = Image.new("RGBA", (sum(i.width + 10 for i in ims), ims[0].height), (40, 40, 44, 255))
    x = 0
    for i in ims:
        sheet.alpha_composite(i, (x, 0))
        x += i.width + 10
    sheet.save(os.path.join(out, "walltex_2.png"))
