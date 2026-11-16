extends Node3D
# Floating glowing pickup. kind "crystal" counts for the quest, "heal" restores HP.

const TOON = preload("res://scripts/anime/toon.gd")
const FX = preload("res://scripts/anime/fx.gd")

signal collected

var kind: String = "crystal"
var _spin: Node3D
var _halo: MeshInstance3D
var _t: float = 0.0
var _base_y: float = 0.0
var _player = null
var _done: bool = false

func _ready() -> void:
	_base_y = position.y
	_t = randf() * 6.0
	if kind == "crystal":
		add_to_group("crystal")
	else:
		add_to_group("heal")
	_spin = Node3D.new()
	_spin.position = Vector3(0.0, 1.0, 0.0)
	add_child(_spin)
	var col: Color = Color(0.45, 0.85, 1.0)
	var glow: Color = Color(0.3, 0.8, 1.0)
	if kind != "crystal":
		col = Color(1.0, 0.55, 0.7)
		glow = Color(1.0, 0.4, 0.6)
	var m: ShaderMaterial = TOON.mat(col, null, false, glow, 1.6, 1.0, 0.8)
	m.next_pass = TOON.outline(0.02)
	if kind == "crystal":
		var up := MeshInstance3D.new()
		up.mesh = _cone(false)
		up.material_override = m
		up.position = Vector3(0.0, 0.2, 0.0)
		_spin.add_child(up)
		var dn := MeshInstance3D.new()
		dn.mesh = _cone(false)
		dn.material_override = m
		dn.position = Vector3(0.0, -0.2, 0.0)
		dn.rotation_degrees = Vector3(180.0, 0.0, 0.0)
		_spin.add_child(dn)
	else:
		var sp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.4
		sp.mesh = sm
		sp.material_override = m
		_spin.add_child(sp)
	_halo = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.8, 1.8)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.albedo_texture = FX.dot_tex()
	hm.albedo_color = Color(glow.r, glow.g, glow.b, 0.55)
	hm.disable_fog = true
	q.material = hm
	_halo.mesh = q
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin.add_child(_halo)
	var sparks := CPUParticles3D.new()
	sparks.amount = 6
	sparks.lifetime = 1.4
	sparks.mesh = FX.particle_mesh()
	sparks.direction = Vector3.UP
	sparks.spread = 40.0
	sparks.initial_velocity_min = 0.2
	sparks.initial_velocity_max = 0.5
	sparks.gravity = Vector3.ZERO
	sparks.scale_amount_min = 0.05
	sparks.scale_amount_max = 0.10
	sparks.color = Color(glow.r, glow.g, glow.b, 0.9)
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.35
	sparks.local_coords = true
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin.add_child(sparks)

func _cone(_flip: bool) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.24
	c.height = 0.4
	c.radial_segments = 4
	c.rings = 1
	return c

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_spin.rotation.y += delta * 1.8
	_spin.position.y = 1.0 + sin(_t * 2.0) * 0.15
	_halo.scale = Vector3.ONE * (1.0 + sin(_t * 3.0) * 0.12)
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	var to: Vector3 = _player.global_position + Vector3(0.0, 0.9, 0.0) - (global_position + Vector3(0.0, 1.0, 0.0))
	var dist: float = to.length()
	if kind != "crystal" and dist < 6.0 and dist > 0.01:
		global_position += to.normalized() * minf(dist, 7.0 * delta)
	if dist < 1.7:
		_collect()

func _collect() -> void:
	_done = true
	var col: Color = Color(0.5, 0.9, 1.0)
	if kind == "heal":
		col = Color(1.0, 0.6, 0.75)
		if _player != null and _player.has_method("heal"):
			_player.call("heal", 25.0)
		FX.sfx(self, "heal", -2.0)
	else:
		FX.sfx(self, "pickup", 0.0)
		FX.vibrate(25)
	FX.burst(self, global_position + Vector3(0.0, 1.0, 0.0), col, 18, 5.0, 0.16, 0.6, 3.0)
	FX.ring(self, global_position, 2.4, col, 0.4)
	if kind == "crystal":
		collected.emit()
	queue_free()
