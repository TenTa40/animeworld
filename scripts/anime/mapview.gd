extends Control
# Full-screen island map (opens when the minimap is tapped). Terrain is painted at runtime from the world generator,
# drawn on a Kenney cartography parchment with ink icons. Drag = pan, pinch / +- = zoom.

const IMG_N := 288
const HALF := 500.0
const SPAN := 1000.0
const ROWS_PER_FRAME := 3
const DIR := "res://assets/ui/map/"

var world = null
var gen = null
var font: Font = null
var tex: ImageTexture = null
var progress: float = 0.0
var ready_map: bool = false

var _img: Image
var _hs: PackedFloat32Array = PackedFloat32Array()
var _land: PackedColorArray = PackedColorArray()
var _row: int = 0
var _phase: int = 0
var _shade_row: int = 0
var _parch: Texture2D = null
var _icons: Dictionary = {}
var _marks: Array = []        # [Vector2 world, icon, size_mult]
var _labels: Array = []       # [Vector2 world, text]
var _canvas: Control = null
var _center: Vector2 = Vector2.ZERO
var _scale: float = 0.4
var _min_scale: float = 0.3
var _touches: Dictionary = {}
var _starts: Dictionary = {}
var _t_down: Dictionary = {}
var _pinch: float = 0.0
var _mouse_down: bool = false
var _mouse_moved: float = 0.0
var _t: float = 0.0

class Canvas extends Control:
	var h = null
	func _draw() -> void:
		if h != null:
			h._paint_map(self)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = load("res://assets/fonts/ui_bold.ttf") as Font
	_canvas = Canvas.new()
	(_canvas as Canvas).h = self
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	if ResourceLoader.exists(DIR + "parchment.jpg"):
		_parch = load(DIR + "parchment.jpg") as Texture2D
	for n in ["castleWide", "castleTall", "house", "houses", "houseChimney", "compass", "treePines", "treePine", "treePineTall", "rocksMountain", "rocksTall", "cactus", "cactusLarge", "tent", "campfire", "flag", "gate", "towerWatch", "well", "lake", "bridge"]:
		if ResourceLoader.exists(DIR + n + ".png"):
			_icons[n] = load(DIR + n + ".png")

func setup(w) -> void:
	world = w
	if w != null and w.get("terrain") != null:
		gen = w.terrain.gen

# ---------------------------------------------------------------- open / close
func open_map() -> void:
	if gen == null:
		return
	if tex == null and _phase == 0:
		_begin()
	var pl: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var pp: Vector2 = Vector2.ZERO
	if pl != null:
		pp = Vector2(pl.global_position.x, pl.global_position.z)
	_layout()
	_scale = clampf(_min_scale * 2.4, _min_scale, 1.6)
	_center = pp
	_clamp_view()
	visible = true
	get_tree().paused = true
	queue_redraw()

func close_map() -> void:
	visible = false
	get_tree().paused = false
	_touches.clear()
	_starts.clear()
	_t_down.clear()
	var h = get_parent()
	if h != null and h.has_method("reset_input"):
		h.reset_input()

func _begin() -> void:
	_img = Image.create(IMG_N, IMG_N, false, Image.FORMAT_RGBA8)
	_hs.resize(IMG_N * IMG_N)
	_land.resize(IMG_N * IMG_N)
	_row = 0
	_phase = 1
	progress = 0.0
	_labels = [
		[Vector2(110.0, -60.0), "شهر قلعه‌ی ابر"],
		[Vector2(0.0, -9.0), "دروازه‌ی آغاز"],
	]

# ---------------------------------------------------------------- layout
func _panel() -> Rect2:
	var s: Vector2 = get_viewport_rect().size
	return Rect2(s.x * 0.03, s.y * 0.04, s.x * 0.94, s.y * 0.92)

func _inner() -> Rect2:
	var p: Rect2 = _panel()
	var pad: float = minf(p.size.x, p.size.y) * 0.045
	return Rect2(p.position + Vector2(pad, pad), p.size - Vector2(pad, pad) * 2.0)

func _layout() -> void:
	var r: Rect2 = _inner()
	_canvas.position = r.position
	_canvas.size = r.size
	_min_scale = r.size.y / SPAN * 0.98

func _u() -> float:
	return clampf(minf(get_viewport_rect().size.x, get_viewport_rect().size.y) / 720.0, 0.7, 2.2)

