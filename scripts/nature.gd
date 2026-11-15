extends Node3D
# Streams the Quaternius "Stylized Nature MegaKit" models around the player:
# the world is split into 16 m chunks that are generated deterministically and
# only exist near the camera (MultiMesh per model per chunk). Far chunks are freed.

const DIR := "res://assets/nature/"
const CHUNK := 16.0
const Q := 1.0          # global radius multiplier: lower (e.g. 0.7) = faster, less to see
const DENSITY := 1.0    # global density multiplier

# d = instances per m2, r = build radius (m)
const CATS := [
	{"names": ["CommonTree_5", "CommonTree_3", "CommonTree_4", "Pine_5", "Pine_4"], "d": 0.010, "r": 80.0, "smin": 0.9, "smax": 1.5, "hmin": 1.8, "hmax": 9.5, "slope": 30.0, "forest": true, "collide": true, "rmin": 9.0},
	{"names": ["Bush_Common", "Bush_Common_Flowers"], "d": 0.008, "r": 60.0, "smin": 0.8, "smax": 1.5, "hmin": 1.6, "hmax": 9.5, "slope": 35.0, "forest": true, "rmin": 6.0},
	{"names": ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], "d": 0.0035, "r": 80.0, "smin": 0.7, "smax": 1.8, "hmin": 0.6, "hmax": 13.0, "slope": 60.0, "collide": true, "rmin": 10.0},
	{"names": ["Grass_Common_Short", "Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short"], "d": 0.28, "r": 28.0, "smin": 1.3, "smax": 2.1, "hmin": 1.3, "hmax": 9.2, "slope": 42.0},
	{"names": ["Fern_1", "Plant_1_Big", "Plant_7_Big", "Clover_1"], "d": 0.03, "r": 42.0, "smin": 0.5, "smax": 1.0, "hmin": 1.6, "hmax": 9.0, "slope": 40.0, "forest": true},
	{"names": ["Flower_3_Group", "Flower_3_Single", "Flower_4_Group"], "d": 0.04, "r": 40.0, "smin": 0.9, "smax": 1.4, "hmin": 1.6, "hmax": 8.5, "slope": 30.0},
	{"names": ["Mushroom_Common"], "d": 0.006, "r": 40.0, "smin": 1.0, "smax": 1.8, "hmin": 1.6, "hmax": 9.0, "slope": 30.0, "forest": true},
	{"names": ["Pebble_Round_1", "Pebble_Round_3", "Pebble_Square_1", "Pebble_Square_3"], "d": 0.04, "r": 35.0, "smin": 0.8, "smax": 1.8, "hmin": 0.5, "hmax": 9.0, "slope": 40.0},
]
# build order: what you see right around you first
const ORDER := [3, 5, 4, 7, 1, 6, 0, 2]

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
		(groups[nm] as Array).append(xf)
		if bool(cat.get("collide", false)):
			_add_collider(holder, d["p"] as Vector3, float(d["s"]), nm)
	for nm in groups.keys():
		var arr: Array = groups[nm]
		var md2: Array = _mesh(str(nm))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = md2[0] as Mesh
		mm.instance_count = arr.size()
		for i in range(arr.size()):
			mm.set_instance_transform(i, arr[i] as Transform3D)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if not bool(cat.get("shadow", false)):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)

# deterministic content of one chunk: [{"n","p","s","b"}]
func _gen(ci: int, cx: int, cz: int) -> Array:
	var cat: Dictionary = CATS[ci]
	var names: Array = cat["names"]
	var out: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = (cx * 73856093) ^ (cz * 19349663) ^ (ci * 83492791) ^ 12345
	var expected: float = float(cat["d"]) * CHUNK * CHUNK * DENSITY
	var cnt: int = int(expected)
	if r.randf() < expected - float(cnt):
		cnt += 1
	var min_cos: float = cos(deg_to_rad(float(cat["slope"])))
	var use_forest: bool = bool(cat.get("forest", false))
	for i in range(cnt):
		var x: float = float(cx) * CHUNK + r.randf() * CHUNK
		var z: float = float(cz) * CHUNK + r.randf() * CHUNK
		var rad: float = Vector2(x, z).length()
		if rad > 90.0 or rad < float(cat.get("rmin", 0.0)):
			continue
		var h: float = world.height(x, z)
		if h < float(cat["hmin"]) or h > float(cat["hmax"]):
			continue
		if ci != 7 and world.road_weight(x, z, h) > 0.2:
			continue
		var nrm: Vector3 = Vector3(world.height(x - 1.0, z) - world.height(x + 1.0, z), 2.0, world.height(x, z - 1.0) - world.height(x, z + 1.0)).normalized()
		if nrm.y < min_cos:
			continue
		if use_forest:
			var f: float = world.forest(x, z)
			if r.randf() > smoothstep(0.35, 0.65, f) + 0.1:
				continue
		var nm: String = str(names[r.randi() % names.size()])
		if _mesh(nm).is_empty():
			continue
		var s: float = r.randf_range(float(cat["smin"]), float(cat["smax"]))
		var b: Basis = Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s, s))
		out.append({"n": nm, "p": Vector3(x, h - 0.05, z), "s": s, "b": b})
	return out

func near_tree(p: Vector3, dist: float = 1.8) -> bool:
	var cx0: int = int(floor(p.x / CHUNK))
	var cz0: int = int(floor(p.z / CHUNK))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k: String = "%d|%d" % [cx0 + dx, cz0 + dz]
			if not _tree_cache.has(k):
				_tree_cache[k] = _gen(0, cx0 + dx, cz0 + dz)
			for it in (_tree_cache[k] as Array):
				var q: Vector3 = (it as Dictionary)["p"]
				if Vector2(q.x - p.x, q.z - p.z).length() < dist:
					return true
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
