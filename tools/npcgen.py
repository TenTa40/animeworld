#!/usr/bin/env python3
"""Builds the citizen models (assets/npc/*.gltf) from the Quaternius Universal Base Characters + Modular Fantasy Outfits.

usage: python3 -I npcgen.py <ubc_dir> <outfit_dir> <project_dir> [--preview dir]

Each citizen = outfit parts (skin + cloth) + the head cut out of the base body + eyes + hair (rigid on the Head bone),
all skinned to the base skeleton (65 bones, same names as the UAL clips) and merged into 4 surfaces:
  0 skin, 1 cloth, 2 hair, 3 eyes
"""
import json, os, struct, sys, glob
import numpy as np
from PIL import Image

UBC, OUTF, PROJ = sys.argv[1:4]
PREV = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def find(root, pat):
    r = glob.glob(os.path.join(root, "**", pat), recursive=True)
    if not r:
        raise SystemExit("missing " + pat)
    return r[0]


class G:
    def __init__(s, path):
        s.dir = os.path.dirname(path)
        s.j = json.load(open(path))
        s.bins = [open(os.path.join(s.dir, b["uri"]), "rb").read() for b in s.j["buffers"]]

    def acc(s, i):
        a = s.j["accessors"][i]
        bv = s.j["bufferViews"][a["bufferView"]]
        ct = CT[a["componentType"]]
        n = NC[a["type"]]
        it = np.dtype(ct).itemsize
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        st = bv.get("byteStride", 0)
        b = s.bins[bv["buffer"]]
        if st and st != it * n:
            return np.ndarray((a["count"], n), dtype=ct, buffer=b, offset=off, strides=(st, it)).copy()
        return np.frombuffer(b, dtype=ct, count=a["count"] * n, offset=off).reshape(a["count"], n).copy()

    def joint_names(s):
        sk = s.j["skins"][0]
        return [s.j["nodes"][i]["name"] for i in sk["joints"]]

    def tex_path(s, mat_i):
        m = s.j["materials"][mat_i]
        ti = m["pbrMetallicRoughness"]["baseColorTexture"]["index"]
        return os.path.join(s.dir, s.j["images"][s.j["textures"][ti]["source"]]["uri"]), m["name"]

    def prims(s):
        """yield (mesh_name, material_index, dict of arrays)"""
        nn = {}
        for n in s.j["nodes"]:
            if "mesh" in n:
                nn[n["mesh"]] = n["name"]
        for mi_, mesh in enumerate(s.j["meshes"]):
            for p in mesh["primitives"]:
                at = p["attributes"]
                d = {"pos": s.acc(at["POSITION"]).astype(np.float32), "nrm": s.acc(at["NORMAL"]).astype(np.float32),
                     "uv": s.acc(at["TEXCOORD_0"]).astype(np.float32), "idx": s.acc(p["indices"]).reshape(-1).astype(np.int64)}
                if "JOINTS_0" in at:
                    d["j"] = s.acc(at["JOINTS_0"]).astype(np.int64)
                    w = s.acc(at["WEIGHTS_0"]).astype(np.float32)
                    if w.dtype != np.float32 or w.max() > 1.5:
                        w = w / 255.0
                    d["w"] = w
                yield nn.get(mi_, mesh["name"]), p.get("material", 0), d


base_m = G(find(UBC, "Superhero_Male_FullBody.gltf"))
base_f = G(find(UBC, "Superhero_Female_FullBody.gltf"))
HAIRDIR = os.path.dirname(find(UBC, "Hair_Long.gltf"))
OUT_PARTS = os.path.dirname(find(OUTF, "Male_Peasant.gltf"))


def remap(d, names_src, names_dst):
    lut = np.array([names_dst.index(n) for n in names_src], dtype=np.int64)
    d = dict(d)
    d["j"] = lut[d["j"]]
    return d


def cat(parts):
    out = {"pos": [], "nrm": [], "uv": [], "j": [], "w": [], "idx": []}
    off = 0
    for d in parts:
        for k in ("pos", "nrm", "uv", "j", "w"):
            out[k].append(d[k])
        out["idx"].append(d["idx"] + off)
        off += len(d["pos"])
    if not parts:
        return None
    return {k: np.concatenate(v) for k, v in out.items()}


