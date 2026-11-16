extends CanvasLayer
# Title screen, pause menu, settings and victory screen (all built in code).

const SET = preload("res://scripts/anime/settings.gd")
const FX = preload("res://scripts/anime/fx.gd")

signal start_pressed
signal resume_pressed
signal restart_pressed
signal continue_pressed
signal settings_changed

var _font: Font
var _title: Control
var _pause: Control
var _settings: Control
var _victory: Control
var _vic_text: Label
var _rows: Dictionary = {}
var _settings_back: String = "title"

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load("res://assets/fonts/ui_bold.ttf") as Font
	_build_title()
	_build_pause()
	_build_settings()
	_build_victory()
	hide_all()

# ------------------------------------------------------------ helpers
func _full() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(c)
	return c

func _grad(top_a: float, bottom_a: float) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.02, 0.12, top_a))
	g.set_color(1, Color(0.04, 0.02, 0.12, bottom_a))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	t.width = 4
	t.height = 256
	var tr := TextureRect.new()
	tr.texture = t
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.16, 0.06, 0.30))
	l.add_theme_constant_override("outline_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _btn(text: String, w: float, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 74.0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 32)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(str(key), Color(1, 1, 1))
	var base: Color = Color(1.0, 0.42, 0.62, 0.96) if primary else Color(0.14, 0.11, 0.30, 0.88)
	var normal := _style(base)
	var pressed := _style(base.lightened(0.25))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	b.pressed.connect(func() -> void: FX.sfx(self, "click", -4.0))
	return b

func _style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(30)
	sb.border_color = Color(1, 1, 1, 0.9)
	sb.set_border_width_all(3)
	sb.content_margin_left = 28.0
	sb.content_margin_right = 28.0
	return sb

func _vbox(parent: Control, w: float) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(w, 0.0)
	vb.add_theme_constant_override("separation", 18)
	cc.add_child(vb)
	return vb

# ------------------------------------------------------------ screens
func _build_title() -> void:
	_title = _full()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(_grad(0.55, 0.0))
	var bottom: TextureRect = _grad(0.0, 0.7)
	_title.add_child(bottom)
	var name_l: Label = _label("جزیره‌ی آرام", 112, Color(1.0, 0.93, 0.97))
	_title.add_child(name_l)
	name_l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	name_l.offset_left = -640.0
	name_l.offset_right = 640.0
	name_l.offset_top = 26.0
	name_l.offset_bottom = 170.0
	var sub: Label = _label("ماجراجویی انیمه‌ای · کریستال‌ها رو پیدا کن", 32, Color(1.0, 0.82, 0.9))
	_title.add_child(sub)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.offset_left = -640.0
	sub.offset_right = 640.0
	sub.offset_top = 150.0
	sub.offset_bottom = 205.0
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 28)
	_title.add_child(hb)
	hb.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hb.offset_left = -400.0
	hb.offset_right = 400.0
	hb.offset_top = -140.0
	hb.offset_bottom = -50.0
	var start: Button = _btn("شروع ماجراجویی", 380.0, true)
	var sett: Button = _btn("تنظیمات", 240.0, false)
	hb.add_child(start)
	hb.add_child(sett)
	start.pressed.connect(func() -> void: start_pressed.emit())
	sett.pressed.connect(func() -> void: _open_settings("title"))

func _build_pause() -> void:
	_pause = _full()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.10, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.add_child(dim)
	var vb: VBoxContainer = _vbox(_pause, 460.0)
	vb.add_child(_label("مکث", 90, Color(1.0, 0.93, 0.97)))
	var r: Button = _btn("ادامه", 460.0, true)
	var s: Button = _btn("تنظیمات", 460.0, false)
	var q: Button = _btn("شروع دوباره", 460.0, false)
	vb.add_child(r)
	vb.add_child(s)
	vb.add_child(q)
	r.pressed.connect(func() -> void: resume_pressed.emit())
	s.pressed.connect(func() -> void: _open_settings("pause"))
	q.pressed.connect(func() -> void: restart_pressed.emit())

