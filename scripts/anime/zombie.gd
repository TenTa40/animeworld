extends CharacterBody3D
# Simple monster (roach if available, else zombie): chases the player when close, hits when adjacent. Group "enemy".

const TOON = preload("res://scripts/anime/toon.gd")
const UT = preload("res://scripts/anime/util.gd")
const FX = preload("res://scripts/anime/fx.gd")
const HPBAR = preload("res://scripts/anime/hpbar.gd")
const CRYSTAL = preload("res://scripts/anime/crystal.gd")
const ROACH := "res://assets/enemies/roach.glb"
const ROACH_LENGTH := 1.9
const ROACH_YAW := 0.0   # extra turn if the roach model faces the wrong way (radians)
signal died

var hp: int = 3
var max_hp: int = 3
var _bar = null
var dead: bool = false
var player = null

var _model: Node3D = null
var _anim: AnimationPlayer = null
var _mats: Array = []
var _hit_cd: float = 0.0
var _kb: Vector3 = Vector3.ZERO
var _names: Dictionary = {}
var _cur: String = ""
var _yaw_off: float = 0.0

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
	var d: Dictionary = _make_roach()
	if d.is_empty():
		d = TOON.character(self, "zombieMaleA", 1.85, Color(0.8, 0.95, 0.8))
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
	FX.blob(self, 0.7)
	_bar = HPBAR.new()
	add_child(_bar)
	_bar.position = Vector3(0.0, 2.2, 0.0)

func _make_roach() -> Dictionary:
	if not ResourceLoader.exists(ROACH):
		return {}
	var w: Node3D = UT.place_model(self, ROACH, 0.0, ROACH_LENGTH, 0.0)
	if w == null:
		return {}
	var mats: Array = TOON.outline_existing(w, 0.03, Color(0.32, 0.17, 0.08))
	var ap: AnimationPlayer = null
	for n in w.find_children("*", "AnimationPlayer", true, false):
		ap = n as AnimationPlayer
		break
	if ap != null:
		for an in ap.get_animation_list():
			var low: String = String(an).to_lower()
			if low == "reset":
				continue
			var kind: String = ""
			if low.contains("walk") or low.contains("run") or low.contains("move"):
				kind = "walk"
			elif low.contains("idle") or low.contains("stand"):
				kind = "idle"
			elif low.contains("attack1"):
				kind = "attack"
			elif low.contains("attack") and not _names.has("attack"):
				kind = "attack"
			if kind != "" and not _names.has(kind):
				_names[kind] = an
				if kind != "attack":
					ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		if _names.is_empty():
			var first: String = ""
			for an2 in ap.get_animation_list():
				if String(an2).to_lower() != "reset":
					first = String(an2)
					break
			if first != "":
				_names["walk"] = first
				ap.get_animation(first).loop_mode = Animation.LOOP_LINEAR
	_yaw_off = ROACH_YAW
	return {"model": w, "anim": ap, "mats": mats}

func _play(kind: String) -> void:
	if _anim == null or not _names.has(kind) or _cur == kind:
		return
	_cur = kind
	_anim.speed_scale = 1.0
	_anim.play(String(_names[kind]), 0.15)

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
			_model.rotation.y = lerp_angle(_model.rotation.y, atan2(to.x, to.z) + _yaw_off, minf(1.0, 8.0 * delta))
		if dist < 1.6 and _hit_cd <= 0.0:
			_hit_cd = 1.1
			if _names.has("attack"):
				_cur = ""
				_play("attack")
			player.take_damage(12.0)
	_kb = _kb.move_toward(Vector3.ZERO, 20.0 * delta)
	velocity.x = want.x + _kb.x
	velocity.z = want.z + _kb.z
	move_and_slide()
	if _anim != null:
		if _names.is_empty():
			_anim.speed_scale = 1.0 if want.length() > 0.1 else 0.0
		elif _hit_cd < 0.6 or not _names.has("attack"):
			if want.length() > 0.1:
				_play("walk")
			elif _names.has("idle"):
				_play("idle")
			else:
				_anim.speed_scale = 0.0

func take_hit(dir: Vector3, dmg: int = 1) -> void:
	if dead:
		return
	hp -= dmg
	_kb = dir * 9.0
	var base: int = dmg * (110 + randi() % 50)
	FX.dmg_number(self, global_position + Vector3(0.0, 2.1, 0.0), FX.fa(base), Color(1.0, 1.0, 1.0), 54)
	FX.burst(self, global_position + Vector3(0.0, 1.0, 0.0), Color(0.8, 1.0, 0.7), 8, 4.0, 0.12, 0.35, 8.0)
	for m in _mats:
		_flash(m)
	if _bar != null:
		_bar.set_ratio(float(maxi(hp, 0)) / float(max_hp))
	if hp <= 0:
		dead = true
		died.emit()
		FX.sfx(self, "kill", -2.0, 0.8)
		FX.burst(self, global_position + Vector3(0.0, 1.0, 0.0), Color(0.6, 1.0, 0.6), 24, 6.0, 0.2, 0.6, 5.0)
		FX.ring(self, global_position, 2.2, Color(0.6, 1.0, 0.6), 0.35)
		if randf() < 0.5:
			var drop = CRYSTAL.new()
			drop.kind = "heal"
			get_parent().add_child(drop)
			drop.global_position = global_position
		var tw2 := create_tween()
		tw2.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
		tw2.tween_callback(queue_free)

func _flash(m) -> void:
	if m is ShaderMaterial:
		var sm: ShaderMaterial = m as ShaderMaterial
		sm.set_shader_parameter("emission_color", Color(1, 0.2, 0.2))
		sm.set_shader_parameter("emission_energy", 2.0)
		var tw := create_tween()
		tw.tween_property(sm, "shader_parameter/emission_energy", 0.0, 0.3)
	elif m is BaseMaterial3D:
		var bm: BaseMaterial3D = m as BaseMaterial3D
		bm.emission_enabled = true
		bm.emission = Color(1, 0.2, 0.2)
		bm.emission_energy_multiplier = 2.0
		var tw2 := create_tween()
		tw2.tween_property(bm, "emission_energy_multiplier", 0.0, 0.3)
