extends Node3D
# Streams the Quaternius "Stylized Nature MegaKit" models around the player:
# the world is split into 16 m chunks that are generated deterministically and
# only exist near the camera (MultiMesh per model per chunk). Far chunks are freed.

const DIR := "res://assets/nature/"
const CHUNK := 16.0
var Q: float = 1.0
var DENSITY: float = 1.0

# d = instances per m2, r = build radius (m), bw = density per biome [plains, forest, desert, mountain]
const CATS := [
	{"names": ["CommonTree_5", "CommonTree_3", "CommonTree_4", "CommonTree_1"], "d": 0.010, "r": 80.0, "smin": 0.9, "smax": 1.5, "hmin": 1.8, "hmax": 42.0, "slope": 30.0, "forest": true, "collide": true, "rmin": 9.0, "bw": [0.35, 1.2, 0.0, 0.08], "grove": 3.0},
	{"names": ["Pine_5", "Pine_4"], "d": 0.010, "r": 80.0, "smin": 0.9, "smax": 1.6, "hmin": 1.8, "hmax": 58.0, "slope": 34.0, "forest": true, "collide": true, "rmin": 9.0, "bw": [0.05, 0.7, 0.0, 0.9]},
	{"names": ["Bush_Common", "Bush_Common_Flowers"], "d": 0.008, "r": 60.0, "smin": 0.8, "smax": 1.5, "hmin": 1.6, "hmax": 45.0, "slope": 35.0, "forest": true, "rmin": 6.0, "bw": [0.8, 1.0, 0.2, 0.15]},
	{"names": ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], "d": 0.0035, "r": 80.0, "smin": 0.7, "smax": 1.8, "hmin": 0.8, "hmax": 200.0, "slope": 70.0, "collide": true, "rmin": 10.0, "bw": [0.4, 0.5, 1.4, 2.2]},
	{"names": ["Grass_Common_Short", "Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short"], "d": 0.28, "r": 28.0, "smin": 1.3, "smax": 2.1, "hmin": 1.3, "hmax": 48.0, "slope": 42.0, "bw": [1.0, 0.8, 0.0, 0.15]},
	{"names": ["Fern_1", "Plant_1_Big", "Plant_7_Big", "Clover_1"], "d": 0.03, "r": 42.0, "smin": 0.5, "smax": 1.0, "hmin": 1.6, "hmax": 45.0, "slope": 40.0, "forest": true, "bw": [0.4, 1.2, 0.0, 0.2]},
	{"names": ["Flower_3_Group", "Flower_3_Single", "Flower_4_Group"], "d": 0.04, "r": 40.0, "smin": 0.9, "smax": 1.4, "hmin": 1.6, "hmax": 30.0, "slope": 30.0, "bw": [1.3, 0.2, 0.0, 0.05], "grove": 2.5},
	{"names": ["Mushroom_Common"], "d": 0.006, "r": 40.0, "smin": 1.0, "smax": 1.8, "hmin": 1.6, "hmax": 40.0, "slope": 30.0, "forest": true, "bw": [0.1, 1.0, 0.0, 0.0]},
	{"names": ["Pebble_Round_1", "Pebble_Round_3", "Pebble_Square_1", "Pebble_Square_3"], "d": 0.04, "r": 35.0, "smin": 0.8, "smax": 1.8, "hmin": 0.4, "hmax": 80.0, "slope": 45.0, "bw": [0.5, 0.5, 1.5, 1.2]},
	{"names": ["Plant_1_Big", "Plant_7_Big", "Fern_1"], "d": 0.012, "r": 55.0, "smin": 0.5, "smax": 1.1, "hmin": 1.5, "hmax": 30.0, "slope": 30.0, "bw": [0.0, 0.0, 1.0, 0.0], "dry": true},
]
# build order: what you see right around you first
const ORDER := [4, 6, 5, 8, 2, 7, 9, 0, 1, 3]

var world = null
var player = null
var _meshes: Dictionary = {}
var _live: Dictionary = {}
var _tree_cache: Dictionary = {}
var _t: float = 0.0

