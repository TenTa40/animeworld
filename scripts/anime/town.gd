extends Node3D
# Castle town: terraced streets, castle, plaza market and shops with furnished interiors.
# Everything is built from the pre-merged glTF scenes written by tools/towngen.py.
# Falls back to nothing (no crash) when an asset is missing.

const DATA = preload("res://scripts/anime/town_data.gd")
const SH := "res://shaders/anime/town.gdshader"

var world = null
var _shader: Shader = null
var _mats: Dictionary = {}
var _body: StaticBody3D = null
var loaded: bool = false
var msg: String = ""

func setup(w) -> void:
	world = w
	_shader = load(SH) as Shader
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	var o: Vector2 = DATA.ORIGIN
	var n_ok: int = 0
	var castle: Node3D = _inst(DATA.CASTLE, Vector3(o.x, 0.0, o.y), 0.0, 0.0)
	if castle != null:
		n_ok += 1
	var plaza: Node3D = _inst(DATA.PLAZA, Vector3(o.x, 0.0, o.y), 0.0, 0.0)
	if plaza != null:
		n_ok += 1
	for b in DATA.CASTLE_BOXES:
		_box_world(b)
	for b in DATA.PLAZA_BOXES:
		_box_world(b)
	for pl in DATA.PLOTS:
		var t: String = str(pl[0])
		var u: float = float(pl[1])
		var v: float = float(pl[2])
		var yaw: float = float(pl[3])
		var ty: Dictionary = DATA.TYPES[t]
		var pos: Vector3 = Vector3(o.x + u, world.terrain.gen.town_h(u), o.y + v)
		if _inst(str(ty["out"]), pos, yaw, 0.0) != null:
			n_ok += 1
		var ins: Node3D = _inst(str(ty["in"]), pos, yaw, 38.0)
		if ins != null:
			n_ok += 1
		for b in ty["boxes"]:
			_box_local(b, pos, yaw)
	loaded = n_ok > 0
	msg = "town " + str(n_ok)

func _inst(path: String, pos: Vector3, yaw: float, vis_end: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return null
	var n: Node3D = ps.instantiate() as Node3D
	if n == null:
		return null
	n.position = pos
	n.rotation.y = yaw
	add_child(n)
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var sm: ShaderMaterial = _toon_of(mi.mesh.surface_get_material(i))
			if sm != null:
				mi.set_surface_override_material(i, sm)
		if vis_end > 0.0:
			mi.visibility_range_end = vis_end
			mi.visibility_range_end_margin = 4.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

func _toon_of(src: Material) -> ShaderMaterial:
	var bm: BaseMaterial3D = src as BaseMaterial3D
	if bm == null or bm.albedo_texture == null:
		return null
	var key: int = bm.albedo_texture.get_instance_id()
	if _mats.has(key):
		return _mats[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo_tex", bm.albedo_texture)
	m.set_shader_parameter("tint", bm.albedo_color)
	_mats[key] = m
	return m

func _add_shape(c: Vector3, size: Vector3, yaw: float) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), c)
	_body.add_child(cs)

# castle / plaza boxes: [u, y(world), v, sx, sy, sz, yaw]
func _box_world(b: Array) -> void:
	var o: Vector2 = DATA.ORIGIN
	_add_shape(Vector3(o.x + float(b[0]), float(b[1]), o.y + float(b[2])), Vector3(float(b[3]), float(b[4]), float(b[5])), float(b[6]))

# building boxes: [x, y(from floor), z, sx, sy, sz] in the building's local frame
func _box_local(b: Array, pos: Vector3, yaw: float) -> void:
	var l: Vector3 = Vector3(float(b[0]), float(b[1]), float(b[2]))
	var c: Vector3 = pos + Basis(Vector3.UP, yaw) * l
	_add_shape(c, Vector3(float(b[3]), float(b[4]), float(b[5])), yaw)
