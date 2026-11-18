#!/usr/bin/env python3
"""Builds the mobile-friendly nature assets for iko from the Quaternius Stylized Nature MegaKit.

usage: python3 -I lodgen.py <kit_dir> <out_dir>
  <kit_dir> = folder that contains glTF/ and Textures/
  <out_dir> = e.g. assets/nature

For every model it writes
  Name.gltf     near version (leaf cards thinned, thin branches merged away)
  Name_L.gltf   far version for trees / bushes / grass (even fewer cards)
Normal maps are dropped and the textures are shrunk.
"""
import json, os, struct, sys
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

KIT = sys.argv[1]
OUT = sys.argv[2]
os.makedirs(OUT, exist_ok=True)

# texture -> max size
TEX = {
    "Bark_NormalTree": 512, "Bark_TwistedTree": 512, "Bark_DeadTree": 512,
    "Leaves_NormalTree_C": 512, "Leaves_TwistedTree_C": 512, "Leaf_Pine_C": 1024,
    "Leaves": 1024, "Flowers": 512, "Grass": 128, "Mushrooms": 512,
    "Rocks_Diffuse": 1024, "PathRocks_Diffuse": 512, "Rocks_Desert_Diffuse": 1024,
}

# name: (kind, hi params, lo params or None)
# leaf params = (keep ratio, bark triangle budget)
SPEC = {
    "CommonTree_1": ("tree", (0.40, 900), (0.15, 260)),
    "CommonTree_3": ("tree", (0.50, 800), (0.20, 240)),
    "CommonTree_4": ("tree", (0.50, 850), (0.20, 240)),
    "CommonTree_5": ("tree", (0.55, 800), (0.22, 240)),
    "Pine_4": ("tree", (0.60, 450), (0.28, 160)),
    "Pine_5": ("tree", (0.70, 300), (0.35, 120)),
    "Pine_2": ("tree", (0.60, 500), (0.28, 170)),
    "TwistedTree_1": ("tree", (0.20, 1300), (0.13, 420)),
    "TwistedTree_3": ("tree", (0.20, 1300), (0.13, 420)),
    "DeadTree_2": ("bare", (1.0, 800), (1.0, 480)),
    "DeadTree_5": ("bare", (1.0, 750), (1.0, 450)),
    "Bush_Common": ("cards", (0.65, 0), (0.30, 0)),
    "Bush_Common_Flowers": ("cards", (0.65, 0), (0.30, 0)),
    "Grass_Common_Short": ("cards", (1.0, 0), (0.55, 0)),
    "Grass_Common_Tall": ("cards", (0.85, 0), (0.45, 0)),
    "Grass_Wispy_Short": ("cards", (0.60, 0), (0.30, 0)),
    "Grass_Wispy_Tall": ("cards", (0.60, 0), (0.30, 0)),
    "Fern_1": ("cards", (1.0, 0), None),
    "Plant_1_Big": ("cards", (1.0, 0), None),
    "Plant_7_Big": ("cards", (1.0, 0), None),
    "Clover_1": ("cards", (0.8, 0), None),
    "Flower_3_Group": ("cards", (0.85, 0), None),
    "Flower_3_Single": ("cards", (1.0, 0), None),
    "Flower_4_Group": ("cards", (0.5, 0), None),
    "Flower_4_Single": ("cards", (0.8, 0), None),
    "Mushroom_Common": ("plain", None, None),
    "Rock_Medium_1": ("plain", None, None),
    "Rock_Medium_2": ("plain", None, None),
    "Rock_Medium_3": ("plain", None, None),
    "Pebble_Round_1": ("plain", None, None),
    "Pebble_Round_3": ("plain", None, None),
    "Pebble_Round_5": ("plain", None, None),
    "Pebble_Square_1": ("plain", None, None),
    "Pebble_Square_3": ("plain", None, None),
    "Pebble_Square_5": ("plain", None, None),
    "RockPath_Square_Small_2": ("plain", None, None),
    "RockPath_Round_Small_1": ("plain", None, None),
}


