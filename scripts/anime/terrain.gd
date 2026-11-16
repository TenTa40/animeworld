extends Node3D
# Streams the big world as 64 m chunks with 4 levels of detail (2 m / 4 m / 8 m / 16 m cells).
# Heights are generated in small time-sliced steps so walking never hitches.

const GEN = preload("res://scripts/anime/worldgen.gd")
const CS := 64.0
const THRESH := [1.6, 3.3, 6.6, 10.6]    # chunk distance limits for LOD 0..3

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

var _chunks: Dictionary = {}
var _queue: Array = []
var _job: Job = null
var _center: Vector3 = Vector3.ZERO
var _upd_t: float = 0.0

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
	for dz in range(-11, 12):
		for dx in range(-11, 12):
			var cx: int = ccx + dx
			var cz: int = ccz + dz
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
		if d <= float(THRESH[i]):
			lod = i
			break
	if lod >= 0 and cur >= 0 and absi(cur - lod) == 1:
		var b: float = float(THRESH[mini(cur, lod)])
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
	var depth: float = 4.0 + 5.0 * float(j.s)
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
	_set_record(j.key, rec)

func _set_record(key: Vector2i, rec: Dictionary) -> void:
	if _chunks.has(key):
		_free_chunk(key)
	_chunks[key] = rec

func _free_chunk(key: Vector2i) -> void:
	if not _chunks.has(key):
		return
	var rec: Dictionary = _chunks[key]
	for nm in ["mi", "body", "wi"]:
		if rec.has(nm):
			var n: Node = rec[nm] as Node
			if n != null and is_instance_valid(n):
				n.queue_free()
	_chunks.erase(key)
