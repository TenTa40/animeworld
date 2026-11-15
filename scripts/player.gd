extends CharacterBody3D
# Third-person player: orbit camera, run/jump, sword swing (attack button).

const TOON = preload("res://scripts/toon.gd")
const SPEED := 6.5
const JUMP := 8.5
const GRAV := 24.0

var hud = null
var hp: float = 100.0
var yaw: float = 0.0
var pitch: float = -0.35
var spawn_pos: Vector3 = Vector3.ZERO

var _rig: Node3D
var _cam: Camera3D
var _model: Node3D = null
var _anim: AnimationPlayer = null
var _atk_cd: float = 0.0
var _inv: float = 0.0
var _cam_dist: float = 5.5

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
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
	var d: Dictionary = TOON.character(self, "humanMaleA", 1.75, Color(1, 1, 1))
	if d.is_empty():
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = 1.7
		mi.mesh = cm
		mi.position = Vector3(0, 0.85, 0)
		mi.material_override = TOON.mat(Color(0.9, 0.6, 0.7))
		add_child(mi)
	else:
		_model = d["model"]
		_anim = d["anim"]
		if _anim != null:
			_anim.speed_scale = 0.0
	_rig = Node3D.new()
	_rig.position = Vector3(0, 1.5, 0)
	add_child(_rig)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0, _cam_dist)
	_cam.fov = 70.0
	_cam.far = 220.0
	_rig.add_child(_cam)
	_cam.current = true

func _physics_process(delta: float) -> void:
	if hud == null:
		return
	yaw -= hud.look.x
	pitch = clampf(pitch - hud.look.y, -1.2, 0.7)
	hud.look = Vector2.ZERO
	_rig.rotation = Vector3(pitch, yaw, 0.0)
	_atk_cd = maxf(0.0, _atk_cd - delta)
	_inv = maxf(0.0, _inv - delta)

	var inp: Vector2 = hud.move
	var dir: Vector3 = Basis(Vector3.UP, yaw) * Vector3(inp.x, 0.0, inp.y)
	var tgt: Vector3 = dir * SPEED
	velocity.x = move_toward(velocity.x, tgt.x, 40.0 * delta)
	velocity.z = move_toward(velocity.z, tgt.z, 40.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAV * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	if hud.take_jump() and is_on_floor():
		velocity.y = JUMP
	if hud.take_attack():
		_attack()
	move_and_slide()

	var moving: bool = dir.length() > 0.1
	if moving and _model != null:
		var ty: float = atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, ty, minf(1.0, 12.0 * delta))
	if _anim != null:
		_anim.speed_scale = 1.2 if (moving and is_on_floor()) else 0.0

	if global_position.y < -6.0:
		_respawn()
	_update_camera()

func _update_camera() -> void:
	var from: Vector3 = _rig.global_position
	var to: Vector3 = _rig.global_transform * Vector3(0, 0, _cam_dist)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var r: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var dd: float = _cam_dist
	if not r.is_empty():
		dd = maxf(0.8, from.distance_to(r["position"]) - 0.3)
	_cam.position.z = lerpf(_cam.position.z, dd, 0.35)

func _attack() -> void:
	if _atk_cd > 0.0:
		return
	_atk_cd = 0.55
	var fy: float = 0.0
	if _model != null:
		fy = _model.rotation.y
		var tw := create_tween()
		tw.tween_property(_model, "rotation:x", -0.5, 0.08)
		tw.tween_property(_model, "rotation:x", 0.0, 0.14)
	var fwd: Vector3 = Vector3(sin(fy), 0.0, cos(fy))
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.dead):
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var dist: float = to.length()
		if dist < 2.8 and (dist < 1.2 or fwd.dot(to.normalized()) > 0.0):
			e.take_hit(to.normalized())

func take_damage(amount: float) -> void:
	if _inv > 0.0:
		return
	_inv = 0.7
	hp -= amount
	if hud != null:
		hud.flash()
		hud.set_hp(maxf(hp, 0.0))
	if hp <= 0.0:
		_respawn()

func _respawn() -> void:
	hp = 100.0
	global_position = spawn_pos
	velocity = Vector3.ZERO
	if hud != null:
		hud.set_hp(hp)
		hud.toast("از حال رفتی... دوباره از اردوگاه شروع می‌کنی.")
