extends Node3D
# Glowing battery that spins and bobs; collected when the player gets close.

const UT = preload("res://scripts/util.gd")
const TOON = preload("res://scripts/toon.gd")
signal collected

var _spin: Node3D
var _t: float = 0.0
var _base_y: float = 0.0
var _player = null

func _ready() -> void:
	_base_y = position.y
	_t = randf() * 6.0
	_spin = Node3D.new()
	_spin.position = Vector3(0, 0.9, 0)
	add_child(_spin)
	var m: Node3D = UT.place_item(_spin, "battery", 0.7, 0.0)
	if m != null:
		m.position = Vector3(0, -0.35, 0)
		for n in m.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).material_override = TOON.mat(Color(1.0, 0.9, 0.4), null, false, Color(1.0, 0.8, 0.2), 1.2)
	else:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		mi.mesh = sm
		mi.material_override = TOON.mat(Color(1.0, 0.9, 0.4), null, false, Color(1.0, 0.8, 0.2), 1.2)
		_spin.add_child(mi)

func _process(delta: float) -> void:
	_t += delta
	_spin.rotation.y += delta * 1.8
	_spin.position.y = 0.9 + sin(_t * 2.0) * 0.15
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	if _player.global_position.distance_to(global_position + Vector3(0, 0.9, 0)) < 1.8:
		collected.emit()
		queue_free()
