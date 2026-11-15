extends CharacterBody3D
# Simple zombie: chases the player when close, hits when adjacent. Group "enemy".

const TOON = preload("res://scripts/toon.gd")
signal died

var hp: int = 3
var dead: bool = false
var player = null

var _model: Node3D = null
var _anim: AnimationPlayer = null
var _mats: Array = []
var _hit_cd: float = 0.0
var _kb: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 9
	floor_snap_length = 0.7
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	var d: Dictionary = TOON.character(self, "zombieMaleA", 1.85, Color(0.8, 0.95, 0.8))
	if d.is_empty():
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.8
		mi.mesh = cm
		mi.position = Vector3(0, 0.9, 0)
		mi.material_override = TOON.mat(Color(0.4, 0.7, 0.4))
		add_child(mi)
	else:
		_model = d["model"]
		_anim = d["anim"]
		_mats = d["mats"]
		if _anim != null:
			_anim.speed_scale = 0.0

func _physics_process(delta: float) -> void:
	if dead:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	_hit_cd = maxf(0.0, _hit_cd - delta)
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	var want: Vector3 = Vector3.ZERO
	if player != null:
		var to: Vector3 = player.global_position - global_position
		to.y = 0.0
		var dist: float = to.length()
		if dist < 22.0 and dist > 1.1:
			want = to.normalized() * 2.7
		if dist > 0.1 and _model != null and dist < 22.0:
			_model.rotation.y = lerp_angle(_model.rotation.y, atan2(to.x, to.z), minf(1.0, 8.0 * delta))
		if dist < 1.6 and _hit_cd <= 0.0:
			_hit_cd = 1.1
			player.take_damage(12.0)
	_kb = _kb.move_toward(Vector3.ZERO, 20.0 * delta)
	velocity.x = want.x + _kb.x
	velocity.z = want.z + _kb.z
	move_and_slide()
	if _anim != null:
		_anim.speed_scale = 1.0 if want.length() > 0.1 else 0.0

func take_hit(dir: Vector3) -> void:
	if dead:
		return
	hp -= 1
	_kb = dir * 9.0
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter("emission_color", Color(1, 0.2, 0.2))
		(m as ShaderMaterial).set_shader_parameter("emission_energy", 2.0)
		var tw := create_tween()
		tw.tween_property(m, "shader_parameter/emission_energy", 0.0, 0.3)
	if hp <= 0:
		dead = true
		died.emit()
		var tw2 := create_tween()
		tw2.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
		tw2.tween_callback(queue_free)
