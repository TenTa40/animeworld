extends CharacterBody3D
# Third-person anime hero: run, jump, double jump, glide, dash, 3-hit combo, skill (E) and burst (Q).

const HERO = preload("res://scripts/anime/hero.gd")
const FX = preload("res://scripts/anime/fx.gd")

const SPEED := 8.0
const JUMP := 9.0
const GRAV := 26.0
const SKILL_CD := 7.0
const DASH_CD := 0.9
const MAX_HP := 100.0

var hud = null
var world = null
var spawn_pos: Vector3 = Vector3.ZERO
var hp: float = MAX_HP
var energy: float = 0.0
var yaw: float = 0.0
var pitch: float = -0.35
var title_mode: bool = true
var deaths: int = 0

var _hero = null
var _rig: Node3D
var _cam: Camera3D
var _shadow: MeshInstance3D
var _cam_dist: float = 4.6
var _cam_dist_target: float = 4.6
var _fov_target: float = 46.0
var _face_y: float = 0.0
var _inv: float = 0.0
var _atk_cd: float = 0.0
var _combo: int = 0
var _combo_t: float = 0.0
var _hit_t: float = -1.0
var _lunge_t: float = 0.0
var _dash_t: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _skill_cd: float = 0.0
var _jumps: int = 0
var _air_t: float = 0.0
var _gliding: bool = false
var _shake: float = 0.0
var _step_t: float = 0.0
var _swim: bool = false
var _swim_fx: float = 0.0

# iko's own model when its data file is there and loads; otherwise the procedural hero
var _hero_msg: String = ""

func _make_hero() -> Node3D:
	for path: String in ["res://scripts/anime/hero_rig.gd", "res://scripts/anime/hero_iko.gd"]:
		if not ResourceLoader.exists(path):
			_hero_msg += path.get_file() + ": missing\n"
			continue
		var sc: GDScript = load(path) as GDScript
		if sc == null or not sc.can_instantiate():
			_hero_msg += path.get_file() + ": script error\n"
			continue
		var h: Node3D = sc.new() as Node3D
		if h != null:
			if bool(h.get("loaded")):
				_hero_msg += path.get_file() + ": OK " + String(h.get("fail"))
				return h
			_hero_msg += path.get_file() + ": FAIL " + String(h.get("fail")) + "\n"
			h.free()
	return HERO.new()

func _show_hero_msg() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 100
	var lb := Label.new()
	lb.text = _hero_msg
	lb.position = Vector2(12.0, 90.0)
	lb.add_theme_font_size_override("font_size", 22)
	cl.add_child(lb)
	add_child(cl)
	get_tree().create_timer(12.0).timeout.connect(cl.queue_free)

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 9
	floor_snap_length = 0.7
	floor_max_angle = deg_to_rad(60.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0.0, 0.85, 0.0)
	add_child(cs)
	_hero = _make_hero()
	_hero.scale = Vector3(0.95, 0.95, 0.95)
	add_child(_hero)
	_show_hero_msg()
	_shadow = FX.blob(self, 0.6)
	_shadow.top_level = true
	_rig = Node3D.new()
	_rig.position = Vector3(0.0, 1.45, 0.0)
	add_child(_rig)
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 0.0, _cam_dist)
	_cam.fov = 46.0
	_cam.near = 0.12
	_cam.far = 1700.0
	_rig.add_child(_cam)
	_cam.current = true

func start_play() -> void:
	title_mode = false
	_cam_dist_target = 5.6
	_fov_target = 70.0
	pitch = -0.30

func heal(amount: float) -> void:
	hp = minf(MAX_HP, hp + amount)
	FX.dmg_number(self, global_position + Vector3(0.0, 2.2, 0.0), "+" + FX.fa(int(amount)), Color(0.6, 1.0, 0.7), 54)

func add_shake(a: float) -> void:
	_shake = maxf(_shake, a)

