extends RefCounted
# Bakes a few of the real tree models into billboard sprites once, while loading.
# Distant forests then look like the real trees instead of simple shapes.

const NAMES := ["Pine_5", "CommonTree_5", "Pine_4", "CommonTree_3"]
const TILE := 256

# returns {"tex": ImageTexture, "info": [Vector3(side, centre_y, valid) per atlas cell]} or {} on failure
static func bake(host: Node, nature) -> Dictionary:
	var out: Dictionary = {}
	if nature == null:
		return out
	var vps: Array = []
	var info: Array = []
	for i in range(NAMES.size()):
		var md: Array = nature._mesh(str(NAMES[i]))
		if md.is_empty():
			vps.append(null)
			info.append(Vector3(1.0, 0.0, 0.0))
			continue
		var mesh: Mesh = md[0] as Mesh
		var xf: Transform3D = md[1] as Transform3D
		var box: AABB = xf * mesh.get_aabb()
		var side: float = maxf(box.size.y, maxf(box.size.x, box.size.z)) * 1.12
		var cen: Vector3 = box.get_center()
		var vp := SubViewport.new()
		vp.size = Vector2i(TILE, TILE)
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		host.add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.68, 0.95)
		env.ambient_light_energy = 0.8
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
		light.light_energy = 1.15
		light.light_color = Color(1.0, 0.96, 0.88)
		vp.add_child(light)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = xf
		vp.add_child(mi)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = side
		cam.near = 0.1
		cam.far = 80.0
		cam.position = Vector3(cen.x, cen.y, cen.z + 30.0)
		vp.add_child(cam)
		cam.current = true
		vps.append(vp)
		info.append(Vector3(side, cen.y, 1.0))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var atlas := Image.create(TILE * 2, TILE * 2, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var ok: bool = false
	for i in range(vps.size()):
		var v = vps[i]
		if v == null:
			continue
		var vp2: SubViewport = v as SubViewport
		var img: Image = vp2.get_texture().get_image()
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(img, Rect2i(0, 0, TILE, TILE), Vector2i((i % 2) * TILE, (i / 2) * TILE))
			ok = true
		else:
			info[i] = Vector3(1.0, 0.0, 0.0)
		vp2.queue_free()
	if not ok:
		return out
	atlas.generate_mipmaps()
	out["tex"] = ImageTexture.create_from_image(atlas)
	out["info"] = info
	return out
