extends Node3D
# iko — streams the Quaternius "Stylized Nature MegaKit" around the player.
# The world is cut into chunks (size depends on the category); every chunk is generated deterministically
# and gets one MultiMesh per model. Far chunks are freed.
#
# Two-level models: trees, bushes and grass exist as a near model (Name.gltf) and a far model (Name_L.gltf).
# Both use the same chunk size and seed, so each instance exists in both; the shaders cross-fade them by distance
# (trees: dithered dissolve, grass: size envelope). Beyond TREE_R the terrain draws impostor billboards.

const DIR := "res://assets/nature/"
const TREE_R := 140.0
const FOLIAGE_SH := "res://shaders/anime/foliage.gdshader"
const GRASS_SH := "res://shaders/anime/grass.gdshader"
# model-name prefix -> distance range [a, b] where the near model hands over to the far model
const FADES := {
	"CommonTree": Vector2(30.0, 40.0),
	"Pine": Vector2(34.0, 46.0),
	"TwistedTree": Vector2(40.0, 50.0),
	"DeadTree": Vector2(40.0, 50.0),
	"Bush": Vector2(22.0, 30.0),
	"Grass": Vector2(12.0, 19.0),
}

var Q: float = 1.0
var DENSITY: float = 1.0
var us_budget: int = 3000

var world = null
var player = null
var CATS: Array = []
var ORDER: Array = []

var _meshes: Dictionary = {}
var _live: Dictionary = {}
var _t: float = 0.0
var _cc: Vector2i = Vector2i(99999, 99999)
var _lastq: float = -1.0
var _incomplete: bool = true
var _has_road: bool = false
var _has_aut: bool = false
var _foliage_shader: Shader = null
var _grass_shader: Shader = null
var _grass_mats: Array = []
var _inst_total: int = 0
var _tri_total: int = 0

func _init() -> void:
	_make_cats()

# ------------------------------------------------------------ category table
# d = instances per m2, r = outer radius (m), rin = inner radius, cs = chunk size, bw = density per biome [plains, forest, desert, mountain]
# qs = radius is scaled by the quality factor Q, path: -1 avoid roads, 1 only on roads, mode: 0 plain, 1 near model, 2 far model
func _pair(base: Dictionary, key: String) -> void:
	var fd: Vector2 = FADES[key]
	var hi: Dictionary = base.duplicate(true)
	hi["mode"] = 1
	hi["cs"] = float(base.get("cs", 32.0))
	hi["r"] = fd.y + 0.71 * float(hi["cs"]) + 1.0
	hi["qs"] = false
	hi["collide"] = bool(base.get("collide", false))
	var lo: Dictionary = base.duplicate(true)
	lo["mode"] = 2
	lo["suffix"] = "_L"
	lo["cs"] = float(hi["cs"])
	lo["rin"] = maxf(fd.x - 0.71 * float(lo["cs"]), 0.0)
	lo["r"] = float(base["r"])
	lo["qs"] = true
	lo["collide"] = false
	CATS.append(hi)
	CATS.append(lo)

