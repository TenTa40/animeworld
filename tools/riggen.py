#!/usr/bin/env python3
"""Rigs iko onto the Quaternius UAL2 skeleton and packs mesh + animations into one GLB.

usage: python3 -I riggen.py <iko.dat> <Mannequin_F.glb> <UAL2_Standard.glb> <out.glb> [--preview dir]

* iko.dat is the arms-down character made by herogen.py (IKO1).
* The mannequin skeleton is T-posed, iko stands with arms down: weights are computed against a copy of the
  skeleton with the arms rotated down (distance to bone segments), then the mesh is un-posed into the T-pose
  with inverse linear blend skinning so that it matches the skeleton's rest pose and the UAL clips.
* Vertex colours are written as COLOR_0 (sRGB-encoded floats, the shader decodes them).
* Only the clips listed in KEEP are copied (constant channels are reduced to two keys).
"""
import json, struct, sys, os
import numpy as np

DAT, MAN, UAL, OUT = sys.argv[1:5]
PREVIEW = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None

KEEP = ["A_TPose", "Idle_No_Loop", "Idle_FoldArms_Loop", "Idle_Shield_Loop", "Walk_Carry_Loop", "Zombie_Walk_Fwd_Loop",
        "NinjaJump_Start", "NinjaJump_Idle_Loop", "NinjaJump_Land", "Sword_Regular_A", "Sword_Regular_A_Rec",
        "Sword_Regular_B", "Sword_Regular_B_Rec", "Sword_Regular_C", "Sword_Regular_Combo", "Sword_Heavy_Combo",
        "Sword_Dash", "Sword_Block", "Hit_Knockback", "Slide_Start", "Slide_Loop", "Slide_Exit", "Melee_Hook",
        "Shield_Dash", "Yes"]
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class GLB:
    def __init__(s, path):
        b = open(path, "rb").read()
        cl, _ = struct.unpack("<II", b[12:20])
        s.j = json.loads(b[20:20 + cl])
        s.bin = b[20 + cl + 8:]

    def acc(s, i):
        a = s.j["accessors"][i]
        bv = s.j["bufferViews"][a["bufferView"]]
        ct = CT[a["componentType"]]
        n = NC[a["type"]]
        it = np.dtype(ct).itemsize
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        st = bv.get("byteStride", 0)
        if st and st != it * n:
            return np.ndarray((a["count"], n), dtype=ct, buffer=s.bin, offset=off, strides=(st, it)).copy()
        return np.frombuffer(s.bin, dtype=ct, count=a["count"] * n, offset=off).reshape(a["count"], n).copy()


def qmat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def local_mat(t, q, s):
    M = np.eye(4)
    M[:3, :3] = qmat(q) @ np.diag(s)
    M[:3, 3] = t
    return M


def node_local(n):
    if "matrix" in n:
        return np.array(n["matrix"]).reshape(4, 4).T
    return local_mat(n.get("translation", [0, 0, 0]), n.get("rotation", [0, 0, 0, 1]), n.get("scale", [1, 1, 1]))


def slerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0:
        b = -b
        d = -d
    if d > 0.9995:
        r = a + (b - a) * t
        return r / np.linalg.norm(r)
    th = np.arccos(d)
    return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)


man = GLB(MAN)
ual = GLB(UAL)
nodes = man.j["nodes"]
parent = {}
for i, n in enumerate(nodes):
    for c in n.get("children", []):
        parent[c] = i
skin = man.j["skins"][0]
J = skin["joints"]
jname = [nodes[i]["name"] for i in J]
jidx = {n: k for k, n in enumerate(jname)}
nidx = {n["name"]: i for i, n in enumerate(nodes)}


def gmat(i):
    M = node_local(nodes[i])
    while i in parent:
        i = parent[i]
        M = node_local(nodes[i]) @ M
    return M


G = np.array([gmat(i) for i in J])          # rest global per joint
IBM = np.linalg.inv(G)
P = G[:, :3, 3]
MAN_H = 1.808

