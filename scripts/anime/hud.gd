extends CanvasLayer
# Touch HUD: joystick, look-drag, action buttons with cooldown rings, minimap, HP bar, quest text.

const FX = preload("res://scripts/anime/fx.gd")
signal pause_pressed

const JOY_R := 90.0

var move: Vector2 = Vector2.ZERO
var look: Vector2 = Vector2.ZERO
var hp: float = 100.0
var energy: float = 0.0
var skill_cd: float = 0.0
var dash_cd: float = 0.0
var cells: int = 0
var cells_total: int = 10
var kills: int = 0
var glide_held: bool = false
var input_enabled: bool = false

var _touch_move: Vector2 = Vector2.ZERO
var _jump: bool = false
var _attack: bool = false
var _dash: bool = false
var _skill: bool = false
var _burst: bool = false
var _key_glide: bool = false
var _touch_glide: bool = false
var _joy_id: int = -1
var _look_id: int = -1
var _joy_origin: Vector2 = Vector2.ZERO
var _joy_pos: Vector2 = Vector2.ZERO
var _btn_touch: Dictionary = {}
var _pad: Control
var _flash: ColorRect
var _toast: Label
var _info: Label
var _font: Font
var _toast_tw: Tween = null
var _player = null
var _t: float = 0.0
var _sb_bg: StyleBoxFlat
var _sb_fill: StyleBoxFlat
var _near_t: float = 0.0
var _near_txt: String = ""

class Pad extends Control:
	var h = null
	func _draw() -> void:
		if h != null:
			h.paint(self)

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load("res://assets/fonts/ui_bold.ttf") as Font
	_sb_bg = StyleBoxFlat.new()
	_sb_bg.bg_color = Color(0.05, 0.03, 0.14, 0.72)
	_sb_bg.set_corner_radius_all(14)
	_sb_bg.border_color = Color(1, 1, 1, 0.8)
	_sb_bg.set_border_width_all(2)
	_sb_fill = StyleBoxFlat.new()
	_sb_fill.bg_color = Color(0.4, 0.9, 0.55)
	_sb_fill.set_corner_radius_all(10)
	var pd = Pad.new()
	pd.h = self
	_pad = pd
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pad)
	_flash = ColorRect.new()
	_flash.color = Color(0.9, 0.05, 0.05, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_info = _label(26, Control.PRESET_CENTER_TOP)
	_info.offset_left = -400
	_info.offset_right = 400
	_info.offset_top = 52
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast = _label(30, Control.PRESET_CENTER_TOP)
	_toast.offset_left = -560
	_toast.offset_right = 560
	_toast.offset_top = 110
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_refresh()

func _label(sz: int, preset: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.2))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.set_anchors_and_offsets_preset(preset)
	return l

func fa(n: int) -> String:
	return FX.fa(n)

func _refresh() -> void:
	_info.text = "کریستال‌ها: %s / %s    ·    شکست‌خورده‌ها: %s" % [fa(cells), fa(cells_total), fa(kills)]

func set_hp(v: float) -> void:
	hp = v

func set_counts(c: int, k: int) -> void:
	cells = c
	kills = k
	_refresh()

func flash() -> void:
	_flash.color.a = 0.35
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.4)

func toast(text: String, secs: float = 3.5) -> void:
	_toast.text = text
	if _toast_tw != null:
		_toast_tw.kill()
	_toast.modulate.a = 1.0
	_toast_tw = create_tween()
	_toast_tw.tween_interval(secs)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.6)

func take_jump() -> bool:
	var v: bool = _jump
	_jump = false
	return v

func take_attack() -> bool:
	var v: bool = _attack
	_attack = false
	return v

func take_dash() -> bool:
	var v: bool = _dash
	_dash = false
	return v

func take_skill() -> bool:
	var v: bool = _skill
	_skill = false
	return v

func take_burst() -> bool:
	var v: bool = _burst
	_burst = false
	return v

func reset_input() -> void:
	move = Vector2.ZERO
	look = Vector2.ZERO
	_touch_move = Vector2.ZERO
	_joy_id = -1
	_look_id = -1
	_btn_touch.clear()
	_touch_glide = false
	_key_glide = false
	_jump = false
	_attack = false
	_dash = false
	_skill = false
	_burst = false

# ---------------------------------------------------------------- layout
func _size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _u() -> float:
	return clampf(_size().y / 720.0, 0.75, 1.6)

func _btn_pos(nm: String) -> Vector2:
	var s: Vector2 = _size()
	var u: float = _u()
	var a: Vector2 = Vector2(s.x - 150.0 * u, s.y - 140.0 * u)
	match nm:
		"attack":
			return a
		"jump":
			return a + Vector2(-190.0, 40.0) * u
		"skill":
			return a + Vector2(-190.0, -100.0) * u
		"burst":
			return a + Vector2(-70.0, -185.0) * u
		"dash":
			return a + Vector2(-330.0, -10.0) * u
		"pause":
			return Vector2(s.x - 56.0 * u, 52.0 * u)
	return Vector2.ZERO

