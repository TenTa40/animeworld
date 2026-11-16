extends RefCounted
# Cel-shading helpers (toon material + inverted-hull outline).

const UT = preload("res://scripts/anime/util.gd")
const SH_TOON := "res://shaders/anime/toon.gdshader"
const SH_OUT := "res://shaders/anime/outline.gdshader"

static func mat(color: Color, tex: Texture2D = null, vcol: bool = false, emission: Color = Color(0, 0, 0), energy: float = 0.0, spec: float = 0.0, rim: float = -1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SH_TOON) as Shader
	m.set_shader_parameter("albedo_color", color)
	if tex != null:
		m.set_shader_parameter("albedo_tex", tex)
		m.set_shader_parameter("use_tex", true)
	m.set_shader_parameter("use_vcol", vcol)
	m.set_shader_parameter("emission_color", emission)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("spec_strength", spec)
	if rim >= 0.0:
		m.set_shader_parameter("rim_strength", rim)
	return m

static func outline(thickness: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SH_OUT) as Shader
	m.set_shader_parameter("thickness", thickness)
	return m

# root must already be inside the scene tree (its scale is read to keep the
# outline the same width in the world). Returns the materials that were set.
static func apply_outline(root: Node3D, thickness_world: float, base: ShaderMaterial) -> Array:
	var out: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null:
			continue
		var sc: float = mi.global_transform.basis.get_scale().x
		if sc < 0.0001:
			sc = 1.0
		var m: ShaderMaterial = base.duplicate() as ShaderMaterial
		m.next_pass = outline(thickness_world / sc)
		mi.material_override = m
		out.append(m)
	return out

# Kenney character (mesh + run animation in run.fbx) with a skin and outline.
# Returns {"model": Node3D, "anim": AnimationPlayer, "mats": Array} or {} if missing.
static func character(parent: Node3D, skin: String, height: float, tint: Color) -> Dictionary:
	var w: Node3D = UT.place_model(parent, "res://assets/models/characters/run.fbx", height, 0.0, 0.0)
	if w == null:
		return {}
	var tex: Texture2D = null
	var tp: String = "res://assets/models/characters/%s.png" % skin
	if ResourceLoader.exists(tp):
		tex = load(tp) as Texture2D
	var base: ShaderMaterial = mat(tint, tex)
	var mats: Array = apply_outline(w, 0.03, base)
	var ap: AnimationPlayer = UT.play_first_anim(w)
	return {"model": w, "anim": ap, "mats": mats}

# Outline for a model that keeps its own materials. Surfaces without a texture
# get a toon colour (fallback). Returns every material that can flash.
static func outline_existing(root: Node3D, thickness_world: float, fallback: Color) -> Array:
	var out: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var sc: float = mi.global_transform.basis.get_scale().x
		if sc < 0.0001:
			sc = 1.0
		for i in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(i)
			var bm: BaseMaterial3D = mat as BaseMaterial3D
			if bm != null and bm.albedo_texture != null:
				var d: BaseMaterial3D = bm.duplicate() as BaseMaterial3D
				d.next_pass = outline(thickness_world / sc)
				mi.set_surface_override_material(i, d)
				out.append(d)
			else:
				var t: ShaderMaterial = mat(fallback)
				t.next_pass = outline(thickness_world / sc)
				mi.set_surface_override_material(i, t)
				out.append(t)
	return out
