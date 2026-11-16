extends RefCounted
# Procedural world: ~900 m island with four biomes, lakes, beaches and a sakura grove.
# North = -Z. Mountains (north), desert (east), dark forest (west), meadows (south/center).

const R := 480.0                       # island radius
const GROVE := Vector2(-108.0, 228.0)   # sakura grove centre

var n_warp := FastNoiseLite.new()
var n_hill := FastNoiseLite.new()
var n_det := FastNoiseLite.new()
var n_dune := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_col := FastNoiseLite.new()
var n_forest := FastNoiseLite.new()
var lakes: Array = []

func _init() -> void:
	_setup(n_warp, 0.004, 2, 11)
	_setup(n_hill, 0.008, 3, 7)
	_setup(n_det, 0.035, 2, 23)
	_setup(n_dune, 0.016, 2, 31)
	_setup(n_ridge, 0.0045, 4, 41)
	_setup(n_col, 0.05, 1, 53)
	_setup(n_forest, 0.014, 2, 99)
	# x, z, radius, depth
	lakes = [Vector4(-250.0, 48.0, 72.0, 8.0), Vector4(84.0, 282.0, 54.0, 7.0), Vector4(306.0, 12.0, 34.0, 5.0), Vector4(-84.0, -150.0, 50.0, 7.0)]

func _setup(n: FastNoiseLite, freq: float, oct: int, seed_v: int) -> void:
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = oct
	n.seed = seed_v

# weights (plains, forest, desert, mountain), sum = 1
func masks(x: float, z: float) -> Vector4:
	var wn: float = n_warp.get_noise_2d(x, z)
	var px: float = x / R
	var pz: float = z / R
	var m: float = 1.0 - smoothstep(-0.55, -0.26, pz + wn * 0.12)
	var d: float = smoothstep(0.30, 0.55, px + wn * 0.10) * (1.0 - m)
	var f: float = (1.0 - smoothstep(-0.55, -0.30, px + wn * 0.10)) * (1.0 - m) * (1.0 - d)
	var p: float = maxf(0.0, 1.0 - m - d - f)
	return Vector4(p, f, d, m)

func grove(x: float, z: float) -> float:
	return 1.0 - smoothstep(30.0, 65.0, Vector2(x, z).distance_to(GROVE))

func forest(x: float, z: float) -> float:
	return n_forest.get_noise_2d(x, z) * 0.5 + 0.5

func height(x: float, z: float) -> float:
	var w: Vector4 = masks(x, z)
	var hills: float = n_hill.get_noise_2d(x, z)
	var det: float = n_det.get_noise_2d(x, z)
	var h: float = w.x * (4.0 + hills * 4.0 + det * 0.8)
	h += w.y * (7.0 + hills * 12.0 + det * 1.5)
	if w.z > 0.01:
		h += w.z * (5.0 + n_dune.get_noise_2d(x, z * 2.0) * 6.0 + hills * 3.0)
	if w.w > 0.01:
		var ridge: float = 1.0 - absf(n_ridge.get_noise_2d(x, z))
		h += w.w * (16.0 + hills * 10.0 + pow(ridge, 2.2) * 72.0 + det * 2.0)
	# spawn plateau
	var d0: float = Vector2(x, z).length()
	h = lerpf(h, 2.6, 1.0 - smoothstep(6.0, 22.0, d0))
	# lakes
	for lk in lakes:
		var l: Vector4 = lk
		var t: float = 1.0 - smoothstep(l.z * 0.5, l.z, Vector2(x - l.x, z - l.y).length())
		if t > 0.0:
			h = lerpf(h, -l.w, t)
	# coastline
	var cd: float = d0 + n_warp.get_noise_2d(z + 500.0, x) * 45.0
	h = lerpf(h, -30.0, smoothstep(R * 0.80, R * 0.99, cd))
	return h

# base colour (linear) with detail selector in alpha (1 = grass detail, 0 = stone detail)
func color(x: float, z: float, h: float, ny: float) -> Color:
	var w: Vector4 = masks(x, z)
	var c: float = n_col.get_noise_2d(x, z) * 0.5 + 0.5
	var g_plain: Color = Color(0.50, 0.80, 0.28).lerp(Color(0.72, 0.92, 0.34), c)
	var g_forest: Color = Color(0.16, 0.46, 0.22).lerp(Color(0.24, 0.58, 0.24), c)
	var sand: Color = Color(0.93, 0.74, 0.44).lerp(Color(0.86, 0.58, 0.34), c)
	var rock: Color = Color(0.50, 0.48, 0.54).lerp(Color(0.64, 0.60, 0.62), c)
	var m_low: Color = g_forest.lerp(rock, smoothstep(28.0, 48.0, h))
	var col: Color = g_plain * w.x + g_forest * w.y + sand * w.z + m_low * w.w
	var grass_amt: float = w.x + w.y + w.w * (1.0 - smoothstep(28.0, 48.0, h))
	# sakura grove: pinkish ground
	var gv: float = grove(x, z) * w.x
	if gv > 0.0:
		col = col.lerp(Color(0.95, 0.72, 0.82), gv * 0.55)
	# steep slopes show rock (reddish in the desert)
	var slope: float = 1.0 - smoothstep(0.62, 0.80, ny)
	var rock_col: Color = rock.lerp(Color(0.72, 0.46, 0.34), w.z)
	col = col.lerp(rock_col, slope)
	grass_amt *= (1.0 - slope)
	# snow
	var snow_line: float = 58.0 + (c - 0.5) * 14.0
	var snow: float = smoothstep(snow_line - 6.0, snow_line + 6.0, h) * smoothstep(0.50, 0.72, ny)
	col = col.lerp(Color(0.96, 0.97, 1.0), snow)
	grass_amt *= (1.0 - snow)
	# beaches and lake shores
	var beach: float = 1.0 - smoothstep(0.6, 1.9, h)
	col = col.lerp(Color(0.96, 0.90, 0.70), beach)
	grass_amt *= (1.0 - beach)
	col = col.srgb_to_linear()
	return Color(col.r, col.g, col.b, clampf(grass_amt, 0.0, 1.0))

func biome_name(w: Vector4, gv: float) -> String:
	if gv > 0.55:
		return "باغ شکوفه‌ها"
	var best: int = 0
	var bv: float = w.x
	if w.y > bv:
		best = 1
		bv = w.y
	if w.z > bv:
		best = 2
		bv = w.z
	if w.w > bv:
		best = 3
		bv = w.w
	if bv < 0.5:
		return ""
	match best:
		1:
			return "جنگل تاریک"
		2:
			return "صحرای سوزان"
		3:
			return "کوه‌های برفی"
	return "چمنزارهای آرام"