# ---------------------------------------------------------------- iko mesh
b = open(DAT, "rb").read()
nv, ni = struct.unpack("<II", b[4:12])
o = 12
pos = np.frombuffer(b, np.float32, nv * 3, o).reshape(-1, 3).astype(np.float64)
o += nv * 12 + nv * 3
col = np.frombuffer(b, np.uint8, nv * 3, o).reshape(-1, 3).astype(np.float32) / 255.0
o += nv * 3
tris = np.frombuffer(b, np.uint32, ni, o).reshape(-1, 3).astype(np.int64)
sc = MAN_H / pos[:, 1].max()
# --- clean the noisy atlas colours: neighbour smoothing, then a small palette (flat anime look)
lin = np.power(col.astype(np.float64), 2.2)
nb_i = np.concatenate([tris[:, 0], tris[:, 1], tris[:, 2], tris[:, 1], tris[:, 2], tris[:, 0]])
nb_j = np.concatenate([tris[:, 1], tris[:, 2], tris[:, 0], tris[:, 0], tris[:, 1], tris[:, 2]])
for _ in range(6):
    acc_c = np.zeros_like(lin)
    cnt = np.zeros(len(lin))
    np.add.at(acc_c, nb_i, lin[nb_j])
    np.add.at(cnt, nb_i, 1.0)
    lin = 0.35 * lin + 0.65 * (acc_c / np.maximum(cnt, 1)[:, None])
K = 9
rng = np.random.default_rng(3)
cen = lin[rng.choice(len(lin), K, replace=False)]
for _ in range(25):
    lab = np.argmin(((lin[:, None] - cen[None]) ** 2).sum(-1), axis=1)
    for k in range(K):
        if (lab == k).any():
            cen[k] = lin[lab == k].mean(0)
lin = cen[lab]
# lift very dark colours a little so the outfit still reads
lum = lin @ np.array([0.3, 0.59, 0.11])
lin = lin * (1.0 + 0.9 * np.clip(0.06 - lum, 0, 1) / 0.06)[:, None] + 0.01
col = np.power(np.clip(lin, 0, 1), 1 / 2.2).astype(np.float32)
print("palette", np.round(np.power(cen, 1 / 2.2) * 255).astype(int).tolist())

pos = pos * sc
print("iko verts", nv, "tris", len(tris), "scale", round(sc, 4))

# ---------------------------------------------------------------- posed skeleton (arms down)
ARM_DOWN = np.radians(72.0)


def rot_z(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0, 0], [s, c, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1.0]])


def descendants(name):
    out = []
    todo = [jidx[name]]
    while todo:
        k = todo.pop()
        out.append(k)
        for c in nodes[J[k]].get("children", []):
            if c in J:
                todo.append(J.index(c))
    return out


Gp = G.copy()
for side, sgn in (("l", -1.0), ("r", 1.0)):
    ks = descendants("upperarm_" + side)
    pv = P[jidx["upperarm_" + side]]
    T = np.eye(4)
    T[:3, 3] = pv
    Ti = np.eye(4)
    Ti[:3, 3] = -pv
    R = T @ rot_z(sgn * ARM_DOWN) @ Ti
    for k in ks:
        Gp[k] = R @ G[k]
Pp = Gp[:, :3, 3]

FINGER = ("index", "middle", "pinky", "ring", "thumb")


def is_finger(n):
    return n.startswith(FINGER)


seg = []   # (joint index, a, b)
up = np.array([0, 0.22, 0.0])
for s in ("l", "r"):
    seg.append((jidx["clavicle_" + s], Pp[jidx["clavicle_" + s]], Pp[jidx["upperarm_" + s]]))
    seg.append((jidx["upperarm_" + s], Pp[jidx["upperarm_" + s]], Pp[jidx["lowerarm_" + s]]))
    seg.append((jidx["lowerarm_" + s], Pp[jidx["lowerarm_" + s]], Pp[jidx["hand_" + s]]))
    h0 = Pp[jidx["hand_" + s]]
    h1 = Pp[jidx["middle_02_" + s]]
    seg.append((jidx["hand_" + s], h0, h1))
    seg.append((jidx["thigh_" + s], Pp[jidx["thigh_" + s]], Pp[jidx["calf_" + s]]))
    seg.append((jidx["calf_" + s], Pp[jidx["calf_" + s]], Pp[jidx["foot_" + s]]))
    seg.append((jidx["foot_" + s], Pp[jidx["foot_" + s]], Pp[jidx["ball_" + s]]))
    seg.append((jidx["ball_" + s], Pp[jidx["ball_" + s]], Pp[jidx["ball_leaf_" + s]]))