# returns false when no tree model could be loaded (caller uses its fallback)
func setup(w) -> bool:
	world = w
	var ok: bool = false
	for t in CATS[0]["names"]:
		if not _mesh(str(t)).is_empty():
			ok = true
	if not ok:
		return false
	_update(Vector3.ZERO, 100000)
	return true

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.2:
		return
	_t = 0.0
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	_update(player.global_position, 3)

func _update(center: Vector3, budget: int) -> void:
	var cx0: int = int(floor(center.x / CHUNK))
	var cz0: int = int(floor(center.z / CHUNK))
	var c2: Vector2 = Vector2(center.x, center.z)
	var built: int = 0
	for ci in ORDER:
		var R: float = float(CATS[ci]["r"]) * Q
		var n: int = int(ceil(R / CHUNK))
		for dz in range(-n, n + 1):
			for dx in range(-n, n + 1):
				if built >= budget:
					break
				var cx: int = cx0 + dx
				var cz: int = cz0 + dz
				var cc: Vector2 = Vector2((float(cx) + 0.5) * CHUNK, (float(cz) + 0.5) * CHUNK)
				if cc.distance_to(c2) > R:
					continue
				var key: String = "%d|%d|%d" % [ci, cx, cz]
				if _live.has(key):
					continue
				_build(ci, cx, cz, key, cc)
				built += 1
	# free chunks that are far away
	for key in _live.keys():
		var e: Dictionary = _live[key]
		var R2: float = float(CATS[int(e["ci"])]["r"]) * Q + CHUNK * 1.5
		if (e["c"] as Vector2).distance_to(c2) > R2:
			(e["n"] as Node).queue_free()
			_live.erase(key)

func _build(ci: int, cx: int, cz: int, key: String, cc: Vector2) -> void:
	var cat: Dictionary = CATS[ci]
	var holder := Node3D.new()
	add_child(holder)
	_live[key] = {"n": holder, "ci": ci, "c": cc}
	var items: Array = _gen(ci, cx, cz)
	if items.is_empty():
		return
	var groups: Dictionary = {}
	for it in items:
		var d: Dictionary = it
		var nm: String = str(d["n"])
		var md: Array = _mesh(nm)
		var xf: Transform3D = Transform3D(d["b"] as Basis, d["p"] as Vector3) * (md[1] as Transform3D)
		if not groups.has(nm):
			groups[nm] = []
		(groups[nm] as Array).append([xf, d["t"]])
		if bool(cat.get("collide", false)):
			_add_collider(holder, d["p"] as Vector3, float(d["s"]), nm)
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
			mm.set_instance_custom_data(i, e[1] as Color)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if not bool(cat.get("shadow", false)):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)

