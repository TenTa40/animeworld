extends Node3D
# Small stylized open island: procedural terrain, cel-shading, trees, water,
# battery collecting and roaming zombies.

const TOON = preload("res://scripts/toon.gd")
const PLAYER = preload("res://scripts/player.gd")
const ENEMY = preload("res://scripts/enemy.gd")
const HUD = preload("res://scripts/hud.gd")
const PICKUP = preload("res://scripts/pickup.gd")
const NATURE = preload("res://scripts/nature.gd")

const RADIUS := 95.0
const HALF := 96.0
const CELL := 2.0
const CELLS_TOTAL := 10
const MAX_ZOMBIES := 7

var noise := FastNoiseLite.new()
var forest_noise := FastNoiseLite.new()
var nature = null
var hud = null
var player = null
var collected: int = 0
var kills: int = 0
var _rng := RandomNumberGenerator.new()
var _respawn_t: float = 8.0
var _sun: DirectionalLight3D

func _ready() -> void:
	_rng.randomize()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	noise.seed = 7
	forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest_noise.frequency = 0.014
	forest_noise.seed = 99
	_make_environment()
	_build_terrain()
	_build_water()
	nature = NATURE.new()
	add_child(nature)
	if not nature.setup(self):
		nature.queue_free()
		nature = null
		_build_trees()
	hud = HUD.new()
	add_child(hud)
	player = PLAYER.new()
	player.hud = hud
	player.spawn_pos = Vector3(0, height(0.0, 0.0) + 1.0, 0)
	player.position = player.spawn_pos + Vector3(0, 1.0, 0)
	add_child(player)
	for i in range(CELLS_TOTAL):
		_spawn_pickup()
	for i in range(5):
		_spawn_zombie()
	hud.cells_total = CELLS_TOTAL
	hud.set_counts(0, 0)
	hud.toast("به جزیره‌ی آرام خوش اومدی! ۱۰ باتری پیدا کن و مواظب زامبی‌ها باش.", 6.0)

func _process(delta: float) -> void:
	_respawn_t -= delta
	if _respawn_t <= 0.0:
		_respawn_t = 12.0
		if get_tree().get_nodes_in_group("enemy").size() < MAX_ZOMBIES:
			_spawn_zombie()

# ------------------------------------------------------------ terrain
func height(x: float, z: float) -> float:
	var d: float = Vector2(x, z).length()
	var h: float = noise.get_noise_2d(x, z) * 9.0 + 4.0
	var plateau: float = 1.0 - smoothstep(0.0, 14.0, d)
	h = lerpf(h, 2.5, plateau)
	h -= smoothstep(RADIUS * 0.5, RADIUS, d) * 16.0
	return h

# 0..1, high = dense forest
func forest(x: float, z: float) -> float:
	return forest_noise.get_noise_2d(x, z) * 0.5 + 0.5

func _terrain_color(h: float, x: float, z: float) -> Color:
	var t: float = noise.get_noise_2d(x * 3.1 + 50.0, z * 3.1) * 0.5 + 0.5
	var col: Color = Color(0.42, 0.78, 0.26).lerp(Color(0.66, 0.9, 0.3), t)
	var sand: float = 1.0 - smoothstep(0.6, 1.5, h)
	col = col.lerp(Color(0.93, 0.85, 0.58), sand)
	var rock: float = smoothstep(9.0, 11.0, h)
	col = col.lerp(Color(0.6, 0.6, 0.68), rock)
	return col.srgb_to_linear()

func _build_terrain() -> void:
	var n: int = int(HALF * 2.0 / CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(n + 1):
		for i in range(n + 1):
			var x: float = -HALF + float(i) * CELL
			var z: float = -HALF + float(j) * CELL
			var h: float = height(x, z)
			st.set_color(_terrain_color(h, x, z))
			st.set_uv(Vector2(float(i), float(j)))
			st.add_vertex(Vector3(x, h, z))
	for j in range(n):
		for i in range(n):
			var a: int = j * (n + 1) + i
			var b: int = a + 1
			var c: int = a + (n + 1)
			var d: int = c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = TOON.mat(Color(1, 1, 1), null, true)
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)

