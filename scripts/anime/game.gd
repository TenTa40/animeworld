extends Node3D
# iko — anime open-world prototype: terrain, day/night, clouds, camp, quests, menus.

const TOON = preload("res://scripts/anime/toon.gd")
const PLAYER = preload("res://scripts/anime/player.gd")
const SLIME = preload("res://scripts/anime/slime.gd")
const ZOMBIE = preload("res://scripts/anime/zombie.gd")
const CRYSTAL = preload("res://scripts/anime/crystal.gd")
const NATURE = preload("res://scripts/anime/nature.gd")
const HUD = preload("res://scripts/anime/hud.gd")
const MENU = preload("res://scripts/anime/menu.gd")
const AUDIO = preload("res://scripts/anime/audio.gd")
const FX = preload("res://scripts/anime/fx.gd")
const SET = preload("res://scripts/anime/settings.gd")
const TERRAIN = preload("res://scripts/anime/terrain.gd")
const IMPOSTOR = preload("res://scripts/anime/impostor.gd")

const CRYSTALS_TOTAL := 10
const MAX_ENEMIES := 8
const DAY_LEN := 320.0
const GATE_Z := -9.0

var terrain = null
var nature = null
var hud = null
var player = null
var menu = null
var audio = null
var actors: Node3D
var state: String = "title"
var collected: int = 0
var kills: int = 0
var game_time: float = 0.0
var tod: float = 0.33
var night: float = 0.0

var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _tick: float = 0.0
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky_m: ProceduralSkyMaterial
var _water_mat: ShaderMaterial
var _far_ocean: MeshInstance3D
var _far_mat: StandardMaterial3D
var _enemy_t: float = 0.0
var _biome_t: float = 0.0
var _biome_cur: String = ""
var _ld = null
var _inited: bool = false
var _dbg_t: float = 0.0
var _cloud_mat: StandardMaterial3D
var _clouds: Array = []
var _stars: MeshInstance3D
var _stars_mat: ShaderMaterial
var _petals: CPUParticles3D
var _petal_night: bool = false
var _fire_light: OmniLight3D
var _beacon: Node3D = null
var _kf: Array = []
var _gov_level: int = 0
var _gov_t: float = 0.0
var _gov_frames: int = 0
var _gov_low: int = 0

func _ready() -> void:
	_boot()

func _step(p: float, text: String) -> void:
	if _ld != null:
		_ld.set_progress(p, text)
	await get_tree().process_frame

func _boot() -> void:
	_ld = get_tree().get_first_node_in_group("loading")
	SET.load_cfg()
	_rng.randomize()
	await _step(0.03, "آماده‌سازی آسمان و نور...")
	_init_keyframes()
	_make_environment()
	terrain = TERRAIN.new()
	add_child(terrain)
	terrain.mat = _terrain_material()
	terrain.water_mat = _water_material()
	terrain.budget_us = 12000
	_build_far_ocean()
	_build_clouds()
	nature = NATURE.new()
	add_child(nature)
	await _step(0.08, "ساختن جنگل‌های دور...")
	var imp: Dictionary = await IMPOSTOR.bake(self, nature)
	if not imp.is_empty():
		terrain.set_impostors(imp["tex"] as Texture2D, imp["info"] as Array)
	await _step(0.14, "شکل دادن به زمین...")
	terrain.update(Vector3.ZERO)
	var tot: int = maxi(1, terrain.pending(3.6))
	while true:
		var rem: int = terrain.pending(3.6)
		if rem <= 0:
			break
		await _step(0.14 + 0.36 * (1.0 - float(rem) / float(tot)), "شکل دادن به زمین...")
	await _step(0.52, "کاشتن درخت و چمن...")
	if not nature.setup(self):
		nature.queue_free()
		nature = null
	if nature != null:
		var ntot: int = maxi(1, nature.pending(Vector3.ZERO))
		while true:
			var nrem: int = nature.pending(Vector3.ZERO)
			if nrem <= 0:
				break
			nature.build_some(Vector3.ZERO, 14000)
			await _step(0.52 + 0.24 * (1.0 - float(nrem) / float(ntot)), "کاشتن درخت و چمن...")
	await _step(0.78, "اردوگاه، صدا و کریستال‌ها...")
	_build_camp()
	_build_petals()
	audio = AUDIO.new()
	add_child(audio)
	actors = Node3D.new()
	add_child(actors)
	hud = HUD.new()
	add_child(hud)
	hud.visible = false
	hud.cells_total = CRYSTALS_TOTAL
	hud.pause_pressed.connect(_on_pause)
	await _step(0.84, "ساختن قهرمان...")
	player = PLAYER.new()
	player.hud = hud
	player.world = self
	player.spawn_pos = Vector3(0.0, height(0.0, 0.0) + 1.0, 0.0)
	player.position = player.spawn_pos + Vector3(0.0, 1.0, 0.0)
	add_child(player)
	menu = MENU.new()
	add_child(menu)
	menu.start_pressed.connect(_on_start)
	menu.resume_pressed.connect(_on_resume)
	menu.restart_pressed.connect(_on_restart)
	menu.continue_pressed.connect(_on_continue)
	menu.settings_changed.connect(_on_settings_changed)
	_spawn_crystals()
	await _step(0.90, "آماده‌سازی جلوه‌ها...")
	_apply_settings()
	_update_time()
	await _warmup()
	terrain.budget_us = 7000
	terrain.follow = player
	actors.process_mode = Node.PROCESS_MODE_DISABLED
	_inited = true
	await _step(1.0, "آماده‌ست!")
	menu.show_title()
	if _ld != null:
		_ld.finish()

