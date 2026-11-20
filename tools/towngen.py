#!/usr/bin/env python3
"""Builds the castle town (assets/town/*) + scripts/anime/town_data.gd from the Quaternius / Kenney kits.
usage: python3 -I towngen.py <village_gltf_dir> <props_gltf_dir> <kenney_glb_dir> <project_dir> [--preview dir]"""
import sys, os, json, struct, math
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from townlib import Scene, load_any, rot_y, preview

VIL, PRO, KEN, PROJ = [os.path.abspath(a) for a in sys.argv[1:5]]
PREV = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
OUTD = os.path.join(PROJ, "assets", "town")
os.makedirs(os.path.join(OUTD, "tex"), exist_ok=True)
V = lambda n: os.path.join(VIL, n + ".gltf")
P = lambda n: os.path.join(PRO, n + ".gltf")
K = lambda n: os.path.join(KEN, n + ".glb")

ORIGIN = (110.0, -60.0)
H0, H1, H2 = 6.0, 10.5, 17.0


def ss(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def town_h(u):
    return H0 + (H1 - H0) * ss(-38, -26, u) + (H2 - H1) * ss(22, 34, u)


WALL_TOP = 3.12


# ------------------------------------------------------------------ houses
class B:
    """one building type: exterior scene + interior scene + collision boxes (local coords, y from floor)"""

    def __init__(self, name, A, Bd):
        self.name, self.A, self.Bd = name, A, Bd
        self.out, self.inn = Scene(), Scene()
        self.boxes = []
        self.nx, self.nz = A // 2, Bd // 2

    def box(self, cx, cy, cz, sx, sy, sz):
        self.boxes.append([round(float(v), 3) for v in (cx, cy, cz, sx, sy, sz)])

    def prop(self, name, x, z, yaw=0.0, y=0.0, sc=1.0, col=True, scene=None):
        sc_ = scene or self.inn
        path = P(name)
        sc_.add(path, pos=(x, y, z), yaw=yaw, scale=sc)
        if col:
            pts = np.concatenate([p["pos"] for p in sc_.model(path)]) * sc
            pts = (rot_y(yaw) @ pts.T).T
            lo, hi = pts.min(0), pts.max(0)
            if hi[1] - lo[1] > 0.3:
                self.box(x + (lo[0] + hi[0]) / 2, y + (lo[1] + hi[1]) / 2, z + (lo[2] + hi[2]) / 2,
                         hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])

    def build(self, door_i=None, brick=False, floor="Floor_WoodDark", windows=True):
        A, Bd, nx, nz = self.A, self.Bd, self.nx, self.nz
        o = self.out
        wall = "Wall_UnevenBrick" if brick else "Wall_Plaster"
        if door_i is None:
            door_i = nx // 2
        T = 0.4

        def seg(kind, cx, cz, yaw, along_x, is_door=False):
            o.add(V(kind), pos=(cx, 0, cz), yaw=yaw)
            # collision (door gap in the middle of door modules)
            if is_door:
                for s in (-1, 1):
                    off = s * 0.83
                    if along_x:
                        self.box(cx + off, WALL_TOP / 2, cz - 0.1, 0.35, WALL_TOP, T)
                    else:
                        self.box(cx - 0.1 * math.sin(yaw) + 0, WALL_TOP / 2, cz + off, T, WALL_TOP, 0.35)
            else:
                if along_x:
                    self.box(cx, WALL_TOP / 2, cz - 0.1 * math.cos(yaw), 2.0, WALL_TOP, T)
                else:
                    self.box(cx - 0.1 * math.sin(yaw), WALL_TOP / 2, cz, T, WALL_TOP, 2.0)
        win_wide = wall + "_Window_Wide_Flat"
        win_thin = wall + "_Window_Thin_Round"
        for i in range(nx):
            x = -A / 2 + 1 + 2 * i
            # front (+z)
            if i == door_i:
                seg(wall + "_Door_Flat", x, Bd / 2, 0.0, True, True)
            else:
                seg(win_wide if (windows and (i % 2 == 0 or True)) else wall + "_Straight", x, Bd / 2, 0.0, True)
            # back (-z)
            seg(win_thin if (windows and i == nx // 2) else wall + "_Straight", x, -Bd / 2, math.pi, True)
        for j in range(nz):
            z = -Bd / 2 + 1 + 2 * j
            seg(win_thin if (windows and j % 2 == 1) else wall + "_Straight", -A / 2, z, -math.pi / 2, False)
            seg(win_thin if (windows and j % 2 == 1) else wall + "_Straight", A / 2, z, math.pi / 2, False)
        for sx in (-1, 1):
            for sz in (-1, 1):
                o.add(V("Corner_Exterior_Wood"), pos=(sx * A / 2, 0, sz * Bd / 2))
        o.add(V("Roof_RoundTiles_%dx%d" % (A, Bd)), pos=(0, WALL_TOP, 0))
        o.add(V("Roof_Front_Brick%d" % A), pos=(0, WALL_TOP, Bd / 2), yaw=0.0)
        o.add(V("Roof_Front_Brick%d" % A), pos=(0, WALL_TOP, -Bd / 2), yaw=math.pi)
        # interior floor
        for i in range(nx):
            for j in range(nz):
                self.inn.add(V(floor), pos=(-A / 2 + 1 + 2 * i, 0.04, -Bd / 2 + 1 + 2 * j))
        # doorstep / foundation strip so walls never float
        for i in range(nx):
            o.add(V("Wall_BottomCover"), pos=(-A / 2 + 1 + 2 * i, 0, Bd / 2 + 0.05), yaw=0.0)
        self.door_x = -A / 2 + 1 + 2 * door_i
        return self


def shop_weapon():
    b = B("shop_weapon", 8, 12).build(door_i=2, brick=True)
    b.prop("Table_Large", -1.6, 2.2, 0.0)
    b.prop("CandleStick", -2.4, 2.2, 0.0, y=0.81, col=False)
    b.prop("Sword_Bronze", -1.0, 2.1, 1.2, y=0.84, col=False)
    b.prop("WeaponStand", -2.6, -5.0, 0.0)
    b.prop("WeaponStand", 0.0, -5.0, 0.0)
    b.prop("Shield_Wooden", 2.4, -5.7, 0.0, y=1.7, col=False)
    b.prop("Shield_Wooden", -3.3, -3.0, math.pi / 2, y=1.6, col=False)
    b.prop("Workbench", 3.0, -3.0, -math.pi / 2)
    b.prop("Anvil", 2.2, 0.2, 0.0)
    b.prop("Barrel", -3.2, -5.1)
    b.prop("Crate_Wooden", -3.2, -4.1)
    b.prop("Chest_Wood", 3.1, -5.0, 0.0)
    b.prop("Axe_Bronze", 3.8, -0.8, -math.pi / 2, y=1.5, col=False)
    b.keeper = (-1.6, 0.9, 0.0)
    return b


def shop_general():
    b = B("shop_general", 8, 12).build(door_i=2)
    b.prop("Table_Large", -1.6, 2.2, 0.0)
    b.prop("Bag", -2.6, 2.2, 0.4, y=0.81, col=False)
    b.prop("FarmCrate_Apple", -0.7, 2.2, 0.0, y=0.81, col=False)
    b.prop("Bookcase_2", -2.6, -5.6, 0.0)
    b.prop("Bookcase_2", 0.0, -5.6, 0.0)
    b.prop("Cabinet", 2.7, -5.7, 0.0)
    b.prop("Barrel_Apples", 3.3, -3.4)
    b.prop("Barrel", 3.3, -2.4)
    b.prop("Crate_Wooden", -3.3, -3.4, math.pi / 2)
    b.prop("Bag", -3.3, -2.0, math.pi / 2)
    b.prop("Shelf_Arch", -3.65, 0.0, math.pi / 2, y=1.2, col=False)
    b.prop("Chest_Wood", 3.1, 2.8, -math.pi / 2)
    b.keeper = (-1.6, 0.9, 0.0)
    return b


def shop_potion():
    b = B("shop_potion", 6, 8).build(door_i=1, brick=False)
    b.prop("Table_Large", -0.9, 1.0, 0.0)
    b.prop("Potion_1", -1.6, 1.0, 0.0, y=0.81, col=False)
    b.prop("Potion_2", -1.2, 1.1, 0.0, y=0.81, col=False)
    b.prop("Potion_4", -0.4, 1.0, 0.0, y=0.81, col=False)
    b.prop("Bookcase_2", -1.6, -3.6, 0.0)
    b.prop("Bookcase_2", 0.3, -3.6, 0.0)
    b.prop("Cauldron", 2.1, -2.8)
    b.prop("Shelf_Small_Bottles", 2.65, 0.6, -math.pi / 2, y=1.3, col=False)
    b.prop("Pot_1", 2.3, -1.0, 0.0)
    b.keeper = (-0.9, -0.3, 0.0)
    return b


def house_a():
    b = B("house_a", 6, 8).build(door_i=1)
    b.prop("Bed_Twin1", -1.9, -2.7, 0.0)
    b.prop("Cabinet", 2.3, -3.65, 0.0)
    b.prop("Table_Large", 0.5, 1.2, 0.0)
    b.prop("Chair_1", 0.0, 0.2, 0.0)
    b.prop("Chair_1", 1.2, 0.2, 0.0)
    b.prop("Stool", -1.6, 1.8)
    b.prop("Chest_Wood", -2.4, 3.2, math.pi / 2)
    b.prop("Pot_1", 2.5, 1.0, 0.0)
    return b


def house_b():
    b = B("house_b", 6, 6).build(door_i=1, brick=True)
    b.prop("Bed_Twin2", 1.9, -1.7, 0.0)
    b.prop("Table_Large", -0.9, 0.2, 0.0)
    b.prop("Chair_1", -1.2, -0.8, 0.0)
    b.prop("Bookcase_2", -2.2, -2.7, 0.0)
    b.prop("Barrel", 2.5, 2.2)
    return b


def inn():
    b = B("inn", 8, 12).build(door_i=2)
    for i, z in enumerate((-1.5, 1.8)):
        b.prop("Table_Large", -2.3, z, math.pi / 2)
        b.prop("Bench", -1.0, z, math.pi / 2)
        b.prop("Bench", -3.6, z, math.pi / 2)
        b.prop("Mug", -2.3, z, 0.0, y=0.82, col=False)
    b.prop("Table_Large", 2.4, -1.5, math.pi / 2)
    b.prop("Bench", 1.1, -1.5, math.pi / 2)
    b.prop("Bench", 3.6, -1.5, math.pi / 2)
    b.prop("Table_Large", 0.0, -5.0, 0.0)          # bar
    b.prop("Barrel", -3.3, -5.2)
    b.prop("Barrel", 3.3, -5.2)
    b.prop("Barrel", 3.3, -4.2)
    b.prop("Chest_Wood", 3.2, 3.3, -math.pi / 2)
    b.prop("Cabinet", -3.7, -3.2, math.pi / 2)
    b.keeper = (0.0, -4.0, math.pi)
    return b


TYPES = {f.__name__: f() for f in (shop_weapon, shop_general, shop_potion, house_a, house_b, inn)}

# ------------------------------------------------------------------ castle + plaza (absolute local coords, y absolute)
cas = Scene()
cbox = []   # [cx,cy,cz,sx,sy,sz,yaw]


def cbx(cx, cy, cz, sx, sy, sz, yaw=0.0):
    cbox.append([round(float(v), 3) for v in (cx, cy, cz, sx, sy, sz, yaw)])


WS = 4.0     # wall scale (1 m kit unit -> 4 m)


def wall_run(p0, p1, gate_at=None, gate_w=0.0):
    """straight wall between two (u,v) points made of narrow wall segments, following the terrace heights"""
    p0 = np.array(p0, float)
    p1 = np.array(p1, float)
    L = np.linalg.norm(p1 - p0)
    n = max(1, int(round(L / WS)))
    d = (p1 - p0) / L
    yaw = math.atan2(d[0], d[1])          # local +z -> direction d
    for i in range(n):
        a = p0 + d * (L * i / n)
        b = p0 + d * (L * (i + 1) / n)
        c = (a + b) / 2
        if gate_at is not None and abs(c[0] - gate_at[0]) < gate_w / 2 and abs(c[1] - gate_at[1]) < gate_w / 2:
            continue
        y = min(town_h(a[0]), town_h(b[0])) - 0.8
        s = (L / n)
        # wall-narrow occupies x in [-0.5,0]: shift by +0.25*s along the local x axis to centre it on the line
        off = rot_y(yaw) @ np.array([0.25 * s, 0, 0])
        cas.add(K("wall-narrow"), pos=(c[0] + off[0], y, c[1] + off[2]), yaw=yaw, scale=s)
        cbx(c[0], y + 2.6, c[1], 2.0 if abs(d[0]) < 0.5 else s, 5.2, s if abs(d[0]) < 0.5 else 2.0, 0.0)


def tower(u, v, tiers=2, sc=5.0, roof="tower-square-top-roof"):
    y = town_h(u) - 0.8
    cas.add(K("tower-square-base"), pos=(u, y, v), scale=sc)
    yy = y + 1.01 * sc
    for t in range(tiers):
        cas.add(K("tower-square-mid"), pos=(u, yy, v), scale=sc)
        yy += 1.01 * sc
    cas.add(K(roof), pos=(u, yy, v), scale=sc)
    top = yy + 1.0 * sc
    cbx(u, (y + top) / 2, v, sc, top - y, sc)
    return top


# outer wall: west wall at u=-26 with gate, north/south at v=+-30, east at u=78; inner wall at u=28 with gate
UW, UE, VN, VS = -26.0, 78.0, -30.0, 30.0
wall_run((UW, VN), (UW, VS), gate_at=(UW, 0.0), gate_w=8.0)
wall_run((UW, VN), (UE, VN))
wall_run((UW, VS), (UE, VS))
wall_run((UE, VN), (UE, VS))
wall_run((28, VN), (28, VS), gate_at=(28, 0.0), gate_w=8.0)
for (u, v) in ((UW, VN), (UW, VS), (UE, VN), (UE, VS), (28, VN), (28, VS)):
    tower(u, v, tiers=2 if u != 28 else 1)
# gate houses
for sgn in (-1, 1):
    tower(UW, sgn * 6.0, tiers=2, sc=5.0)
    tower(28, sgn * 6.0, tiers=1, sc=5.0)
# gate lintel (doorway wall piece spanning the gap)
for (gu, sc) in ((UW, 6.0), (28, 6.0)):
    y = town_h(gu) - 0.8
    off = rot_y(0.0) @ np.array([0, 0, 0])
    cas.add(K("wall-doorway"), pos=(gu + 0.25 * sc, y, 0.0), yaw=-math.pi / 2 * 0 + math.pi / 2 * 0, scale=sc)
# keep
ky = town_h(62) - 0.8
cas.add(K("tower-square-base"), pos=(62, ky, 0), scale=10.0)
yy = ky + 10.1
for t in range(3):
    cas.add(K("tower-square-mid"), pos=(62, yy, 0), scale=10.0)
    yy += 10.1
cas.add(K("tower-square-top-roof"), pos=(62, yy, 0), scale=10.0)
cbx(62, (ky + yy + 10) / 2, 0, 10.0, yy + 10 - ky, 10.0)
for k, (fu, fv) in enumerate(((56.5, 0), (67.5, 0))):
    cas.add(K("flag-banner-long"), pos=(fu, yy - 8.0, fv + (0 if k == 0 else 0)), yaw=-math.pi / 2 if k == 0 else math.pi / 2, scale=4.0)
# keep annex + courtyard decor
cas.add(K("tower-hexagon-base"), pos=(46, ky, -14), scale=7.0)
cas.add(K("tower-hexagon-roof"), pos=(46, ky + 9.17, -14), scale=7.0)
cbx(46, ky + 4.6, -14, 6.3, 9.2, 5.4)
cas.add(K("tower-hexagon-base"), pos=(46, ky, 14), scale=7.0)
cas.add(K("tower-hexagon-roof"), pos=(46, ky + 9.17, 14), scale=7.0)
cbx(46, ky + 4.6, 14, 6.3, 9.2, 5.4)
for (tu, tv, ts) in ((-70, -22, 3.5), (-70, 22, 3.5), (-48, -26, 3.0), (-48, 26, 3.2), (20, -27, 3.0), (20, 27, 3.0), (72, -22, 3.4), (72, 22, 3.4)):
    cas.add(K("tree-large"), pos=(tu, town_h(tu), tv), scale=ts)
    cbx(tu, town_h(tu) + 1.5, tv, 1.0, 3.0, 1.0)
# banners along the main street
for u in (-20, -8, 4, 16):
    for sgn in (-1, 1):
        cas.add(K("flag-banner-long"), pos=(u, town_h(u) + 0.0, sgn * 6.4), yaw=0.0, scale=1.6)

plaza = Scene()
pbox = []
for i, u in enumerate((-68, -60, -52, -44)):
    for sgn in (-1, 1):
        v = sgn * 11.0
        yaw = math.pi if sgn < 0 else 0.0        # faces the centre (stall front is +z)
        y = H0
        plaza.add(P("Stall_Empty"), pos=(u, y, v), yaw=yaw, scale=1.9)
        pbox.append([u, y + 2.4, v, 3.6, 4.8, 1.6, 0.0])
        s = 1 if sgn > 0 else -1
        goods = ["Crate_Wooden", "FarmCrate_Apple", "Barrel_Apples", "Bag", "Barrel", "Pot_1", "Vase_2", "Crate_Wooden"][(i * 2 + (0 if sgn < 0 else 1)) % 8]
        plaza.add(P(goods), pos=(u + 2.4, y, v + s * 0.3), yaw=yaw, scale=1.2)
        plaza.add(P("Barrel"), pos=(u - 2.3, y, v + s * 0.5), yaw=0.0, scale=1.2)
        pbox.append([u - 2.3, y + 0.5, v + s * 0.5, 0.9, 1.1, 0.9, 0.0])
for (u, v, yw) in ((-56, 0, 0.0),):
    plaza.add(V("Prop_Wagon"), pos=(u, H0, v), yaw=math.pi / 2, scale=1.3)
    pbox.append([u, H0 + 1.0, v, 3.4, 2.0, 2.6, 0.0])
for u in range(-72, -36, 2):
    for sgn in (-1, 1):
        if abs(u) < 0 or True:
            plaza.add(V("Prop_WoodenFence_Single"), pos=(u + 1.0, H0 - 0.05, sgn * 28.0), yaw=0.0, scale=1.0)
for sgn in (-1, 1):
    pbox.append([-54, H0 + 0.5, sgn * 28.0, 36, 1.0, 0.3, 0.0])
for u in (-72,):
    for v in range(-28, 28, 2):
        plaza.add(V("Prop_WoodenFence_Single"), pos=(u, H0 - 0.05, v + 1.0), yaw=math.pi / 2, scale=1.0)
pbox.append([-72, H0 + 0.5, 0, 0.3, 1.0, 56, 0.0])
plaza.add(P("Bench"), pos=(-40, H0, -7), yaw=0.0, scale=1.3)
plaza.add(P("Bench"), pos=(-40, H0, 7), yaw=math.pi, scale=1.3)
pbox.append([-40, H0 + 0.4, -7, 3.6, 0.8, 0.8, 0.0])
pbox.append([-40, H0 + 0.4, 7, 3.6, 0.8, 0.8, 0.0])

# ------------------------------------------------------------------ plots
PLOTS = []
for (u, t) in ((-17, "shop_weapon"), (-4.5, "house_a"), (6.5, "shop_potion"), (17, "house_b")):
    b = TYPES[t]
    PLOTS.append((t, u, -(7.0 + b.Bd / 2), 0.0))
for (u, t) in ((-17, "shop_general"), (-4.5, "inn"), (6.5, "house_a"), (17, "house_b")):
    b = TYPES[t]
    PLOTS.append((t, u, 7.0 + b.Bd / 2, math.pi))


# ------------------------------------------------------------------ writer
def write_scene(sc, name, tex_ready):
    mats, prims, chunks, bviews, accs = [], [], [], [], []

    def add(arr, ct, typ, tgt=None, mm=False):
        raw = arr.tobytes()
        raw += b"\0" * ((-len(raw)) % 4)
        off = sum(len(c) for c in chunks)
        chunks.append(raw)
        bv = {"buffer": 0, "byteOffset": off, "byteLength": len(raw)}
        if tgt:
            bv["target"] = tgt
        bviews.append(bv)
        a = {"bufferView": len(bviews) - 1, "componentType": ct, "count": int(arr.shape[0]), "type": typ}
        if mm:
            a["min"] = [float(x) for x in arr.min(0)]
            a["max"] = [float(x) for x in arr.max(0)]
        accs.append(a)
        return len(accs) - 1
    for mi, nm in enumerate(sc.m):
        pos, nrm, uv, idx = sc.arrays(nm)
        nrm = nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
        m = {"name": nm, "doubleSided": True, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 1.0}}
        tp = sc.tex.get(nm)
        if tp:
            m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex_ready(nm, tp)}
        else:
            m["pbrMetallicRoughness"]["baseColorFactor"] = [float(x) for x in sc.col.get(nm, [0.7, 0.7, 0.7, 1])]
        mats.append(m)
        ai = add(pos.astype(np.float32), 5126, "VEC3", 34962, True)
        an = add(nrm.astype(np.float32), 5126, "VEC3", 34962)
        au = add(uv.astype(np.float32), 5126, "VEC2", 34962)
        ax = add(idx.reshape(-1, 1).astype(np.uint32), 5125, "SCALAR", 34963)
        prims.append({"attributes": {"POSITION": ai, "NORMAL": an, "TEXCOORD_0": au}, "indices": ax, "material": mi})
    return mats, prims, chunks, bviews, accs