func _physics_process(delta: float) -> void:
	_update_shadow()
	if title_mode:
		_title_step(delta)
		return
	if hud == null:
		return
	yaw -= hud.look.x
	pitch = clampf(pitch - hud.look.y, -1.2, 0.7)
	hud.look = Vector2.ZERO
	_rig.rotation = Vector3(pitch, yaw, 0.0)
	_inv = maxf(0.0, _inv - delta)
	_atk_cd = maxf(0.0, _atk_cd - delta)
	_combo_t = maxf(0.0, _combo_t - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_skill_cd = maxf(0.0, _skill_cd - delta)
	energy = minf(100.0, energy)

	var inp: Vector2 = hud.move
	var mag: float = clampf(inp.length() * 1.15, 0.0, 1.0)
	var dir: Vector3 = Basis(Vector3.UP, yaw) * Vector3(inp.x, 0.0, inp.y)
	if dir.length() > 0.01:
		dir = dir.normalized()
	var moving: bool = mag > 0.1
	if moving:
		_face_y = atan2(dir.x, dir.z)

	var on_floor: bool = is_on_floor()
	var gh: float = 0.0
	if world != null:
		gh = float(world.height(global_position.x, global_position.z))
	_swim = gh < -0.9 and global_position.y < 0.3
	if on_floor:
		_air_t = 0.0
		_jumps = 0
	else:
		_air_t += delta

	# actions
	if hud.take_dash() and _dash_cd <= 0.0:
		_start_dash(dir if moving else Vector3(sin(_face_y), 0.0, cos(_face_y)))
	if hud.take_skill() and _skill_cd <= 0.0:
		_skill()
	if hud.take_burst() and energy >= 100.0:
		_burst()
	if hud.take_attack() and _atk_cd <= 0.0 and _dash_t <= 0.0:
		_attack(dir if moving else Vector3.ZERO)
	if hud.take_jump():
		if _swim:
			velocity.y = 5.0
			FX.sfx(self, "jump", -8.0, 0.8)
		elif on_floor:
			velocity.y = JUMP
			_jumps = 1
			FX.sfx(self, "jump", -4.0)
		elif _jumps < 2:
			velocity.y = JUMP * 0.85
			_jumps = 2
			FX.sfx(self, "jump", -4.0, 1.25)
			FX.burst(self, global_position + Vector3(0.0, 0.2, 0.0), Color(0.8, 0.9, 1.0), 8, 3.0, 0.12, 0.35, 2.0)

	# delayed sword hit
	if _hit_t > 0.0:
		_hit_t -= delta
		if _hit_t <= 0.0:
			_do_hit()

	# horizontal movement
	_gliding = false
	if _dash_t > 0.0:
		_dash_t -= delta
		velocity.x = _dash_dir.x * 20.0
		velocity.z = _dash_dir.z * 20.0
	else:
		var tgt: Vector3 = dir * SPEED * mag * (0.6 if _swim else 1.0)
		if _lunge_t > 0.0:
			_lunge_t -= delta
			tgt += Vector3(sin(_face_y), 0.0, cos(_face_y)) * 5.0
		if not on_floor and not _swim and hud.glide_held and _air_t > 0.35 and velocity.y < 0.5:
			_gliding = true
			var cam_fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
			var gd: Vector3 = dir if moving else cam_fwd
			_face_y = atan2(gd.x, gd.z)
			tgt = gd * 10.0
		velocity.x = move_toward(velocity.x, tgt.x, 45.0 * delta)
		velocity.z = move_toward(velocity.z, tgt.z, 45.0 * delta)

	# vertical
	if _swim:
		velocity.y = lerpf(velocity.y, clampf((-0.35 - global_position.y) * 5.0, -4.0, 4.0), minf(1.0, 8.0 * delta))
	elif _gliding:
		velocity.y = maxf(velocity.y - 8.0 * delta, -2.4)
	elif not on_floor:
		velocity.y -= GRAV * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()

	# visuals
	_hero.rotation.y = lerp_angle(_hero.rotation.y, _face_y, minf(1.0, 14.0 * delta))
	var hs: float = Vector2(velocity.x, velocity.z).length() / SPEED
	_hero.run = clampf(hs, 0.0, 1.2) if on_floor else clampf(hs, 0.0, 1.0)
	_hero.airborne = (not is_on_floor()) and not _swim
	_hero.gliding = _gliding
	if on_floor and hs > 0.4:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.32
			FX.sfx(self, "step", -12.0, randf_range(0.9, 1.1))
	hud.hp = hp
	hud.energy = energy
	hud.skill_cd = _skill_cd / SKILL_CD
	hud.dash_cd = _dash_cd / DASH_CD
	if _swim:
		_swim_fx -= delta
		if _swim_fx <= 0.0 and hs > 0.2:
			_swim_fx = 0.55
			FX.ring(self, Vector3(global_position.x, 0.0, global_position.z), 1.6, Color(1, 1, 1, 0.55), 0.5)
	elif world != null and gh > -0.5 and global_position.y < gh - 6.0:
		global_position.y = gh + 2.0
		velocity.y = 0.0
	if global_position.y < -60.0:
		_respawn(false)
	var flat: Vector2 = Vector2(global_position.x, global_position.z)
	if flat.length() > 620.0:
		var kk: float = 620.0 / flat.length()
		global_position.x *= kk
		global_position.z *= kk
	_cam_dist_target = 5.6 + (1.3 if _gliding else 0.0)
	_fov_target = 70.0 + (9.0 if _gliding else 0.0) + (4.0 if _dash_t > 0.0 else 0.0)
	_update_camera(delta)

func _title_step(delta: float) -> void:
	yaw += delta * 0.22
	pitch = lerpf(pitch, -0.10, minf(1.0, 3.0 * delta))
	_rig.rotation = Vector3(pitch, yaw, 0.0)
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= GRAV * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	_hero.run = 0.0
	_hero.airborne = false
	_hero.gliding = false
	_cam_dist_target = 4.6
	_fov_target = 46.0
	_update_camera(delta)

func _update_shadow() -> void:
	if _shadow == null:
		return
	var gh: float = global_position.y
	if world != null:
		gh = float(world.height(global_position.x, global_position.z))
	_shadow.global_position = Vector3(global_position.x, gh + 0.06, global_position.z)
	var k: float = clampf(1.0 - (global_position.y - gh) * 0.12, 0.35, 1.0)
	_shadow.scale = Vector3(k, k, k)

func _update_camera(delta: float) -> void:
	var from: Vector3 = _rig.global_position
	var to: Vector3 = _rig.global_transform * Vector3(0.0, 0.0, _cam_dist_target)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var r: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var dd: float = _cam_dist_target
	if not r.is_empty():
		dd = maxf(0.8, from.distance_to(r["position"]) - 0.3)
	_cam.position.z = lerpf(_cam.position.z, dd, 0.3)
	_cam.fov = lerpf(_cam.fov, _fov_target, minf(1.0, 4.0 * delta))
	_shake = move_toward(_shake, 0.0, delta * 1.6)
	_cam.h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
	_cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.25

# ------------------------------------------------------------ combat
func _nearest_enemy(max_d: float):
	var best = null
	var bd: float = max_d
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.dead):
			continue
		var d: float = (e.global_position - global_position).length()
		if d < bd:
			bd = d
			best = e
	return best

