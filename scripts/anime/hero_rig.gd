extends Node3D
# iko with a real skeleton: assets/characters/iko_rig.glb (made by tools/riggen.py) holds the iko mesh
# skinned to the Quaternius UAL2 skeleton plus the UAL2 clips. Same public API as hero.gd / hero_iko.gd
# (run, airborne, gliding, swing, cast, flash). `loaded` is false when anything is missing, and the caller
# then falls back to hero_iko.gd (shader pose) or the procedural hero.

const TOON = preload("res://scripts/anime/toon.gd")
const GLB := "res://assets/characters/iko_rig.glb"
const SH_BODY := "res://shaders/anime/hero_rig.gdshader"
const SH_OUT := "res://shaders/anime/hero_rig_outline.gdshader"
const HIP_Y := 0.85
const MODEL_SCALE := 0.885      # mannequin skeleton is 1.808 m tall, the hero is 1.6 m
const STEEL := Color(0.93, 0.96, 1.0)
const GOLD := Color(1.0, 0.82, 0.35)
const OUTFIT := Color(0.97, 0.97, 1.0)

# game state -> clip names (change here when other clips are added to the GLB)
const CLIP_IDLE := "Idle_No_Loop"
const CLIP_RUN := "Walk_Carry_Loop"
const CLIP_JUMP := "NinjaJump_Start"
const CLIP_AIR := "NinjaJump_Idle_Loop"
const CLIP_GLIDE := "NinjaJump_Idle_Loop"
const CLIP_HIT := "Hit_Knockback"
const CLIP_CAST := "Sword_Dash"
const CLIPS_ATK: Array = ["Sword_Regular_A", "Sword_Regular_B", "Sword_Regular_C"]
const ATK_SPEED: Array = [1.25, 1.3, 2.1]
const ATK_TIME: Array = [0.36, 0.42, 0.62]
const LOOPS: Array = ["Idle_No_Loop", "Walk_Carry_Loop", "NinjaJump_Idle_Loop", "Idle_FoldArms_Loop", "Slide_Loop", "Zombie_Walk_Fwd_Loop", "Idle_Shield_Loop"]
# blade direction in the hand_r bone frame (measured from the UAL2 sword clips)
const GRIP_POS := Vector3(0.0, 0.08, 0.0)

var loaded: bool = false
var run: float = 0.0
var airborne: bool = false
var gliding: bool = false

var _t: float = 0.0
var _atk_t: float = 9.0
var _atk_idx: int = 0
var _cast_t: float = 9.0
var _hit_t: float = 9.0
var _slash_t: float = 9.0
var _air_t: float = 0.0
var _cur: String = ""
var _pivot: Node3D
var _model: Node3D
var _skel: Skeleton3D
var _ap: AnimationPlayer
var _mat: ShaderMaterial
var _glider: Node3D
var _sword: Node3D
var _slash: MeshInstance3D
var _slash_mat: ShaderMaterial

func _init() -> void:
	loaded = _build()

func is_ready_ok() -> bool:
	return loaded

func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, emission: Color = Color(0, 0, 0), energy: float = 0.0, outline: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m: ShaderMaterial = TOON.mat(color, null, false, emission, energy, 0.0)
	if outline:
		m.next_pass = TOON.outline(0.012)
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m

func _build() -> bool:
	if not ResourceLoader.exists(GLB) or not ResourceLoader.exists(SH_BODY) or not ResourceLoader.exists(SH_OUT):
		return false
	var ps: PackedScene = load(GLB) as PackedScene
	if ps == null:
		return false
	var inst: Node = ps.instantiate()
	_model = inst as Node3D
	if _model == null:
		if inst != null:
			inst.free()
		return false
	var sk: Array = _model.find_children("*", "Skeleton3D", true, false)
	_ap = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var mis: Array = _model.find_children("*", "MeshInstance3D", true, false)
	if sk.is_empty() or _ap == null or mis.is_empty():
		_model.free()
		return false
	_skel = sk[0] as Skeleton3D
	if _skel == null or _skel.find_bone("hand_r") < 0 or not _ap.has_animation(CLIP_IDLE) or not _ap.has_animation(CLIP_RUN):
		_model.free()
		return false
	_mat = ShaderMaterial.new()
	_mat.shader = load(SH_BODY) as Shader
	var om := ShaderMaterial.new()
	om.shader = load(SH_OUT) as Shader
	_mat.next_pass = om
	for n in mis:
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null:
			continue
		mi.material_override = _mat
		mi.extra_cull_margin = 1.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for nm in LOOPS:
		if _ap.has_animation(nm):
			_ap.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, HIP_Y, 0.0)
	add_child(_pivot)
	_model.position = Vector3(0.0, -HIP_Y, 0.0)
	_model.scale = Vector3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	_pivot.add_child(_model)
	# sword in the right hand
	var ba := BoneAttachment3D.new()
	ba.bone_name = "hand_r"
	_skel.add_child(ba)
	_sword = Node3D.new()
	_sword.position = GRIP_POS
	_sword.visible = false
	ba.add_child(_sword)
	_part(_sword, _box(0.032, 0.032, 0.16), Color(0.25, 0.2, 0.3), Vector3.ZERO, Vector3.ZERO, Color(0, 0, 0), 0.0, false)
	_part(_sword, _box(0.16, 0.035, 0.03), GOLD, Vector3(0.0, 0.0, 0.095), Vector3.ZERO, Color(1.0, 0.8, 0.3), 0.4, false)
	_part(_sword, _box(0.014, 0.05, 0.86), STEEL, Vector3(0.0, 0.0, 0.54), Vector3.ZERO, Color(0.8, 0.9, 1.0), 0.25, false)
	# glider (shown while gliding)
	_glider = Node3D.new()
	_glider.position = Vector3(0.0, 0.52, -0.12)
	_glider.visible = false
	_pivot.add_child(_glider)
	_part(_glider, _box(0.85, 0.025, 0.55), OUTFIT, Vector3(-0.46, 0.55, -0.05), Vector3(0.0, 0.0, deg_to_rad(10.0)))
	_part(_glider, _box(0.85, 0.025, 0.55), OUTFIT, Vector3(0.46, 0.55, -0.05), Vector3(0.0, 0.0, deg_to_rad(-10.0)))
	_part(_glider, _box(0.10, 0.04, 0.7), GOLD, Vector3(0.0, 0.58, -0.05), Vector3.ZERO, Color(1.0, 0.8, 0.3), 0.6)
	# slash effect
	_slash = MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(3.0, 3.0)
	_slash.mesh = sq
	_slash_mat = ShaderMaterial.new()
	_slash_mat.shader = load("res://shaders/anime/slash.gdshader") as Shader
	_slash.material_override = _slash_mat
	_slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_slash.position = Vector3(0.0, 1.05, 0.95)
	_slash.visible = false
	add_child(_slash)
	_play(CLIP_IDLE, 0.0, 1.0)
	return true

