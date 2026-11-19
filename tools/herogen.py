#!/usr/bin/env python3
"""Turns the 300k-triangle character GLB into a light mobile mesh with baked vertex colours.

usage: python3 -I herogen.py <character.glb> <out.dat> [target_triangles] [height_m]

The source texture is a shattered 4096 atlas, so colours are sampled per vertex, then the mesh is
simplified by quadric-optimised vertex clustering. Output (little endian):
  "IKO1", u32 nv, u32 ni, f32[nv*3] pos, i8[nv*3] normal, u8[nv*3] colour (sRGB), u32[ni] indices
Feet are at y = 0, the character faces +Z.
"""
import io, json, struct, sys
import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
SRC, OUT = sys.argv[1], sys.argv[2]
TARGET = int(sys.argv[3]) if len(sys.argv) > 3 else 26000
HEIGHT = float(sys.argv[4]) if len(sys.argv) > 4 else 1.6


def load_glb(path):
    b = open(path, "rb").read()
    cl, _ = struct.unpack("<II", b[12:20])
    j = json.loads(b[20:20 + cl])
    bo = 20 + cl + 8

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        ct = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[a["componentType"]]
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
        off = bo + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        return np.frombuffer(b, dtype=ct, count=a["count"] * n, offset=off).reshape(a["count"], n).copy()

    p = j["meshes"][0]["primitives"][0]
    im = j["images"][j["textures"][j["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["extensions"]["EXT_texture_webp"]["source"]]
    bv = j["bufferViews"][im["bufferView"]]
    data = b[bo + bv.get("byteOffset", 0): bo + bv.get("byteOffset", 0) + bv["byteLength"]]
    img = Image.open(io.BytesIO(data)).convert("RGB")
    return acc(p["attributes"]["POSITION"]), acc(p["attributes"]["TEXCOORD_0"]), acc(p["indices"]).reshape(-1, 3).astype(np.int64), np.array(img)


pos, uv, idx, img = load_glb(SRC)
H, W, _ = img.shape
u = np.clip((uv[:, 0] * W).astype(int), 0, W - 1)
v = np.clip((uv[:, 1] * H).astype(int), 0, H - 1)
col = img[v, u].astype(np.float64)  # sRGB 0..255

# weld vertices that share a position
key = np.round(pos / 1e-5).astype(np.int64)
_, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
inv = inv.reshape(-1)
nw = len(first)
cnt = np.bincount(inv, minlength=nw).astype(np.float64)
wpos = pos[first].astype(np.float64)
wcol = np.stack([np.bincount(inv, weights=col[:, k], minlength=nw) for k in range(3)], axis=1) / cnt[:, None]
tri = inv[idx]
ok = (tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])
tri = tri[ok]
print("welded", len(pos), "->", nw, "verts,", len(tri), "tris")


def decimate(cell, lam=0.15):
    mn = wpos.min(0)
    q = np.floor((wpos - mn) / cell).astype(np.int64)
    _, cinv = np.unique(q, axis=0, return_inverse=True)
    cinv = cinv.reshape(-1)
    K = cinv.max() + 1
    p0, p1, p2 = wpos[tri[:, 0]], wpos[tri[:, 1]], wpos[tri[:, 2]]
    n = np.cross(p1 - p0, p2 - p0)
    a2 = np.linalg.norm(n, axis=1)
    good = a2 > 1e-14
    nn = np.zeros_like(n)
    nn[good] = n[good] / a2[good, None]
    d = -np.sum(nn * p0, axis=1)
    w = a2 * 0.5
    A = np.zeros((K, 3, 3))
    bvec = np.zeros((K, 3))
    wsum = np.zeros(K)
    for c in range(3):
        cc = cinv[tri[:, c]]
        for r in range(3):
            for s in range(3):
                A[:, r, s] += np.bincount(cc, weights=w * nn[:, r] * nn[:, s], minlength=K)
            bvec[:, r] += np.bincount(cc, weights=w * nn[:, r] * d, minlength=K)
        wsum += np.bincount(cc, weights=w, minlength=K)
    ccount = np.bincount(cinv, minlength=K).astype(np.float64)
    pm = np.stack([np.bincount(cinv, weights=wpos[:, k], minlength=K) for k in range(3)], axis=1) / ccount[:, None]
    cm = np.stack([np.bincount(cinv, weights=wcol[:, k], minlength=K) for k in range(3)], axis=1) / ccount[:, None]
    eps = (lam * np.maximum(wsum, 1e-12))[:, None, None] * np.eye(3)[None]
    x = np.linalg.solve(A + eps, (-bvec + (eps @ pm[:, :, None])[:, :, 0])[:, :, None])[:, :, 0]
    lo = pm - 0.9 * cell
    hi = pm + 0.9 * cell
    bad = np.any((x < lo) | (x > hi), axis=1) | ~np.all(np.isfinite(x), axis=1)
    x[bad] = pm[bad]
    t = cinv[tri]
    m = (t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])
    t = t[m]
    # drop duplicate triangles (same 3 vertices, any order)
    srt = np.sort(t, axis=1)
    _, ui = np.unique(srt, axis=0, return_index=True)
    t = t[np.sort(ui)]
    return x, cm, t


lo, hi = 0.002, 0.05
best = None
for _ in range(14):
    mid = (lo + hi) * 0.5
    x, cm, t = decimate(mid)
    if len(t) > TARGET:
        lo = mid
    else:
        hi = mid
        best = (mid, x, cm, t)
cell, x, cm, t = best
print("cell", round(cell, 5), "tris", len(t), "verts", len(x))

# keep only used vertices
used = np.unique(t)
remap = -np.ones(len(x), np.int64)
remap[used] = np.arange(len(used))
x = x[used]
cm = cm[used]
t = remap[t]

# scale and put the feet on y = 0, centred in x / z
mn = x.min(0)
mx = x.max(0)
s = HEIGHT / (mx[1] - mn[1])
x = (x - np.array([(mn[0] + mx[0]) * 0.5, mn[1], (mn[2] + mx[2]) * 0.5])) * s

# smooth normals
p0, p1, p2 = x[t[:, 0]], x[t[:, 1]], x[t[:, 2]]
fn = np.cross(p1 - p0, p2 - p0)
nrm = np.zeros_like(x)
for c in range(3):
    for k in range(3):
        nrm[:, k] += np.bincount(t[:, c], weights=fn[:, k], minlength=len(x))
nl = np.linalg.norm(nrm, axis=1, keepdims=True)
nrm = nrm / np.maximum(nl, 1e-9)

out = bytearray()
out += b"IKO1"
out += struct.pack("<II", len(x), t.size)
out += x.astype("<f4").tobytes()
out += np.clip(np.round(nrm * 127), -127, 127).astype(np.int8).tobytes()
out += np.clip(np.round(cm), 0, 255).astype(np.uint8).tobytes()
out += t.astype("<u4").reshape(-1).tobytes()
open(OUT, "wb").write(bytes(out))
print("wrote", OUT, len(out) // 1024, "KB; bbox", x.min(0).round(3), x.max(0).round(3))
