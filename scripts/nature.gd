extends Node3D
# Scatters the Quaternius "Stylized Nature MegaKit" models over the island with
# MultiMesh chunks (cheap on mobile). Falls back gracefully if models are missing.

const DIR := "res://assets/nature/"
const TREES := ["CommonTree_1", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_4", "Pine_5"]

var world = null
var rng := RandomNumberGenerator.new()
var tree_pos: Array = []
var _meshes: Dictionary = {}
var _chunks: Dictionary = {}

# returns false when no tree model could be loaded (caller uses its fallback)
func setup(w) -> bool:
	world = w
	rng.seed = 11
	var have_tree: bool = false
	for t in TREES:
		if not _mesh(t).is_empty():
			have_tree = true
	if not have_tree:
		return false
	# trees (with a small trunk collider so you can't walk through them)
	_scatter(TREES, 80, {"rmin": 9.0, "rmax": 88.0, "hmin": 1.8, "hmax": 9.5, "smin": 0.9, "smax": 1.5, "forest": true, "vis": 150.0, "chunk": 32.0, "collide": true, "slope": 30.0})
	_scatter(["Bush_Common", "Bush_Common_Flowers"], 70, {"rmin": 6.0, "rmax": 88.0, "hmin": 1.6, "hmax": 9.5, "smin": 0.8, "smax": 1.5, "forest": true, "vis": 90.0, "chunk": 32.0, "slope": 35.0})
	_scatter(["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], 40, {"rmin": 10.0, "rmax": 90.0, "hmin": 0.6, "hmax": 13.0, "smin": 0.7, "smax": 1.8, "vis": 140.0, "chunk": 32.0, "collide": true, "slope": 60.0})
	_scatter(["Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short"], 1500, {"rmin": 0.0, "rmax": 88.0, "hmin": 1.4, "hmax": 9.0, "smin": 0.9, "smax": 1.6, "vis": 60.0, "chunk": 24.0, "noshadow": true, "slope": 40.0})
	_scatter(["Fern_1", "Plant_1_Big", "Plant_7_Big", "Clover_1"], 150, {"rmin": 4.0, "rmax": 88.0, "hmin": 1.6, "hmax": 9.0, "smin": 0.5, "smax": 1.0, "forest": true, "vis": 70.0, "chunk": 24.0, "noshadow": true, "slope": 40.0})
	_scatter(["Flower_3_Group", "Flower_3_Single", "Flower_4_Group"], 160, {"rmin": 3.0, "rmax": 85.0, "hmin": 1.6, "hmax": 8.5, "smin": 0.9, "smax": 1.4, "vis": 60.0, "chunk": 24.0, "noshadow": true, "slope": 30.0})
	_scatter(["Mushroom_Common"], 30, {"rmin": 5.0, "rmax": 85.0, "hmin": 1.6, "hmax": 9.0, "smin": 1.0, "smax": 1.8, "forest": true, "vis": 50.0, "chunk": 32.0, "noshadow": true, "slope": 30.0})
	_scatter(["Pebble_Round_1", "Pebble_Round_3", "Pebble_Square_1", "Pebble_Square_3"], 140, {"rmin": 0.0, "rmax": 88.0, "hmin": 0.5, "hmax": 9.0, "smin": 0.8, "smax": 1.8, "vis": 45.0, "chunk": 24.0, "noshadow": true, "slope": 40.0})
	_flush()
	return true

func near_tree(p: Vector3, dist: float = 1.8) -> bool:
	for t in tree_pos:
		var q: Vector3 = t
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

func _scatter(names: Array, count: int, o: Dictionary) -> void:
	var avail: Array = []
	for nm in names:
		if not _mesh(str(nm)).is_empty():
			avail.append(str(nm))
	if avail.is_empty():
		return
	var chunk: float = float(o.get("chunk", 32.0))
	var min_cos: float = cos(deg_to_rad(float(o.get("slope", 40.0))))
	var placed: int = 0
	var tries: int = 0
	while placed < count and tries < count * 12:
		tries += 1
		var r: float = lerpf(float(o["rmin"]), float(o["rmax"]), sqrt(rng.randf()))
		var ang: float = rng.randf() * TAU
		var x: float = cos(ang) * r
		var z: float = sin(ang) * r
		var h: float = world.height(x, z)
		if h < float(o["hmin"]) or h > float(o["hmax"]):
			continue
		var nrm: Vector3 = Vector3(world.height(x - 1.0, z) - world.height(x + 1.0, z), 2.0, world.height(x, z - 1.0) - world.height(x, z + 1.0)).normalized()
		if nrm.y < min_cos:
			continue
		if bool(o.get("forest", false)):
			var f: float = world.forest(x, z)
			if rng.randf() > smoothstep(0.35, 0.65, f) + 0.1:
				continue
		var nm: String = avail[rng.randi() % avail.size()]
		var s: float = rng.randf_range(float(o["smin"]), float(o["smax"]))
		var b: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		var pos: Vector3 = Vector3(x, h - 0.05, z)
		var md: Array = _mesh(nm)
		var xf: Transform3D = Transform3D(b, pos) * (md[1] as Transform3D)
		var key: String = "%s|%d|%d|%d|%d|%d" % [nm, int(floor(x / chunk)), int(floor(z / chunk)), int(float(o.get("vis", 100.0))), 1 if bool(o.get("noshadow", false)) else 0, 0]
		if not _chunks.has(key):
			_chunks[key] = []
		(_chunks[key] as Array).append(xf)
		placed += 1
		if bool(o.get("collide", false)):
			_add_collider(pos, s, nm)
			if nm.begins_with("Common") or nm.begins_with("Pine"):
				tree_pos.append(pos)

func _add_collider(pos: Vector3, s: float, nm: String) -> void:
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
	body.position = pos
	add_child(body)

func _flush() -> void:
	for key in _chunks.keys():
		var parts: PackedStringArray = str(key).split("|")
		var nm: String = parts[0]
		var vis: float = float(parts[3])
		var noshadow: bool = parts[4] == "1"
		var arr: Array = _chunks[key]
		var md: Array = _mesh(nm)
		if md.is_empty() or arr.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = md[0] as Mesh
		mm.instance_count = arr.size()
		for i in range(arr.size()):
			mm.set_instance_transform(i, arr[i] as Transform3D)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if noshadow:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# visibility range is measured to the chunk centre, so add some slack
		mmi.visibility_range_end = vis + 20.0
		mmi.visibility_range_end_margin = 6.0
		add_child(mmi)
	_chunks.clear()