func _make_cats() -> void:
	CATS.clear()
	# 0,1 broadleaf trees
	_pair({"gid": 0, "names": ["CommonTree_5", "CommonTree_3", "CommonTree_1"], "d": 0.0105, "r": TREE_R, "smin": 0.9, "smax": 1.5, "hmin": 1.8, "hmax": 42.0, "slope": 30.0, "forest": true, "collide": true, "rmin": 9.0, "bw": [0.35, 1.2, 0.0, 0.08], "grove": 3.0, "aut": true, "kind": "tree"}, "CommonTree")
	# 2,3 pines
	_pair({"gid": 1, "names": ["Pine_5", "Pine_4"], "d": 0.011, "r": TREE_R, "smin": 0.9, "smax": 1.6, "hmin": 1.8, "hmax": 58.0, "slope": 34.0, "forest": true, "collide": true, "rmin": 9.0, "bw": [0.05, 0.7, 0.0, 0.9], "kind": "tree"}, "Pine")
	# 4,5 rare big twisted trees
	_pair({"gid": 2, "names": ["TwistedTree_1", "TwistedTree_3"], "d": 0.0011, "r": TREE_R, "smin": 0.65, "smax": 1.0, "hmin": 1.8, "hmax": 40.0, "slope": 26.0, "collide": true, "rmin": 14.0, "bw": [0.6, 0.9, 0.0, 0.0], "aut": true, "kind": "tree"}, "TwistedTree")
	# 6,7 dead trees (desert and rocky slopes)
	_pair({"gid": 3, "names": ["DeadTree_5", "DeadTree_2"], "d": 0.0016, "r": TREE_R, "smin": 0.7, "smax": 1.1, "hmin": 1.8, "hmax": 55.0, "slope": 30.0, "collide": true, "rmin": 12.0, "bw": [0.0, 0.0, 1.0, 0.25], "kind": "tree"}, "DeadTree")
	# 8,9 bushes
	_pair({"gid": 4, "names": ["Bush_Common", "Bush_Common_Flowers"], "d": 0.008, "r": 110.0, "smin": 0.6, "smax": 1.0, "hmin": 1.6, "hmax": 45.0, "slope": 35.0, "forest": true, "rmin": 6.0, "bw": [0.8, 1.0, 0.2, 0.15], "kind": "bush", "cs": 24.0}, "Bush")
	# 10 grass, near tufts (full model, small and dense)
	CATS.append({"gid": 5, "names": ["Grass_Common_Short", "Grass_Common_Short", "Grass_Wispy_Short", "Grass_Common_Short"], "d": 1.4, "r": 26.0, "cs": 8.0, "qs": false, "mode": 1, "smin": 0.28, "smax": 0.44, "hmin": 1.3, "hmax": 48.0, "slope": 42.0, "bw": [1.0, 0.8, 0.0, 0.15], "kind": "grass", "pthr": 0.35, "warm": 0.06})
	# 11 grass, far tufts (fewer, a bit bigger, lighter model), reaches far out
	CATS.append({"gid": 6, "names": ["Grass_Common_Short", "Grass_Wispy_Short", "Grass_Common_Tall", "Grass_Common_Short"], "suffix": "_L", "d": 0.30, "r": 85.0, "rin": 0.0, "cs": 24.0, "qs": true, "mode": 2, "smin": 0.30, "smax": 0.46, "hmin": 1.3, "hmax": 48.0, "slope": 42.0, "bw": [1.0, 0.8, 0.0, 0.15], "kind": "grass", "pthr": 0.35, "warm": 0.06})
	# 12 ferns and leafy plants
	CATS.append({"gid": 7, "names": ["Fern_1", "Plant_1_Big", "Plant_7_Big", "Clover_1"], "d": 0.05, "r": 50.0, "cs": 24.0, "qs": true, "smin": 0.20, "smax": 0.42, "hmin": 1.6, "hmax": 45.0, "slope": 40.0, "forest": true, "bw": [0.4, 1.2, 0.0, 0.2], "kind": "small"})
	# 13 flowers
	CATS.append({"gid": 8, "names": ["Flower_3_Group", "Flower_3_Single", "Flower_4_Group", "Flower_4_Single"], "d": 0.10, "r": 50.0, "cs": 24.0, "qs": true, "smin": 0.20, "smax": 0.36, "hmin": 1.6, "hmax": 30.0, "slope": 30.0, "bw": [1.3, 0.2, 0.0, 0.05], "grove": 2.5, "kind": "small"})
	# 14 mushrooms
	CATS.append({"gid": 9, "names": ["Mushroom_Common"], "d": 0.006, "r": 40.0, "cs": 32.0, "qs": true, "smin": 0.5, "smax": 1.0, "hmin": 1.6, "hmax": 40.0, "slope": 30.0, "forest": true, "bw": [0.1, 1.0, 0.0, 0.0], "kind": "rock"})
	# 15 rocks
	CATS.append({"gid": 10, "names": ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], "d": 0.0035, "r": 160.0, "cs": 48.0, "qs": true, "smin": 0.5, "smax": 1.3, "hmin": 0.8, "hmax": 200.0, "slope": 70.0, "collide": true, "rmin": 10.0, "bw": [0.4, 0.5, 1.4, 2.2], "kind": "rock"})
	# 16 loose pebbles
	CATS.append({"gid": 11, "names": ["Pebble_Round_1", "Pebble_Round_3", "Pebble_Square_1", "Pebble_Square_3"], "d": 0.04, "r": 36.0, "cs": 24.0, "qs": true, "smin": 0.4, "smax": 0.9, "hmin": 0.4, "hmax": 80.0, "slope": 45.0, "bw": [0.5, 0.5, 1.5, 1.2], "kind": "rock"})
	# 17 stones lining the dirt roads
	CATS.append({"gid": 12, "names": ["Pebble_Round_5", "Pebble_Square_5", "Pebble_Round_3", "Pebble_Square_1", "Pebble_Square_3"], "d": 0.22, "r": 46.0, "cs": 24.0, "qs": true, "smin": 0.35, "smax": 0.8, "hmin": 1.0, "hmax": 60.0, "slope": 40.0, "bw": [0.8, 0.8, 1.2, 0.5], "kind": "rock", "path": 1})
	# 18 dry plants in the desert
	CATS.append({"gid": 13, "names": ["Plant_1_Big", "Plant_7_Big", "Fern_1"], "d": 0.012, "r": 55.0, "cs": 32.0, "qs": true, "smin": 0.18, "smax": 0.4, "hmin": 1.5, "hmax": 30.0, "slope": 30.0, "bw": [0.0, 0.0, 1.0, 0.0], "dry": true, "kind": "small"})
	# build order: what is right around you first
	ORDER = [10, 11, 13, 12, 17, 16, 8, 14, 0, 2, 15, 4, 6, 18, 9, 1, 3, 5, 7]
	for i in range(CATS.size()):
		if not ORDER.has(i):
			ORDER.append(i)