# deterministic content of one chunk: [{"n","p","s","b","t"}]
func _gen(ci: int, cx: int, cz: int) -> Array:
	var cat: Dictionary = CATS[ci]
	var names: Array = cat["names"]
	var bw: Array = cat["bw"]
	var bw0: float = float(bw[0])
	var bw1: float = float(bw[1])
	var bw2: float = float(bw[2])
	var bw3: float = float(bw[3])
	var maxbw: float = maxf(maxf(bw0, bw1), maxf(bw2, bw3))
	var gmul: float = float(cat.get("grove", 0.0))
	var cap: float = maxbw * (1.0 + gmul)
	var out: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = (cx * 73856093) ^ (cz * 19349663) ^ (ci * 83492791) ^ 12345
	var expected: float = float(cat["d"]) * CHUNK * CHUNK * DENSITY * cap
	var cnt: int = int(expected)
	if r.randf() < expected - float(cnt):
		cnt += 1
	var min_cos: float = cos(deg_to_rad(float(cat["slope"])))
	var use_forest: bool = bool(cat.get("forest", false))
	var dry: bool = bool(cat.get("dry", false))
	var rmin: float = float(cat.get("rmin", 0.0))
	for i in range(cnt):
		var x: float = float(cx) * CHUNK + r.randf() * CHUNK
		var z: float = float(cz) * CHUNK + r.randf() * CHUNK
		var acc: float = r.randf() * cap
		var pick: float = r.randf()
		var sc: float = r.randf()
		var rot: float = r.randf()
		var vv: float = r.randf_range(0.88, 1.08)
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
		var nrm: Vector3 = Vector3(world.height(x - 1.0, z) - world.height(x + 1.0, z), 2.0, world.height(x, z - 1.0) - world.height(x, z + 1.0)).normalized()
		if nrm.y < min_cos:
			continue
		if use_forest:
			var f: float = world.forest(x, z)
			if r.randf() > smoothstep(0.30, 0.60, f) + 0.12:
				continue
		var nm: String = str(names[int(pick * float(names.size())) % names.size()])
		if _mesh(nm).is_empty():
			continue
		var s: float = lerpf(float(cat["smin"]), float(cat["smax"]), sc)
		var b: Basis = Basis(Vector3.UP, rot * TAU).scaled(Vector3(s, s, s))
		var tint: Color = Color(vv, vv, vv, 0.0)
		if dry:
			tint = Color(0.95, 0.78, 0.40, 0.75)
		elif ci == 0 and gv > 0.5:
			tint = Color(1.0, 0.70, 0.84, 0.92)
		elif ci <= 1 or ci == 2:
			if w.w > 0.5:
				tint = Color(vv * 0.84, vv * 0.97, vv * 0.98, 0.0)
			elif w.y > 0.5:
				tint = Color(vv * 0.82, vv * 0.94, vv * 0.82, 0.0)
		out.append({"n": nm, "p": Vector3(x, h - 0.05, z), "s": s, "b": b, "t": tint})
	return out

func near_tree(p: Vector3, dist: float = 1.8) -> bool:
	var cx0: int = int(floor(p.x / CHUNK))
	var cz0: int = int(floor(p.z / CHUNK))
	for ci in [0, 1]:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var k: String = "%d|%d|%d" % [int(ci), cx0 + dx, cz0 + dz]
				if not _tree_cache.has(k):
					_tree_cache[k] = _gen(int(ci), cx0 + dx, cz0 + dz)
				for it in (_tree_cache[k] as Array):
					var q: Vector3 = (it as Dictionary)["p"]
					if Vector2(q.x - p.x, q.z - p.z).length() < dist:
						return true
	if _tree_cache.size() > 600:
		_tree_cache.clear()
	return false

# returns [Mesh, Transform3D] or [] if the model is not available
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
				var xf: Transform3D = mi.transform
				res = [m, xf]
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

# ---- anime look: cel-lit foliage with wind sway (falls back to the original material if anything is missing)
const FOLIAGE_SH := "res://shaders/anime/foliage.gdshader"
var _foliage_shader: Shader = null

func _toonify(m: Mesh, nm: String) -> void:
	if _foliage_shader == null:
		if not ResourceLoader.exists(FOLIAGE_SH):
			return
		_foliage_shader = load(FOLIAGE_SH) as Shader
	if _foliage_shader == null:
		return
	var small: bool = nm.begins_with("Grass") or nm.begins_with("Fern") or nm.begins_with("Plant") or nm.begins_with("Clover") or nm.begins_with("Flower") or nm.begins_with("Mushroom")
	for i in range(m.get_surface_count()):
		var src: Material = m.surface_get_material(i)
		var bm: BaseMaterial3D = src as BaseMaterial3D
		if bm == null or bm.albedo_texture == null:
			continue
		var sm := ShaderMaterial.new()
		sm.shader = _foliage_shader
		sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
		sm.set_shader_parameter("tint", bm.albedo_color)
		var cut: bool = bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		sm.set_shader_parameter("use_alpha", cut)
		var thr: float = bm.alpha_scissor_threshold
		if thr <= 0.0:
			thr = 0.5
		sm.set_shader_parameter("alpha_cut", thr)
		var sw: float = 0.0
		if cut and small:
			sw = 3.0
		elif cut:
			sw = 0.16
		sm.set_shader_parameter("sway", sw)
		m.surface_set_material(i, sm)
