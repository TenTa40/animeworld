"""Retargets a Mixamo (binary FBX) clip onto the UAL2 skeleton by world-space rotation deltas.
Used by riggen.py; returns channels [(node_index, 'rotation'|'translation', times, values)]."""
import numpy as np
from fbxb import parse

TICKS = 46186158000.0
MAP = {"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Spine1", "spine_03": "Spine2", "neck_01": "Neck", "Head": "Head",
       "clavicle_l": "LeftShoulder", "upperarm_l": "LeftArm", "lowerarm_l": "LeftForeArm", "hand_l": "LeftHand",
       "clavicle_r": "RightShoulder", "upperarm_r": "RightArm", "lowerarm_r": "RightForeArm", "hand_r": "RightHand",
       "thigh_l": "LeftUpLeg", "calf_l": "LeftLeg", "foot_l": "LeftFoot", "ball_l": "LeftToeBase",
       "thigh_r": "RightUpLeg", "calf_r": "RightLeg", "foot_r": "RightFoot", "ball_r": "RightToeBase"}


def rx(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def euler(v):
    x, y, z = np.radians(v)
    return rz(z) @ ry(y) @ rx(x)


def mat_quat(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def load_clip(path):
    r = parse(path)
    ob = r.find("Objects")[0]
    byid = {c.props[0]: c for c in ob.children}
    models = {}
    for c in ob.children:
        if c.name != "Model":
            continue
        nm = c.props[1].split("\x00")[0].replace("mixamorig:", "")
        d = {"name": nm, "T": np.zeros(3), "R": np.zeros(3), "pre": np.zeros(3), "parent": None, "curves": {}}
        for p in c.find("Properties70")[0].children:
            k = p.props[0]
            if k == "Lcl Translation":
                d["T"] = np.array(p.props[4:7], float)
            elif k == "Lcl Rotation":
                d["R"] = np.array(p.props[4:7], float)
            elif k == "PreRotation":
                d["pre"] = np.array(p.props[4:7], float)
        models[c.props[0]] = d
    cons = r.find("Connections")[0].children
    cnode = {}
    for c in cons:
        t, ch, pa = c.props[0], c.props[1], c.props[2]
        if t == "OO" and ch in models and pa in models:
            models[ch]["parent"] = pa
        if t == "OP" and byid.get(ch) is not None and byid[ch].name == "AnimationCurveNode" and pa in models:
            cnode[ch] = (pa, c.props[3])
    for c in cons:
        if c.props[0] == "OP" and c.props[1] in byid and byid[c.props[1]].name == "AnimationCurve" and c.props[2] in cnode:
            mid, prop = cnode[c.props[2]]
            ax = c.props[3].split("|")[-1]
            cv = byid[c.props[1]]
            tt = cv.find("KeyTime")[0].props[0].astype(np.float64) / TICKS
            vv = cv.find("KeyValueFloat")[0].props[0].astype(np.float64)
            models[mid]["curves"][(prop, ax)] = (tt, vv)
    return models


def sample_clip(models, fps=30.0):
    tmax = 0.0
    for m in models.values():
        for tt, _ in m["curves"].values():
            tmax = max(tmax, tt.max())
    n = int(round(tmax * fps)) + 1
    times = np.arange(n) / fps
    return times


def val(m, prop, base, t):
    v = base.copy()
    for i, ax in enumerate("XYZ"):
        cv = m["curves"].get((prop, ax))
        if cv is not None:
            v[i] = np.interp(t, cv[0], cv[1])
    return v


def retarget(path, J, jname, parent_joint, rest_G, rest_local_R, rest_parent_R, pelvis_h, report=True):
    """J-order lists. rest_G: (n,4,4) global rest; rest_local_R: (n,3,3) local rest rotation;
    rest_parent_R: (n,3,3) global rest rotation of the parent *node* (identity-chained for the root)."""
    models = load_clip(path)
    byname = {m["name"]: k for k, m in models.items()}
    times = sample_clip(models)
    order = []

    def depth(k):
        d = 0
        while models[k]["parent"] in models:
            k = models[k]["parent"]
            d += 1
        return d
    order = sorted(models.keys(), key=depth)

    def globals_at(t, rest=False):
        G = {}
        for k in order:
            m = models[k]
            T = m["T"] if rest else val(m, "Lcl Translation", m["T"], t)
            Rl = euler(m["R"] if rest else val(m, "Lcl Rotation", m["R"], t))
            L = np.eye(4)
            L[:3, :3] = euler(m["pre"]) @ Rl
            L[:3, 3] = T
            G[k] = G[m["parent"]] @ L if m["parent"] in G else L
        return G
    Grest = globals_at(0.0, True)
    if report:
        for nm in ("Hips", "LeftArm", "LeftHand", "LeftFoot", "LeftToeBase", "Head", "RightArm"):
            print("  mixamo rest", nm, np.round(Grest[byname[nm]][:3, 3], 1))
    hip_k = byname["Hips"]
    hip_h = Grest[hip_k][1, 3]
    scale = pelvis_h / hip_h
    n = len(times)
    jindex = {nm: i for i, nm in enumerate(jname)}
    rots = np.zeros((n, len(J), 4))
    hip_pos = np.zeros((n, 3))
    for f, t in enumerate(times):
        Ga = globals_at(t)
        hip_pos[f] = Ga[hip_k][:3, 3] * scale
        newR = [None] * len(J)
        for j, nm in enumerate(jname):
            mx = MAP.get(nm)
            pj = parent_joint[j]
            parR = newR[pj] if pj >= 0 else rest_parent_R[j]
            if mx is not None and mx in byname:
                k = byname[mx]
                D = Ga[k][:3, :3] @ np.linalg.inv(Grest[k][:3, :3])
                gR = D @ rest_G[j][:3, :3]
            else:
                gR = parR @ rest_local_R[j]
            newR[j] = gR
            loc = parR.T @ gR
            q = mat_quat(loc)
            rots[f, j] = q
    # keep quaternions continuous
    for j in range(len(J)):
        for f in range(1, n):
            if np.dot(rots[f, j], rots[f - 1, j]) < 0:
                rots[f, j] = -rots[f, j]
    # pelvis translation: remove drift, keep the periodic bob
    tr = hip_pos - hip_pos.mean(0)
    for ax in range(3):
        lin = np.polyfit(times, tr[:, ax], 1)
        tr[:, ax] -= np.polyval(lin, times)
    if report:
        print("  frames", n, "loop err (rot)", float(np.abs(rots[0] - rots[-1]).max().round(4)), "hip bob", np.round(tr.max(0) - tr.min(0), 3))
    return times, rots, tr
