extends Node3D
# Procedural anime hero (no model files): chibi proportions, big eyes, hair, ponytail, cape and sword.
# Faces +Z. Origin at the feet.

const TOON = preload("res://scripts/anime/toon.gd")

const SKIN := Color(1.0, 0.86, 0.78)
const HAIR := Color(0.80, 0.74, 1.0)
const HAIR_D := Color(0.58, 0.50, 0.90)
const OUTFIT := Color(0.97, 0.97, 1.0)
const OUTFIT2 := Color(0.24, 0.36, 0.86)
const GOLD := Color(1.0, 0.82, 0.35)
const BOOT := Color(0.22, 0.20, 0.32)
const STOCK := Color(0.30, 0.30, 0.44)
const CAPE := Color(0.27, 0.40, 0.92)
const RIBBON := Color(1.0, 0.35, 0.52)
const STEEL := Color(0.93, 0.96, 1.0)

var run: float = 0.0
var airborne: bool = false
var gliding: bool = false

var _t: float = 0.0
var _phase: float = 0.0
var _atk_t: float = 9.0
var _atk_idx: int = 0
var _cast_t: float = 9.0
var _slash_t: float = 9.0
var _mats: Array = []

var _hips: Node3D
var _lower: Node3D
var _head: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _tail: Array = []
var _cape: Array = []
var _glider: Node3D
var _slash: MeshInstance3D
var _slash_mat: ShaderMaterial

func _ready() -> void:
	_build()

# ------------------------------------------------------------ building blocks
func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0 + 0.001)
	m.radial_segments = 10
	m.rings = 4
	return m

func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 8
	return m

