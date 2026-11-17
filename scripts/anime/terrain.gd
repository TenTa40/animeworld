extends Node3D
# Streams the big world as 64 m chunks with 4 levels of detail (2 m / 4 m / 8 m / 16 m cells).
# Heights are generated in small time-sliced steps so walking never hitches.

const GEN = preload("res://scripts/anime/worldgen.gd")
const TOON = preload("res://scripts/anime/toon.gd")
const CS := 64.0
const THRESH := [1.6, 3.6, 7.5, 12.0, 19.0]    # chunk distance limits for LOD 0..4 (cells 2/4/8/16/32 m)

class Job extends RefCounted:
	var key: Vector2i = Vector2i.ZERO
	var cx: int = 0
	var cz: int = 0
	var lod: int = 0
	var s: int = 1
	var V: int = 33
	var P: int = 35
	var d: float = 0.0
	var stage: int = 0
	var row: int = 0
	var minh: float = 1e9
	var maxh: float = -1e9
	var hg: PackedFloat32Array = PackedFloat32Array()
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()

var gen = GEN.new()
var mat: ShaderMaterial = null
var water_mat: ShaderMaterial = null
var follow: Node3D = null
var budget_us: int = 3500
var dist_scale: float = 1.0

var _chunks: Dictionary = {}
var _queue: Array = []
var _job: Job = null
var _center: Vector3 = Vector3.ZERO
var _upd_t: float = 0.0
var imp_mat: ShaderMaterial = null
var imp_info: Array = []
var _imp_mesh: QuadMesh = null
var _tree_mesh: CylinderMesh = null
var _tree_mat: ShaderMaterial = null

# ------------------------------------------------------------ public
func sample(x: float, z: float) -> float:
	var cx: int = int(floor(x / CS))
	var cz: int = int(floor(z / CS))
	var key := Vector2i(cx, cz)
	if _chunks.has(key):
		var rec: Dictionary = _chunks[key]
		if rec.has("hg"):
			var hg: PackedFloat32Array = rec["hg"]
			var u: float = (x - float(cx) * CS) / 2.0 + 1.0
			var v: float = (z - float(cz) * CS) / 2.0 + 1.0
			var i0: int = int(floor(u))
			var j0: int = int(floor(v))
			var fu: float = u - float(i0)
			var fv: float = v - float(j0)
			var h00: float = hg[j0 * 35 + i0]
			var h10: float = hg[j0 * 35 + i0 + 1]
			var h01: float = hg[(j0 + 1) * 35 + i0]
			var h11: float = hg[(j0 + 1) * 35 + i0 + 1]
			return lerpf(lerpf(h00, h10, fu), lerpf(h01, h11, fu), fv)
	return gen.height(x, z)

func has_collision_at(x: float, z: float) -> bool:
	var key := Vector2i(int(floor(x / CS)), int(floor(z / CS)))
	if _chunks.has(key):
		return (_chunks[key] as Dictionary).has("body")
	return false

func prime(center: Vector3, d_max: float) -> void:
	update(center)
	var guard: int = 0
	while not _queue.is_empty() and guard < 600:
		var q: Job = _queue[0] as Job
		if q.d > d_max:
			break
		_queue.pop_front()
		_job = q
		while not _job_step(_job):
			pass
		_job = null
		guard += 1

func update(center: Vector3) -> void:
	_center = center
	var ccx: int = int(floor(center.x / CS))
	var ccz: int = int(floor(center.z / CS))
	var cpos: Vector2 = Vector2(center.x, center.z)
	var wanted: Dictionary = {}
	var newq: Array = []
	var lim: int = int(ceil((gen.R + 150.0) / CS))
	for cz in range(maxi(ccz - 19, -lim), mini(ccz + 19, lim - 1) + 1):
		for cx in range(maxi(ccx - 19, -lim), mini(ccx + 19, lim - 1) + 1):
			var cc: Vector2 = Vector2((float(cx) + 0.5) * CS, (float(cz) + 0.5) * CS)
			if cc.length() > gen.R + 150.0:
				continue
			var d: float = cc.distance_to(cpos) / CS
			var key := Vector2i(cx, cz)
			var cur: int = -1
			if _chunks.has(key):
				cur = int((_chunks[key] as Dictionary)["lod"])
			var lod: int = _lod_for(d, cur)
			if lod < 0:
				continue
			wanted[key] = lod
			if cur != lod:
				if _job != null and _job.key == key and _job.lod == lod:
					continue
				var j := Job.new()
				j.key = key
				j.cx = cx
				j.cz = cz
				j.lod = lod
				j.d = d
				newq.append(j)
	newq.sort_custom(func(a, b): return a.d < b.d)
	_queue = newq
	if _job != null and not wanted.has(_job.key):
		_job = null
	for key in _chunks.keys():
		if not wanted.has(key):
			_free_chunk(key)