# ------------------------------------------------------------ setup / streaming
# returns false when no tree model could be loaded (caller uses its fallback)
func setup(w) -> bool:
	world = w
	_has_road = world.has_method("road_at")
	_has_aut = world.has_method("autumn_at")
	var ok: bool = false
	for t in ["CommonTree_5", "CommonTree_3", "Pine_5"]:
		if not _mesh(str(t)).is_empty():
			ok = true
	return ok

func refresh() -> void:
	_incomplete = true
	_cc = Vector2i(99999, 99999)

func tree_fade() -> Vector2:
	var fe: float = maxf(TREE_R * Q - 4.0, 6.0)
	return Vector2(fe * 0.78, fe)

func _radius(cat: Dictionary) -> float:
	if bool(cat.get("qs", true)):
		return float(cat["r"]) * Q
	return float(cat["r"])

func _key(ci: int, cx: int, cz: int) -> int:
	return ((ci * 4096 + (cx + 2048)) * 4096) + (cz + 2048)

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	var pp: Vector3 = player.global_position
	for gm in _grass_mats:
		(gm as ShaderMaterial).set_shader_parameter("player_pos", pp)
	_t += delta
	if _t < 0.06:
		return
	_t = 0.0
	_update(pp, us_budget)

# how many chunks around `center` are still missing
func pending(center: Vector3) -> int:
	var c2: Vector2 = Vector2(center.x, center.z)
	var n: int = 0
	for ci in ORDER:
		var cat: Dictionary = CATS[ci]
		var cs: float = float(cat["cs"])
		var R: float = _radius(cat)
		var rin: float = float(cat.get("rin", 0.0))
		var cx0: int = int(floor(center.x / cs))
		var cz0: int = int(floor(center.z / cs))
		var k: int = int(ceil(R / cs))
		for dz in range(-k, k + 1):
			for dx in range(-k, k + 1):
				var cx: int = cx0 + dx
				var cz: int = cz0 + dz
				var cc: Vector2 = Vector2((float(cx) + 0.5) * cs, (float(cz) + 0.5) * cs)
				var dd: float = cc.distance_to(c2)
				if dd > R or dd < rin:
					continue
				if not _live.has(_key(ci, cx, cz)):
					n += 1
	return n

func build_some(center: Vector3, us: int) -> void:
	_incomplete = true
	_update(center, us)

