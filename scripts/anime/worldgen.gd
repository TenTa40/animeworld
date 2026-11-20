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
var n_path := FastNoiseLite.new()
var n_gate := FastNoiseLite.new()
var n_aut := FastNoiseLite.new()
var n_mesa := FastNoiseLite.new()
var n_river := FastNoiseLite.new()
var lakes: Array = []

# dirt roads: the zero line of a smooth noise field makes long winding paths (width in noise units)
const PATH_IN := 0.028    # noise value where a road is fully dirt (~1.6 m from its centre line)
const PATH_OUT := 0.062   # noise value where the road ends (~3.3 m from its centre line)

func _init() -> void:
	_setup(n_warp, 0.004, 2, 11)
	_setup(n_hill, 0.008, 3, 7)
	_setup(n_det, 0.035, 2, 23)
	_setup(n_dune, 0.016, 2, 31)
	_setup(n_ridge, 0.0045, 4, 41)
	_setup(n_col, 0.05, 1, 53)
	_setup(n_forest, 0.014, 2, 99)
	_setup(n_path, 0.0052, 2, 61)
	_setup(n_gate, 0.0028, 1, 67)
	_setup(n_aut, 0.0065, 2, 73)
	_setup(n_mesa, 0.0034, 2, 83)
	_setup(n_river, 0.0042, 2, 89)
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

# 0..1: how much of a dirt road is at this spot (0 = none). Roads fade out in mountains and near water.
func path(x: float, z: float) -> float:
	var n: float = absf(n_path.get_noise_2d(x, z))
	if n > PATH_OUT:
		return 0.0
	var band: float = 1.0 - smoothstep(PATH_IN, PATH_OUT, n)
	var gate: float = smoothstep(-0.18, 0.12, n_gate.get_noise_2d(x + 300.0, z - 200.0))
	return clampf(band * gate, 0.0, 1.0)

# road weight with the same height limits the ground colour uses (no roads on snow, in water or on the beach)
func road(x: float, z: float, h: float) -> float:
	return path(x, z) * (1.0 - smoothstep(34.0, 52.0, h)) * smoothstep(1.0, 2.2, h)

# 0..1: patches of autumn-coloured trees (orange / yellow like the reference image)
func autumn(x: float, z: float) -> float:
	return smoothstep(0.54, 0.72, n_aut.get_noise_2d(x, z) * 0.5 + 0.5)

# ---- castle town (terraced; the profile must match tools/towngen.py town_h)
const TOWN_O := Vector2(110.0, -60.0)
const TOWN_H0 := 6.0
const TOWN_H1 := 10.5
const TOWN_H2 := 17.0
const TOWN_U0 := -74.0
const TOWN_U1 := 84.0
const TOWN_V := 36.0
const TOWN_FALL := 55.0

func town_h(u: float) -> float:
	return TOWN_H0 + (TOWN_H1 - TOWN_H0) * smoothstep(-38.0, -26.0, u) + (TOWN_H2 - TOWN_H1) * smoothstep(22.0, 34.0, u)

# distance outside the town rectangle (0 = inside)
func town_dist(x: float, z: float) -> float:
	var u: float = x - TOWN_O.x
	var v: float = z - TOWN_O.y
	var du: float = maxf(maxf(TOWN_U0 - u, u - TOWN_U1), 0.0)
	var dv: float = maxf(absf(v) - TOWN_V, 0.0)
	return sqrt(du * du + dv * dv)

# 1 inside the town, fading to 0 over TOWN_FALL metres
func town_k(x: float, z: float) -> float:
	var d: float = town_dist(x, z)
	if d >= TOWN_FALL:
		return 0.0
	return 1.0 - smoothstep(0.0, TOWN_FALL, d)

func in_town(x: float, z: float, margin: float = 0.0) -> bool:
	return town_dist(x, z) <= margin

func height(x: float, z: float) -> float:
	var h: float = _height_nat(x, z)
	if town_dist(x, z) < TOWN_FALL:
		h = lerpf(h, town_h(x - TOWN_O.x), town_k(x, z))
	return h