func _cyl(rt: float, rb: float, h: float, seg: int = 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m

func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m

func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, outline: float = 0.014, rot: Vector3 = Vector3.ZERO, emission: Color = Color(0, 0, 0), energy: float = 0.0, spec: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m: ShaderMaterial = TOON.mat(color, null, false, emission, energy, spec)
	if outline > 0.0:
		m.next_pass = TOON.outline(outline)
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	_mats.append(m)
	return mi

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

# ------------------------------------------------------------ face texture
func _eye(p: Vector2, ctr: Vector2, base: Color) -> Color:
	var d: Vector2 = p - ctr
	var rx: float = 15.0
	var ry: float = 19.0
	var e: float = (d.x * d.x) / (rx * rx) + (d.y * d.y) / (ry * ry)
	var out: Color = base
	if e < 1.0:
		var ie: float = (d.x * d.x) / (12.0 * 12.0) + (d.y * d.y) / (17.0 * 17.0)
		var col: Color = Color(1, 1, 1, 1)
		if ie < 1.0:
			var v: float = clampf((d.y + 17.0) / 34.0, 0.0, 1.0)
			col = Color(0.14, 0.22, 0.60).lerp(Color(0.38, 0.88, 0.96), v)
			var pe: float = (d.x * d.x) / 25.0 + ((d.y + 1.0) * (d.y + 1.0)) / 64.0
			if pe < 1.0:
				col = Color(0.05, 0.08, 0.22)
			if ie > 0.80:
				col = col.darkened(0.30)
		var h1: float = (d.x + 5.0) * (d.x + 5.0) + (d.y + 8.0) * (d.y + 8.0)
		var h2: float = (d.x - 5.0) * (d.x - 5.0) + (d.y - 8.0) * (d.y - 8.0)
		if h1 < 14.0 or h2 < 5.0:
			col = Color(1, 1, 1, 1)
		out = Color(col.r, col.g, col.b, 1.0)
	var edge: float = 1.0 + 0.32 * clampf(-d.y / ry, 0.0, 1.0)
	if e < edge and e > 0.88:
		out = Color(0.12, 0.07, 0.22, 1.0)
	return out

func _face_tex() -> ImageTexture:
	var w: int = 128
	var h: int = 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var el := Vector2(34.0, 34.0)
	var er := Vector2(94.0, 34.0)
	for y in range(h):
		for x in range(w):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var c: Color = Color(0, 0, 0, 0)
			c = _eye(p, el, c)
			c = _eye(p, er, c)
			if c.a < 0.5:
				# blush
				var b1: float = p.distance_to(Vector2(24.0, 52.0))
				var b2: float = p.distance_to(Vector2(104.0, 52.0))
				var bl: float = maxf(1.0 - minf(b1, b2) / 9.0, 0.0)
				if bl > 0.0:
					c = Color(1.0, 0.45, 0.55, bl * 0.55)
				# eyebrows
				for ex in [34.0, 94.0]:
					var dx: float = p.x - float(ex)
					if absf(dx) < 11.0 and absf(p.y - (13.0 + 0.012 * dx * dx)) < 1.5:
						c = Color(0.48, 0.40, 0.75, 0.95)
				# small smile
				var mx: float = p.x - 64.0
				if absf(mx) < 6.0 and absf(p.y - (56.0 - 0.10 * mx * mx)) < 1.2:
					c = Color(0.65, 0.25, 0.32, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------ build
func _build() -> void:
	_hips = _pivot(self, Vector3(0.0, 0.80, 0.0))
	_lower = _pivot(self, Vector3(0.0, 0.80, 0.0))
	# torso, skirt
	_part(_hips, _capsule(0.15, 0.46), OUTFIT, Vector3(0.0, 0.24, 0.0))
	_part(_hips, _cyl(0.16, 0.30, 0.22), OUTFIT2, Vector3(0.0, 0.0, 0.0))
	_part(_hips, _cyl(0.30, 0.305, 0.03), GOLD, Vector3(0.0, -0.10, 0.0), 0.0, Vector3.ZERO, Color(1.0, 0.8, 0.3), 0.3)
	_part(_hips, _sphere(0.035), GOLD, Vector3(0.0, 0.40, 0.145), 0.0, Vector3.ZERO, Color(1.0, 0.85, 0.4), 1.2)
	# legs
	_leg_l = _pivot(_lower, Vector3(-0.09, -0.04, 0.0))
	_leg_r = _pivot(_lower, Vector3(0.09, -0.04, 0.0))
	for lg in [_leg_l, _leg_r]:
		var leg: Node3D = lg as Node3D
		_part(leg, _capsule(0.055, 0.78), STOCK, Vector3(0.0, -0.39, 0.0), 0.012)
		_part(leg, _capsule(0.07, 0.22), BOOT, Vector3(0.0, -0.66, 0.015), 0.012)
	# arms
	_arm_l = _pivot(_hips, Vector3(-0.21, 0.40, 0.0))
	_arm_r = _pivot(_hips, Vector3(0.21, 0.40, 0.0))
	for ar in [_arm_l, _arm_r]:
		var arm: Node3D = ar as Node3D
		_part(arm, _capsule(0.045, 0.44), OUTFIT, Vector3(0.0, -0.20, 0.0), 0.012)
		_part(arm, _sphere(0.05), SKIN, Vector3(0.0, -0.43, 0.0), 0.012)
	# sword in the right hand
	var sword: Node3D = _pivot(_arm_r, Vector3(0.0, -0.43, 0.03))
	sword.rotation.x = deg_to_rad(120.0)
	_part(sword, _box(0.035, 0.14, 0.035), BOOT, Vector3(0.0, 0.0, 0.0), 0.008)
	_part(sword, _box(0.16, 0.03, 0.05), GOLD, Vector3(0.0, 0.08, 0.0), 0.008, Vector3.ZERO, Color(1.0, 0.8, 0.3), 0.4)
	_part(sword, _box(0.05, 0.75, 0.012), STEEL, Vector3(0.0, 0.47, 0.0), 0.008, Vector3.ZERO, Color(0.5, 0.85, 1.0), 0.5, 1.0)
	# head
	_head = _pivot(_hips, Vector3(0.0, 0.66, 0.0))
	var head_mesh: MeshInstance3D = _part(_head, _sphere(0.21), SKIN, Vector3(0.0, 0.15, 0.0), 0.014)
	head_mesh.scale = Vector3(1.0, 0.96, 0.98)
	var face := MeshInstance3D.new()
	face.mesh = _sphere(0.2135)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/anime/face.gdshader") as Shader
	fm.set_shader_parameter("face_tex", _face_tex())
	face.material_override = fm
	face.position = Vector3(0.0, 0.15, 0.0)
	face.scale = Vector3(1.0, 0.96, 0.98)
	_head.add_child(face)
	# hair: back volume, top cap, bangs, side locks, ahoge
	_part(_head, _sphere(0.225), HAIR, Vector3(0.0, 0.14, -0.06), 0.014)
	var cap: MeshInstance3D = _part(_head, _hemi(0.232), HAIR, Vector3(0.0, 0.20, 0.0), 0.014)
	cap.scale = Vector3(1.0, 0.95, 1.0)
	for k in range(5):
		var bx: float = -0.12 + 0.06 * float(k)
		var bang: MeshInstance3D = _part(_head, _cyl(0.0, 0.05, 0.12, 6), HAIR, Vector3(bx, 0.25, 0.19), 0.01, Vector3(deg_to_rad(165.0), 0.0, 0.0))
		bang.rotation.z = -bx * 1.5
	_part(_head, _capsule(0.035, 0.30), HAIR, Vector3(-0.205, 0.04, 0.05), 0.01)
	_part(_head, _capsule(0.035, 0.30), HAIR, Vector3(0.205, 0.04, 0.05), 0.01)
	_part(_head, _cyl(0.0, 0.03, 0.18, 6), HAIR_D, Vector3(0.02, 0.42, 0.02), 0.008, Vector3(0.0, 0.0, deg_to_rad(-25.0)))
	_part(_head, _sphere(0.045), RIBBON, Vector3(0.0, 0.34, -0.19), 0.01, Vector3.ZERO, Color(1.0, 0.4, 0.5), 0.3)
	# ponytail (3 chained segments)
	var tp: Node3D = _pivot(_head, Vector3(0.0, 0.30, -0.20))
	for k in range(3):
		_part(tp, _capsule(0.06 - 0.012 * float(k), 0.26), HAIR if k < 2 else HAIR_D, Vector3(0.0, -0.11, 0.0), 0.01)
		_tail.append(tp)
		var nxt: Node3D = _pivot(tp, Vector3(0.0, -0.22, 0.0))
		tp = nxt
	# cape (3 chained segments)
	var cp: Node3D = _pivot(_hips, Vector3(0.0, 0.46, -0.165))
	var widths: Array = [0.36, 0.38, 0.32]
	for k in range(3):
		var wd: float = float(widths[k])
		_part(cp, _box(wd, 0.30, 0.025), CAPE, Vector3(0.0, -0.15, -0.01), 0.01)
		_cape.append(cp)
		var nc: Node3D = _pivot(cp, Vector3(0.0, -0.30, 0.0))
		cp = nc
	# glider (shown while gliding)
	_glider = _pivot(_hips, Vector3(0.0, 0.62, -0.12))
	_glider.visible = false
	var wl: MeshInstance3D = _part(_glider, _box(0.85, 0.025, 0.55), OUTFIT, Vector3(-0.46, 0.55, -0.05), 0.012, Vector3(0.0, 0.0, deg_to_rad(10.0)))
	var wr: MeshInstance3D = _part(_glider, _box(0.85, 0.025, 0.55), OUTFIT, Vector3(0.46, 0.55, -0.05), 0.012, Vector3(0.0, 0.0, deg_to_rad(-10.0)))
	wl.set_meta("w", 1)
	wr.set_meta("w", 1)
	_part(_glider, _box(0.10, 0.04, 0.7), GOLD, Vector3(0.0, 0.58, -0.05), 0.01, Vector3.ZERO, Color(1.0, 0.8, 0.3), 0.6)
	_part(_glider, _cyl(0.012, 0.012, 0.6, 6), GOLD, Vector3(-0.16, 0.30, -0.02), 0.0, Vector3(0.0, 0.0, deg_to_rad(-20.0)))
	_part(_glider, _cyl(0.012, 0.012, 0.6, 6), GOLD, Vector3(0.16, 0.30, -0.02), 0.0, Vector3(0.0, 0.0, deg_to_rad(20.0)))
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

func _hemi(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.is_hemisphere = true
	m.radial_segments = 14
	m.rings = 6
	return m

# ------------------------------------------------------------ actions
func swing(idx: int) -> void:
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
	for m in _mats:
		var sm: ShaderMaterial = m as ShaderMaterial
		sm.set_shader_parameter("emission_color", Color(1.0, 0.25, 0.3))
		sm.set_shader_parameter("emission_energy", 1.6)
		var tw := create_tween()
		tw.tween_property(sm, "shader_parameter/emission_energy", 0.0, 0.35)

func _ease(cur: float, target: float, k: float, delta: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-k * delta))

# ------------------------------------------------------------ animation
func _process(delta: float) -> void:
	if _hips == null:
		return
	_t += delta
	_atk_t += delta
	_cast_t += delta
	_slash_t += delta
	var sp: float = clampf(run, 0.0, 1.0)
	_phase += delta * (5.0 + 9.0 * sp)
	var s: float = sin(_phase)
	var k: float = 14.0

	var ll: float = s * 0.85 * sp
	var lr: float = -s * 0.85 * sp
	var al: float = -s * 0.7 * sp
	var ar: float = s * 0.35 * sp - 0.2
	var al_z: float = -0.08
	var ar_z: float = 0.08
	var lean: float = 0.14 * sp
	var twist: float = 0.0
	if airborne and not gliding:
		ll = -0.7
		lr = 0.45
		al = -0.8
		ar = -1.0
		al_z = -0.5
		ar_z = 0.5
		lean = 0.05
	if gliding:
		ll = 0.35
		lr = 0.35
		al = 0.0
		ar = 0.0
		al_z = -1.35
		ar_z = 1.35
		lean = 0.85
	if _atk_t < 0.34 and not gliding:
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
		al_z = -0.5
		ar_z = 0.5
		k = 18.0
	_leg_l.rotation.x = _ease(_leg_l.rotation.x, ll, k, delta)
	_leg_r.rotation.x = _ease(_leg_r.rotation.x, lr, k, delta)
	_arm_l.rotation.x = _ease(_arm_l.rotation.x, al, k, delta)
	_arm_r.rotation.x = _ease(_arm_r.rotation.x, ar, k, delta)
	_arm_l.rotation.z = _ease(_arm_l.rotation.z, al_z, k, delta)
	_arm_r.rotation.z = _ease(_arm_r.rotation.z, ar_z, k, delta)
	_hips.rotation.x = _ease(_hips.rotation.x, lean, 10.0, delta)
	_hips.rotation.y = _ease(_hips.rotation.y, twist, 18.0, delta)
	_hips.position.y = 0.80 + absf(s) * 0.04 * sp + sin(_t * 2.0) * 0.008
	_lower.position.y = _hips.position.y
	_head.rotation.z = sin(_phase * 0.5) * 0.04 * sp
	_head.rotation.x = -lean * 0.5

	# hair + cape sway
	for i in range(_tail.size()):
		var tn: Node3D = _tail[i] as Node3D
		tn.rotation.x = 0.45 + 0.55 * sp + sin(_t * 3.0 - float(i) * 0.9) * (0.10 + 0.12 * sp)
		tn.rotation.z = sin(_t * 2.2 - float(i) * 0.7) * 0.10
	for i in range(_cape.size()):
		var cn: Node3D = _cape[i] as Node3D
		cn.rotation.x = 0.06 + 0.40 * sp + (0.35 if gliding else 0.0) + sin(_t * 4.0 - float(i) * 0.8) * (0.05 + 0.08 * sp)

	_glider.visible = gliding
	if _slash.visible:
		var pr: float = clampf(_slash_t / 0.24, 0.0, 1.0)
		_slash_mat.set_shader_parameter("progress", pr)
		if pr >= 1.0:
			_slash.visible = false