TEXLIST = {}


def tex_index_factory():
    images, textures = [], []
    cache = {}

    def f(matname, src):
        key = os.path.basename(src)
        if key not in cache:
            dst = os.path.join(OUTD, "tex", key)
            if not os.path.exists(dst):
                im = Image.open(src).convert("RGB")
                lim = 256 if "colormap" in key.lower() else 512
                if max(im.size) > lim:
                    im = im.resize((lim, lim), Image.LANCZOS)
                im.save(dst, optimize=True)
            images.append({"uri": "tex/" + key})
            textures.append({"source": len(images) - 1})
            cache[key] = len(textures) - 1
        return cache[key]
    return f, images, textures


def save(sc, name):
    f, images, textures = tex_index_factory()
    mats, prims, chunks, bviews, accs = write_scene(sc, name, f)
    doc = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": name, "mesh": 0}],
           "meshes": [{"name": name, "primitives": prims}], "materials": mats, "accessors": accs, "bufferViews": bviews,
           "buffers": [{"uri": name + ".bin", "byteLength": sum(len(c) for c in chunks)}]}
    if images:
        doc["images"] = images
        doc["textures"] = textures
        for m in mats:
            pass
    with open(os.path.join(OUTD, name + ".gltf"), "w") as fh:
        json.dump(doc, fh, separators=(",", ":"))
    with open(os.path.join(OUTD, name + ".bin"), "wb") as fh:
        fh.write(b"".join(chunks))
    print(name, "tris", sc.tris(), "mats", len(mats))


