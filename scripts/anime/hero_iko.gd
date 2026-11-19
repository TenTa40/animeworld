extends Node3D
# iko — the player's character: a 26k-triangle mesh with baked vertex colours (assets/characters/iko.dat,
# made by tools/herogen.py). The source model had no skeleton, so legs, arms and cloth are animated by
# hero_body.gdshader. Same public API as hero.gd (run, airborne, gliding, swing, cast, flash).
# `loaded` is false when the data file is missing/broken; the caller then uses the procedural hero.

const TOON = preload("res://scripts/anime/toon.gd")
const DAT := "res://assets/characters/iko.dat"
const SH_BODY := "res://shaders/anime/hero_body.gdshader"
const SH_OUT := "res://shaders/anime/hero_outline.gdshader"
const HIP_Y := 0.85
const STEEL := Color(0.93, 0.96, 1.0)
const GOLD := Color(1.0, 0.82, 0.35)
const OUTFIT := Color(0.97, 0.97, 1.0)

var loaded: bool = false
var run: float = 0.0
var airborne: bool = false
var gliding: bool = false

var _t: float = 0.0
var _phase: float = 0.0
var _atk_t: float = 9.0
var _atk_idx: int = 0
var _cast_t: float = 9.0
var _slash_t: float = 9.0
var _pivot: Node3D
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _omat: ShaderMaterial
var _glider: Node3D
var _sword_pivot: Node3D
var _slash: MeshInstance3D
var _slash_mat: ShaderMaterial
var _legl: float = 0.0
var _legr: float = 0.0
var _arml: float = 0.0
var _armr: float = 0.0
var _rolll: float = 0.08
var _rollr: float = 0.08
var _flut: float = 0.2

func _init() -> void:
	loaded = _build()

func is_ready_ok() -> bool:
	return loaded

# ------------------------------------------------------------ mesh from the .dat file
func _load_mesh() -> ArrayMesh:
	if not FileAccess.file_exists(DAT):
		return null
	var f: FileAccess = FileAccess.open(DAT, FileAccess.READ)
	if f == null:
		return null
	var buf: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if buf.size() < 12:
		return null
	if buf.slice(0, 4).get_string_from_ascii() != "IKO1":
		return null
	var nv: int = buf.decode_u32(4)
	var ni: int = buf.decode_u32(8)
	if nv < 3 or ni < 3 or buf.size() < 12 + nv * 18 + ni * 4:
		return null
	var o: int = 12
	var pf: PackedFloat32Array = buf.slice(o, o + nv * 12).to_float32_array()
	o += nv * 12
	var nb: PackedByteArray = buf.slice(o, o + nv * 3)
	o += nv * 3
	var cb: PackedByteArray = buf.slice(o, o + nv * 3)
	o += nv * 3
	var ib: PackedInt32Array = buf.slice(o, o + ni * 4).to_int32_array()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nv)
	norms.resize(nv)
	cols.resize(nv)
	for i in range(nv):
		verts[i] = Vector3(pf[i * 3], pf[i * 3 + 1], pf[i * 3 + 2])
		var nx: int = nb[i * 3]
		var ny: int = nb[i * 3 + 1]
		var nz: int = nb[i * 3 + 2]
		if nx > 127:
			nx -= 256
		if ny > 127:
			ny -= 256
		if nz > 127:
			nz -= 256
		norms[i] = Vector3(float(nx), float(ny), float(nz)) / 127.0
		cols[i] = Color(float(cb[i * 3]) / 255.0, float(cb[i * 3 + 1]) / 255.0, float(cb[i * 3 + 2]) / 255.0, 1.0)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = ib
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, emission: Color = Color(0, 0, 0), energy: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m: ShaderMaterial = TOON.mat(color, null, false, emission, energy, 0.0)
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

func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 6
	return m

func _build() -> bool:
	var mesh: ArrayMesh = _load_mesh()
	if mesh == null:
		return false
	if not ResourceLoader.exists(SH_BODY) or not ResourceLoader.exists(SH_OUT):
		return false
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, HIP_Y, 0.0)
	add_child(_pivot)
	_mat = ShaderMaterial.new()
	_mat.shader = load(SH_BODY) as Shader
	_omat = ShaderMaterial.new()
	_omat.shader = load(SH_OUT) as Shader
	_mat.next_pass = _omat
	_mi = MeshInstance3D.new()
	_mi.mesh = mesh
	_mi.material_override = _mat
	_mi.position = Vector3(0.0, -HIP_Y, 0.0)
	_mi.extra_cull_margin = 0.8
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(_mi)
	# glider (shown while gliding)
	_glider = Node3D.new()
	_glider.position = Vector3(0.0, 0.52, -0.12)
	_glider.visible = false
	_pivot.add_child(_glider)
	var wl: MeshInstance3D = _part(_glider, _box(0.85, 0.025, 0.55), OUTFIT, Vector3(-0.46, 0.55, -0.05), Vector3(0.0, 0.0, deg_to_rad(10.0)))
	var wr: MeshInstance3D = _part(_glider, _box(0.85, 0.025, 0.55), OUTFIT, Vector3(0.46, 0.55, -0.05), Vector3(0.0, 0.0, deg_to_rad(-10.0)))
	wl.set_meta("w", 1)
	wr.set_meta("w", 1)
	_part(_glider, _box(0.10, 0.04, 0.7), GOLD, Vector3(0.0, 0.58, -0.05), Vector3.ZERO, Color(1.0, 0.8, 0.3), 0.6)
	# sword: hangs from the right shoulder and follows the swing
	_sword_pivot = Node3D.new()
	_sword_pivot.position = Vector3(-0.11, 0.45, 0.02)
	_sword_pivot.visible = false
	_pivot.add_child(_sword_pivot)
	var hand: Node3D = Node3D.new()
	hand.position = Vector3(-0.06, -0.52, 0.0)
	hand.rotation.x = deg_to_rad(90.0)
	_sword_pivot.add_child(hand)
	_part(hand, _cyl(0.014, 0.014, 0.13), Color(0.25, 0.2, 0.3), Vector3(0.0, 0.0, 0.0))
	_part(hand, _box(0.16, 0.02, 0.04), GOLD, Vector3(0.0, 0.08, 0.0), Vector3.ZERO, Color(1.0, 0.8, 0.3), 0.4)
	_part(hand, _box(0.045, 0.78, 0.012), STEEL, Vector3(0.0, 0.48, 0.0), Vector3.ZERO, Color(0.8, 0.9, 1.0), 0.25)
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
	return true

