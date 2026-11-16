extends CharacterBody3D
# Bouncy elemental slime: hops toward the player, damages on contact. Group "enemy".

const TOON = preload("res://scripts/anime/toon.gd")
const FX = preload("res://scripts/anime/fx.gd")
const HPBAR = preload("res://scripts/anime/hpbar.gd")
const CRYSTAL = preload("res://scripts/anime/crystal.gd")

signal died

var kind: int = 0          # 0 green, 1 blue, 2 red
var hp: int = 3
var max_hp: int = 3
var dead: bool = false

var _player = null
var _body: Node3D
var _mats: Array = []
var _bar = null
var _hop_t: float = 1.0
var _hit_cd: float = 0.0
var _kb: Vector3 = Vector3.ZERO
var _squash: float = 0.0
var _was_floor: bool = true
var _t: float = 0.0
var _speed: float = 4.0
var _color: Color = Color(0.45, 0.85, 0.35)

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 9
	floor_snap_length = 0.5
	_t = randf() * 6.0
	_hop_t = randf_range(0.2, 1.5)
	if kind == 1:
		_color = Color(0.35, 0.66, 1.0)
		max_hp = 4
		_speed = 4.3
	elif kind == 2:
		_color = Color(1.0, 0.48, 0.36)
		max_hp = 5
		_speed = 4.8
	else:
		max_hp = 3
	hp = max_hp
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 0.9
	cs.shape = cap
	cs.position = Vector3(0.0, 0.45, 0.0)
	add_child(cs)
	_body = Node3D.new()
	_body.position = Vector3(0.0, 0.0, 0.0)
	add_child(_body)
	var bm: ShaderMaterial = TOON.mat(_color, null, false, _color, 0.25, 1.0, 0.9)
	bm.set_shader_parameter("shadow_tint", Vector3(_color.r * 0.5, _color.g * 0.5, _color.b * 0.7))
	bm.next_pass = TOON.outline(0.03)
	_mats.append(bm)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.9
	sm.radial_segments = 20
	sm.rings = 10
	body.mesh = sm
	body.material_override = bm
	body.position = Vector3(0.0, 0.42, 0.0)
	_body.add_child(body)
	var tip := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.12
	tm.height = 0.24
	tip.mesh = tm
	tip.material_override = bm
	tip.position = Vector3(0.0, 0.9, 0.0)
	_body.add_child(tip)
	var eye_m: ShaderMaterial = TOON.mat(Color(0.08, 0.05, 0.14))
	var white_m: ShaderMaterial = TOON.mat(Color(1, 1, 1), null, false, Color(1, 1, 1), 1.0)
	for sx in [-1.0, 1.0]:
		var xs: float = float(sx)
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.085
		em.height = 0.17
		e.mesh = em
		e.material_override = eye_m
		e.position = Vector3(0.17 * xs, 0.5, 0.40)
		_body.add_child(e)
		var h := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.03
		hm.height = 0.06
		h.mesh = hm
		h.material_override = white_m
		h.position = Vector3(0.17 * xs + 0.03, 0.54, 0.47)
		_body.add_child(h)
	var mouth := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.04
	mm.height = 0.05
	mouth.mesh = mm
	mouth.material_override = eye_m
	mouth.position = Vector3(0.0, 0.36, 0.45)
	_body.add_child(mouth)
	FX.blob(self, 0.55)
	_bar = HPBAR.new()
	add_child(_bar)
	_bar.position = Vector3(0.0, 1.5, 0.0)

func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_hit_cd = maxf(0.0, _hit_cd - delta)
	_hop_t -= delta
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	var to: Vector3 = Vector3.ZERO
	var dist: float = 999.0
	if _player != null:
		to = _player.global_position - global_position
		to.y = 0.0
		dist = to.length()
	var chasing: bool = dist < 15.0
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 26.0 * delta) + _kb.x
		velocity.z = move_toward(velocity.z, 0.0, 26.0 * delta) + _kb.z
		if _hop_t <= 0.0:
			var d: Vector3 = Vector3.ZERO
			if chasing and dist > 0.8:
				_hop_t = randf_range(0.65, 1.0)
				d = to.normalized()
			else:
				_hop_t = randf_range(1.6, 3.2)
				var a: float = randf() * TAU
				d = Vector3(cos(a), 0.0, sin(a)) * 0.5
			velocity = Vector3(d.x * _speed, 6.3, d.z * _speed)
			_squash = -0.35
			if d.length() > 0.01:
				_body.rotation.y = atan2(d.x, d.z)
	_kb = _kb.move_toward(Vector3.ZERO, 22.0 * delta)
	move_and_slide()
	var on_floor: bool = is_on_floor()
	if on_floor and not _was_floor:
		_squash = 0.4
	_was_floor = on_floor
	if dist < 1.15 and _hit_cd <= 0.0 and _player != null:
		_hit_cd = 1.2
		_player.take_damage(8.0 + float(kind) * 2.0)
		_kb = -to.normalized() * 5.0
		_squash = 0.5
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-9.0 * delta))
	var breathe: float = sin(_t * 3.0) * 0.02
	_body.scale = Vector3(1.0 + _squash * 0.35 - breathe, 0.9 - _squash * 0.55 + breathe, 1.0 + _squash * 0.35 - breathe)

func take_hit(dir: Vector3, dmg: int = 1) -> void:
	if dead:
		return
	hp -= dmg
	_kb = dir * 8.0
	velocity.y = 4.0
	_squash = 0.55
	var base: int = dmg * (90 + randi() % 40)
	var crit: bool = randf() < 0.15
	if crit:
		base = int(float(base) * 1.6)
	FX.dmg_number(self, global_position + Vector3(0.0, 1.5, 0.0), FX.fa(base), Color(1.0, 0.86, 0.3) if crit else Color(1.0, 1.0, 1.0), 72 if crit else 54)
	FX.burst(self, global_position + Vector3(0.0, 0.6, 0.0), _color.lightened(0.3), 8, 4.0, 0.12, 0.35, 8.0)
	for m in _mats:
		var sm: ShaderMaterial = m as ShaderMaterial
		sm.set_shader_parameter("emission_color", Color(1, 1, 1))
		sm.set_shader_parameter("emission_energy", 2.2)
		var tw := create_tween()
		tw.tween_property(sm, "shader_parameter/emission_energy", 0.25, 0.25)
	_bar.set_ratio(float(maxi(hp, 0)) / float(max_hp))
	if hp <= 0:
		_die()

func _die() -> void:
	dead = true
	died.emit()
	FX.sfx(self, "kill", -2.0, 1.0 + randf() * 0.2)
	FX.burst(self, global_position + Vector3(0.0, 0.6, 0.0), _color, 22, 6.0, 0.2, 0.6, 5.0)
	FX.ring(self, global_position, 2.0, _color, 0.35)
	if randf() < 0.35:
		var drop = CRYSTAL.new()
		drop.kind = "heal"
		get_parent().add_child(drop)
		drop.global_position = global_position
	var tw2 := create_tween()
	tw2.tween_property(_body, "scale", Vector3(1.4, 0.2, 1.4), 0.12)
	tw2.tween_property(_body, "scale", Vector3(0.01, 0.01, 0.01), 0.18)
	tw2.tween_callback(queue_free)
