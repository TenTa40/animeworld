"""Helpers to merge kit models (Quaternius glTF, Kenney GLB) into per-material meshes, write glTF, and preview."""
import json, os, struct
import numpy as np
from PIL import Image

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_any(path):
    """returns list of dict(pos,nrm,uv,idx,mat=name,tex=path or None, color=None)"""
    if path.endswith(".glb"):
        b = open(path, "rb").read()
        cl, _ = struct.unpack("<II", b[12:20])
        j = json.loads(b[20:20 + cl])
        bufs = [b[20 + cl + 8:]]
    else:
        j = json.load(open(path))
        d = os.path.dirname(path)
        bufs = [open(os.path.join(d, x["uri"]), "rb").read() for x in j["buffers"]]
    d = os.path.dirname(path)

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        ct = CT[a["componentType"]]
        n = NC[a["type"]]
        it = np.dtype(ct).itemsize
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        st = bv.get("byteStride", 0)
        bb = bufs[bv["buffer"]]
        if st and st != it * n:
            return np.ndarray((a["count"], n), dtype=ct, buffer=bb, offset=off, strides=(st, it)).copy()
        return np.frombuffer(bb, dtype=ct, count=a["count"] * n, offset=off).reshape(a["count"], n).copy()
    # node transforms (apply nodes that carry meshes)
    nodes = j.get("nodes", [])
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def nmat(i):
        n = nodes[i]
        if "matrix" in n:
            M = np.array(n["matrix"]).reshape(4, 4).T
        else:
            M = np.eye(4)
            s = n.get("scale", [1, 1, 1])
            q = n.get("rotation", [0, 0, 0, 1])
            x, y, z, w = q
            R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                          [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                          [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
            M[:3, :3] = R @ np.diag(s)
            M[:3, 3] = n.get("translation", [0, 0, 0])
        return nmat(parent[i]) @ M if i in parent else M
    out = []
    for ni, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        M = nmat(ni)
        for p in j["meshes"][n["mesh"]]["primitives"]:
            at = p["attributes"]
            pos = acc(at["POSITION"]).astype(np.float64)
            nrm = acc(at["NORMAL"]).astype(np.float64) if "NORMAL" in at else np.zeros_like(pos)
            uv = acc(at["TEXCOORD_0"]).astype(np.float64) if "TEXCOORD_0" in at else np.zeros((len(pos), 2))
            idx = acc(p["indices"]).reshape(-1, 3).astype(np.int64)
            pos = (M[:3, :3] @ pos.T).T + M[:3, 3]
            nrm = (np.linalg.inv(M[:3, :3]).T @ nrm.T).T
            mat = j["materials"][p["material"]] if "material" in p else {"name": "default"}
            tex = None
            bc = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
            if bc is not None:
                tx = j["textures"][bc["index"]]
                im = j["images"][tx["source"]]
                if "uri" in im:
                    tex = os.path.join(d, im["uri"])
            col = mat.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
            out.append(dict(pos=pos, nrm=nrm, uv=uv, idx=idx, mat=mat.get("name", "m"), tex=tex, color=col))
    return out


def rot_y(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


class Scene:
    """accumulates geometry per material name"""

    def __init__(self):
        self.m = {}      # mat -> dict(pos,nrm,uv,idx lists)
        self.tex = {}    # mat -> texture path
        self.col = {}
        self.cache = {}
        self.boxes = []  # collision boxes (cx,cy,cz,sx,sy,sz,yaw)

    def model(self, path):
        if path not in self.cache:
            self.cache[path] = load_any(path)
        return self.cache[path]

    def add(self, path, pos=(0, 0, 0), yaw=0.0, scale=1.0, mat_map=None, sy=None):
        R = rot_y(yaw) * scale
        if sy is not None:
            R = R @ np.diag([1, sy / scale if scale else sy, 1]) if False else R
        for p in self.model(path):
            nm = p["mat"]
            if mat_map and nm in mat_map:
                nm = mat_map[nm]
            e = self.m.setdefault(nm, dict(pos=[], nrm=[], uv=[], idx=[], n=0))
            P = (R @ p["pos"].T).T + np.array(pos)
            N = (rot_y(yaw) @ p["nrm"].T).T
            e["pos"].append(P)
            e["nrm"].append(N)
            e["uv"].append(p["uv"])
            e["idx"].append(p["idx"] + e["n"])
            e["n"] += len(P)
            if p["tex"]:
                self.tex[nm] = p["tex"]
            self.col[nm] = p["color"]

    def tris(self):
        return sum(sum(len(i) for i in e["idx"]) for e in self.m.values())

    def arrays(self, nm):
        e = self.m[nm]
        return (np.concatenate(e["pos"]), np.concatenate(e["nrm"]), np.concatenate(e["uv"]), np.concatenate(e["idx"]))


_texavg = {}


def tex_color(path, uv):
    """nearest-sample colour of a (cached, small) texture"""
    if path is None:
        return None
    if path not in _texavg:
        im = Image.open(path).convert("RGB")
        im.thumbnail((128, 128))
        _texavg[path] = np.array(im)
    a = _texavg[path]
    h, w, _ = a.shape
    u = np.mod(uv[:, 0], 1.0)
    v = np.mod(uv[:, 1], 1.0)
    return a[(v * (h - 1)).astype(int), (u * (w - 1)).astype(int)]


def preview(scene, out, views=((0.6, 0.35), (2.4, 0.35)), size=700, center=None, span=None, skip=()):
    """painter's-algorithm render from yaw/pitch views side by side"""
    from PIL import ImageDraw
    tris = []
    for nm in scene.m:
        if nm in skip:
            continue
        P, N, UV, I = scene.arrays(nm)
        tc = tex_color(scene.tex.get(nm), UV)
        for t in I:
            if tc is not None:
                c = tc[t].mean(0)
            else:
                c = np.array(scene.col.get(nm, [0.7, 0.7, 0.7, 1])[:3]) * 255
            tris.append((P[t], N[t].mean(0), c))
    allp = np.concatenate([t[0] for t in tris])
    ctr = center if center is not None else (allp.min(0) + allp.max(0)) / 2
    sp = span if span is not None else np.abs(allp - ctr).max() * 1.15
    img = Image.new("RGB", (size * len(views), size), (150, 190, 230))
    d = ImageDraw.Draw(img)
    L = np.array([0.4, 0.8, 0.3])
    L /= np.linalg.norm(L)
    for vi, (yaw, pit) in enumerate(views):
        R = rot_y(yaw)
        cp, sp_ = np.cos(pit), np.sin(pit)
        Rx = np.array([[1, 0, 0], [0, cp, -sp_], [0, sp_, cp]])
        items = []
        for P, n, c in tris:
            Q = ((P - ctr) @ R.T) @ Rx.T
            depth = Q[:, 2].mean()
            nw = n / (np.linalg.norm(n) + 1e-9)
            lit = 0.55 + 0.45 * max(0.0, float(nw @ L))
            items.append((depth, Q, np.clip(c * lit, 0, 255).astype(int)))
        items.sort(key=lambda x: -x[0])
        for depth, Q, c in items:
            pts = [(vi * size + size / 2 + q[0] / sp * size / 2, size / 2 - q[1] / sp * size / 2) for q in Q]
            d.polygon(pts, fill=tuple(int(x) for x in c))
    img.save(out)