def load(path):
    j = json.load(open(path))
    b = open(path[:-5] + ".bin", "rb").read()

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        ct = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[a["componentType"]]
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", 0)
        item = np.dtype(ct).itemsize
        if stride and stride != item * n:
            return np.ndarray((a["count"], n), dtype=ct, buffer=b, offset=off, strides=(stride, item)).copy()
        return np.frombuffer(b, dtype=ct, count=a["count"] * n, offset=off).reshape(a["count"], n).copy()

    return j, acc


class Prim:
    def __init__(self, pos, nrm, uv, idx, mat):
        self.pos, self.nrm, self.uv, self.idx, self.mat = pos, nrm, uv, idx, mat


def components(p):
    """triangle -> component id (vertices merged by position)."""
    key = {}
    vid = np.zeros(len(p.pos), np.int64)
    for i, v in enumerate(map(tuple, np.round(p.pos, 3))):
        vid[i] = key.setdefault(v, len(key))
    e = vid[p.idx]
    n = len(key)
    r = np.concatenate([e[:, 0], e[:, 1]])
    c = np.concatenate([e[:, 1], e[:, 2]])
    g = coo_matrix((np.ones(len(r)), (r, c)), shape=(n, n))
    _, lab = connected_components(g, directed=False)
    return lab[e[:, 0]]


def subset(p, tri_mask, scale_about=None, scale=1.0, comp=None):
    idx = p.idx[tri_mask]
    used = np.unique(idx)
    remap = -np.ones(len(p.pos), np.int64)
    remap[used] = np.arange(len(used))
    pos = p.pos[used].copy()
    return Prim(pos, p.nrm[used], p.uv[used], remap[idx], p.mat)


def thin_cards(p, keep, seed):
    """keep a fraction of the leaf cards, make the rest bigger so the canopy stays full."""
    if keep >= 0.999:
        return p
    comp = components(p)
    ncomp = comp.max() + 1
    rng = np.random.RandomState(seed)
    order = rng.permutation(ncomp)
    nkeep = max(1, int(round(ncomp * keep)))
    kept = np.zeros(ncomp, bool)
    kept[order[:nkeep]] = True
    tri_mask = kept[comp]
    q = subset(p, tri_mask)
    # scale each kept card about its own centre (per component, recomputed on the subset)
    comp2 = components(q)
    s = min(1.75, (1.0 / max(keep, 0.05)) ** 0.5 * 0.92)
    pos = q.pos.copy()
    vcomp = np.zeros(len(q.pos), np.int64)
    vcomp[q.idx[:, 0]] = comp2
    vcomp[q.idx[:, 1]] = comp2
    vcomp[q.idx[:, 2]] = comp2
    for c in range(comp2.max() + 1):
        m = vcomp == c
        ctr = pos[m].mean(0)
        pos[m] = ctr + (pos[m] - ctr) * s
    q.pos = pos.astype(np.float32)
    return q