seg.append((jidx["pelvis"], Pp[jidx["pelvis"]] + np.array([0, -0.06, 0]), Pp[jidx["spine_01"]]))
seg.append((jidx["spine_01"], Pp[jidx["spine_01"]], Pp[jidx["spine_02"]]))
seg.append((jidx["spine_02"], Pp[jidx["spine_02"]], Pp[jidx["spine_03"]]))
seg.append((jidx["spine_03"], Pp[jidx["spine_03"]], Pp[jidx["neck_01"]]))
seg.append((jidx["neck_01"], Pp[jidx["neck_01"]], Pp[jidx["Head"]]))
seg.append((jidx["Head"], Pp[jidx["Head"]], Pp[jidx["Head"]] + np.array([0, 0.30, 0])))
sj = [s[0] for s in seg]
A = np.array([s[1] for s in seg])
B = np.array([s[2] for s in seg])


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p[:, None, :] - a[None]) * ab[None]).sum(-1) / (ab * ab).sum(-1)[None], 0, 1)
    q = a[None] + t[..., None] * ab[None]
    return np.linalg.norm(p[:, None, :] - q, axis=-1)


D = seg_dist(pos, A, B)                       # (nv, nseg)
dmin = D.min(1, keepdims=True)
W = np.exp(-((D - dmin) / 0.05) ** 2)
# cloth far from every bone follows pelvis/spine more than the legs
far = np.clip((dmin[:, 0] - 0.06) / 0.10, 0.0, 1.0)
pel = sj.index(jidx["pelvis"])
sp1 = sj.index(jidx["spine_01"])
for k, name in enumerate(sj):
    nm = jname[name]
    if nm.startswith(("thigh", "calf", "foot", "ball", "upperarm", "lowerarm", "hand")):
        W[:, k] *= (1.0 - 0.85 * far)
W[:, pel] += 0.5 * far
W[:, sp1] += 0.2 * far
W /= W.sum(1, keepdims=True)
top = np.argsort(-W, axis=1)[:, :4]
Wt = np.take_along_axis(W, top, 1)
Wt /= Wt.sum(1, keepdims=True)
Jt = np.array(sj)[top]                         # joint index per influence

# ---------------------------------------------------------------- un-pose to T-pose with inverse LBS
Mj = Gp @ np.linalg.inv(G)                     # posed <- rest, per joint
Mv = np.einsum("vk,vkab->vab", Wt, Mj[Jt])
ph = np.concatenate([pos, np.ones((nv, 1))], 1)
rest = np.einsum("vab,vb->va", np.linalg.inv(Mv), ph)[:, :3]
print("unposed bbox", rest.min(0).round(3), rest.max(0).round(3))
pos = rest

# normals
fn = np.cross(pos[tris[:, 1]] - pos[tris[:, 0]], pos[tris[:, 2]] - pos[tris[:, 0]])
nrm = np.zeros_like(pos)
for k in range(3):
    np.add.at(nrm, tris[:, k], fn)
nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)

# ---------------------------------------------------------------- animations
by_name = {a["name"]: a for a in ual.j["animations"]}
unodes = ual.j["nodes"]
anims = []
for nm in KEEP:
    a = by_name[nm]
    chans = []
    for c in a["channels"]:
        tn = unodes[c["target"]["node"]]["name"]
        if tn not in nidx:
            continue
        sm = a["samplers"][c["sampler"]]
        assert sm.get("interpolation", "LINEAR") in ("LINEAR", "STEP")
        t = ual.acc(sm["input"])[:, 0].astype(np.float32)
        v = ual.acc(sm["output"]).astype(np.float32)
        if len(t) > 2 and np.allclose(v, v[0], atol=1e-5):
            t = t[[0, -1]]
            v = v[[0, -1]]
        chans.append((nidx[tn], c["target"]["path"], t, v, sm.get("interpolation", "LINEAR")))
    anims.append((nm, chans))

RUN_FBX = sys.argv[sys.argv.index("--run") + 1] if "--run" in sys.argv else None
if RUN_FBX:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import retarget_mx
    pj = []
    for k in J:
        pn = parent.get(k)
        pj.append(J.index(pn) if pn in J else -1)
    rest_loc_R = np.array([node_local(nodes[k])[:3, :3] for k in J])
    rest_par_R = np.array([(np.eye(3) if k not in parent else gmat(parent[k])[:3, :3]) for k in J])
    tm, rq, tr = retarget_mx.retarget(RUN_FBX, J, jname, pj, G, rest_loc_R, rest_par_R, float(P[jidx["pelvis"]][1]))
    rchans = []
    for j, k in enumerate(J):
        rchans.append((k, "rotation", tm.astype(np.float32), rq[:, j].astype(np.float32), "LINEAR"))
    pel = jidx["pelvis"]
    Gpar = G[jidx["root"]]
    loc_t = np.array([(np.linalg.inv(Gpar) @ np.append(P[pel] + d, 1))[:3] for d in tr], dtype=np.float32)
    rchans.append((J[pel], "translation", tm.astype(np.float32), loc_t, "LINEAR"))
    anims.append(("Run", rchans))
    print("added clip Run", len(tm), "frames")