func _attack(move_dir: Vector3) -> void:
	if _combo_t > 0.0:
		_combo = (_combo + 1) % 3
	else:
		_combo = 0
	_combo_t = 0.9
	_atk_cd = 0.36 if _combo < 2 else 0.55
	var tgt = _nearest_enemy(6.5)
	if tgt != null:
		var to: Vector3 = tgt.global_position - global_position
		_face_y = atan2(to.x, to.z)
	elif move_dir.length() > 0.1:
		_face_y = atan2(move_dir.x, move_dir.z)
	_hero.swing(_combo)
	var pitches: Array = [1.0, 1.12, 0.86]
	FX.sfx(self, "slash", -4.0, float(pitches[_combo]))
	_hit_t = 0.11
	_lunge_t = 0.14

func _do_hit() -> void:
	var fwd := Vector3(sin(_face_y), 0.0, cos(_face_y))
	var reach: float = 3.1 if _combo < 2 else 3.8
	var dmg: int = 1 if _combo < 2 else 2
	var any: bool = false
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.dead):
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var dist: float = to.length()
		if dist < reach and (dist < 1.3 or fwd.dot(to.normalized()) > 0.1):
			e.take_hit(to.normalized(), dmg)
			any = true
	if any:
		energy = minf(100.0, energy + 9.0)
		FX.sfx(self, "hit", -2.0, randf_range(0.95, 1.1))
		FX.hit_stop(self, 0.05)
		_shake = maxf(_shake, 0.25)
		FX.vibrate(18)

func _start_dash(d: Vector3) -> void:
	_dash_cd = DASH_CD
	_dash_t = 0.18
	_dash_dir = d.normalized()
	_inv = maxf(_inv, 0.28)
	_face_y = atan2(_dash_dir.x, _dash_dir.z)
	FX.sfx(self, "dash", -3.0)
	FX.burst(self, global_position + Vector3(0.0, 0.6, 0.0), Color(0.8, 0.9, 1.0), 10, 3.0, 0.16, 0.4, 1.0)

func _skill() -> void:
	_skill_cd = SKILL_CD
	_hero.cast()
	FX.sfx(self, "skill", -2.0)
	FX.ring(self, global_position, 6.0, Color(0.55, 0.85, 1.0), 0.5)
	FX.burst(self, global_position + Vector3(0.0, 1.0, 0.0), Color(0.6, 0.9, 1.0), 26, 7.0, 0.2, 0.6, 2.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.dead):
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		if to.length() < 5.8:
			e.take_hit(to.normalized() * 1.5, 2)
	energy = minf(100.0, energy + 20.0)
	_shake = maxf(_shake, 0.3)
	FX.vibrate(30)

func _burst() -> void:
	energy = 0.0
	_inv = 1.2
	_hero.cast()
	FX.sfx(self, "burst", 0.0)
	FX.ring(self, global_position, 12.0, Color(1.0, 0.85, 0.4), 0.7)
	FX.ring(self, global_position, 8.0, Color(1.0, 0.5, 0.7), 0.5)
	FX.burst(self, global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.85, 0.5), 40, 10.0, 0.25, 0.8, 3.0)
	FX.hit_stop(self, 0.1)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.dead):
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		if to.length() < 12.0:
			e.take_hit(to.normalized() * 1.8, 5)
	_shake = maxf(_shake, 0.6)
	FX.vibrate(80)

func take_damage(amount: float) -> void:
	if _inv > 0.0 or title_mode:
		return
	_inv = 0.7
	hp -= amount
	FX.sfx(self, "hurt", -2.0)
	FX.vibrate(40)
	_shake = maxf(_shake, 0.35)
	_hero.flash()
	if hud != null:
		hud.flash()
	if hp <= 0.0:
		_respawn(true)

func _respawn(from_death: bool) -> void:
	if from_death:
		deaths += 1
	hp = MAX_HP
	energy = 0.0
	global_position = spawn_pos
	velocity = Vector3.ZERO
	_inv = 1.5
	if hud != null:
		hud.toast("از حال رفتی... دوباره از اردوگاه شروع می‌کنی.")