# ------------------------------------------------------------ actions
func swing(idx: int) -> void:
	if not loaded:
		return
	_atk_idx = idx % 3
	_atk_t = 0.0
	_slash_t = 0.0
	var rolls: Array = [28.0, -28.0, 90.0]
	_slash.rotation_degrees = Vector3(0.0, 0.0, float(rolls[_atk_idx]))
	_slash_mat.set_shader_parameter("progress", 0.0)
	_slash.visible = true
	_play(String(CLIPS_ATK[_atk_idx]), 0.05, float(ATK_SPEED[_atk_idx]), true)

func cast() -> void:
	if not loaded:
		return
	_cast_t = 0.0
	_atk_t = 9.0
	_play(CLIP_CAST, 0.08, 1.8, true)

func flash() -> void:
	if not loaded:
		return
	_mat.set_shader_parameter("emission_color", Color(1.0, 0.25, 0.3))
	_mat.set_shader_parameter("emission_energy", 1.6)
	var tw := create_tween()
	tw.tween_property(_mat, "shader_parameter/emission_energy", 0.0, 0.35)
	if _cast_t > 0.8 and _atk_t > 0.7:
		_hit_t = 0.0
		_play(CLIP_HIT, 0.05, 1.5, true)

func _play(clip: String, blend: float, speed: float, restart: bool = false) -> void:
	if _ap == null or not _ap.has_animation(clip):
		return
	if _cur == clip and not restart:
		return
	_cur = clip
	_ap.speed_scale = 1.0
	_ap.play(clip, blend, speed)

func _ease(cur: float, target: float, k: float, delta: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-k * delta))

# ------------------------------------------------------------ state machine
func _process(delta: float) -> void:
	if not loaded:
		return
	_t += delta
	_atk_t += delta
	_cast_t += delta
	_hit_t += delta
	_slash_t += delta
	if airborne:
		_air_t += delta
	else:
		_air_t = 0.0
	var atk_dur: float = float(ATK_TIME[_atk_idx])
	var attacking: bool = _atk_t < atk_dur and not gliding
	var casting: bool = _cast_t < 0.85
	var hurt: bool = _hit_t < 0.45
	var lean: float = 0.0
	if casting or attacking or hurt:
		pass
	elif gliding:
		_play(CLIP_GLIDE, 0.2, 1.0)
		lean = 0.95
	elif airborne:
		if _air_t < 0.35:
			_play(CLIP_JUMP, 0.1, 1.9)
		else:
			_play(CLIP_AIR, 0.25, 1.0)
	elif run > 0.12:
		_play(CLIP_RUN, 0.15, 1.0)
		_ap.speed_scale = 0.85 + 1.0 * clampf(run, 0.0, 1.2)
		lean = 0.08 * clampf(run, 0.0, 1.0)
	else:
		_play(CLIP_IDLE, 0.25, 1.0)
	_pivot.rotation.x = _ease(_pivot.rotation.x, lean, 10.0, delta)
	_glider.visible = gliding
	_sword.visible = attacking or casting or _atk_t < 1.4
	if _slash.visible:
		var pr: float = clampf(_slash_t / 0.24, 0.0, 1.0)
		_slash_mat.set_shader_parameter("progress", pr)
		if pr >= 1.0:
			_slash.visible = false