func _btn_rect(nm: String) -> Rect2:
	var r: Rect2 = _inner()
	var u: float = _u()
	var sz: float = 64.0 * u
	match nm:
		"close":
			return Rect2(r.end.x - sz - 8.0 * u, r.position.y + 8.0 * u, sz, sz)
		"zin":
			return Rect2(r.end.x - sz - 8.0 * u, r.end.y - sz * 2.0 - 16.0 * u, sz, sz)
		"zout":
			return Rect2(r.end.x - sz - 8.0 * u, r.end.y - sz - 8.0 * u, sz, sz)
		"me":
			return Rect2(r.position.x + 8.0 * u, r.end.y - sz - 8.0 * u, sz, sz)
	return Rect2()

func _hit(p: Vector2) -> String:
	for nm in ["close", "zin", "zout", "me"]:
		if _btn_rect(nm).grow(6.0).has_point(p):
			return nm
	return ""

# ---------------------------------------------------------------- generation (spread over frames)
func _px_world(ix: int, iy: int) -> Vector2:
	return Vector2((float(ix) + 0.5) / float(IMG_N) * SPAN - HALF, (float(iy) + 0.5) / float(IMG_N) * SPAN - HALF)

func _base_col(h: float, w: Vector4, x: float, z: float) -> Color:
	var plains: Color = Color(0.76, 0.84, 0.54)
	var forest: Color = Color(0.50, 0.66, 0.42)
	var desert: Color = Color(0.94, 0.82, 0.56)
	var rock: Color = Color(0.74, 0.69, 0.63)
	var low: Color = forest.lerp(rock, smoothstep(26.0, 50.0, h))
	var c: Color = plains * w.x + forest * w.y + desert * w.z + low * w.w
	var tot: float = w.x + w.y + w.z + w.w
	if tot > 0.001:
		c = c / tot
	c = c.lerp(Color(0.97, 0.96, 0.93), smoothstep(52.0, 66.0, h))
	if gen.has_method("in_town") and gen.in_town(x, z, 0.0):
		c = c.lerp(Color(0.86, 0.80, 0.68), 0.85)
	return c

func _process(delta: float) -> void:
	_t += delta
	if _phase == 1:
		for k in range(ROWS_PER_FRAME):
			if _row >= IMG_N:
				break
			for ix in range(IMG_N):
				var p: Vector2 = _px_world(ix, _row)
				var h: float = gen.height(p.x, p.y)
				var w: Vector4 = gen.masks(p.x, p.y)
				_hs[_row * IMG_N + ix] = h
				_land[_row * IMG_N + ix] = _base_col(h, w, p.x, p.y)
			_row += 1
		progress = float(_row) / float(IMG_N) * 0.8
		if _row >= IMG_N:
			_phase = 2
			_shade_row = 0
	elif _phase == 2:
		for k in range(12):
			if _shade_row >= IMG_N:
				break
			_shade(_shade_row)
			_shade_row += 1
		progress = 0.8 + float(_shade_row) / float(IMG_N) * 0.2
		if _shade_row >= IMG_N:
			tex = ImageTexture.create_from_image(_img)
			_make_marks()
			_phase = 3
			ready_map = true
			_hs = PackedFloat32Array()
			_land = PackedColorArray()
	if visible:
		queue_redraw()
		_canvas.queue_redraw()

func _hat(ix: int, iy: int) -> float:
	ix = clampi(ix, 0, IMG_N - 1)
	iy = clampi(iy, 0, IMG_N - 1)
	return _hs[iy * IMG_N + ix]

func _shade(y: int) -> void:
	var sea: float = 0.35
	var ink: Color = Color(0.30, 0.20, 0.10)
	for x in range(IMG_N):
		var h: float = _hat(x, y)
		if h < sea:
			var depth: float = clampf(-h / 10.0, 0.0, 1.0)
			var wc: Color = Color(0.62, 0.80, 0.84).lerp(Color(0.40, 0.62, 0.74), depth)
			wc.a = 0.78
			# coast outline on the water side
			if _hat(x - 1, y) >= sea or _hat(x + 1, y) >= sea or _hat(x, y - 1) >= sea or _hat(x, y + 1) >= sea:
				wc = Color(ink.r, ink.g, ink.b, 0.85)
			_img.set_pixel(x, y, wc)
			continue
		var c: Color = _land[y * IMG_N + x]
		var sh: float = ((_hat(x - 1, y) - _hat(x + 1, y)) + (_hat(x, y - 1) - _hat(x, y + 1))) * 0.5
		var f: float = 1.0 + clampf(sh * 0.035, -0.22, 0.22)
		c = Color(c.r * f, c.g * f, c.b * f, 0.88)
		# contour lines
		var band: float = floorf(h / 7.0)
		if floorf(_hat(x + 1, y) / 7.0) != band or floorf(_hat(x, y + 1) / 7.0) != band:
			c = c.lerp(ink, 0.18)
		_img.set_pixel(x, y, c)

