extends MeshInstance3D
# Floating billboard health bar. Appears for 3 s after each change.

var _mat: ShaderMaterial = null
var _t: float = 0.0

func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.13)
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/anime/hpbar.gdshader") as Shader
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

func set_ratio(r: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("ratio", clampf(r, 0.0, 1.0))
	_t = 3.0
	visible = true

func _process(delta: float) -> void:
	if _t > 0.0:
		_t -= delta
		if _t <= 0.0:
			visible = false