def sample(chans, tm):
    loc = {}
    for n, path, t, v, _ in chans:
        if tm <= t[0]:
            r = v[0]
        elif tm >= t[-1]:
            r = v[-1]
        else:
            k = int(np.searchsorted(t, tm) - 1)
            f = (tm - t[k]) / (t[k + 1] - t[k])
            r = slerp(v[k], v[k + 1], f) if path == "rotation" else v[k] + (v[k + 1] - v[k]) * f
        loc.setdefault(n, {})[path] = r
    return loc


def pose_mats(loc):
    cache = {}

    def g(i):
        if i in cache:
            return cache[i]
        n = nodes[i]
        d = loc.get(i, {})
        t = d.get("translation", n.get("translation", [0, 0, 0]))
        q = d.get("rotation", n.get("rotation", [0, 0, 0, 1]))
        s = d.get("scale", n.get("scale", [1, 1, 1]))
        M = local_mat(t, q, s)
        if i in parent:
            M = g(parent[i]) @ M
        cache[i] = M
        return M
    return np.array([g(i) for i in J])


def skin_pts(Gx):
    Mk = Gx @ IBM
    Mv2 = np.einsum("vk,vkab->vab", Wt, Mk[Jt])
    ph2 = np.concatenate([pos, np.ones((nv, 1))], 1)
    return np.einsum("vab,vb->va", Mv2, ph2)[:, :3]