func _lod_for(d: float, cur: int) -> int:
	var lod: int = -1
	for i in range(THRESH.size()):
		if d <= float(THRESH[i]) * dist_scale:
			lod = i
			break
	if lod >= 0 and cur >= 0 and absi(cur - lod) == 1:
		var b: float = float(THRESH[mini(cur, lod)]) * dist_scale
		if absf(d - b) < 0.35:
			lod = cur
	return lod

func _process(delta: float) -> void:
	_upd_t += delta
	if _upd_t >= 0.25:
		_upd_t = 0.0
		if follow != null and is_instance_valid(follow):
			update(follow.global_position)
	var t0: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < budget_us:
		if _job == null:
			if _queue.is_empty():
				break
			_job = _queue.pop_front() as Job
			_init_job(_job)
		if _job_step(_job):
			_job = null

# ------------------------------------------------------------ chunk jobs
func _init_job(j: Job) -> void:
	j.s = 1 << j.lod
	j.V = 32 / j.s + 1
	j.P = j.V + 2
	j.hg.resize(j.P * j.P)
	j.verts.resize(j.V * j.V)
	j.norms.resize(j.V * j.V)
	j.cols.resize(j.V * j.V)

# returns true when the job is finished
func _job_step(j: Job) -> bool:
	if j.hg.size() == 0:
		_init_job(j)
	var step: float = 2.0 * float(j.s)
	if j.stage == 0:
		var jr: int = j.row
		var z: float = float(j.cz) * CS + float(jr - 1) * step
		for pi in range(j.P):
			var x: float = float(j.cx) * CS + float(pi - 1) * step
			var h: float = gen.height(x, z)
			j.hg[jr * j.P + pi] = h
			if pi >= 1 and pi <= j.V and jr >= 1 and jr <= j.V:
				j.minh = minf(j.minh, h)
				j.maxh = maxf(j.maxh, h)
		j.row += 1
		if j.row >= j.P:
			j.row = 0
			if j.maxh < -1.5:
				_set_record(j.key, {"lod": j.lod, "empty": true})
				return true
			j.stage = 1
		return false
	if j.stage == 1:
		var jj: int = j.row
		for ii in range(j.V):
			var p: int = (jj + 1) * j.P + (ii + 1)
			var h: float = j.hg[p]
			var n: Vector3 = Vector3(j.hg[p - 1] - j.hg[p + 1], 2.0 * step, j.hg[p - j.P] - j.hg[p + j.P]).normalized()
			var wx: float = float(j.cx) * CS + float(ii) * step
			var wz: float = float(j.cz) * CS + float(jj) * step
			var idx: int = jj * j.V + ii
			j.verts[idx] = Vector3(float(ii) * step, h, float(jj) * step)
			j.norms[idx] = n
			j.cols[idx] = gen.color(wx, wz, h, n.y)
		j.row += 1
		if j.row >= j.V:
			j.stage = 2
		return false
	_finalize(j)
	return true