func _btn_r(nm: String) -> float:
	var u: float = _u()
	match nm:
		"attack":
			return 84.0 * u
		"jump":
			return 62.0 * u
		"skill":
			return 56.0 * u
		"burst":
			return 52.0 * u
		"dash":
			return 50.0 * u
		"pause":
			return 34.0 * u
	return 0.0

func _hit_button(p: Vector2) -> String:
	for nm in ["attack", "jump", "skill", "burst", "dash", "pause"]:
		if p.distance_to(_btn_pos(nm)) < _btn_r(nm) * 1.15:
			return nm
	return ""

func _press(nm: String) -> void:
	match nm:
		"attack":
			_attack = true
		"jump":
			_jump = true
			_touch_glide = true
		"dash":
			_dash = true
		"skill":
			_skill = true
		"burst":
			_burst = true
		"pause":
			pause_pressed.emit()

func _release(nm: String) -> void:
	if nm == "jump":
		_touch_glide = false

# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not input_enabled or get_tree().paused:
		return
	var st: InputEventScreenTouch = event as InputEventScreenTouch
	var sd: InputEventScreenDrag = event as InputEventScreenDrag
	var ke: InputEventKey = event as InputEventKey
	if st != null:
		var p: Vector2 = st.position
		if st.pressed:
			var hit: String = _hit_button(p)
			if hit != "":
				_btn_touch[st.index] = hit
				_press(hit)
			elif p.x < _size().x * 0.45 and _joy_id == -1:
				_joy_id = st.index
				_joy_origin = p
				_joy_pos = p
			elif _look_id == -1 and p.x >= _size().x * 0.45:
				_look_id = st.index
		else:
			if _btn_touch.has(st.index):
				_release(str(_btn_touch[st.index]))
				_btn_touch.erase(st.index)
			if st.index == _joy_id:
				_joy_id = -1
				_touch_move = Vector2.ZERO
			if st.index == _look_id:
				_look_id = -1
	elif sd != null:
		if sd.index == _joy_id:
			_joy_pos = sd.position
			var v: Vector2 = (_joy_pos - _joy_origin) / JOY_R
			if v.length() > 1.0:
				v = v.normalized()
			_touch_move = v
		elif sd.index == _look_id:
			look += sd.relative * 0.005
	elif ke != null and not ke.echo:
		if ke.pressed:
			if ke.keycode == KEY_SPACE:
				_jump = true
				_key_glide = true
			elif ke.keycode == KEY_J or ke.keycode == KEY_F:
				_attack = true
			elif ke.keycode == KEY_SHIFT or ke.keycode == KEY_K:
				_dash = true
			elif ke.keycode == KEY_E:
				_skill = true
			elif ke.keycode == KEY_Q:
				_burst = true
			elif ke.keycode == KEY_ESCAPE:
				pause_pressed.emit()
		else:
			if ke.keycode == KEY_SPACE:
				_key_glide = false

func _process(delta: float) -> void:
	_t += delta
	_near_t -= delta
	if _near_t <= 0.0:
		_near_t = 0.5
		_update_near()
	glide_held = _key_glide or _touch_glide
	var kb: Vector2 = Vector2.ZERO
	if input_enabled and not get_tree().paused:
		if Input.is_key_pressed(KEY_A):
			kb.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			kb.x += 1.0
		if Input.is_key_pressed(KEY_W):
			kb.y -= 1.0
		if Input.is_key_pressed(KEY_S):
			kb.y += 1.0
		var lk: Vector2 = Vector2.ZERO
		if Input.is_key_pressed(KEY_LEFT):
			lk.x -= 1.0
		if Input.is_key_pressed(KEY_RIGHT):
			lk.x += 1.0
		if Input.is_key_pressed(KEY_UP):
			lk.y -= 1.0
		if Input.is_key_pressed(KEY_DOWN):
			lk.y += 1.0
		look += lk * delta * 2.0
	move = _touch_move if _touch_move.length() > 0.05 else kb.normalized()
	if visible and _pad != null:
		_pad.queue_redraw()

# ---------------------------------------------------------------- drawing
func _pie(c: Control, ctr: Vector2, r: float, frac: float, col: Color) -> void:
	if frac <= 0.001:
		return
	var f: float = minf(frac, 0.999)
	var pts := PackedVector2Array()
	pts.append(ctr)
	var n: int = 28
	var a0: float = -PI * 0.5
	for i in range(n + 1):
		var a: float = a0 + TAU * f * float(i) / float(n)
		pts.append(ctr + Vector2(cos(a), sin(a)) * r)
	c.draw_colored_polygon(pts, col)

