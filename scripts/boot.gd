extends Node3D
# Entry point. Shows the loading screen first, then starts the anime version;
# if it cannot load for any reason the classic prototype is used instead.

const NEW_PATH := "res://scripts/anime/game.gd"
const OLD_PATH := "res://scripts/world.gd"
const LOAD_PATH := "res://scripts/anime/loading.gd"

func _ready() -> void:
	var ld = null
	var ls = load(LOAD_PATH)
	if ls != null and ls is GDScript and (ls as GDScript).can_instantiate():
		ld = ls.new()
		add_child(ld)
		await get_tree().process_frame
		await get_tree().process_frame
	var s = load(NEW_PATH)
	if s != null and s is GDScript and (s as GDScript).can_instantiate():
		var g = s.new()
		add_child(g)
		return
	push_warning("anime game failed to load, starting classic version")
	if ld != null:
		ld.queue_free()
	var o = load(OLD_PATH)
	if o != null and o is GDScript:
		var w = o.new()
		add_child(w)