def cut_head(base, names):
    keep_j = {names.index("Head"), names.index("neck_01")}
    res = []
    for mn, mi, d in base.prims():
        if "j" not in d or mn.startswith("Eyes") or mn.startswith("Eyebrows"):
            continue
        dom = d["j"][np.arange(len(d["j"])), np.argmax(d["w"], axis=1)]
        inh = np.isin(dom, list(keep_j))
        tri = d["idx"].reshape(-1, 3)
        sel = inh[tri].all(axis=1)
        t = tri[sel]
        used = np.unique(t)
        lut = -np.ones(len(d["pos"]), dtype=np.int64)
        lut[used] = np.arange(len(used))
        nd = {k: d[k][used] for k in ("pos", "nrm", "uv", "j", "w")}
        nd["idx"] = lut[t].reshape(-1)
        res.append(nd)
    return res


def rigid(d, jidx):
    d = dict(d)
    n = len(d["pos"])
    d["j"] = np.zeros((n, 4), dtype=np.int64)
    d["j"][:, 0] = jidx
    d["w"] = np.zeros((n, 4), dtype=np.float32)
    d["w"][:, 0] = 1.0
    return d


def eyes_of(base, names):
    for mn, mi, d in base.prims():
        if mn.startswith("Eyes"):
            return d
    return None


def load_part(path, names_dst, skin_pred=lambda n: n.startswith("MI_Regular"), drop=()):
    g = G(path)
    nm = g.joint_names()
    skin, cloth, ctex = [], [], None
    for mn, mi, d in g.prims():
        if any(x in mn for x in drop):
            continue
        tp, matname = g.tex_path(mi)
        d = remap(d, nm, names_dst)
        if skin_pred(matname):
            skin.append(d)
        else:
            cloth.append(d)
            ctex = tp
    return skin, cloth, ctex


def hair_of(path, names_dst):
    g = G(path)
    res = []
    tp = None
    for mn, mi, d in g.prims():
        res.append(rigid(d, names_dst.index("Head")))
        tp = g.tex_path(mi)[0]
    return res, tp


TEXOUT = os.path.join(PROJ, "assets", "npc", "tex")
os.makedirs(TEXOUT, exist_ok=True)
_tex_done = {}


def export_tex(src, name, size, alpha=False):
    if name in _tex_done:
        return _tex_done[name]
    im = Image.open(src).convert("RGBA" if alpha else "RGB")
    if im.size[0] > size:
        im = im.resize((size, size), Image.LANCZOS)
    im.save(os.path.join(TEXOUT, name + ".png"), optimize=True)
    _tex_done[name] = "tex/" + name + ".png"
    return _tex_done[name]


def write_gltf(base, path, surfaces, tex_uris):
    """surfaces: list of (merged dict, tex uri). Skeleton nodes copied from base."""
    j0 = base.j
    nodes = json.loads(json.dumps(j0["nodes"]))
    arm = [i for i, n in enumerate(nodes) if n["name"] == "Armature"][0]
    mesh_nodes = [i for i, n in enumerate(nodes) if "mesh" in n]
    keep = mesh_nodes[0]
    for i in mesh_nodes:
        if i != keep:
            nodes[i].pop("mesh", None)
            nodes[i].pop("skin", None)
    nodes[arm]["children"] = [c for c in nodes[arm]["children"] if c == keep or c not in mesh_nodes]
    nodes[keep]["name"] = "NpcMesh"
    nodes[keep]["mesh"] = 0
    nodes[keep]["skin"] = 0
    buf = bytearray()
    bvs, accs, prims, mats, imgs, texs = [], [], [], [], [], []

    def addbuf(arr, ctype, typ, target=None, mm=False):
        while len(buf) % 4:
            buf.append(0)
        bvs.append({"buffer": 0, "byteOffset": len(buf), "byteLength": arr.nbytes, **({"target": target} if target else {})})
        buf.extend(arr.tobytes())
        a = {"bufferView": len(bvs) - 1, "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
        if mm:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        accs.append(a)
        return len(accs) - 1

    # inverse bind matrices from the base skeleton
    ibm = base.acc(j0["skins"][0]["inverseBindMatrices"]).astype(np.float32)
    ibm_i = addbuf(ibm, 5126, "MAT4")
    for si, (d, uri, mname) in enumerate(surfaces):
        at = {
            "POSITION": addbuf(d["pos"].astype(np.float32), 5126, "VEC3", 34962, True),
            "NORMAL": addbuf(d["nrm"].astype(np.float32), 5126, "VEC3", 34962),
            "TEXCOORD_0": addbuf(d["uv"].astype(np.float32), 5126, "VEC2", 34962),
            "JOINTS_0": addbuf(d["j"].astype(np.uint8), 5121, "VEC4", 34962),
            "WEIGHTS_0": addbuf(d["w"].astype(np.float32), 5126, "VEC4", 34962),
        }
        ii = addbuf(d["idx"].astype(np.uint32).reshape(-1, 1), 5125, "SCALAR", 34963)
        accs[ii]["count"] = len(d["idx"])
        prims.append({"attributes": at, "indices": ii, "material": si})
        imgs.append({"uri": uri})
        texs.append({"source": si})
        mats.append({"name": mname, "doubleSided": True, "pbrMetallicRoughness": {"baseColorTexture": {"index": si}, "metallicFactor": 0.0, "roughnessFactor": 1.0}})
    j = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [arm]}], "nodes": nodes,
         "meshes": [{"name": "NpcMesh", "primitives": prims}], "materials": mats, "images": imgs, "textures": texs,
         "skins": [{"inverseBindMatrices": ibm_i, "joints": j0["skins"][0]["joints"], "name": "Armature"}],
         "accessors": accs, "bufferViews": bvs, "buffers": [{"uri": os.path.basename(path)[:-5] + ".bin", "byteLength": len(buf)}]}
    open(path[:-5] + ".bin", "wb").write(bytes(buf))
    json.dump(j, open(path, "w"), separators=(",", ":"))


