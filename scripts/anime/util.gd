extends RefCounted
# Small shared static helpers.

static func load_scene(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var ps = load(path)
	if ps is PackedScene:
		return ps.instantiate()
	return null

static func _rel_xf(n: Node3D, root: Node3D) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

static func model_aabb(root: Node3D) -> AABB:
	# works with or without the node being inside the tree (root's own transform excluded)
	var first: bool = true
	var out: AABB = AABB()
	var arr: Array = root.find_children("*", "MeshInstance3D", true, false)
	for n in arr:
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ab: AABB = _rel_xf(mi, root) * mi.get_aabb()
		if first:
			out = ab
			first = false
		else:
			out = out.merge(ab)
	return out

static func play_first_anim(root: Node) -> AnimationPlayer:
	var arr: Array = root.find_children("*", "AnimationPlayer", true, false)
	if arr.is_empty():
		return null
	var ap: AnimationPlayer = arr[0] as AnimationPlayer
	if ap == null:
		return null
	for n in ap.get_animation_list():
		if str(n) == "RESET":
			continue
		var a: Animation = ap.get_animation(n)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
		ap.play(n)
		return ap
	return null

static func col_from(arr, d: Color) -> Color:
	if typeof(arr) == TYPE_ARRAY and arr.size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return d

# Loads a glb/fbx, fits it (by height or by longest horizontal side), puts its
# bottom at y=0 and its center at x=z=0 inside a wrapper Node3D. Returns the
# wrapper or null if the model is missing. Front of glTF models is +Z.
static func place_model(parent: Node, path: String, height: float, length: float = 0.0, yaw: float = 0.0) -> Node3D:
	var model: Node = load_scene(path)
	if model == null or not (model is Node3D):
		return null
	return _place_loaded(parent, model as Node3D, height, length, yaw)

static func _place_loaded(parent: Node, m3: Node3D, height: float, length: float, yaw: float) -> Node3D:
	var wrapper := Node3D.new()
	wrapper.add_child(m3)
	parent.add_child(wrapper)
	var ab: AABB = model_aabb(m3)
	if ab.size.y < 0.0001:
		wrapper.queue_free()
		return null
	var s: float = 1.0
	if height > 0.0:
		s = height / ab.size.y
	elif length > 0.0:
		s = length / maxf(ab.size.x, ab.size.z)
	m3.scale = Vector3(s, s, s)
	m3.position = Vector3(-(ab.position.x + ab.size.x * 0.5) * s, -ab.position.y * s, -(ab.position.z + ab.size.z * 0.5) * s)
	wrapper.rotation.y = yaw
	wrapper.set_meta("size", ab.size * s)
	return wrapper

# ---- items: one shared fbx ("Survival items") holding many separate objects.
const ITEMS_FBX := "res://assets/models/items/items.fbx"
const ITEMS_PALETTE := "res://assets/models/items/items_palette.png"
# game item kind -> object name inside items.fbx
const ITEM_NODES := {"battery": "battery", "can": "metal bottle", "flashlight": "flashlight"}

static func _norm(n: String) -> String:
	return n.to_lower().replace(" ", "").replace("_", "").replace("-", "")

static func has_item_model(kind: String) -> bool:
	if ResourceLoader.exists("res://assets/models/items/%s.glb" % kind):
		return true
	return ITEM_NODES.has(kind) and ResourceLoader.exists(ITEMS_FBX)

static func place_item(parent: Node, kind: String, height: float, yaw: float = 0.0) -> Node3D:
	var glb: String = "res://assets/models/items/%s.glb" % kind
	if ResourceLoader.exists(glb):
		return place_model(parent, glb, height, 0.0, yaw)
	if not ITEM_NODES.has(kind):
		return null
	var root: Node = load_scene(ITEMS_FBX)
	if root == null or not (root is Node3D):
		return null
	var want: String = _norm(str(ITEM_NODES[kind]))
	var target: Node = null
	for n in root.find_children("*", "", true, false):
		if _norm(str(n.name)) == want:
			target = n
			break
	if target == null:
		for n in root.find_children("*", "", true, false):
			if _norm(str(n.name)).contains(want) and (n is MeshInstance3D or n.get_child_count() > 0):
				target = n
				break
	if target == null:
		var names: PackedStringArray = PackedStringArray()
		for n in root.find_children("*", "", true, false):
			names.append(str(n.name))
		push_warning("items.fbx: no node '%s'. Found: %s" % [want, ", ".join(names)])
		root.free()
		return null
	# drop every mesh that is not part of the wanted object
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if n == target or target.is_ancestor_of(n):
			continue
		n.get_parent().remove_child(n)
		n.free()
	# the pack uses one palette texture; assign it if the importer did not
	var pal: Texture2D = null
	if ResourceLoader.exists(ITEMS_PALETTE):
		pal = load(ITEMS_PALETTE) as Texture2D
	if pal != null:
		var meshes: Array = []
		if target is MeshInstance3D:
			meshes.append(target)
		meshes.append_array(target.find_children("*", "MeshInstance3D", true, false))
		for mn in meshes:
			var mi: MeshInstance3D = mn as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			for i in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var sm: StandardMaterial3D = mat as StandardMaterial3D
					if sm.albedo_texture == null and sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
						var d: StandardMaterial3D = sm.duplicate() as StandardMaterial3D
						d.albedo_texture = pal
						d.albedo_color = Color(1, 1, 1)
						d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
						mi.set_surface_override_material(i, d)
	return _place_loaded(parent, root as Node3D, height, 0.0, yaw)