func _update(center: Vector3, us: int) -> void:
	var cur: Vector2i = Vector2i(int(floor(center.x / 8.0)), int(floor(center.z / 8.0)))
	if cur == _cc and not _incomplete and is_equal_approx(Q, _lastq):
		return
	_cc = cur
	_lastq = Q
	var t0: int = Time.get_ticks_usec()
	var c2: Vector2 = Vector2(center.x, center.z)
	var stop: bool = false
	for ci in ORDER:
		if stop:
			break
		var cat: Dictionary = CATS[ci]
		var cs: float = float(cat["cs"])
		var R: float = _radius(cat)
		var rin: float = float(cat.get("rin", 0.0))
		var cx0: int = int(floor(center.x / cs))
		var cz0: int = int(floor(center.z / cs))
		var n: int = int(ceil(R / cs))
		for dz in range(-n, n + 1):
			if stop:
				break
			for dx in range(-n, n + 1):
				var cx: int = cx0 + dx
				var cz: int = cz0 + dz
				var cc: Vector2 = Vector2((float(cx) + 0.5) * cs, (float(cz) + 0.5) * cs)
				var dd: float = cc.distance_to(c2)
				if dd > R or dd < rin:
					continue
				var key: int = _key(ci, cx, cz)
				if _live.has(key):
					continue
				_build(ci, cx, cz, key, cc)
				if Time.get_ticks_usec() - t0 > us:
					stop = true
					break
	_incomplete = stop
	# free chunks that are far away
	for key in _live.keys():
		var e: Dictionary = _live[key]
		var cat2: Dictionary = CATS[int(e["ci"])]
		var R2: float = _radius(cat2) + float(cat2["cs"]) * 1.5
		var dd2: float = (e["c"] as Vector2).distance_to(c2)
		if dd2 > R2:
			_inst_total -= int(e["inst"])
			_tri_total -= int(e["tri"])
			(e["n"] as Node).queue_free()
			_live.erase(key)

func _build(ci: int, cx: int, cz: int, key: int, cc: Vector2) -> void:
	var cat: Dictionary = CATS[ci]
	var holder := Node3D.new()
	add_child(holder)
	var rec: Dictionary = {"n": holder, "ci": ci, "c": cc, "inst": 0, "tri": 0}
	_live[key] = rec
	var items: Array = _gen(ci, cx, cz)
	if items.is_empty():
		return
	var collide: bool = bool(cat.get("collide", false))
	var groups: Dictionary = {}
	for it in items:
		var d: Dictionary = it
		var nm: String = str(d["n"])
		var md: Array = _mesh(nm)
		if md.is_empty():
			continue
		var xf: Transform3D = Transform3D(d["b"] as Basis, d["p"] as Vector3) * (md[1] as Transform3D)
		if not groups.has(nm):
			groups[nm] = []
		(groups[nm] as Array).append([xf, d["t"]])
		if collide:
			_add_collider(holder, d["p"] as Vector3, float(d["s"]), nm)
	var mode: int = int(cat.get("mode", 0))
	var fe: float = 1.0
	if mode != 1:
		fe = maxf(_radius(cat) - 4.0, 6.0)
	var inst_n: int = 0
	var tri_n: int = 0
	for nm in groups.keys():
		var arr: Array = groups[nm]
		var md2: Array = _mesh(str(nm))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = md2[0] as Mesh
		mm.instance_count = arr.size()
		for i in range(arr.size()):
			var e: Array = arr[i]
			mm.set_instance_transform(i, e[0] as Transform3D)
			var tc: Color = e[1] as Color
			if tc.a > 0.01:
				tc.a = -fe
			else:
				tc.a = fe
			mm.set_instance_custom_data(i, tc)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)
		inst_n += arr.size()
		tri_n += arr.size() * int(md2[2])
	rec["inst"] = inst_n
	rec["tri"] = tri_n
	_inst_total += inst_n
	_tri_total += tri_n