func _map_offset(wp: Vector3, ppos: Vector3, yaw: float, k: float, mr: float, clamp_edge: bool) -> Vector2:
	var d: Vector3 = wp - ppos
	d.y = 0.0
	var rt := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fw := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var v: Vector2 = Vector2(d.dot(rt), -d.dot(fw)) * k
	var lim: float = mr - 8.0
	if v.length() > lim:
		if clamp_edge:
			v = v.normalized() * lim
		else:
			return Vector2(INF, INF)
	return v

func _update_near() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var best: float = INF
	for n in get_tree().get_nodes_in_group("crystal"):
		var d: float = (n as Node3D).global_position.distance_to(_player.global_position)
		if d < best:
			best = d
	if is_inf(best):
		var bc: Node = get_tree().get_first_node_in_group("beacon")
		if bc != null:
			_near_txt = "دروازه: " + fa(int((bc as Node3D).global_position.distance_to(_player.global_position))) + " متر"
		else:
			_near_txt = ""
	else:
		_near_txt = "کریستال: " + fa(int(best)) + " متر"

func _paint_minimap(c: Control, u: float) -> void:
	var mr: float = 84.0 * u
	var mc: Vector2 = Vector2(24.0 * u + mr, 24.0 * u + mr)
	c.draw_circle(mc, mr, Color(0.06, 0.05, 0.16, 0.58))
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		c.draw_arc(mc, mr, 0.0, TAU, 48, Color(1, 1, 1, 0.85), 3.0 * u)
		return
	var yaw: float = float(_player.yaw)
	var ppos: Vector3 = _player.global_position
	var k: float = mr / 60.0
	c.draw_colored_polygon(PackedVector2Array([mc, mc + Vector2(-0.62, -1.0) * mr * 0.8, mc + Vector2(0.62, -1.0) * mr * 0.8]), Color(1, 1, 1, 0.10))
	for n in get_tree().get_nodes_in_group("heal"):
		var o0: Vector2 = _map_offset((n as Node3D).global_position, ppos, yaw, k, mr, false)
		if not is_inf(o0.x):
			c.draw_circle(mc + o0, 4.0 * u, Color(1.0, 0.6, 0.75, 0.95))
	for n in get_tree().get_nodes_in_group("enemy"):
		var en: Node3D = n as Node3D
		if en == null or bool(en.get("dead")):
			continue
		var o1: Vector2 = _map_offset(en.global_position, ppos, yaw, k, mr, false)
		if not is_inf(o1.x):
			c.draw_circle(mc + o1, 4.5 * u, Color(1.0, 0.3, 0.35, 0.95))
	for n in get_tree().get_nodes_in_group("crystal"):
		var o2: Vector2 = _map_offset((n as Node3D).global_position, ppos, yaw, k, mr, true)
		var q: Vector2 = mc + o2
		var s: float = 6.5 * u
		c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -s), q + Vector2(s * 0.7, 0), q + Vector2(0, s), q + Vector2(-s * 0.7, 0)]), Color(0.45, 0.9, 1.0, 1.0))
	for n in get_tree().get_nodes_in_group("beacon"):
		var o3: Vector2 = _map_offset((n as Node3D).global_position, ppos, yaw, k, mr, true)
		var g: Vector2 = mc + o3
		c.draw_circle(g, 9.0 * u, Color(1.0, 0.85, 0.35, 0.9))
		c.draw_arc(g, 12.0 * u, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 2.5 * u)
	# player arrow
	var a: float = 8.0 * u
	c.draw_colored_polygon(PackedVector2Array([mc + Vector2(0, -a * 1.3), mc + Vector2(a, a), mc + Vector2(0, a * 0.5), mc + Vector2(-a, a)]), Color(1, 1, 1, 1))
	# north marker
	var nm: Vector2 = _map_offset(ppos + Vector3(0, 0, -100.0), ppos, yaw, 1.0, 100.0, true)
	var nd: Vector2 = nm.normalized() * (mr - 12.0 * u)
	c.draw_string(_font, mc + nd + Vector2(-8.0 * u, 7.0 * u), "N", HORIZONTAL_ALIGNMENT_CENTER, 16.0 * u, int(18.0 * u), Color(1.0, 0.85, 0.5))
	c.draw_arc(mc, mr, 0.0, TAU, 48, Color(1, 1, 1, 0.85), 3.0 * u)
	if _near_txt != "":
		c.draw_string(_font, mc + Vector2(-mr, mr + 30.0 * u), _near_txt, HORIZONTAL_ALIGNMENT_CENTER, mr * 2.0, int(22.0 * u), Color(1, 1, 1, 0.95))

