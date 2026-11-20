extends Node3D
# Town citizens: shopkeepers behind their counters + people strolling the streets, plaza and courtyard.
# Models come from assets/npc/npc_*.gltf (built by tools/npcgen.py), animated with the shared UAL clips from iko_rig.glb.

const DATA = preload("res://scripts/anime/town_data.gd")
const SET = preload("res://scripts/anime/settings.gd")
const SH := "res://shaders/anime/town.gdshader"
const VARIANTS := ["m1", "m2", "f1", "f2"]
const CLIPS := ["Idle_No", "Idle_FoldArms", "Run", "Yes"]
const LOOPED := ["Idle_No", "Idle_FoldArms", "Run"]
const SKIN := [Color(1.0, 0.94, 0.88), Color(0.92, 0.76, 0.64), Color(0.74, 0.54, 0.42), Color(0.56, 0.40, 0.30)]
const HAIR := [Color(0.16, 0.11, 0.08), Color(0.36, 0.22, 0.11), Color(0.82, 0.64, 0.32), Color(0.68, 0.26, 0.12), Color(0.95, 0.95, 0.93), Color(0.30, 0.22, 0.36)]
const CLOTH := [Color(1, 1, 1), Color(1.0, 0.88, 0.86), Color(0.86, 0.96, 0.9), Color(0.88, 0.9, 1.0), Color(1.0, 0.94, 0.76), Color(0.8, 0.86, 1.0), Color(0.95, 0.8, 0.95)]
const VIS := 62.0
const ANIM_D := 34.0

static var _alib: AnimationLibrary = null

var world = null
var _shader: Shader = null
var _list: Array = []
var _t: float = 0.0
var loaded: bool = false
var msg: String = ""
var _rng := RandomNumberGenerator.new()

class Citizen extends Node3D:
	const VIS := 62.0
	const ANIM_D := 34.0
	var world = null
	var mode: String = "stand"       # stand | wander
	var region: Rect2 = Rect2()
	var avoid: Array = []            # [Vector2 centre, radius]
	var speed: float = 1.5
	var target: Vector2 = Vector2.ZERO
	var wait: float = 0.0
	var ap: AnimationPlayer = null
	var clip: String = ""
	var home_yaw: float = 0.0
	var fixed_y: float = -999.0
	var greet_t: float = 0.0
	var rng := RandomNumberGenerator.new()

	func _blocked(a: Vector2, b: Vector2) -> bool:
		for av in avoid:
			var c: Vector2 = av[0]
			var r: float = float(av[1])
			var ab: Vector2 = b - a
			var l2: float = ab.length_squared()
			var t: float = 0.0 if l2 < 0.0001 else clampf((c - a).dot(ab) / l2, 0.0, 1.0)
			if (a + ab * t).distance_to(c) < r:
				return true
		return false

	func _pick() -> void:
		var cur: Vector2 = Vector2(position.x, position.z)
		for k in range(10):
			var p: Vector2 = Vector2(rng.randf_range(region.position.x, region.end.x), rng.randf_range(region.position.y, region.end.y))
			if p.distance_to(cur) > 3.0 and not _blocked(cur, p):
				target = p
				return
		target = cur

	func play(nm: String, spd: float) -> void:
		if ap == null:
			return
		if clip != nm:
			clip = nm
			if ap.has_animation(nm):
				ap.play(nm, 0.25)
		ap.speed_scale = spd

	func tick(delta: float, pp: Vector3) -> void:
		var d: float = Vector2(pp.x - position.x, pp.z - position.z).length()
		if d > VIS:
			if visible:
				visible = false
				if ap != null:
					ap.active = false
			return
		if not visible:
			visible = true
		if ap != null:
			ap.active = d < ANIM_D
		var h: float = fixed_y if fixed_y > -900.0 else world.height(position.x, position.z)
		position.y = h
		if d >= ANIM_D:
			return
		if mode == "stand":
			var want: float = home_yaw
			if d < 6.5:
				want = atan2(pp.x - position.x, pp.z - position.z)
				greet_t -= delta
				if greet_t < 0.0:
					greet_t = rng.randf_range(7.0, 14.0)
					if d < 4.5:
						play("Yes", 1.0)
				elif clip == "Yes" and greet_t < 11.0:
					play("Idle_FoldArms", 1.0)
			elif clip == "Yes":
				play("Idle_FoldArms", 1.0)
			rotation.y = lerp_angle(rotation.y, want, minf(1.0, 5.0 * delta))
			return
		if wait > 0.0:
			wait -= delta
			play("Idle_No" if int(position.x * 7.0) % 2 == 0 else "Idle_FoldArms", 1.0)
			if wait <= 0.0:
				_pick()
			return
		var cur: Vector2 = Vector2(position.x, position.z)
		var dir: Vector2 = target - cur
		var dist: float = dir.length()
		if dist < 0.35:
			wait = rng.randf_range(2.0, 7.0)
			return
		var step: float = minf(speed * delta, dist)
		dir = dir / dist
		position.x += dir.x * step
		position.z += dir.y * step
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.y), minf(1.0, 7.0 * delta))
		play("Run", speed * 0.28)