func _finalize(j: Job) -> void:
	var V: int = j.V
	var idx := PackedInt32Array()
	for jj in range(V - 1):
		for ii in range(V - 1):
			var a: int = jj * V + ii
			var b: int = a + 1
			var c: int = a + V
			var d: int = c + 1
			idx.append(a)
			idx.append(b)
			idx.append(c)
			idx.append(b)
			idx.append(d)
			idx.append(c)
	var rec: Dictionary = {"lod": j.lod}
	var origin: Vector3 = Vector3(float(j.cx) * CS, 0.0, float(j.cz) * CS)

	# collision (nearest level only)
	if j.lod == 0:
		var faces := PackedVector3Array()
		for jj in range(V - 1):
			for ii in range(V - 1):
				var a2: int = jj * V + ii
				faces.append(j.verts[a2])
				faces.append(j.verts[a2 + 1])
				faces.append(j.verts[a2 + V])
				faces.append(j.verts[a2 + 1])
				faces.append(j.verts[a2 + V + 1])
				faces.append(j.verts[a2 + V])
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		cs.shape = shape
		body.add_child(cs)
		body.position = origin
		add_child(body)
		rec["body"] = body
		rec["hg"] = j.hg

	# water (only where the chunk dips close to or below sea level)
	if j.minh < 1.5:
		var wv := PackedVector3Array()
		var wc := PackedColorArray()
		wv.resize(V * V)
		wc.resize(V * V)
		for k in range(V * V):
			var v3: Vector3 = j.verts[k]
			wv[k] = Vector3(v3.x, 0.0, v3.z)
			wc[k] = Color(clampf((2.0 - v3.y) / 8.0, 0.0, 1.0), 0.0, 0.0, 1.0)
		var warr: Array = []
		warr.resize(Mesh.ARRAY_MAX)
		warr[Mesh.ARRAY_VERTEX] = wv
		warr[Mesh.ARRAY_COLOR] = wc
		warr[Mesh.ARRAY_INDEX] = idx
		var wmesh := ArrayMesh.new()
		wmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warr)
		var wi := MeshInstance3D.new()
		wi.mesh = wmesh
		wi.material_override = water_mat
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wi.position = origin
		add_child(wi)
		rec["wi"] = wi

	# skirts hide cracks between neighbouring levels of detail
	var border: Array = []
	for i in range(V):
		border.append(i)
	for jj in range(1, V):
		border.append(jj * V + (V - 1))
	for i in range(V - 2, -1, -1):
		border.append((V - 1) * V + i)
	for jj in range(V - 2, 0, -1):
		border.append(jj * V)
	var base: int = V * V
	var depth: float = minf(4.0 + 3.0 * float(j.s), 40.0)
	for b in border:
		var bi: int = int(b)
		j.verts.append(j.verts[bi] - Vector3(0.0, depth, 0.0))
		j.norms.append(j.norms[bi])
		j.cols.append(j.cols[bi])
	var bn: int = border.size()
	for t in range(bn):
		var a3: int = int(border[t])
		var b3: int = int(border[(t + 1) % bn])
		var a4: int = base + t
		var b4: int = base + ((t + 1) % bn)
		idx.append(a3)
		idx.append(b3)
		idx.append(a4)
		idx.append(b3)
		idx.append(b4)
		idx.append(a4)

	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = j.verts
	arr[Mesh.ARRAY_NORMAL] = j.norms
	arr[Mesh.ARRAY_COLOR] = j.cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = origin
	add_child(mi)
	rec["mi"] = mi
	var ft: MultiMeshInstance3D = null
	if imp_mat != null:
		ft = _far_trees_imp(j, origin)
	elif j.lod >= 1:
		ft = _far_trees(j, origin)
	if ft != null:
		add_child(ft)
		rec["ft"] = ft
	_set_record(j.key, rec)

func _set_record(key: Vector2i, rec: Dictionary) -> void:
	if _chunks.has(key):
		_free_chunk(key)
	_chunks[key] = rec

func _free_chunk(key: Vector2i) -> void:
	if not _chunks.has(key):
		return
	var rec: Dictionary = _chunks[key]
	for nm in ["mi", "body", "wi", "ft"]:
		if rec.has(nm):
			var n: Node = rec[nm] as Node
			if n != null and is_instance_valid(n):
				n.queue_free()
	_chunks.erase(key)

# ------------------------------------------------------------ cheap distant forests
func _hbil(j: Job, lx: float, lz: float) -> float:
	var step: float = 2.0 * float(j.s)
	var u: float = clampf(lx / step, 0.0, float(j.V - 1) - 0.001) + 1.0
	var v: float = clampf(lz / step, 0.0, float(j.V - 1) - 0.001) + 1.0
	var i0: int = int(floor(u))
	var j0: int = int(floor(v))
	var fu: float = u - float(i0)
	var fv: float = v - float(j0)
	var h00: float = j.hg[j0 * j.P + i0]
	var h10: float = j.hg[j0 * j.P + i0 + 1]
	var h01: float = j.hg[(j0 + 1) * j.P + i0]
	var h11: float = j.hg[(j0 + 1) * j.P + i0 + 1]
	return lerpf(lerpf(h00, h10, fu), lerpf(h01, h11, fu), fv)

func _tree_resources() -> void:
	if _tree_mesh != null:
		return
	_tree_mesh = CylinderMesh.new()
	_tree_mesh.top_radius = 0.0
	_tree_mesh.bottom_radius = 1.7
	_tree_mesh.height = 6.5
	_tree_mesh.radial_segments = 6
	_tree_mesh.rings = 1
	_tree_mesh.cap_bottom = false
	_tree_mat = TOON.mat(Color(1, 1, 1), null, true, Color(0, 0, 0), 0.0, 0.0, 0.15)
	_tree_mesh.material = _tree_mat