func _hash(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)

func _make_marks() -> void:
	_marks.clear()
	var step: float = 38.0
	var gx: int = 0
	var x: float = -HALF + 20.0
	while x < HALF:
		var z: float = -HALF + 20.0
		while z < HALF:
			var jx: float = x + (_hash(x, z) - 0.5) * step * 0.8
			var jz: float = z + (_hash(z, x) - 0.5) * step * 0.8
			if not (gen.has_method("in_town") and gen.in_town(jx, jz, 70.0)) and Vector2(jx, jz).length() > 20.0:
				var h: float = gen.height(jx, jz)
				if h > 0.8:
					var w: Vector4 = gen.masks(jx, jz)
					var r: float = _hash(jx * 0.37, jz * 0.71)
					if w.w > 0.55 and h > 38.0:
						if r < 0.40:
							_marks.append([Vector2(jx, jz), "rocksMountain" if r < 0.25 else "rocksTall", 1.15])
					elif w.y > 0.6:
						if r < 0.32:
							_marks.append([Vector2(jx, jz), "treePines" if r < 0.12 else ("treePineTall" if r < 0.22 else "treePine"), 0.8])
					elif w.z > 0.6:
						if r < 0.10:
							_marks.append([Vector2(jx, jz), "cactusLarge" if r < 0.04 else "cactus", 0.8])
					elif w.x > 0.6:
						if r < 0.03:
							_marks.append([Vector2(jx, jz), "treePine", 0.7])
			z += step
		x += step
	# the castle town
	var o: Vector2 = Vector2(110.0, -60.0)
	_marks.append([o + Vector2(52.0, 0.0), "castleWide", 3.2])
	_marks.append([o + Vector2(-8.0, -26.0), "houseChimney", 1.3])
	_marks.append([o + Vector2(10.0, -26.0), "house", 1.3])
	_marks.append([o + Vector2(-8.0, 26.0), "houses", 1.3])
	_marks.append([o + Vector2(14.0, 26.0), "house", 1.3])
	_marks.append([o + Vector2(-44.0, 0.0), "well", 1.2])
	_marks.append([o + Vector2(-26.0, 0.0), "gate", 1.4])
	_marks.append([Vector2(0.0, -9.0), "gate", 1.6])
	_marks.append([Vector2(8.0, 6.0), "campfire", 1.2])

# ---------------------------------------------------------------- painting
func _w2s(wp: Vector2) -> Vector2:
	return _canvas.size * 0.5 + (wp - _center) * _scale