def cluster_simplify(p, target, uvq=1.0):
    """vertex-clustering decimation, cell size found by bisection to reach `target` triangles."""
    if len(p.idx) <= target:
        return p
    lo, hi = 0.01, 3.0
    best = None
    mn = p.pos.min(0)
    for _ in range(14):
        cell = (lo + hi) * 0.5
        q = (np.floor((p.pos - mn) / cell)).astype(np.int64)
        uq = np.floor(p.uv * uvq).astype(np.int64)
        keys = np.concatenate([q, uq], axis=1)
        _, inv = np.unique(keys, axis=0, return_inverse=True)
        inv = inv.reshape(-1)
        tri = inv[p.idx]
        ok = (tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])
        n = int(ok.sum())
        if n > target:
            lo = cell
        else:
            hi = cell
            best = (inv, tri[ok])
    if best is None:
        cell = hi
        q = (np.floor((p.pos - mn) / cell)).astype(np.int64)
        uq = np.floor(p.uv * uvq).astype(np.int64)
        _, inv = np.unique(np.concatenate([q, uq], axis=1), axis=0, return_inverse=True)
        inv = inv.reshape(-1)
        tri = inv[p.idx]
        ok = (tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])
        best = (inv, tri[ok])
    inv, tri = best
    nv = inv.max() + 1
    cnt = np.bincount(inv, minlength=nv).astype(np.float64)

    def avg(a):
        out = np.zeros((nv, a.shape[1]))
        for k in range(a.shape[1]):
            out[:, k] = np.bincount(inv, weights=a[:, k], minlength=nv)
        return out / cnt[:, None]

    pos = avg(p.pos)
    nrm = avg(p.nrm)
    nl = np.linalg.norm(nrm, axis=1, keepdims=True)
    nrm = nrm / np.maximum(nl, 1e-6)
    uv = avg(p.uv)
    used = np.unique(tri)
    remap = -np.ones(nv, np.int64)
    remap[used] = np.arange(len(used))
    return Prim(pos[used].astype(np.float32), nrm[used].astype(np.float32), uv[used].astype(np.float32), remap[tri], p.mat)


def is_leaf(mat_name):
    return mat_name.startswith("Leaf") or mat_name.startswith("Leaves")


def build_variant(j, acc, kind, params, seed, lod):
    prims = []
    for m in j["meshes"]:
        for pr in m["primitives"]:
            idx = acc(pr["indices"]).reshape(-1, 3).astype(np.int64)
            pos = acc(pr["attributes"]["POSITION"]).astype(np.float32)
            nrm = acc(pr["attributes"]["NORMAL"]).astype(np.float32)
            uv = acc(pr["attributes"]["TEXCOORD_0"]).astype(np.float32)
            mat = j["materials"][pr["material"]]
            prims.append(Prim(pos, nrm, uv, idx, mat))
    out = []
    for k, p in enumerate(prims):
        nm = p.mat["name"]
        if kind in ("tree", "bare"):
            if is_leaf(nm):
                p = thin_cards(p, params[0], seed + k)
            else:
                p = cluster_simplify(p, params[1])
        elif kind == "cards":
            p = thin_cards(p, params[0], seed + k)
        out.append(p)
    return out