if PREVIEW:
    import PIL.Image as I
    os.makedirs(PREVIEW, exist_ok=True)
    shots = [("Run", 0.0), ("Run", 0.1), ("Run", 0.2), ("Run", 0.3), ("Run", 0.4), ("Run", 0.5), ("Run", 0.6), ("Run", 0.75)] if os.environ.get("PVRUN") else [("A_TPose", 0.0), ("Idle_No_Loop", 0.5), ("Walk_Carry_Loop", 0.3), ("Sword_Regular_A", 0.2),
             ("Sword_Regular_B", 0.25), ("Sword_Heavy_Combo", 1.0), ("NinjaJump_Idle_Loop", 0.5), ("Sword_Dash", 0.5), ("Run", 0.3)]
    cd = dict(anims)
    Wd, Hd = 260, 400
    img = np.zeros((Hd * 2, Wd * 4, 3), np.uint8)
    for si, (nm, tm) in enumerate(shots):
        Pq = skin_pts(pose_mats(sample(cd[nm], tm)))
        ox, oy = (si % 4) * Wd, (si // 4) * Hd
        for ax, off in ((0, 0), ):
            px = ((Pq[:, int(os.environ.get('PVAX', '0'))] + 1.0) / 2.0 * (Wd - 2)).astype(int)
            py = (Hd - 1 - (Pq[:, 1] + 0.1) / 2.1 * (Hd - 1)).astype(int)
            ok = (px >= 0) & (px < Wd - 1) & (py >= 1) & (py < Hd)
            c8 = np.clip(np.power(col, 0.6) * 255 * 1.6, 0, 255).astype(np.uint8)
            c8 = np.maximum(c8, 70)
            for dx in (0, 1):
                for dy in (0, -1):
                    img[np.clip(py[ok] + dy + oy, 0, 2 * Hd - 1), px[ok] + dx + ox] = c8[ok]
    I.fromarray(img).save(os.path.join(PREVIEW, "rig_preview.png"))
    # grip axis from the finger curl in a sword clip
    cd2 = cd["Sword_Regular_A"]
    Gs = pose_mats(sample(cd2, 0.15))
    for s in ("r", "l"):
        hj = jidx["hand_" + s]
        Hm = np.linalg.inv(Gs[hj])
        pi = (Hm @ np.append(Gs[jidx["index_01_" + s]][:3, 3], 1))[:3]
        pk = (Hm @ np.append(Gs[jidx["pinky_01_" + s]][:3, 3], 1))[:3]
        print("hand", s, "index-pinky dir in hand frame", np.round((pi - pk) / np.linalg.norm(pi - pk), 3),
              "pos of hand", np.round(Gs[hj][:3, 3], 2))
        # curl axis: fingertip (index_03) vs index_01 in hand frame
        p3 = (Hm @ np.append(Gs[jidx["index_03_" + s]][:3, 3], 1))[:3]
        print("  index_03 in hand frame", np.round(p3, 3))
    for s in ("r", "l"):
        tot = 0.0
        for tm in np.linspace(0, 0.4, 5):
            Gs = pose_mats(sample(cd2, tm))
            k = jidx["index_02_" + s]
            rel = np.linalg.inv(Gs[jidx["index_01_" + s]]) @ Gs[k]
            tot += np.degrees(np.arccos(np.clip((np.trace(rel[:3, :3]) - 1) / 2, -1, 1)))
        print("finger curl", s, round(tot / 5, 1))
    sys.exit(0)

# ---------------------------------------------------------------- pack GLB
chunks = []
bviews = []
accs = []


def add(arr, ctype, typ, target=None, mm=False):
    raw = arr.tobytes()
    pad = (-len(raw)) % 4
    off = sum(len(c) for c in chunks)
    chunks.append(raw + b"\0" * pad)
    bv = {"buffer": 0, "byteOffset": off, "byteLength": len(raw)}
    if target:
        bv["target"] = target
    bviews.append(bv)
    a = {"bufferView": len(bviews) - 1, "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
    if mm:
        a["min"] = [float(x) for x in arr.min(0)]
        a["max"] = [float(x) for x in arr.max(0)]
    accs.append(a)
    return len(accs) - 1


a_pos = add(pos.astype(np.float32), 5126, "VEC3", 34962, True)
a_nrm = add(nrm.astype(np.float32), 5126, "VEC3", 34962)
a_col = add(np.concatenate([col, np.ones((nv, 1), np.float32)], 1), 5126, "VEC4", 34962)
a_jnt = add(Jt.astype(np.uint8), 5121, "VEC4", 34962)
a_wgt = add(Wt.astype(np.float32), 5126, "VEC4", 34962)
a_idx = add(tris.reshape(-1).astype(np.uint32).reshape(-1, 1), 5125, "SCALAR", 34963)
a_ibm = add(IBM.transpose(0, 2, 1).astype(np.float32).reshape(-1, 16), 5126, "MAT4")

out_nodes = json.loads(json.dumps(nodes))
for n in out_nodes:
    if "mesh" in n:
        n["name"] = "IkoMesh"
out_anims = []
for nm, chans in anims:
    samplers = []
    channels = []
    for n, path, t, v, interp in chans:
        ai = add(t.reshape(-1, 1), 5126, "SCALAR")
        accs[ai]["min"] = [float(t.min())]
        accs[ai]["max"] = [float(t.max())]
        ao = add(v, 5126, "VEC4" if path == "rotation" else "VEC3")
        samplers.append({"input": ai, "output": ao, "interpolation": interp})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": n, "path": path}})
    out_anims.append({"name": nm, "samplers": samplers, "channels": channels})

skin_out = {"joints": J, "inverseBindMatrices": a_ibm}
for k in ("skeleton",):
    if k in skin:
        skin_out[k] = skin[k]
doc = {
    "asset": {"version": "2.0", "generator": "iko riggen"},
    "scene": man.j.get("scene", 0),
    "scenes": man.j["scenes"],
    "nodes": out_nodes,
    "skins": [skin_out],
    "meshes": [{"name": "IkoMesh", "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "COLOR_0": a_col,
                                                                    "JOINTS_0": a_jnt, "WEIGHTS_0": a_wgt},
                                                    "indices": a_idx, "material": 0}]}],
    "materials": [{"name": "iko", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0,
                                                           "roughnessFactor": 1.0}, "doubleSided": True}],
    "animations": out_anims,
    "accessors": accs,
    "bufferViews": bviews,
    "buffers": [{"byteLength": sum(len(c) for c in chunks)}],
}
js = json.dumps(doc, separators=(",", ":")).encode()
js += b" " * ((-len(js)) % 4)
binb = b"".join(chunks)
total = 12 + 8 + len(js) + 8 + len(binb)
with open(OUT, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, total))
    f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    f.write(struct.pack("<II", len(binb), 0x004E4942) + binb)
print("wrote", OUT, total // 1024, "KB,", len(out_anims), "clips")