# deterministic content of one chunk: [{"n","p","s","b","t"}]
# NOTE: hi and lo versions of a pair run exactly this function with the same seed, so they place identical instances.
func _gen(ci: int, cx: int, cz: int) -> Array:
	var cat: Dictionary = CATS[ci]
	var cs: float = float(cat["cs"])
	var names: Array = cat["names"]
	var suffix: String = str(cat.get("suffix", ""))
	var bw: Array = cat["bw"]
	var bw0: float = float(bw[0])
	var bw1: float = float(bw[1])
	var bw2: float = float(bw[2])
	var bw3: float = float(bw[3])
	var maxbw: float = maxf(maxf(bw0, bw1), maxf(bw2, bw3))
	var gmul: float = float(cat.get("grove", 0.0))
	var cap: float = maxbw * (1.0 + gmul)
	var gid: int = int(cat["gid"])
	var out: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = (cx * 73856093) ^ (cz * 19349663) ^ (gid * 83492791) ^ 12345
	var expected: float = float(cat["d"]) * cs * cs * DENSITY * cap
	var cnt: int = int(expected)
	if r.randf() < expected - float(cnt):
		cnt += 1
	var min_cos: float = cos(deg_to_rad(float(cat["slope"])))
	var use_forest: bool = bool(cat.get("forest", false))
	var dry: bool = bool(cat.get("dry", false))
	var rmin: float = float(cat.get("rmin", 0.0))
	var pmode: int = int(cat.get("path", -1))
	var pthr: float = float(cat.get("pthr", 0.10))
	var warm: float = float(cat.get("warm", 0.0))
	var aut_ok: bool = bool(cat.get("aut", false)) and _has_aut
	var kind: String = str(cat.get("kind", ""))
	var nn: int = names.size()
	for i in range(cnt):
		var x: float = float(cx) * cs + r.randf() * cs
		var z: float = float(cz) * cs + r.randf() * cs
		var acc: float = r.randf() * cap
		var pick: float = r.randf()
		var sc: float = r.randf()
		var rot: float = r.randf()
		var vv: float = r.randf_range(0.88, 1.08)
		var extra: float = r.randf()
		if Vector2(x, z).length() < rmin:
			continue
		var w: Vector4 = world.biome_vec(x, z)
		var mult: float = w.x * bw0 + w.y * bw1 + w.z * bw2 + w.w * bw3
		var gv: float = 0.0
		if gmul > 0.0:
			gv = world.grove(x, z)
			mult *= (1.0 + gmul * gv)
		if acc > mult:
			continue
		var h: float = world.height(x, z)
		if h < float(cat["hmin"]) or h > float(cat["hmax"]):
			continue
		if _has_road:
			var pa: float = world.road_at(x, z, h)
			if pmode < 0:
				if pa > pthr:
					continue
			else:
				if pa < 0.30:
					continue
		elif pmode > 0:
			continue
		var hx: float = world.height(x + 1.2, z)
		var hz: float = world.height(x, z + 1.2)
		var nrm: Vector3 = Vector3(h - hx, 1.2, h - hz).normalized()
		if nrm.y < min_cos:
			continue
		if use_forest:
			var f: float = world.forest(x, z)
			if extra > smoothstep(0.30, 0.60, f) + 0.12:
				continue
		var base_nm: String = str(names[int(pick * float(nn)) % nn])
		var s: float = lerpf(float(cat["smin"]), float(cat["smax"]), sc)
		var b: Basis = Basis(Vector3.UP, rot * TAU).scaled(Vector3(s, s, s))
		var tint: Color = Color(vv, vv, vv, 0.0)
		if dry:
			tint = Color(0.95, 0.78, 0.40, 0.75)
		elif kind == "tree":
			var aut: float = 0.0
			if aut_ok and w.w < 0.4 and w.z < 0.4:
				aut = world.autumn_at(x, z)
			if gv > 0.5:
				tint = Color(1.0, 0.70, 0.84, 0.92)
			elif aut > 0.5 and extra < 0.9:
				if sc < 0.62:
					tint = Color(1.0, 0.52, 0.14, 0.9)
				else:
					tint = Color(1.0, 0.80, 0.22, 0.9)
			elif w.w > 0.5:
				tint = Color(vv * 0.84, vv * 0.97, vv * 0.98, 0.0)
			elif w.y > 0.5:
				tint = Color(vv * 0.86, vv * 0.97, vv * 0.84, 0.0)
		elif kind == "grass":
			tint = Color(vv * 0.80, vv, vv * 0.68, 0.0)
			if w.y > 0.5:
				tint = Color(vv * 0.65, vv * 0.92, vv * 0.65, 0.0)
			elif extra < warm:
				tint = Color(1.0, 0.92, 0.55, 0.0)
		out.append({"n": base_nm + suffix, "p": Vector3(x, h - 0.05, z), "s": s, "b": b, "t": tint})
	return out

# ------------------------------------------------------------ models
# returns [Mesh, Transform3D, triangle_count] or [] if the model is not available
func _mesh(nm: String) -> Array:
	if _meshes.has(nm):
		return _meshes[nm]
	var res: Array = []
	var path: String = DIR + nm + ".gltf"
	if ResourceLoader.exists(path):
		var ps: PackedScene = load(path) as PackedScene
		if ps != null:
			var inst: Node = ps.instantiate()
			var mi: MeshInstance3D = null
			if inst is MeshInstance3D:
				mi = inst as MeshInstance3D
			else:
				for n in inst.find_children("*", "MeshInstance3D", true, false):
					mi = n as MeshInstance3D
					break
			if mi != null and mi.mesh != null:
				var m: Mesh = mi.mesh
				_toonify(m, nm)
				var tris: int = 0
				for i in range(m.get_surface_count()):
					tris += m.surface_get_array_index_len(i) / 3
				res = [m, mi.transform, tris]
			inst.free()
	_meshes[nm] = res
	return res