func _build_water() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader") as Shader
	mi.material_override = m
	mi.position = Vector3(0, 0.0, 0)
	add_child(mi)

func _valid_spot(min_d: float, max_d: float) -> Vector3:
	for k in range(60):
		var ang: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(min_d, max_d)
		var x: float = cos(ang) * r
		var z: float = sin(ang) * r
		var h: float = height(x, z)
		if h > 1.8 and h < 9.5:
			if nature != null and nature.near_tree(Vector3(x, h, z), 2.2):
				continue
			return Vector3(x, h, z)
	return Vector3(0, height(0, 0), 0) + Vector3(3, 0, 3)

func _build_trees() -> void:
	var pts: Array = []
	for k in range(900):
		if pts.size() >= 190:
			break
		var p: Vector3 = _valid_spot(10.0, 85.0)
		if p.length() > 9.0:
			pts.append(p)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.26
	trunk.height = 1.6
	trunk.radial_segments = 6
	trunk.rings = 1
	trunk.material = TOON.mat(Color(0.5, 0.33, 0.22))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 1.5
	crown.height = 3.6
	crown.radial_segments = 8
	crown.rings = 1
	crown.material = TOON.mat(Color(1, 1, 1), null, true)
	var mt := MultiMesh.new()
	mt.transform_format = MultiMesh.TRANSFORM_3D
	mt.mesh = trunk
	mt.instance_count = pts.size()
	var mc := MultiMesh.new()
	mc.transform_format = MultiMesh.TRANSFORM_3D
	mc.use_colors = true
	mc.mesh = crown
	mc.instance_count = pts.size()
	for k in range(pts.size()):
		var p: Vector3 = pts[k]
		var s: float = _rng.randf_range(0.8, 1.5)
		var bs: Basis = Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
		mt.set_instance_transform(k, Transform3D(bs, p + Vector3(0, 0.8 * s, 0)))
		mc.set_instance_transform(k, Transform3D(bs, p + Vector3(0, 1.5 * s + 1.7 * s, 0)))
		var g: Color = Color(0.25, 0.62, 0.3).lerp(Color(0.45, 0.8, 0.35), _rng.randf())
		mc.set_instance_color(k, g.srgb_to_linear())
	var a := MultiMeshInstance3D.new()
	a.multimesh = mt
	add_child(a)
	var b := MultiMeshInstance3D.new()
	b.multimesh = mc
	add_child(b)

# ------------------------------------------------------------ environment
func _make_environment() -> void:
	var sky_m := ProceduralSkyMaterial.new()
	sky_m.sky_top_color = Color(0.3, 0.55, 0.95)
	sky_m.sky_horizon_color = Color(0.85, 0.92, 1.0)
	sky_m.ground_horizon_color = Color(0.85, 0.92, 1.0)
	sky_m.ground_bottom_color = Color(0.55, 0.72, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_m
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.9)
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.9, 1.0)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	_sun.light_energy = 1.25
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 70.0
	add_child(_sun)

# ------------------------------------------------------------ gameplay
func _spawn_pickup() -> void:
	var p: Vector3 = _valid_spot(12.0, 80.0)
	var pk = PICKUP.new()
	pk.position = p
	add_child(pk)
	pk.collected.connect(_on_pickup)

func _on_pickup() -> void:
	collected += 1
	hud.set_counts(collected, kills)
	if collected >= CELLS_TOTAL:
		hud.toast("همه‌ی باتری‌ها رو جمع کردی! جزیره امنه... فعلاً.", 8.0)
	else:
		hud.toast("باتری پیدا شد!", 1.5)

func _spawn_zombie() -> void:
	var p: Vector3 = _valid_spot(25.0, 80.0)
	var e = ENEMY.new()
	e.position = p + Vector3(0, 1.0, 0)
	add_child(e)
	e.died.connect(_on_zombie_died)

func _on_zombie_died() -> void:
	kills += 1
	hud.set_counts(collected, kills)