func _draw_btn(c: Control, nm: String, fill: Color) -> Vector2:
	var p: Vector2 = _btn_pos(nm)
	var r: float = _btn_r(nm)
	var down: bool = _btn_touch.values().has(nm)
	c.draw_circle(p, r, Color(fill.r, fill.g, fill.b, 0.66 if down else 0.44))
	c.draw_arc(p, r, 0.0, TAU, 40, Color(1, 1, 1, 0.85), 3.5)
	return p

func paint(c: Control) -> void:
	var s: Vector2 = _size()
	var u: float = _u()
	_paint_minimap(c, u)
	# hp bar
	var w: float = 360.0 * u
	var h: float = 26.0 * u
	var r := Rect2(s.x * 0.5 - w * 0.5, 16.0 * u, w, h)
	c.draw_style_box(_sb_bg, r)
	var ratio: float = clampf(hp / 100.0, 0.0, 1.0)
	if ratio > 0.01:
		_sb_fill.bg_color = Color(0.35, 0.9, 0.55).lerp(Color(1.0, 0.3, 0.42), 1.0 - ratio)
		c.draw_style_box(_sb_fill, Rect2(r.position + Vector2(4.0, 4.0) * u, Vector2((w - 8.0 * u) * ratio, h - 8.0 * u)))
	# joystick
	if _joy_id != -1:
		c.draw_circle(_joy_origin, JOY_R, Color(1, 1, 1, 0.12))
		c.draw_circle(_joy_origin + (_joy_pos - _joy_origin).limit_length(JOY_R), 38.0, Color(1, 1, 1, 0.4))
	var white: Color = Color(1, 1, 1, 0.95)
	# attack
	var a: Vector2 = _draw_btn(c, "attack", Color(0.95, 0.35, 0.42))
	c.draw_line(a + Vector2(-30, 30) * u, a + Vector2(30, -30) * u, white, 8.0 * u)
	c.draw_line(a + Vector2(-34, 8) * u, a + Vector2(-8, 34) * u, white, 6.0 * u)
	# jump
	var j: Vector2 = _draw_btn(c, "jump", Color(0.35, 0.7, 0.95))
	c.draw_colored_polygon(PackedVector2Array([j + Vector2(0, -26) * u, j + Vector2(26, 14) * u, j + Vector2(-26, 14) * u]), white)
	# dash
	var d: Vector2 = _draw_btn(c, "dash", Color(0.6, 0.55, 1.0))
	c.draw_polyline(PackedVector2Array([d + Vector2(-20, -18) * u, d + Vector2(0, 0), d + Vector2(-20, 18) * u]), white, 6.0 * u)
	c.draw_polyline(PackedVector2Array([d + Vector2(2, -18) * u, d + Vector2(22, 0), d + Vector2(2, 18) * u]), white, 6.0 * u)
	_pie(c, d, _btn_r("dash"), dash_cd, Color(0, 0, 0, 0.55))
	# skill
	var sk: Vector2 = _draw_btn(c, "skill", Color(0.4, 0.8, 1.0))
	c.draw_string(_font, sk + Vector2(-30.0 * u, 14.0 * u), "E", HORIZONTAL_ALIGNMENT_CENTER, 60.0 * u, int(44.0 * u), white)
	_pie(c, sk, _btn_r("skill"), skill_cd, Color(0, 0, 0, 0.55))
	# burst
	var b: Vector2 = _draw_btn(c, "burst", Color(1.0, 0.75, 0.3))
	var ef: float = clampf(energy / 100.0, 0.0, 1.0)
	if ef >= 1.0:
		c.draw_circle(b, _btn_r("burst") + 5.0 * u + sin(_t * 6.0) * 3.0 * u, Color(1.0, 0.85, 0.4, 0.28))
	else:
		c.draw_circle(b, _btn_r("burst"), Color(0, 0, 0, 0.35))
	c.draw_string(_font, b + Vector2(-30.0 * u, 14.0 * u), "Q", HORIZONTAL_ALIGNMENT_CENTER, 60.0 * u, int(44.0 * u), white)
	c.draw_arc(b, _btn_r("burst") + 7.0 * u, -PI * 0.5, -PI * 0.5 + TAU * ef, 48, Color(1.0, 0.85, 0.35, 1.0), 6.0 * u)
	# pause
	var pp: Vector2 = _draw_btn(c, "pause", Color(0.2, 0.15, 0.4))
	c.draw_rect(Rect2(pp + Vector2(-11, -13) * u, Vector2(7, 26) * u), white)
	c.draw_rect(Rect2(pp + Vector2(4, -13) * u, Vector2(7, 26) * u), white)