func setup(w) -> void:
	world = w
	_shader = load(SH) as Shader
	_rng.seed = 77
	var cap: int = 9 if SET.quality == 0 else (13 if SET.quality == 1 else 17)
	var n_ok: int = 0
	# shopkeepers
	var k_i: int = 0
	for kp in DATA.KEEPERS:
		var o: Vector2 = DATA.ORIGIN
		var u: float = float(kp[1])
		var c: Citizen = _make(k_i, "stand")
		if c != null:
			c.position = Vector3(o.x + u, 0.0, o.y + float(kp[2]))
			c.fixed_y = w.terrain.gen.town_h(u)
			c.position.y = c.fixed_y
			c.home_yaw = float(kp[3])
			c.rotation.y = c.home_yaw
			n_ok += 1
		k_i += 1
	# strollers
	var o2: Vector2 = DATA.ORIGIN
	var zones: Array = [
		[Rect2(o2.x - 50.0, o2.y - 2.0, 94.0, 4.0), [], 3, 1.7],                                     # main street, through both gates
		[Rect2(o2.x - 64.0, o2.y - 7.0, 34.0, 14.0), [[Vector2(o2.x - 56.0, o2.y), 3.4]], 4, 1.3],   # market plaza
		[Rect2(o2.x + 32.0, o2.y - 10.0, 18.0, 20.0), [], 2, 1.4],                                   # castle courtyard
	]
	var vi: int = k_i
	for z in zones:
		for i in range(int(z[2])):
			if n_ok >= cap:
				break
			var c2: Citizen = _make(vi, "wander")
			vi += 1
			if c2 == null:
				continue
			c2.region = z[0]
			c2.avoid = z[1]
			c2.speed = float(z[3]) * _rng.randf_range(0.85, 1.15)
			var r: Rect2 = z[0]
			c2.position = Vector3(_rng.randf_range(r.position.x, r.end.x), 0.0, _rng.randf_range(r.position.y, r.end.y))
			c2._pick()
			c2.wait = _rng.randf_range(0.0, 3.0)
			n_ok += 1
	loaded = n_ok > 0
	msg = "npc " + str(n_ok)

func _make(idx: int, mode: String) -> Citizen:
	var path: String = "res://assets/npc/npc_%s.gltf" % VARIANTS[idx % VARIANTS.size()]
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return null
	var model: Node3D = ps.instantiate() as Node3D
	if model == null:
		return null
	var c := Citizen.new()
	c.world = world
	c.mode = mode
	c.rng.seed = 1000 + idx * 31
	add_child(c)
	var sc: float = _rng.randf_range(0.93, 1.06)
	model.scale = Vector3(sc, sc, sc)
	c.add_child(model)
	# materials: 0 skin, 1 cloth, 2 hair, 3 eyes
	var tints: Array = [SKIN[_rng.randi() % SKIN.size()], CLOTH[_rng.randi() % CLOTH.size()], HAIR[_rng.randi() % HAIR.size()], Color(1, 1, 1)]
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.visibility_range_end = VIS + 6.0
		for i in range(mi.mesh.get_surface_count()):
			var bm: BaseMaterial3D = mi.mesh.surface_get_material(i) as BaseMaterial3D
			if bm == null or bm.albedo_texture == null:
				continue
			var sm := ShaderMaterial.new()
			sm.shader = _shader
			sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
			sm.set_shader_parameter("tint", tints[mini(i, 3)])
			mi.set_surface_override_material(i, sm)
	_attach_anim(c, model)
	c.visible = false
	_list.append(c)
	return c

func _attach_anim(c: Citizen, model: Node3D) -> void:
	var sks: Array = model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	if _alib == null:
		_alib = _build_lib(model, sks[0] as Skeleton3D)
	if _alib == null:
		return
	var ap := AnimationPlayer.new()
	model.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", _alib)
	c.ap = ap
	c.play("Idle_No", 1.0)

func _build_lib(model: Node3D, sk: Skeleton3D) -> AnimationLibrary:
	var rp: String = "res://assets/characters/iko_rig.glb"
	if not ResourceLoader.exists(rp):
		return null
	var ps: PackedScene = load(rp) as PackedScene
	if ps == null:
		return null
	var inst: Node = ps.instantiate()
	var src: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if src == null:
		inst.free()
		return null
	var sk_path: String = str(model.get_path_to(sk))
	var lib := AnimationLibrary.new()
	for nm in CLIPS:
		if not src.has_animation(nm):
			continue
		var a: Animation = src.get_animation(nm).duplicate() as Animation
		for t in range(a.get_track_count()):
			var p: String = str(a.track_get_path(t))
			var ci: int = p.find(":")
			if ci > 0:
				a.track_set_path(t, NodePath(sk_path + p.substr(ci)))
		if nm in LOOPED:
			a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(nm, a)
	inst.free()
	return lib

func _process(delta: float) -> void:
	if _list.is_empty():
		return
	var pl: Node3D = world.player as Node3D
	if pl == null:
		return
	var pp: Vector3 = pl.global_position
	_t += delta
	for c in _list:
		(c as Citizen).tick(delta, pp)