# draws one of everything behind the loading screen so shaders compile before gameplay
func _warmup() -> void:
	var holder := Node3D.new()
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(holder)
	var base: Vector3 = player.global_position
	var c1 = CRYSTAL.new()
	c1.position = base + Vector3(0.7, 0.3, 0.5)
	holder.add_child(c1)
	var c2 = CRYSTAL.new()
	c2.kind = "heal"
	c2.position = base + Vector3(-0.7, 0.3, 0.5)
	holder.add_child(c2)
	var sl = SLIME.new()
	sl.position = base + Vector3(-1.0, 0.2, -0.6)
	holder.add_child(sl)
	var zb = ZOMBIE.new()
	zb.position = base + Vector3(1.0, 0.2, -0.7)
	holder.add_child(zb)
	FX.burst(self, base + Vector3(0.0, 1.0, 0.0), Color(1, 1, 1), 8, 2.0, 0.1, 0.5, 2.0)
	FX.ring(self, base, 2.0, Color(1, 1, 1), 0.5)
	FX.dmg_number(self, base + Vector3(0.0, 2.0, 0.0), "۸", Color(1, 1, 1), 40)
	player._hero.swing(0)
	for i in range(14):
		await get_tree().process_frame
	holder.queue_free()

func _process(delta: float) -> void:
	if not _inited:
		return
	_t += delta
	tod = fposmod(tod + delta / DAY_LEN, 1.0)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.2
		_update_time()
	_follow(delta)
	_governor(delta)
	_dbg_t -= delta
	if _dbg_t <= 0.0:
		_dbg_t = 0.5
		if hud != null:
			if SET.debug:
				hud.debug_txt = _dbg_nature() + terrain.debug_text() + " | fps " + str(Engine.get_frames_per_second()) + " | gov " + str(_gov_level) + " | 3d " + str(snappedf(get_viewport().scaling_3d_scale, 0.01))
			else:
				hud.debug_txt = ""
	if state == "playing":
		game_time += delta
		_enemy_t -= delta
		if _enemy_t <= 0.0:
			_enemy_t = 2.0
			_enemy_tick()
		if _beacon != null and player != null:
			var d: Vector2 = Vector2(player.global_position.x - _beacon.global_position.x, player.global_position.z - _beacon.global_position.z)
			if d.length() < 2.8:
				_win()

# ------------------------------------------------------------ terrain access (used by player, nature, enemies)
func height(x: float, z: float) -> float:
	return terrain.sample(x, z)

func forest(x: float, z: float) -> float:
	return terrain.gen.forest(x, z)

func grove(x: float, z: float) -> float:
	return terrain.gen.grove(x, z)

func biome_vec(x: float, z: float) -> Vector4:
	return terrain.gen.masks(x, z)

func road_weight(_x: float, _z: float, _h: float) -> float:
	return 0.0

func road_at(x: float, z: float, h: float) -> float:
	return terrain.gen.road(x, z, h)

func autumn_at(x: float, z: float) -> float:
	return terrain.gen.autumn(x, z)

func _tex_mip(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path) as Texture2D
	if t == null:
		return null
	var img: Image = t.get_image()
	if img == null:
		return t
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _terrain_material() -> ShaderMaterial:
	var g: Texture2D = _tex_mip("res://assets/ground/grass.jpg")
	var st: Texture2D = _tex_mip("res://assets/ground/stones.jpg")
	if g == null or st == null:
		return TOON.mat(Color(1, 1, 1), null, true)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/terrain.gdshader") as Shader
	m.set_shader_parameter("grass_tex", g)
	m.set_shader_parameter("stone_tex", st)
	return m

func _water_material() -> ShaderMaterial:
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/anime/water.gdshader") as Shader
	return _water_mat

