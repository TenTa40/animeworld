extends RefCounted
# Shared helpers: particles, floating numbers, shockwave rings, hit-stop, blob shadows, sfx, haptics.

const SET = preload("res://scripts/anime/settings.gd")

static var _dot_tex: Texture2D = null
static var _ring_tex: Texture2D = null
static var _quad_add: QuadMesh = null
static var _font: Font = null

static func fa(n: int) -> String:
	var d: Array = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]
	var out: String = ""
	for ch in str(n):
		if ch >= "0" and ch <= "9":
			out += str(d[int(ch)])
		else:
			out += ch
	return out

static func dot_tex() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_dot_tex = t
	return _dot_tex

static func ring_tex() -> Texture2D:
	if _ring_tex != null:
		return _ring_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.70, 0.86, 0.96, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_ring_tex = t
	return _ring_tex

static func particle_mesh() -> QuadMesh:
	if _quad_add != null:
		return _quad_add
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = dot_tex()
	m.disable_fog = true
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = m
	_quad_add = q
	return _quad_add

static func scene_of(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().current_scene

static func burst(node: Node, pos: Vector3, color: Color, count: int = 14, speed: float = 4.0, size: float = 0.14, life: float = 0.5, gravity: float = 6.0) -> void:
	var scene: Node = scene_of(node)
	if scene == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = count
	p.lifetime = life
	p.explosiveness = 0.95
	p.mesh = particle_mesh()
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	scene.get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)

static func dmg_number(node: Node, pos: Vector3, text: String, color: Color, size: int = 56) -> void:
	var scene: Node = scene_of(node)
	if scene == null:
		return
	if _font == null and ResourceLoader.exists("res://assets/fonts/ui_bold.ttf"):
		_font = load("res://assets/fonts/ui_bold.ttf") as Font
	var l := Label3D.new()
	l.text = text
	if _font != null:
		l.font = _font
	l.font_size = size
	l.pixel_size = 0.008
	l.outline_size = 14
	l.outline_modulate = Color(0.12, 0.05, 0.25)
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	scene.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y + 1.3, 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)

static func ring(node: Node, pos: Vector3, radius: float, color: Color, dur: float = 0.45) -> void:
	var scene: Node = scene_of(node)
	if scene == null:
		return
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = ring_tex()
	m.albedo_color = color
	m.disable_fog = true
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)
	mi.global_position = pos + Vector3(0.0, 0.12, 0.0)
	mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mi.scale = Vector3(0.2, 0.2, 0.2)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, radius, radius), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)

static func hit_stop(node: Node, dur: float = 0.06) -> void:
	if node == null or not node.is_inside_tree():
		return
	if Engine.time_scale < 0.5:
		return
	Engine.time_scale = 0.06
	node.get_tree().create_timer(dur, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0)

static func blob(parent: Node3D, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = dot_tex()
	m.albedo_color = Color(0.10, 0.05, 0.22, 0.55)
	m.render_priority = 1
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mi.position = Vector3(0.0, 0.05, 0.0)
	parent.add_child(mi)
	return mi

static func sfx(node: Node, nm: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if node == null or not node.is_inside_tree():
		return
	var a: Node = node.get_tree().get_first_node_in_group("audio")
	if a != null:
		a.call("play", nm, vol_db, pitch)

static func vibrate(ms: int) -> void:
	if SET.vibrate:
		Input.vibrate_handheld(ms)