func _far_trees(j: Job, origin: Vector3) -> MultiMeshInstance3D:
	var counts: Array = [10, 8, 6, 4]
	var n: int = int(counts[mini(j.lod - 1, 3)])
	var rng := RandomNumberGenerator.new()
	rng.seed = (j.cx * 73856093) ^ (j.cz * 19349663) ^ 7771
	var cell: float = CS / float(n)
	var xfs: Array = []
	var cols: Array = []
	for gz in range(n):
		for gx in range(n):
			var lx: float = (float(gx) + rng.randf()) * cell
			var lz: float = (float(gz) + rng.randf()) * cell
			var x: float = origin.x + lx
			var z: float = origin.z + lz
			var roll: float = rng.randf()
			var w: Vector4 = gen.masks(x, z)
			var gv: float = gen.grove(x, z) * w.x
			var p: float = w.y * 0.95 + w.w * 0.6 + w.x * (0.08 + 0.9 * gv)
			p *= smoothstep(0.28, 0.55, gen.forest(x, z)) * 0.8 + 0.2
			if roll > p:
				continue
			var h: float = _hbil(j, lx, lz)
			if h < 1.8 or h > 56.0:
				continue
			if absf(_hbil(j, minf(lx + 3.0, CS), lz) - h) > 3.6:
				continue
			var sc: float = (1.0 + 0.45 * float(j.lod)) * rng.randf_range(0.85, 1.25)
			var b: Basis = Basis.IDENTITY.scaled(Vector3(sc, sc, sc))
			xfs.append(Transform3D(b, Vector3(lx, h + 3.0 * sc - 0.3, lz)))
			var v: float = rng.randf_range(0.85, 1.15)
			var c: Color = Color(0.13, 0.38, 0.20)
			if gv > 0.5:
				c = Color(0.95, 0.64, 0.80)
			elif w.w > 0.5:
				c = Color(0.15, 0.36, 0.34)
			elif w.x > 0.5:
				c = Color(0.30, 0.60, 0.24)
			cols.append(Color(c.r * v, c.g * v, c.b * v, 1.0).srgb_to_linear())
	if xfs.is_empty():
		return null
	_tree_resources()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tree_mesh
	mm.instance_count = xfs.size()
	for i in range(xfs.size()):
		mm.set_instance_transform(i, xfs[i] as Transform3D)
		mm.set_instance_color(i, cols[i] as Color)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position = origin
	mmi.visibility_range_begin = 72.0
	return mmi

# ------------------------------------------------------------ impostor forests (billboards of the real trees)
func set_impostors(tex: Texture2D, info: Array) -> void:
	imp_mat = ShaderMaterial.new()
	imp_mat.shader = load("res://shaders/anime/impostor.gdshader") as Shader
	imp_mat.set_shader_parameter("atlas", tex)
	imp_info = info
	_imp_mesh = QuadMesh.new()
	_imp_mesh.size = Vector2(1.0, 1.0)
	_imp_mesh.material = imp_mat

func pending(d_max: float) -> int:
	var n: int = 0
	for q in _queue:
		if (q as Job).d <= d_max:
			n += 1
	if _job != null and _job.d <= d_max:
		n += 1
	return n

func _far_trees_imp(j: Job, origin: Vector3) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = (j.cx * 73856093) ^ (j.cz * 19349663) ^ 4242
	var factors: Array = [1.0, 1.0, 0.6, 0.35, 0.2]
	var tries: int = int(CS * CS * 0.0135 * float(factors[mini(j.lod, 4)]))
	var xfs: Array = []
	var cds: Array = []
	for t in range(tries):
		var lx: float = rng.randf() * CS
		var lz: float = rng.randf() * CS
		var roll: float = rng.randf()
		var r2: float = rng.randf()
		var scl: float = rng.randf_range(0.9, 1.5)
		var br: float = rng.randf_range(0.88, 1.08)
		var x: float = origin.x + lx
		var z: float = origin.z + lz
		var w: Vector4 = gen.masks(x, z)
		var gv: float = gen.grove(x, z) * w.x
		var p: float = w.y + w.w * 0.65 + w.x * (0.06 + 0.9 * gv)
		p *= smoothstep(0.28, 0.55, gen.forest(x, z)) * 0.8 + 0.2
		if roll > p:
			continue
		var h: float = _hbil(j, lx, lz)
		if h < 1.8 or h > 56.0:
			continue
		if absf(_hbil(j, minf(lx + 3.0, CS), lz) - h) > 3.6:
			continue
		var cell: int = 0
		var pink: float = 0.0
		var bright: float = br
		if gv > 0.5:
			cell = 1 if r2 < 0.5 else 3
			pink = 1.0
		elif w.w > 0.5:
			cell = 0 if r2 < 0.5 else 2
			bright = br * 0.88
		elif w.y > 0.5:
			cell = int(r2 * 4.0) % 4
			bright = br * 0.86
		else:
			cell = 1 if r2 < 0.5 else 3
		var inf: Vector3 = imp_info[cell]
		if inf.z < 0.5:
			continue
		var sc: float = scl * (1.0 + 0.22 * float(maxi(j.lod - 1, 0)))
		var side: float = inf.x * sc
		xfs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(side, side, 1.0)), Vector3(lx, h + inf.y * sc - 0.2, lz)))
		cds.append(Color(float(cell), pink, bright, 0.0))
	if xfs.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _imp_mesh
	mm.instance_count = xfs.size()
	for i in range(xfs.size()):
		mm.set_instance_transform(i, xfs[i] as Transform3D)
		mm.set_instance_custom_data(i, cds[i] as Color)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position = origin
	return mmi