func _build_far_ocean() -> void:
	_far_ocean = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000.0, 6000.0)
	_far_ocean.mesh = pm
	_far_mat = StandardMaterial3D.new()
	_far_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_far_mat.albedo_color = Color(0.10, 0.42, 0.80)
	_far_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_far_ocean.material_override = _far_mat
	_far_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_far_ocean.position = Vector3(0.0, -0.4, 0.0)
	add_child(_far_ocean)

# ------------------------------------------------------------ sky, light, time of day
func _init_keyframes() -> void:
	_kf = [
		{"t": 0.00, "top": Color(0.04, 0.05, 0.18), "hor": Color(0.12, 0.14, 0.32), "amb": Color(0.30, 0.34, 0.62), "sun": Color(0.40, 0.50, 1.0), "e": 0.0, "fog": Color(0.08, 0.10, 0.26)},
		{"t": 0.22, "top": Color(0.20, 0.20, 0.50), "hor": Color(0.95, 0.55, 0.55), "amb": Color(0.46, 0.42, 0.64), "sun": Color(1.0, 0.60, 0.42), "e": 0.45, "fog": Color(0.82, 0.56, 0.62)},
		{"t": 0.30, "top": Color(0.35, 0.62, 0.98), "hor": Color(1.0, 0.86, 0.76), "amb": Color(0.60, 0.64, 0.92), "sun": Color(1.0, 0.90, 0.75), "e": 1.0, "fog": Color(0.90, 0.86, 0.92)},
		{"t": 0.50, "top": Color(0.30, 0.55, 0.95), "hor": Color(0.85, 0.92, 1.0), "amb": Color(0.55, 0.60, 0.90), "sun": Color(1.0, 0.96, 0.88), "e": 1.25, "fog": Color(0.72, 0.84, 1.0)},
		{"t": 0.70, "top": Color(0.35, 0.58, 0.95), "hor": Color(1.0, 0.88, 0.72), "amb": Color(0.58, 0.60, 0.88), "sun": Color(1.0, 0.90, 0.70), "e": 1.1, "fog": Color(0.92, 0.84, 0.82)},
		{"t": 0.78, "top": Color(0.35, 0.25, 0.62), "hor": Color(1.0, 0.50, 0.40), "amb": Color(0.50, 0.40, 0.66), "sun": Color(1.0, 0.55, 0.30), "e": 0.6, "fog": Color(0.95, 0.55, 0.52)},
		{"t": 0.86, "top": Color(0.10, 0.10, 0.32), "hor": Color(0.40, 0.25, 0.50), "amb": Color(0.30, 0.30, 0.58), "sun": Color(0.60, 0.40, 0.80), "e": 0.1, "fog": Color(0.30, 0.22, 0.45)},
		{"t": 1.00, "top": Color(0.04, 0.05, 0.18), "hor": Color(0.12, 0.14, 0.32), "amb": Color(0.30, 0.34, 0.62), "sun": Color(0.40, 0.50, 1.0), "e": 0.0, "fog": Color(0.08, 0.10, 0.26)},
	]

func _kf_at(t: float) -> Dictionary:
	var n: int = _kf.size()
	var i: int = 0
	while i < n - 2 and float((_kf[i + 1] as Dictionary)["t"]) <= t:
		i += 1
	var a: Dictionary = _kf[i]
	var b: Dictionary = _kf[i + 1]
	var span: float = float(b["t"]) - float(a["t"])
	var k: float = 0.0
	if span > 0.0001:
		k = clampf((t - float(a["t"])) / span, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return {
		"top": (a["top"] as Color).lerp(b["top"] as Color, k),
		"hor": (a["hor"] as Color).lerp(b["hor"] as Color, k),
		"amb": (a["amb"] as Color).lerp(b["amb"] as Color, k),
		"sun": (a["sun"] as Color).lerp(b["sun"] as Color, k),
		"fog": (a["fog"] as Color).lerp(b["fog"] as Color, k),
		"e": lerpf(float(a["e"]), float(b["e"]), k),
	}

func _make_environment() -> void:
	_sky_m = ProceduralSkyMaterial.new()
	_sky_m.sky_curve = 0.18
	_sky_m.ground_curve = 0.03
	_sky_m.sun_angle_max = 25.0
	_sky_m.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = _sky_m
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.55, 0.6, 0.9)
	_env.ambient_light_energy = 0.75
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.72, 0.84, 1.0)
	_env.fog_density = 0.0016
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	_sun.light_energy = 1.25
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.shadow_enabled = false
	_sun.directional_shadow_max_distance = 70.0
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.rotation_degrees = Vector3(-50.0, 140.0, 0.0)
	_moon.light_energy = 0.0
	_moon.light_color = Color(0.62, 0.72, 1.0)
	_moon.shadow_enabled = false
	add_child(_moon)
	# stars
	_stars = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 200.0
	sm.height = 400.0
	sm.radial_segments = 24
	sm.rings = 12
	_stars.mesh = sm
	_stars_mat = ShaderMaterial.new()
	_stars_mat.shader = load("res://shaders/anime/stars.gdshader") as Shader
	_stars.material_override = _stars_mat
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stars)

