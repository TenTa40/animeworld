extends Node3D
# Entry point. Starts the anime version; if it cannot load for any reason the classic prototype is used instead.

const NEW_PATH := "res://scripts/anime/game.gd"
const OLD_PATH := "res://scripts/world.gd"

func _ready() -> void:
	var s = load(NEW_PATH)
	if s != null and s is GDScript and (s as GDScript).can_instantiate():
		var g = s.new()
		add_child(g)
		return
	push_warning("anime game failed to load, starting classic version")
	var o = load(OLD_PATH)
	if o != null and o is GDScript:
		var w = o.new()
		add_child(w)