func _height_nat(x: float, z: float) -> float:
	var w: Vector4 = masks(x, z)
	var hills: float = n_hill.get_noise_2d(x, z)
	var det: float = n_det.get_noise_2d(x, z)
	var h: float = w.x * (4.0 + hills * 8.0 + det * 0.8)
	h += w.y * (9.0 + hills * 13.0 + det * 1.5)
	if w.z > 0.01:
		h += w.z * (6.0 + n_dune.get_noise_2d(x, z * 2.0) * 7.0 + hills * 5.0)
	if w.w > 0.01:
		var ridge: float = 1.0 - absf(n_ridge.get_noise_2d(x, z))
		h += w.w * (16.0 + hills * 10.0 + pow(ridge, 2.2) * 72.0 + det * 2.0)
	# plateaus / mesas with steep rims (Genshin-like tiers) on the lowlands
	var big: float = n_mesa.get_noise_2d(x, z)
	var tier: float = smoothstep(0.16, 0.26, big) * 13.0 + smoothstep(0.40, 0.50, big) * 9.0
	h += tier * (w.x + w.y * 0.8 + w.z * 0.5)
	# river valleys: deep winding canyons with a water-filled bottom
	var rv: float = absf(n_river.get_noise_2d(x + 700.0, z - 300.0))
	var d_sp: float = Vector2(x, z).length()
	var rmask: float = (1.0 - smoothstep(0.35, 0.65, w.w)) * smoothstep(34.0, 80.0, d_sp)
	var band: float = (1.0 - smoothstep(0.035, 0.17, rv)) * rmask
	if band > 0.0:
		h = lerpf(h, -3.2, band)
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
	var g_plain: Color = Color(0.36, 0.64, 0.20).lerp(Color(0.50, 0.76, 0.24), c)
	g_plain = g_plain.lerp(Color(0.70, 0.68, 0.30), smoothstep(0.72, 0.98, c) * 0.35)
	var g_forest: Color = Color(0.20, 0.44, 0.19).lerp(Color(0.28, 0.54, 0.21), c)
	var sand: Color = Color(0.97, 0.80, 0.48).lerp(Color(0.90, 0.64, 0.36), c)
	var rock: Color = Color(0.52, 0.50, 0.55).lerp(Color(0.66, 0.62, 0.64), c)
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
	# dirt roads (sandy and pale in the desert)
	var tk: float = 0.0
	if town_dist(x, z) < 6.0:
		tk = 1.0 - smoothstep(0.0, 6.0, town_dist(x, z))
		var u: float = x - TOWN_O.x
		var v: float = z - TOWN_O.y
		# lawn everywhere, cobbles on the main street, plaza and keep courtyard
		var lawn: Color = Color(0.42, 0.70, 0.26).lerp(Color(0.52, 0.78, 0.30), c)
		col = col.lerp(lawn, tk)
		grass_amt = lerpf(grass_amt, 1.0, tk)
		var st: float = 1.0 - smoothstep(4.5, 6.5, absf(v))
		var pl: float = (1.0 - smoothstep(14.0, 18.0, absf(u + 44.0))) * (1.0 - smoothstep(24.0, 28.0, absf(v)))
		var cy: float = smoothstep(26.0, 29.0, u) * (1.0 - smoothstep(76.0, 79.0, u)) * (1.0 - smoothstep(22.0, 26.0, absf(v)))
		var pv: float = maxf(maxf(st, pl), cy) * tk
		var cob: Color = Color(0.66, 0.62, 0.56).lerp(Color(0.74, 0.70, 0.64), c)
		col = col.lerp(cob, pv)
		grass_amt *= (1.0 - pv)
	var pa: float = road(x, z, h) * (1.0 - tk)
	if pa > 0.0:
		var dirt: Color = Color(0.66, 0.54, 0.38).lerp(Color(0.93, 0.80, 0.58), w.z)
		dirt = dirt.lerp(Color(0.58, 0.46, 0.32), c * 0.4)
		col = col.lerp(dirt, pa * 0.92)
		grass_amt *= (1.0 - pa)
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