func _update_time() -> void:
	var k: Dictionary = _kf_at(tod)
	var top: Color = k["top"]
	var hor: Color = k["hor"]
	var amb: Color = k["amb"]
	var sc: Color = k["sun"]
	var fog: Color = k["fog"]
	var e: float = float(k["e"])
	night = clampf(1.0 - e / 0.45, 0.0, 1.0)
	_sky_m.sky_top_color = top
	_sky_m.sky_horizon_color = hor
	_sky_m.ground_horizon_color = hor
	_sky_m.ground_bottom_color = top.darkened(0.25)
	_env.ambient_light_color = amb
	_env.ambient_light_energy = lerpf(0.75, 0.6, night)
	_env.fog_light_color = fog
	_sun.light_color = sc
	_sun.light_energy = e
	_moon.light_energy = 0.45 * night
	var sun_e: float = sin((tod - 0.25) * TAU)
	var pitch: float = -(clampf(sun_e, 0.0, 1.0) * 58.0 + 8.0)
	var yaw: float = lerpf(-110.0, 70.0, clampf((tod - 0.25) / 0.5, 0.0, 1.0))
	_sun.rotation_degrees = Vector3(pitch, yaw, 0.0)
	var wt: Color = amb.lerp(sc, 0.55) * clampf(0.30 + e * 0.55, 0.2, 1.25)
	_water_mat.set_shader_parameter("light_tint", Vector3(wt.r, wt.g, wt.b))
	var oc: Color = Color(0.10, 0.42, 0.80) * wt
	oc.a = 1.0
	_far_mat.albedo_color = oc
	if terrain != null and terrain.imp_mat != null:
		terrain.imp_mat.set_shader_parameter("light_tint", Vector3(wt.r, wt.g, wt.b))
	var cc: Color = hor.lerp(Color(1, 1, 1), 0.5) * clampf(0.30 + e * 0.75, 0.28, 1.1)
	cc.a = 0.93
	_cloud_mat.albedo_color = cc
	_stars_mat.set_shader_parameter("night", night)
	var want_night: bool = night > 0.5
	if want_night != _petal_night:
		_petal_night = want_night
		_set_petal_mode(want_night)

func _follow(delta: float) -> void:
	if player == null:
		return
	var pp: Vector3 = player.global_position
	_stars.global_position = pp
	_far_ocean.global_position = Vector3(pp.x, -0.4, pp.z)
	_petals.global_position = pp + Vector3(0.0, 1.5 if _petal_night else 8.0, 0.0)
	for c in _clouds:
		var cm: MeshInstance3D = c as MeshInstance3D
		cm.position.x += delta * 1.6
		var dx: float = cm.position.x - pp.x
		if dx > 300.0:
			cm.position.x -= 600.0
		elif dx < -300.0:
			cm.position.x += 600.0
		var dz: float = cm.position.z - pp.z
		if dz > 300.0:
			cm.position.z -= 600.0
		elif dz < -300.0:
			cm.position.z += 600.0
	if _fire_light != null:
		var base: float = 0.7 + 1.1 * night
		_fire_light.light_energy = base * (1.0 + 0.12 * sin(_t * 17.0) + 0.10 * sin(_t * 7.3))
	if _beacon != null:
		_beacon.rotation.y += delta * 0.6
	_biome_t -= delta
	if _biome_t <= 0.0:
		_biome_t = 0.7
		var w: Vector4 = biome_vec(pp.x, pp.z)
		var nm: String = terrain.gen.biome_name(w, grove(pp.x, pp.z) * w.x)
		if nm != "" and nm != _biome_cur:
			_biome_cur = nm
			if state == "playing":
				hud.toast("منطقه‌ی جدید: " + nm, 3.0)