VARIANTS = [
    ("m1", "m", "Peasant", "Peasant/T_Peasant_BaseColor.png", ["Hair_SimpleParted"], False),
    ("m2", "m", "Peasant", "Peasant/T_Peasant_2_BaseColor.png", ["Hair_Buzzed", "Hair_Beard"], False),
    ("f1", "f", "Peasant", "Peasant/T_Peasant_BaseColor.png", ["Hair_Long"], False),
    ("f2", "f", "Peasant", "Peasant/T_Peasant_2_BaseColor.png", ["Hair_Buns"], False),
]

os.makedirs(os.path.join(PROJ, "assets", "npc"), exist_ok=True)
stats = []
for (name, sex, outfit, otex, hairs, hood) in VARIANTS:
    base = base_m if sex == "m" else base_f
    names = base.joint_names()
    S = "Male" if sex == "m" else "Female"
    skin, cloth, ctex = [], [], None
    drop = () if hood else ("Hood",)
    # all parts of the outfit (full set file lists every mesh)
    s_, c_, t_ = load_part(os.path.join(OUT_PARTS, "%s_%s.gltf" % (S, outfit)), names, drop=drop)
    skin += s_
    cloth += c_
    head = cut_head(base, names)
    skin += head
    eyes = eyes_of(base, names)
    hair_parts = []
    hair_tex = None
    for h in hairs + ["Eyebrows_Regular" if sex == "m" else "Eyebrows_Female"]:
        hp, ht = hair_of(os.path.join(HAIRDIR, h + ".gltf"), names)
        hair_parts += hp
        if hair_tex is None:
            hair_tex = ht
    # skin / cloth textures
    skin_src = find(OUTF, "T_Regular_%s_Dark_BaseColor.png" % S)
    skin_uri = export_tex(skin_src, "skin_" + sex, 512)
    cloth_uri = export_tex(find(OUTF, os.path.basename(otex)), os.path.basename(otex)[:-4].lower(), 512)
    hair_uri = export_tex(hair_tex, "hair_" + os.path.basename(hair_tex)[:-4].lower(), 256)
    eye_uri = export_tex(find(UBC, "T_Eye_Brown.png"), "eye", 64)
    surfaces = []
    for parts, uri, mn in ((skin, skin_uri, "skin"), (cloth, cloth_uri, "cloth"), (hair_parts, hair_uri, "hair"), ([eyes] if eyes is not None else [], eye_uri, "eyes")):
        m = cat(parts)
        if m is not None:
            surfaces.append((m, uri, mn))
    out = os.path.join(PROJ, "assets", "npc", "npc_%s.gltf" % name)
    write_gltf(base, out, surfaces, None)
    tris = sum(len(s[0]["idx"]) // 3 for s in surfaces)
    stats.append((name, tris, [(s[2], len(s[0]["idx"]) // 3) for s in surfaces]))
for s in stats:
    print(s)

if PREV:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    print("preview not implemented in this build")