# ------------------------------------------------------------ actions
func swing(idx: int) -> void:
	if not loaded:
		return
	_atk_idx = idx
	_atk_t = 0.0
	_slash_t = 0.0
	var rolls: Array = [28.0, -28.0, 90.0]
	_slash.rotation_degrees = Vector3(0.0, 0.0, float(rolls[idx % 3]))
	_slash_mat.set_shader_parameter("progress", 0.0)
	_slash.visible = true

func cast() -> void:
	_cast_t = 0.0

func flash() -> void:
	if not loaded:
		return
	_mat.set_shader_parameter("emission_color", Color(1.0, 0.25, 0.3))
	_mat.set_shader_parameter("emission_energy", 1.6)
	var tw := create_tween()
	tw.tween_property(_mat, "shader_parameter/emission_energy", 0.0, 0.35)

func _ease(cur: float, target: float, k: float, delta: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-k * delta))

func _set_both(name: String, v: float) -> void:
	_mat.set_shader_parameter(name, v)
	_omat.set_shader_parameter(name, v)

# ------------------------------------------------------------ animation
func _process(delta: float) -> void:
	if not loaded:
		return
	_t += delta
	_atk_t += delta
	_cast_t += delta
	_slash_t += delta
	var sp: float = clampf(run, 0.0, 1.0)
	_phase += delta * (5.0 + 9.0 * sp)
	var s: float = sin(_phase)
	var k: float = 14.0

	var ll: float = s * 0.75 * sp
	var lr: float = -s * 0.75 * sp
	var al: float = -s * 0.65 * sp
	var ar: float = s * 0.65 * sp
	var rl: float = 0.08
	var rr: float = 0.08
	var lean: float = 0.12 * sp
	var twist: float = 0.0
	var fl: float = 0.18 + 0.9 * sp
	if airborne and not gliding:
		ll = -0.7
		lr = 0.45
		al = -0.6
		ar = -0.6
		rl = 0.45
		rr = 0.45
		lean = 0.05
		fl = 0.9
	if gliding:
		ll = 0.30
		lr = 0.30
		al = 0.0
		ar = 0.0
		rl = 1.3
		rr = 1.3
		lean = 0.85
		fl = 1.3
	var swinging: bool = _atk_t < 0.34 and not gliding
	if swinging:
		var tt: float = clampf(_atk_t / 0.26, 0.0, 1.0)
		var e: float = tt * tt * (3.0 - 2.0 * tt)
		if _atk_idx == 0:
			ar = lerpf(-2.3, 0.5, e)
			twist = lerpf(0.55, -0.45, e)
		elif _atk_idx == 1:
			ar = lerpf(-1.6, 0.9, e)
			twist = lerpf(-0.55, 0.5, e)
		else:
			ar = lerpf(-3.0, 1.0, e)
			lean = lerpf(-0.1, 0.45, e)
		al = 0.6
		k = 30.0
	if _cast_t < 0.6 and not gliding:
		al = -2.7
		ar = -2.7
		rl = 0.5
		rr = 0.5
		k = 18.0
	_legl = _ease(_legl, ll, k, delta)
	_legr = _ease(_legr, lr, k, delta)
	_arml = _ease(_arml, al, k, delta)
	_armr = _ease(_armr, ar, k, delta)
	_rolll = _ease(_rolll, rl, k, delta)
	_rollr = _ease(_rollr, rr, k, delta)
	_flut = _ease(_flut, fl, 6.0, delta)
	_set_both("leg_l", _legl)
	_set_both("leg_r", _legr)
	_set_both("arm_l", _arml)
	_set_both("arm_r", _armr)
	_set_both("roll_l", _rolll)
	_set_both("roll_r", _rollr)
	_set_both("flutter", _flut)

	_pivot.rotation.x = _ease(_pivot.rotation.x, lean, 10.0, delta)
	_pivot.rotation.y = _ease(_pivot.rotation.y, twist, 18.0, delta)
	_pivot.position.y = HIP_Y + absf(s) * 0.035 * sp + sin(_t * 2.0) * 0.006
	_glider.visible = gliding
	_sword_pivot.visible = swinging or _cast_t < 0.45
	if _sword_pivot.visible:
		_sword_pivot.rotation.x = _armr if swinging else -2.4
	if _slash.visible:
		var pr: float = clampf(_slash_t / 0.24, 0.0, 1.0)
		_slash_mat.set_shader_parameter("progress", pr)
		if pr >= 1.0:
			_slash.visible = false