# ------------------------------------------------------------ clouds, petals
func _cloud_tex() -> ImageTexture:
	var w: int = 128
	var h: int = 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var blobs: Array = [Vector3(0.28, 0.56, 0.19), Vector3(0.44, 0.46, 0.25), Vector3(0.62, 0.50, 0.23), Vector3(0.78, 0.58, 0.17), Vector3(0.50, 0.62, 0.28)]
	for y in range(h):
		for x in range(w):
			var u: float = (float(x) + 0.5) / float(w)
			var v: float = (float(y) + 0.5) / float(h)
			var a: float = 0.0
			for bl in blobs:
				var b: Vector3 = bl
				var dx: float = u - b.x
				var dy: float = (v - b.y) * 2.0
				var d: float = sqrt(dx * dx + dy * dy) / b.z
				a = maxf(a, 1.0 - smoothstep(0.55, 1.0, d))
			a *= 1.0 - smoothstep(0.74, 0.82, v)
			var shade: float = 1.0 - v * 0.22
			img.set_pixel(x, y, Color(shade, shade, shade * 1.03, a))
	return ImageTexture.create_from_image(img)

func _build_clouds() -> void:
	_cloud_mat = StandardMaterial3D.new()
	_cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_cloud_mat.albedo_texture = _cloud_tex()
	_cloud_mat.disable_fog = true
	_cloud_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(120.0, 60.0)
	q.material = _cloud_mat
	for i in range(16):
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s: float = _rng.randf_range(0.7, 1.7)
		mi.scale = Vector3(s, s, s)
		mi.position = Vector3(_rng.randf_range(-300.0, 300.0), _rng.randf_range(150.0, 220.0), _rng.randf_range(-300.0, 300.0))
		add_child(mi)
		_clouds.append(mi)

func _build_petals() -> void:
	_petals = CPUParticles3D.new()
	_petals.amount = 70
	_petals.lifetime = 10.0
	_petals.preprocess = 9.0
	_petals.mesh = FX.particle_mesh()
	_petals.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_petals.emission_box_extents = Vector3(16.0, 0.5, 16.0)
	_petals.direction = Vector3(0.0, -1.0, 0.0)
	_petals.spread = 30.0
	_petals.initial_velocity_min = 0.2
	_petals.initial_velocity_max = 0.7
	_petals.gravity = Vector3(0.4, -0.7, 0.2)
	_petals.scale_amount_min = 0.10
	_petals.scale_amount_max = 0.20
	_petals.color = Color(1.0, 0.72, 0.85, 0.85)
	_petals.local_coords = false
	_petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_petals)

func _set_petal_mode(is_night: bool) -> void:
	if is_night:
		_petals.color = Color(1.0, 0.95, 0.50, 0.9)
		_petals.gravity = Vector3(0.0, 0.05, 0.0)
		_petals.direction = Vector3(0.0, 1.0, 0.0)
		_petals.spread = 180.0
		_petals.scale_amount_min = 0.07
		_petals.scale_amount_max = 0.13
	else:
		_petals.color = Color(1.0, 0.72, 0.85, 0.85)
		_petals.gravity = Vector3(0.4, -0.7, 0.2)
		_petals.direction = Vector3(0.0, -1.0, 0.0)
		_petals.spread = 30.0
		_petals.scale_amount_min = 0.10
		_petals.scale_amount_max = 0.20