for n in os.listdir(OUTD):
    if n.endswith((".gltf", ".bin")):
        os.remove(os.path.join(OUTD, n))
for t, b in TYPES.items():
    save(b.out, t + "_out")
    save(b.inn, t + "_in")
save(cas, "castle")
save(plaza, "plaza")

# ------------------------------------------------------------------ data file for the game
def vec(v):
    return "Vector3(%.3f, %.3f, %.3f)" % v


lines = ["extends RefCounted", "# generated by tools/towngen.py - do not edit", "",
         "const ORIGIN := Vector2(%.1f, %.1f)" % ORIGIN, "const H0 := %.2f" % H0, "const H1 := %.2f" % H1, "const H2 := %.2f" % H2, ""]
lines.append("const TYPES := {")
for t, b in TYPES.items():
    lines.append('\t"%s": {"out": "res://assets/town/%s_out.gltf", "in": "res://assets/town/%s_in.gltf", "w": %d, "d": %d, "boxes": %s},' % (t, t, t, b.A, b.Bd, json.dumps(b.boxes)))
lines.append("}")
lines.append("")
lines.append("# [type, u, v, yaw]")
lines.append("const PLOTS := " + json.dumps([[t, u, v, round(y, 4)] for (t, u, v, y) in PLOTS]) + "")
lines.append("")
lines.append('const CASTLE := "res://assets/town/castle.gltf"')
lines.append("const CASTLE_BOXES := " + json.dumps(cbox))
lines.append('const PLAZA := "res://assets/town/plaza.gltf"')
lines.append("const PLAZA_BOXES := " + json.dumps(pbox))
keep = []
for (t, u, v, y) in PLOTS:
    b = TYPES[t]
    if hasattr(b, "keeper"):
        kx, kz, ky_ = b.keeper
        c, s = math.cos(y), math.sin(y)
        wx = u + kx * c + kz * s
        wz = v - kx * s + kz * c
        keep.append([t, round(wx, 2), round(wz, 2), round(y + ky_, 3)])
