extends CanvasLayer
# Touch controls (left joystick, right look-drag, jump + attack buttons) and HUD.

const JOY_R := 90.0

var move: Vector2 = Vector2.ZERO
var look: Vector2 = Vector2.ZERO
var hp: float = 100.0
var cells: int = 0
var cells_total: int = 10
var kills: int = 0

var _touch_move: Vector2 = Vector2.ZERO
var _jump: bool = false
var _attack: bool = false
var _joy_id: int = -1
var _look_id: int = -1
var _joy_origin: Vector2 = Vector2.ZERO
var _joy_pos: Vector2 = Vector2.ZERO
var _pad: Control
var _flash: ColorRect
var _toast: Label
var _info: Label
var _font: Font
var _toast_tw: Tween = null

class Pad extends Control:
	var h = null
	func _draw() -> void:
		if h != null:
			h.paint(self)

func _ready() -> void:
	layer = 10
	_font = load("res://assets/fonts/ui_bold.ttf") as Font
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
	_info = _label(28, Control.PRESET_TOP_RIGHT)
	_info.offset_left = -520
	_info.offset_right = -24
	_info.offset_top = 20
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast = _label(32, Control.PRESET_CENTER_TOP)
	_toast.offset_left = -560
	_toast.offset_right = 560
	_toast.offset_top = 90
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
	var d: Array = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]
	var out: String = ""
	for ch in str(n):
		if ch >= "0" and ch <= "9":
			out += str(d[int(ch)])
		else:
			out += ch
	return out

func _refresh() -> void:
	_info.text = "باتری: %s / %s\nزامبی‌های شکست‌خورده: %s" % [fa(cells), fa(cells_total), fa(kills)]
	if _pad != null:
		_pad.queue_redraw()

func set_hp(v: float) -> void:
	hp = v
	_refresh()

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
	var j: bool = _jump
	_jump = false
	return j

func take_attack() -> bool:
	var a: bool = _attack
	_attack = false
	return a

# ---------------------------------------------------------------- layout
func _size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _atk_c() -> Vector2:
	var s: Vector2 = _size()
	return Vector2(s.x - 140.0, s.y - 150.0)

func _jump_c() -> Vector2:
	var s: Vector2 = _size()
	return Vector2(s.x - 300.0, s.y - 90.0)

func _input(event: InputEvent) -> void:
	var st: InputEventScreenTouch = event as InputEventScreenTouch
	var sd: InputEventScreenDrag = event as InputEventScreenDrag
	var ke: InputEventKey = event as InputEventKey
	if st != null:
		var p: Vector2 = st.position
		if st.pressed:
			if p.distance_to(_atk_c()) < 85.0:
				_attack = true
			elif p.distance_to(_jump_c()) < 70.0:
				_jump = true
			elif p.x < _size().x * 0.45 and _joy_id == -1:
				_joy_id = st.index
				_joy_origin = p
				_joy_pos = p
			elif _look_id == -1 and p.x >= _size().x * 0.45:
				_look_id = st.index
		else:
			if st.index == _joy_id:
				_joy_id = -1
				_touch_move = Vector2.ZERO
			if st.index == _look_id:
				_look_id = -1
		_pad.queue_redraw()
	elif sd != null:
		if sd.index == _joy_id:
			_joy_pos = sd.position
			var v: Vector2 = (_joy_pos - _joy_origin) / JOY_R
			if v.length() > 1.0:
				v = v.normalized()
			_touch_move = v
			_pad.queue_redraw()
		elif sd.index == _look_id:
			look += sd.relative * 0.005
	elif ke != null and ke.pressed and not ke.echo:
		if ke.keycode == KEY_SPACE:
			_jump = true
		elif ke.keycode == KEY_J or ke.keycode == KEY_F:
			_attack = true

func _process(delta: float) -> void:
	var kb: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		kb.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		kb.x += 1.0
	if Input.is_key_pressed(KEY_W):
		kb.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		kb.y += 1.0
	move = _touch_move if _touch_move.length() > 0.05 else kb.normalized()
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

func paint(c: Control) -> void:
	# health bar
	c.draw_rect(Rect2(24, 24, 304, 34), Color(0.05, 0.03, 0.12, 0.7))
	c.draw_rect(Rect2(28, 28, 296.0 * clampf(hp / 100.0, 0.0, 1.0), 26), Color(0.95, 0.3, 0.45))
	# joystick
	if _joy_id != -1:
		c.draw_circle(_joy_origin, JOY_R, Color(1, 1, 1, 0.12))
		c.draw_circle(_joy_origin + (_joy_pos - _joy_origin).limit_length(JOY_R), 38.0, Color(1, 1, 1, 0.4))
	# buttons
	var a: Vector2 = _atk_c()
	c.draw_circle(a, 82.0, Color(0.95, 0.35, 0.4, 0.45))
	c.draw_arc(a, 82.0, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 4.0)
	c.draw_line(a + Vector2(-30, 30), a + Vector2(30, -30), Color(1, 1, 1, 0.9), 8.0)
	var j: Vector2 = _jump_c()
	c.draw_circle(j, 66.0, Color(0.35, 0.7, 0.95, 0.45))
	c.draw_arc(j, 66.0, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 4.0)
	c.draw_colored_polygon(PackedVector2Array([j + Vector2(0, -28), j + Vector2(26, 14), j + Vector2(-26, 14)]), Color(1, 1, 1, 0.9))