# ------------------------------------------------------------ camp (torii gate, lanterns, campfire)
func _prim(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, outline: float = 0.04, emission: Color = Color(0, 0, 0), energy: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m: ShaderMaterial = TOON.mat(color, null, false, emission, energy)
	if outline > 0.0:
		m.next_pass = TOON.outline(outline)
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

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

func _build_camp() -> void:
	var camp := Node3D.new()
	add_child(camp)
	var red: Color = Color(0.88, 0.18, 0.22)
	var dark: Color = Color(0.13, 0.10, 0.17)
	var gh: float = height(0.0, GATE_Z)
	for sx in [-2.6, 2.6]:
		_prim(camp, _cyl(0.28, 0.33, 5.2), red, Vector3(float(sx), gh + 2.6, GATE_Z))
	_prim(camp, _box(6.4, 0.32, 0.42), red, Vector3(0.0, gh + 4.3, GATE_Z))
	_prim(camp, _box(9.4, 0.46, 0.8), red, Vector3(0.0, gh + 5.5, GATE_Z))
	_prim(camp, _box(10.0, 0.22, 1.0), dark, Vector3(0.0, gh + 5.86, GATE_Z))
	_prim(camp, _box(0.8, 0.9, 0.14), Color(1.0, 0.82, 0.35), Vector3(0.0, gh + 4.9, GATE_Z), Vector3.ZERO, 0.03, Color(1.0, 0.8, 0.3), 0.5)
	# stone lanterns
	for lx in [-5.5, 5.5]:
		var x: float = float(lx)
		var lh: float = height(x, -5.0)
		_prim(camp, _cyl(0.30, 0.42, 0.9), Color(0.62, 0.62, 0.72), Vector3(x, lh + 0.45, -5.0))
		_prim(camp, _box(0.72, 0.62, 0.72), Color(1.0, 0.86, 0.5), Vector3(x, lh + 1.2, -5.0), Vector3.ZERO, 0.03, Color(1.0, 0.7, 0.3), 1.6)
		_prim(camp, _cyl(0.0, 0.75, 0.5, 4), Color(0.55, 0.55, 0.66), Vector3(x, lh + 1.75, -5.0), Vector3(0.0, 45.0, 0.0))
	# campfire
	var fx: float = 4.5
	var fz: float = 3.5
	var fh: float = height(fx, fz)
	var fire := Node3D.new()
	fire.position = Vector3(fx, fh, fz)
	camp.add_child(fire)
	for k in range(4):
		var a: float = float(k) * PI * 0.5
		_prim(fire, _cyl(0.10, 0.10, 1.1, 6), Color(0.42, 0.26, 0.16), Vector3(cos(a) * 0.35, 0.18, sin(a) * 0.35), Vector3(0.0, rad_to_deg(-a), 70.0), 0.025)
	var flame := CPUParticles3D.new()
	flame.amount = 16
	flame.lifetime = 0.9
	flame.mesh = FX.particle_mesh()
	flame.direction = Vector3.UP
	flame.spread = 12.0
	flame.initial_velocity_min = 0.6
	flame.initial_velocity_max = 1.4
	flame.gravity = Vector3(0.0, 1.0, 0.0)
	flame.scale_amount_min = 0.30
	flame.scale_amount_max = 0.55
	flame.color = Color(1.0, 0.62, 0.22, 0.95)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	flame.color_ramp = ramp
	flame.position = Vector3(0.0, 0.5, 0.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.add_child(flame)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.62, 0.32)
	_fire_light.omni_range = 11.0
	_fire_light.light_energy = 1.0
	_fire_light.position = Vector3(0.0, 1.2, 0.0)
	fire.add_child(_fire_light)

# ------------------------------------------------------------ spawning
func _slope_ok(x: float, z: float, min_ny: float) -> bool:
	var n: Vector3 = Vector3(height(x - 1.5, z) - height(x + 1.5, z), 3.0, height(x, z - 1.5) - height(x, z + 1.5)).normalized()
	return n.y >= min_ny

func _biome_spot(biome: int, placed: Array) -> Vector3:
	var gen = terrain.gen
	for tries in range(300):
		var x: float = 0.0
		var z: float = 0.0
		var a: float = _rng.randf() * TAU
		if biome == 4:
			var rg: float = _rng.randf_range(5.0, 32.0)
			x = gen.GROVE.x + cos(a) * rg
			z = gen.GROVE.y + sin(a) * rg
		else:
			var rr: float = _rng.randf_range(45.0, 400.0)
			x = cos(a) * rr
			z = sin(a) * rr
			var w: Vector4 = biome_vec(x, z)
			var wv: float = w.x
			if biome == 1:
				wv = w.y
			elif biome == 2:
				wv = w.z
			elif biome == 3:
				wv = w.w
			if wv < 0.75:
				continue
		var h: float = height(x, z)
		if h < 2.2 or h > 52.0:
			continue
		if not _slope_ok(x, z, 0.82):
			continue
		var p: Vector3 = Vector3(x, h, z)
		var ok: bool = true
		for q in placed:
			if (q as Vector3).distance_to(p) < 45.0:
				ok = false
				break
		if ok:
			return p
	return Vector3(40.0 + float(placed.size()) * 12.0, height(40.0, 0.0), 20.0)

func _spawn_crystals() -> void:
	var plan: Array = [0, 0, 1, 1, 2, 2, 3, 3, 4, 1]
	var placed: Array = []
	for b in plan:
		var p: Vector3 = _biome_spot(int(b), placed)
		placed.append(p)
		var cr = CRYSTAL.new()
		cr.position = p
		actors.add_child(cr)
		cr.collected.connect(_on_crystal)

func _enemy_spot(pp: Vector3) -> Vector3:
	for tries in range(30):
		var a: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(38.0, 70.0)
		var x: float = pp.x + cos(a) * r
		var z: float = pp.z + sin(a) * r
		if Vector2(x, z).length() < 32.0:
			continue
		if not terrain.has_collision_at(x, z):
			continue
		var h: float = height(x, z)
		if h < 1.5 or h > 70.0:
			continue
		if not _slope_ok(x, z, 0.7):
			continue
		return Vector3(x, h, z)
	return Vector3(0.0, -100.0, 0.0)

func _spawn_enemy_at(p: Vector3) -> void:
	var w: Vector4 = biome_vec(p.x, p.z)
	var zr: float = 0.15 + 0.45 * night + 0.2 * (w.w + w.z)
	if _rng.randf() < zr:
		var z = ZOMBIE.new()
		z.position = p + Vector3(0.0, 1.0, 0.0)
		actors.add_child(z)
		z.died.connect(_on_enemy_died)
		return
	var kind: int = 0
	if w.z > 0.5:
		kind = 2 if _rng.randf() < 0.75 else 0
	elif w.w > 0.5:
		kind = 1
	elif w.y > 0.5:
		kind = 1 if _rng.randf() < 0.45 else 0
	else:
		kind = 0 if _rng.randf() < 0.75 else 1
	var s = SLIME.new()
	s.kind = kind
	s.position = p + Vector3(0.0, 0.6, 0.0)
	actors.add_child(s)
	s.died.connect(_on_enemy_died)

func _enemy_tick() -> void:
	if player == null:
		return
	var pp: Vector3 = player.global_position
	var alive: int = 0
	for e in get_tree().get_nodes_in_group("enemy"):
		var en: Node3D = e as Node3D
		if en == null or bool(en.get("dead")):
			continue
		if Vector2(en.global_position.x - pp.x, en.global_position.z - pp.z).length() > 100.0:
			en.queue_free()
		else:
			alive += 1
	for k in range(3):
		if alive >= MAX_ENEMIES:
			break
		var p: Vector3 = _enemy_spot(pp)
		if p.y < -50.0:
			break
		_spawn_enemy_at(p)
		alive += 1

func _on_crystal() -> void:
	collected += 1
	hud.set_counts(collected, kills)
	if collected >= CRYSTALS_TOTAL:
		hud.toast("همه‌ی کریستال‌ها رو جمع کردی! برو سمت دروازه‌ی نورانی ✨", 7.0)
		_spawn_beacon()
	else:
		hud.toast("کریستال پیدا شد!  " + FX.fa(collected) + " / " + FX.fa(CRYSTALS_TOTAL), 2.0)

func _on_enemy_died() -> void:
	kills += 1
	hud.set_counts(collected, kills)

func _spawn_beacon() -> void:
	if _beacon != null:
		return
	var gh: float = height(0.0, GATE_Z)
	_beacon = Node3D.new()
	_beacon.position = Vector3(0.0, gh, GATE_Z)
	_beacon.add_to_group("beacon")
	add_child(_beacon)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 1.4
	cm.height = 70.0
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/anime/beam.gdshader") as Shader
	bm.set_shader_parameter("height", 70.0)
	beam.material_override = bm
	beam.position = Vector3(0.0, 35.0, 0.0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.add_child(beam)
	var ring := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(7.0, 7.0)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rm.albedo_texture = FX.ring_tex()
	rm.albedo_color = Color(1.0, 0.85, 0.4, 0.9)
	rm.disable_fog = true
	rq.material = rm
	ring.mesh = rq
	ring.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	ring.position = Vector3(0.0, 0.15, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.add_child(ring)
	var sp := CPUParticles3D.new()
	sp.amount = 30
	sp.lifetime = 2.5
	sp.mesh = FX.particle_mesh()
	sp.direction = Vector3.UP
	sp.spread = 8.0
	sp.initial_velocity_min = 3.0
	sp.initial_velocity_max = 6.0
	sp.gravity = Vector3.ZERO
	sp.scale_amount_min = 0.12
	sp.scale_amount_max = 0.25
	sp.color = Color(1.0, 0.9, 0.5, 0.9)
	sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 1.0
	sp.local_coords = false
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.add_child(sp)
	FX.sfx(self, "pickup", 2.0, 0.8)

# ------------------------------------------------------------ states
func _on_start() -> void:
	state = "playing"
	menu.hide_all()
	player.start_play()
	hud.visible = true
	hud.input_enabled = true
	hud.reset_input()
	hud.set_counts(collected, kills)
	actors.process_mode = Node.PROCESS_MODE_INHERIT
	terrain.budget_us = 3500
	_enemy_tick()
	tod = 0.33
	_update_time()
	hud.toast("iko، به جزیره خوش اومدی! ۱۰ کریستال توی چهار منطقه‌ی جزیره پنهونه؛ نقشه‌ی کوچیک جهتشون رو نشون می‌ده.", 7.0)

func _on_pause() -> void:
	if state != "playing":
		return
	state = "paused"
	hud.reset_input()
	get_tree().paused = true
	menu.show_pause()

func _on_resume() -> void:
	get_tree().paused = false
	menu.hide_all()
	state = "playing"

func _on_restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_continue() -> void:
	if _beacon != null:
		_beacon.queue_free()
		_beacon = null
	menu.hide_all()
	state = "playing"
	hud.input_enabled = true
	actors.process_mode = Node.PROCESS_MODE_INHERIT

func _win() -> void:
	state = "won"
	hud.input_enabled = false
	hud.reset_input()
	actors.process_mode = Node.PROCESS_MODE_DISABLED
	FX.sfx(self, "victory", 0.0)
	FX.burst(self, player.global_position + Vector3(0.0, 1.5, 0.0), Color(1.0, 0.85, 0.45), 60, 9.0, 0.28, 1.4, 4.0)
	FX.burst(self, player.global_position + Vector3(0.0, 1.5, 0.0), Color(1.0, 0.55, 0.75), 50, 8.0, 0.25, 1.4, 4.0)
	FX.vibrate(120)
	var secs: int = int(game_time)
	var mm: String = FX.fa(secs / 60)
	var ss: String = FX.fa(secs % 60)
	if secs % 60 < 10:
		ss = FX.fa(0) + ss
	var txt: String = "کریستال‌ها: %s / %s\nشکست‌خورده‌ها: %s\nزمان: %s:%s" % [FX.fa(collected), FX.fa(CRYSTALS_TOTAL), FX.fa(kills), mm, ss]
	await get_tree().create_timer(1.6).timeout
	if state == "won":
		menu.show_victory(txt)

# ------------------------------------------------------------ settings
func _on_settings_changed() -> void:
	_gov_level = 0
	_apply_settings()

func _dbg_nature() -> String:
	if nature != null:
		return nature.debug_text() + " | "
	return ""

# Auto performance governor: if the game stays under ~26 fps for 6 s it lowers draw distance, plant
# density and 3D resolution one step at a time (it never raises them again until settings are changed).
func _governor(delta: float) -> void:
	if state != "playing" or not SET.auto_perf:
		return
	_gov_t += delta
	_gov_frames += 1
	if _gov_t < 2.5:
		return
	var fps: float = float(_gov_frames) / _gov_t
	_gov_t = 0.0
	_gov_frames = 0
	if fps < 40.0:
		_gov_low += 1
	else:
		_gov_low = 0
	if _gov_low >= 2 and _gov_level < 6:
		_gov_low = 0
		_gov_level += 1
		_apply_settings()

func _apply_settings() -> void:
	_sun.shadow_enabled = SET.shadows
	var vp: Viewport = get_viewport()
	var mobile: bool = OS.has_feature("mobile")
	if SET.quality == 0 or _gov_level >= 2:
		vp.msaa_3d = Viewport.MSAA_DISABLED
	elif SET.quality == 2 and not mobile:
		vp.msaa_3d = Viewport.MSAA_4X
	else:
		vp.msaa_3d = Viewport.MSAA_2X
	# 3D resolution (the HUD stays sharp): phones render the world a bit smaller
	var sc: float = 1.0
	if mobile:
		if SET.quality == 0:
			sc = 0.67
		elif SET.quality == 1:
			sc = 0.80
		sc = maxf(sc - 0.05 * float(_gov_level), 0.5)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = sc
	_env.glow_enabled = SET.quality >= 2
	_env.glow_intensity = 0.55
	_env.glow_bloom = 0.12
	_env.adjustment_enabled = SET.quality >= 2
	_env.adjustment_saturation = 1.15
	_env.adjustment_contrast = 1.05
	var gq: float = maxf(1.0 - 0.11 * float(_gov_level), 0.4)
	var gd: float = maxf(1.0 - 0.12 * float(_gov_level), 0.35)
	if nature != null:
		if SET.quality == 0:
			nature.Q = 0.6 * gq
			nature.DENSITY = 0.6 * gd
		elif SET.quality == 1:
			nature.Q = 0.8 * gq
			nature.DENSITY = 0.85 * gd
		else:
			nature.Q = 1.0 * gq
			nature.DENSITY = 1.0 * gd
		nature.refresh()
	if terrain != null:
		var qf: float = 1.0
		if SET.quality == 0:
			terrain.dist_scale = 0.55
			qf = 0.6
		elif SET.quality == 1:
			terrain.dist_scale = 0.8
			qf = 0.8
		else:
			terrain.dist_scale = 1.0
		terrain.dist_scale *= gq
		if terrain.imp_mat != null:
			if nature != null:
				var tf: Vector2 = nature.tree_fade()
				terrain.imp_mat.set_shader_parameter("fade_in_start", tf.x)
				terrain.imp_mat.set_shader_parameter("fade_in_end", tf.y)
			else:
				terrain.imp_mat.set_shader_parameter("fade_in_start", 62.0 * qf * 0.60)
				terrain.imp_mat.set_shader_parameter("fade_in_end", 62.0 * qf * 0.94)
		if player != null:
			terrain.update(player.global_position)
		else:
			terrain.update(Vector3.ZERO)
	if audio != null:
		audio.apply_volumes()