func _add_collider(parent: Node3D, pos: Vector3, s: float, nm: String) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	if nm.begins_with("Rock"):
		var sp := SphereShape3D.new()
		sp.radius = 1.1 * s
		cs.shape = sp
		cs.position = Vector3(0, 0.6 * s, 0)
	else:
		var cy := CylinderShape3D.new()
		cy.radius = 0.35 * s
		cy.height = 4.0
		cs.shape = cy
		cs.position = Vector3(0, 2.0, 0)
	body.add_child(cs)
	parent.add_child(body)
	body.global_position = pos

func _fade_key(nm: String) -> String:
	for k in FADES.keys():
		if nm.begins_with(str(k)):
			return str(k)
	return ""

# ---- anime look: cel-lit foliage with wind sway (falls back to the original material if anything is missing)
func _toonify(m: Mesh, nm: String) -> void:
	if _foliage_shader == null and ResourceLoader.exists(FOLIAGE_SH):
		_foliage_shader = load(FOLIAGE_SH) as Shader
	if _grass_shader == null and ResourceLoader.exists(GRASS_SH):
		_grass_shader = load(GRASS_SH) as Shader
	if _foliage_shader == null:
		return
	var is_lo: bool = nm.ends_with("_L")
	var base: String = nm.trim_suffix("_L")
	var fk: String = _fade_key(base)
	var mode: int = 0
	var fa: float = 0.0
	var fb: float = 0.0
	if fk != "" and ResourceLoader.exists(DIR + base + "_L.gltf"):
		mode = 2 if is_lo else 1
		var fd: Vector2 = FADES[fk]
		fa = fd.x
		fb = fd.y
	var bb: AABB = m.get_aabb()
	var is_grass: bool = base.begins_with("Grass") and _grass_shader != null
	var is_tree: bool = base.begins_with("CommonTree") or base.begins_with("Pine") or base.begins_with("TwistedTree") or base.begins_with("DeadTree")
	var is_bush: bool = base.begins_with("Bush")
	var is_small: bool = base.begins_with("Fern") or base.begins_with("Plant") or base.begins_with("Clover") or base.begins_with("Flower")
	for i in range(m.get_surface_count()):
		var src: Material = m.surface_get_material(i)
		var bm: BaseMaterial3D = src as BaseMaterial3D
		if bm == null or bm.albedo_texture == null:
			continue
		var sm := ShaderMaterial.new()
		if is_grass:
			sm.shader = _grass_shader
			sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
			sm.set_shader_parameter("blade_h", maxf(bb.size.y, 0.3))
			sm.set_shader_parameter("lod_mode", mode)
			sm.set_shader_parameter("lod_a", fa)
			sm.set_shader_parameter("lod_b", fb)
			_grass_mats.append(sm)
			m.surface_set_material(i, sm)
			continue
		sm.shader = _foliage_shader
		sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
		sm.set_shader_parameter("tint", bm.albedo_color)
		var cut: bool = bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		sm.set_shader_parameter("use_alpha", cut)
		var thr: float = bm.alpha_scissor_threshold
		if thr <= 0.0:
			thr = 0.5
		sm.set_shader_parameter("alpha_cut", thr)
		sm.set_shader_parameter("lod_mode", mode)
		sm.set_shader_parameter("lod_a", fa)
		sm.set_shader_parameter("lod_b", fb)
		var sw: float = 0.0
		var ao_h: float = 0.0
		var ao_min: float = 0.7
		if is_tree:
			ao_h = maxf(bb.size.y * 0.8, 1.0)
			ao_min = 0.62
			if cut:
				sw = 0.26
		elif is_bush:
			ao_h = maxf(bb.size.y, 0.5)
			ao_min = 0.60
			sw = 1.2
		elif is_small:
			ao_h = maxf(bb.size.y, 0.3)
			ao_min = 0.72
			sw = 3.0
		else:
			ao_h = maxf(bb.size.y * 0.5, 0.2)
			ao_min = 0.82
		sm.set_shader_parameter("sway", sw)
		sm.set_shader_parameter("ao_h", ao_h)
		sm.set_shader_parameter("ao_min", ao_min)
		m.surface_set_material(i, sm)

func debug_text() -> String:
	return "nature chunks %d | inst %d | tris ~%dk" % [_live.size(), _inst_total, _tri_total / 1000]