func _paint_map(c: Control) -> void:
	var sz: Vector2 = c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.80, 0.68, 0.46, 0.0))
	if tex != null:
		var tl: Vector2 = _w2s(Vector2(-HALF, -HALF))
		c.draw_texture_rect(tex, Rect2(tl, Vector2(SPAN, SPAN) * _scale), false)
		# sea frame
		var br: Vector2 = tl + Vector2(SPAN, SPAN) * _scale
		c.draw_rect(Rect2(tl, br - tl), Color(0.3, 0.2, 0.1, 0.55), false, 3.0)
	else:
		var u: float = _u()
		var bar: Rect2 = Rect2(sz.x * 0.5 - 200.0 * u, sz.y * 0.5 - 12.0 * u, 400.0 * u, 24.0 * u)
		c.draw_rect(bar, Color(0.3, 0.2, 0.1, 0.35))
		c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), Color(0.45, 0.28, 0.12, 0.9))
		c.draw_string(font, Vector2(bar.position.x, bar.position.y - 14.0 * u), "در حال کشیدن نقشه...", HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, int(26.0 * u), Color(0.25, 0.15, 0.07))
		return
	var u2: float = _u()
	var base: float = clampf(_scale * 46.0, 22.0, 46.0) * u2 * 0.75
	for m in _marks:
		var wp: Vector2 = m[0]
		var sp: Vector2 = _w2s(wp)
		if sp.x < -60.0 or sp.y < -60.0 or sp.x > sz.x + 60.0 or sp.y > sz.y + 60.0:
			continue
		var ic: Texture2D = _icons.get(str(m[1])) as Texture2D
		if ic == null:
			continue
		var s: float = base * float(m[2])
		var asp: float = float(ic.get_width()) / float(ic.get_height())
		var rc: Rect2 = Rect2(sp - Vector2(s * asp * 0.5, s * 0.85), Vector2(s * asp, s))
		c.draw_texture_rect(ic, rc, false, Color(1, 1, 1, 0.92))
	for lb in _labels:
		var lp: Vector2 = _w2s(lb[0]) + Vector2(0.0, 22.0 * u2)
		var fs: int = int(24.0 * u2)
		c.draw_string(font, lp + Vector2(-130.0 * u2 + 2.0, 2.0), str(lb[1]), HORIZONTAL_ALIGNMENT_CENTER, 260.0 * u2, fs, Color(1, 0.95, 0.8, 0.9))
		c.draw_string(font, lp + Vector2(-130.0 * u2, 0.0), str(lb[1]), HORIZONTAL_ALIGNMENT_CENTER, 260.0 * u2, fs, Color(0.25, 0.14, 0.06))
	# player
	var pl: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if pl != null:
		var pp: Vector2 = _w2s(Vector2(pl.global_position.x, pl.global_position.z))
		var yaw: float = float(pl.get("yaw"))
		var fwd: Vector2 = Vector2(-sin(yaw), -cos(yaw))
		var rgt: Vector2 = Vector2(-fwd.y, fwd.x)
		var a: float = 13.0 * u2
		var pulse: float = 1.0 + 0.18 * sin(_t * 4.0)
		c.draw_circle(pp, a * 1.35 * pulse, Color(1.0, 0.45, 0.35, 0.28))
		var pts: PackedVector2Array = PackedVector2Array([pp + fwd * a * 1.5, pp + rgt * a * 0.95 - fwd * a, pp - fwd * a * 0.35, pp - rgt * a * 0.95 - fwd * a])
		c.draw_colored_polygon(pts, Color(0.92, 0.22, 0.20))
		var closed: PackedVector2Array = pts.duplicate()
		closed.append(pts[0])
		c.draw_polyline(closed, Color(0.25, 0.1, 0.05), 2.5)

func _draw() -> void:
	var s: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.03, 0.02, 0.82))
	var p: Rect2 = _panel()
	if _parch != null:
		draw_texture_rect(_parch, p, false)
	else:
		draw_rect(p, Color(0.88, 0.78, 0.58))
	draw_rect(p, Color(0.28, 0.17, 0.07), false, 5.0)
	var r: Rect2 = _inner()
	draw_rect(r, Color(0.28, 0.17, 0.07, 0.9), false, 3.0)
	var u: float = _u()
	# title banner
	var tw: float = 360.0 * u
	var tb: Rect2 = Rect2(r.position.x + r.size.x * 0.5 - tw * 0.5, r.position.y - 18.0 * u, tw, 38.0 * u)
	draw_rect(tb, Color(0.42, 0.25, 0.10, 0.96))
	draw_rect(tb, Color(0.95, 0.85, 0.6), false, 2.0)
	draw_string(font, Vector2(tb.position.x, tb.position.y + 29.0 * u), "نقشه‌ی جزیره‌ی iko", HORIZONTAL_ALIGNMENT_CENTER, tw, int(26.0 * u), Color(1.0, 0.93, 0.72))
	# compass
	var cp: Texture2D = _icons.get("compass") as Texture2D
	if cp != null:
		var cs: float = 96.0 * u
		draw_texture_rect(cp, Rect2(r.position.x + 12.0 * u, r.position.y + 14.0 * u, cs, cs), false, Color(1, 1, 1, 0.95))
		draw_string(font, Vector2(r.position.x + 12.0 * u, r.position.y + 14.0 * u - 2.0), "N", HORIZONTAL_ALIGNMENT_CENTER, cs, int(20.0 * u), Color(0.3, 0.12, 0.06))
	# buttons
	for nm in ["close", "zin", "zout", "me"]:
		var br: Rect2 = _btn_rect(nm)
		var ctr: Vector2 = br.get_center()
		var rr: float = br.size.x * 0.5
		draw_circle(ctr, rr, Color(0.36, 0.22, 0.09, 0.94))
		draw_arc(ctr, rr, 0.0, TAU, 32, Color(0.96, 0.86, 0.6), 3.0)
		var k: float = rr * 0.42
		var ic: Color = Color(1.0, 0.93, 0.72)
		match nm:
			"close":
				draw_line(ctr + Vector2(-k, -k), ctr + Vector2(k, k), ic, 5.0)
				draw_line(ctr + Vector2(-k, k), ctr + Vector2(k, -k), ic, 5.0)
			"zin":
				draw_line(ctr + Vector2(-k, 0), ctr + Vector2(k, 0), ic, 5.0)
				draw_line(ctr + Vector2(0, -k), ctr + Vector2(0, k), ic, 5.0)
			"zout":
				draw_line(ctr + Vector2(-k, 0), ctr + Vector2(k, 0), ic, 5.0)
			"me":
				draw_arc(ctr, k * 0.95, 0.0, TAU, 20, ic, 4.0)
				draw_circle(ctr, k * 0.32, ic)