def write_gltf(path, prims, name, textures_used):
    bin_ = bytearray()
    bvs, accs, meshes_prims, mats, imgs, texs = [], [], [], [], [], []
    img_index = {}

    def add_view(data, target):
        while len(bin_) % 4:
            bin_.append(0)
        off = len(bin_)
        bin_.extend(data)
        bvs.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        return len(bvs) - 1

    def add_acc(view, ct, count, typ, mn=None, mx=None):
        a = {"bufferView": view, "componentType": ct, "count": count, "type": typ}
        if mn is not None:
            a["min"] = mn
            a["max"] = mx
        accs.append(a)
        return len(accs) - 1

    def tex_for(fname):
        if fname not in img_index:
            imgs.append({"uri": fname})
            texs.append({"source": len(imgs) - 1})
            img_index[fname] = len(texs) - 1
        return img_index[fname]

    for p in prims:
        pos = p.pos.astype(np.float32)
        nrm = p.nrm.astype(np.float32)
        uv = p.uv.astype(np.float32)
        idx = p.idx.astype(np.uint16).reshape(-1)
        a_pos = add_acc(add_view(pos.tobytes(), 34962), 5126, len(pos), "VEC3", pos.min(0).tolist(), pos.max(0).tolist())
        a_nrm = add_acc(add_view(nrm.tobytes(), 34962), 5126, len(nrm), "VEC3")
        a_uv = add_acc(add_view(uv.tobytes(), 34962), 5126, len(uv), "VEC2")
        a_idx = add_acc(add_view(idx.tobytes(), 34963), 5123, len(idx), "SCALAR")
        src = p.mat
        bc = src["pbrMetallicRoughness"]["baseColorTexture"]["index"]
        # find source texture file name (stored in gltf images list of the original)
        fname = textures_used[bc]
        leaf = is_leaf(src["name"]) or src["name"] in ("Flowers", "Grass") and src.get("alphaMode") == "MASK"
        m = {
            "name": src["name"],
            "doubleSided": True,
            "pbrMetallicRoughness": {"baseColorTexture": {"index": tex_for(fname)}, "metallicFactor": 0.0, "roughnessFactor": 1.0},
        }
        if src.get("alphaMode") == "MASK" and (is_leaf(src["name"]) or src["name"] in ("Flowers",)):
            m["alphaMode"] = "MASK"
            m["alphaCutoff"] = 0.5
        mats.append(m)
        meshes_prims.append({"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv}, "indices": a_idx, "material": len(mats) - 1, "mode": 4})
    g = {
        "asset": {"version": "2.0", "generator": "iko lodgen"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": meshes_prims}],
        "materials": mats,
        "textures": texs,
        "images": imgs,
        "accessors": accs,
        "bufferViews": bvs,
        "buffers": [{"uri": os.path.basename(path)[:-5] + ".bin", "byteLength": len(bin_)}],
    }
    json.dump(g, open(path, "w"), separators=(",", ":"))
    open(path[:-5] + ".bin", "wb").write(bytes(bin_))


def tri_count(prims):
    return sum(len(p.idx) for p in prims)


def do_textures(names):
    for n in sorted(names):
        src = os.path.join(KIT, "Textures", n + ".png")
        im = Image.open(src).convert("RGBA")
        sz = TEX.get(n, 512)
        if im.size[0] > sz:
            im = im.resize((sz, sz), Image.LANCZOS)
        a = np.array(im)
        alpha = a[:, :, 3]
        if (alpha < 250).any():
            # bleed colour into transparent pixels so mip-mapped edges do not turn dark
            mask = alpha < 8
            if mask.any() and (~mask).any():
                _, (iy, ix) = distance_transform_edt(mask, return_indices=True)
                rgb = a[:, :, :3].copy()
                rgb[mask] = a[iy[mask], ix[mask], :3]
                a[:, :, :3] = rgb
            im = Image.fromarray(a, "RGBA")
        else:
            im = Image.fromarray(a[:, :, :3], "RGB")
        im.save(os.path.join(OUT, n + ".png"), optimize=True)


def main():
    used_tex = set()
    report = []
    for name, (kind, hi, lo) in SPEC.items():
        gp = os.path.join(KIT, "glTF", name + ".gltf")
        j, acc = load(gp)
        # original texture file per texture index
        files = {}
        for ti, t in enumerate(j["textures"]):
            files[ti] = os.path.splitext(os.path.basename(j["images"][t["source"]]["uri"]))[0] + ".png"
        # drop normal maps: the textures list is used by baseColor only
        for ti in list(files):
            pass
        for m in j["materials"]:
            used_tex.add(files[m["pbrMetallicRoughness"]["baseColorTexture"]["index"]][:-4])
        fnames = files
        seed = abs(hash(name)) % 9999 if False else sum(ord(c) * (i + 3) for i, c in enumerate(name))
        if kind == "plain":
            prims = build_variant(j, acc, "plain", None, seed, 0)
        else:
            prims = build_variant(j, acc, kind, hi, seed, 0)
        write_gltf(os.path.join(OUT, name + ".gltf"), prims, name, fnames)
        row = [name, tri_count(prims)]
        if lo is not None:
            prims_l = build_variant(j, acc, kind, lo, seed + 77, 1)
            write_gltf(os.path.join(OUT, name + "_L.gltf"), prims_l, name + "_L", fnames)
            row.append(tri_count(prims_l))
        report.append(row)
    do_textures(used_tex)
    for r in report:
        print(r)
    print("textures:", sorted(used_tex))


main()