func _build_settings() -> void:
	_settings = _full()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.10, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings.add_child(dim)
	var vb: VBoxContainer = _vbox(_settings, 640.0)
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(_label("تنظیمات", 70, Color(1.0, 0.93, 0.97)))
	for key in ["shadows", "quality", "music", "sfx", "vibrate"]:
		var b: Button = _btn("", 640.0, false)
		b.custom_minimum_size = Vector2(640.0, 62.0)
		b.add_theme_font_size_override("font_size", 28)
		var k: String = str(key)
		b.pressed.connect(func() -> void: _cycle(k))
		vb.add_child(b)
		_rows[k] = b
	var back: Button = _btn("بازگشت", 640.0, true)
	back.custom_minimum_size = Vector2(640.0, 66.0)
	back.pressed.connect(func() -> void: _close_settings())
	vb.add_child(back)

func _build_victory() -> void:
	_victory = _full()
	var dim := ColorRect.new()
	dim.color = Color(0.10, 0.05, 0.20, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_victory.add_child(dim)
	var vb: VBoxContainer = _vbox(_victory, 640.0)
	vb.add_child(_label("ماجراجویی تموم شد!", 84, Color(1.0, 0.9, 0.5)))
	_vic_text = _label("", 34, Color(1, 1, 1))
	vb.add_child(_vic_text)
	var c: Button = _btn("ادامه‌ی گشت‌وگذار", 560.0, true)
	var r: Button = _btn("شروع دوباره", 560.0, false)
	vb.add_child(c)
	vb.add_child(r)
	c.pressed.connect(func() -> void: continue_pressed.emit())
	r.pressed.connect(func() -> void: restart_pressed.emit())

# ------------------------------------------------------------ settings logic
func _on_off(v: bool) -> String:
	return "روشن" if v else "خاموش"

func _pct(v: float) -> String:
	if v < 0.01:
		return "خاموش"
	return FX.fa(int(round(v * 100.0))) + "٪"

func _refresh_settings() -> void:
	var q: Array = ["کم", "متوسط", "زیاد"]
	(_rows["shadows"] as Button).text = "سایه‌ها: " + _on_off(SET.shadows)
	(_rows["quality"] as Button).text = "کیفیت: " + str(q[SET.quality])
	(_rows["music"] as Button).text = "موسیقی: " + _pct(SET.music)
	(_rows["sfx"] as Button).text = "جلوه‌های صوتی: " + _pct(SET.sfx)
	(_rows["vibrate"] as Button).text = "لرزش: " + _on_off(SET.vibrate)

func _cycle(key: String) -> void:
	match key:
		"shadows":
			SET.shadows = not SET.shadows
		"quality":
			SET.quality = (SET.quality + 1) % 3
		"music":
			SET.music = _next_of([0.0, 0.3, 0.6, 1.0], SET.music)
		"sfx":
			SET.sfx = _next_of([0.0, 0.5, 1.0], SET.sfx)
		"vibrate":
			SET.vibrate = not SET.vibrate
			if SET.vibrate:
				Input.vibrate_handheld(40)
	SET.save_cfg()
	_refresh_settings()
	settings_changed.emit()

func _next_of(steps: Array, cur: float) -> float:
	var idx: int = 0
	for i in range(steps.size()):
		if absf(float(steps[i]) - cur) < 0.05:
			idx = i
	return float(steps[(idx + 1) % steps.size()])

func _open_settings(from: String) -> void:
	_settings_back = from
	_refresh_settings()
	_title.visible = false
	_pause.visible = false
	_settings.visible = true

func _close_settings() -> void:
	_settings.visible = false
	if _settings_back == "pause":
		_pause.visible = true
	else:
		_title.visible = true

# ------------------------------------------------------------ public
func hide_all() -> void:
	_title.visible = false
	_pause.visible = false
	_settings.visible = false
	_victory.visible = false

func show_title() -> void:
	hide_all()
	_title.visible = true

func show_pause() -> void:
	hide_all()
	_pause.visible = true

func show_victory(text: String) -> void:
	hide_all()
	_vic_text.text = text
	_victory.visible = true