# ---------------------------------------------------------------- view control
func _clamp_view() -> void:
	_scale = clampf(_scale, _min_scale, 1.6)
	var lim: float = HALF * 0.98
	_center = Vector2(clampf(_center.x, -lim, lim), clampf(_center.y, -lim, lim))

func _press_btn(nm: String) -> void:
	match nm:
		"close":
			close_map()
		"zin":
			_scale *= 1.5
		"zout":
			_scale /= 1.5
		"me":
			var pl: Node3D = get_tree().get_first_node_in_group("player") as Node3D
			if pl != null:
				_center = Vector2(pl.global_position.x, pl.global_position.z)
	_clamp_view()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var st: InputEventScreenTouch = event as InputEventScreenTouch
	var sd: InputEventScreenDrag = event as InputEventScreenDrag
	var mb: InputEventMouseButton = event as InputEventMouseButton
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	var ke: InputEventKey = event as InputEventKey
	if ke != null and ke.pressed and (ke.keycode == KEY_ESCAPE or ke.keycode == KEY_M):
		close_map()
		get_viewport().set_input_as_handled()
		return
	var touch_dev: bool = DisplayServer.is_touchscreen_available()
	if st != null:
		if st.pressed:
			_touches[st.index] = st.position
			_starts[st.index] = st.position
			_t_down[st.index] = Time.get_ticks_msec()
			if _touches.size() == 2:
				_pinch = _pinch_dist()
		else:
			if _starts.has(st.index):
				var moved: float = (st.position - Vector2(_starts[st.index])).length()
				var dt: int = Time.get_ticks_msec() - int(_t_down.get(st.index, 0))
				if moved < 16.0 and dt < 500:
					var h0: String = _hit(Vector2(_starts[st.index]))
					if h0 != "" and h0 == _hit(st.position):
						_press_btn(h0)
			_touches.erase(st.index)
			_starts.erase(st.index)
			_t_down.erase(st.index)
			_pinch = 0.0
		get_viewport().set_input_as_handled()
	elif sd != null:
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var d: float = _pinch_dist()
			if _pinch > 1.0 and d > 1.0:
				_scale *= d / _pinch
			_pinch = d
		else:
			_center -= sd.relative / _scale
		_clamp_view()
		get_viewport().set_input_as_handled()
	elif mb != null and not touch_dev:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_down = true
				_mouse_moved = 0.0
			else:
				_mouse_down = false
				if _mouse_moved < 6.0:
					var h1: String = _hit(mb.position)
					if h1 != "":
						_press_btn(h1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_scale *= 1.15
			_clamp_view()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_scale /= 1.15
			_clamp_view()
		get_viewport().set_input_as_handled()
	elif mm != null and not touch_dev:
		if _mouse_down:
			_mouse_moved += mm.relative.length()
			_center -= mm.relative / _scale
			_clamp_view()
		get_viewport().set_input_as_handled()

func _pinch_dist() -> float:
	var ks: Array = _touches.keys()
	if ks.size() < 2:
		return 0.0
	return (Vector2(_touches[ks[0]]) - Vector2(_touches[ks[1]])).length()
