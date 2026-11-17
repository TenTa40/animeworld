extends CanvasLayer
# Full-screen loading screen with real progress while the world is built.

const FX = preload("res://scripts/anime/fx.gd")

const TIPS := [
	"توی هوا دکمه‌ی پرش رو نگه دار تا با گلایدر پرواز کنی.",
	"کریستال‌ها توی چهار منطقه‌ی جزیره پنهونن؛ مینی‌مپ جهتشون رو نشون می‌ده.",
	"جاخالی چند لحظه تو رو شکست‌ناپذیر می‌کنه.",
	"اولتی (Q) رو با ضربه زدن به دشمن‌ها پر کن.",
	"شب‌ها زامبی‌ها بیشتر می‌شن؛ کنار آتیش اردوگاه امن‌تری.",
	"قلب‌های صورتی که از دشمن‌ها می‌افتن، جونت رو پر می‌کنن.",
	"توی دریاچه‌ها می‌تونی شنا کنی.",
]

class Bar extends Control:
	var h = null
	func _draw() -> void:
		if h != null:
			h.paint_bar(self)

class Spin extends Control:
	var h = null
	func _draw() -> void:
		if h != null:
			h.paint_spin(self)

var _target: float = 0.0
var _shown: float = 0.0
var _t: float = 0.0
var _tip_t: float = 0.0
var _tip_i: int = 0
var _font: Font
var _root: Control
var _status: Label
var _pct: Label
var _tip: Label
var _bar: Control
var _spin: Control
var _sb_bg: StyleBoxFlat
var _sb_fill: StyleBoxFlat
var _finishing: bool = false

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("loading")
	_font = load("res://assets/fonts/ui_bold.ttf") as Font
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.07, 0.05, 0.22), Color(0.36, 0.18, 0.48), Color(0.96, 0.52, 0.56)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(0.0, 1.0)
	gt.width = 4
	gt.height = 256
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var title: Label = _label("جزیره‌ی آرام", 96, Color(1.0, 0.93, 0.97))
	_root.add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -600.0
	title.offset_right = 600.0
	title.offset_top = 36.0
	title.offset_bottom = 170.0
	var sp := Spin.new()
	sp.h = self
	_spin = sp
	_spin.custom_minimum_size = Vector2(160.0, 160.0)
	_spin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_spin)
	_spin.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_spin.offset_left = -80.0
	_spin.offset_right = 80.0
	_spin.offset_top = -110.0
	_spin.offset_bottom = 50.0
	_status = _label("", 30, Color(1, 1, 1))
	_root.add_child(_status)
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_status.offset_left = -400.0
	_status.offset_right = 400.0
	_status.offset_top = 70.0
	_status.offset_bottom = 120.0
	var br := Bar.new()
	br.h = self
	_bar = br
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_bar.offset_left = -260.0
	_bar.offset_right = 260.0
	_bar.offset_top = 130.0
	_bar.offset_bottom = 152.0
	_pct = _label("۰٪", 26, Color(1.0, 0.9, 0.7))
	_root.add_child(_pct)
	_pct.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pct.offset_left = -100.0
	_pct.offset_right = 100.0
	_pct.offset_top = 158.0
	_pct.offset_bottom = 200.0
	_tip = _label("", 24, Color(1.0, 0.9, 0.95))
	_root.add_child(_tip)
	_tip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tip.offset_left = -560.0
	_tip.offset_right = 560.0
	_tip.offset_top = -86.0
	_tip.offset_bottom = -30.0
	_tip_i = randi() % TIPS.size()
	_tip.text = "نکته: " + str(TIPS[_tip_i])
	_sb_bg = StyleBoxFlat.new()
	_sb_bg.bg_color = Color(0.05, 0.03, 0.14, 0.7)
	_sb_bg.set_corner_radius_all(11)
	_sb_bg.border_color = Color(1, 1, 1, 0.8)
	_sb_bg.set_border_width_all(2)
	_sb_fill = StyleBoxFlat.new()
	_sb_fill.bg_color = Color(1.0, 0.72, 0.45)
	_sb_fill.set_corner_radius_all(8)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.14, 0.05, 0.28))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func set_progress(p: float, text: String) -> void:
	_target = maxf(_target, clampf(p, 0.0, 1.0))
	if _status != null:
		_status.text = text

func _process(delta: float) -> void:
	_t += delta
	_shown = lerpf(_shown, _target, 1.0 - exp(-5.0 * delta))
	if _pct != null:
		_pct.text = FX.fa(int(round(_shown * 100.0))) + "٪"
	_tip_t += delta
	if _tip_t > 3.6 and _tip != null:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		_tip.text = "نکته: " + str(TIPS[_tip_i])
	if _spin != null:
		_spin.queue_redraw()
	if _bar != null:
		_bar.queue_redraw()

func paint_bar(c: Control) -> void:
	var w: float = c.size.x
	var h: float = c.size.y
	c.draw_style_box(_sb_bg, Rect2(0.0, 0.0, w, h))
	var fw: float = (w - 6.0) * clampf(_shown, 0.0, 1.0)
	if fw > 4.0:
		c.draw_style_box(_sb_fill, Rect2(3.0, 3.0, fw, h - 6.0))
		c.draw_circle(Vector2(3.0 + fw, h * 0.5), h * 0.9, Color(1.0, 0.85, 0.6, 0.25))

func paint_spin(c: Control) -> void:
	var ctr: Vector2 = c.size * 0.5
	c.draw_circle(ctr, 64.0, Color(1.0, 0.75, 0.85, 0.10))
	c.draw_arc(ctr, 62.0, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 2.0)
	for k in range(3):
		var a: float = _t * 1.8 + float(k) * TAU / 3.0
		c.draw_circle(ctr + Vector2(cos(a), sin(a)) * 62.0, 6.0, Color(1.0, 0.9, 0.6, 0.95))
	var wv: float = absf(cos(_t * 1.6)) * 0.8 + 0.2
	var s: float = 46.0
	var pts := PackedVector2Array([ctr + Vector2(0.0, -s), ctr + Vector2(s * 0.55 * wv, 0.0), ctr + Vector2(0.0, s), ctr + Vector2(-s * 0.55 * wv, 0.0)])
	c.draw_colored_polygon(pts, Color(0.55, 0.88, 1.0, 0.95))
	c.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(1, 1, 1, 0.95), 3.0)

func finish() -> void:
	if _finishing:
		return
	_finishing = true
	_target = 1.0
	await get_tree().create_timer(0.6).timeout
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.7)
	await tw.finished
	queue_free()