lines.append("# shop keepers [type, u, v, yaw]")
lines.append("const KEEPERS := " + json.dumps(keep))
open(os.path.join(PROJ, "scripts", "anime", "town_data.gd"), "w").write("\n".join(lines) + "\n")

if PREV:
    os.makedirs(PREV, exist_ok=True)
    for t in ("shop_weapon", "house_a"):
        s = Scene()
        s.m, s.tex, s.col = dict(TYPES[t].out.m), dict(TYPES[t].out.tex), dict(TYPES[t].out.col)
        preview(s, os.path.join(PREV, t + "_out.png"), views=((0.6, 0.35), (2.5, 0.35)), size=600)
        s2 = Scene()
        for src in (TYPES[t].out, TYPES[t].inn):
            for nm, e in src.m.items():
                d = s2.m.setdefault(nm, dict(pos=[], nrm=[], uv=[], idx=[], n=0))
                d["pos"] += e["pos"]; d["nrm"] += e["nrm"]; d["uv"] += e["uv"]
                d["idx"] += [i + d["n"] - e["idx"][0].min() * 0 for i in []]
        # interior only (roof hidden) preview
        si = Scene()
        si.m = {k: v for k, v in TYPES[t].inn.m.items()}
        si.tex, si.col = dict(TYPES[t].inn.tex), dict(TYPES[t].inn.col)
        walls = Scene()
        for k, v in TYPES[t].out.m.items():
            if "RoundTiles" in k:
                continue
            walls.m[k] = v
        walls.tex, walls.col = dict(TYPES[t].out.tex), dict(TYPES[t].out.col)
        for k, v in si.m.items():
            walls.m.setdefault(k, v) if k not in walls.m else None
        walls.tex.update(si.tex); walls.col.update(si.col)
        preview(walls, os.path.join(PREV, t + "_in.png"), views=((0.3, 0.9), (2.0, 0.9)), size=600)
    preview(cas, os.path.join(PREV, "castle.png"), views=((0.9, 0.5), (3.3, 0.5)), size=800, center=np.array([20.0, 10.0, 0.0]), span=95)
    preview(plaza, os.path.join(PREV, "plaza.png"), views=((0.9, 0.5),), size=800)
