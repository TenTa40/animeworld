extends CanvasLayer
# In-game log window: "LOG" button (top right) opens a copyable text box with the hero load message
# and the tail of Godot's log file (user://logs/godot.log).

var info: String = ""
var _btn: Button
var _panel: PanelContainer
var _text: TextEdit

func _ready() -> void:
	layer = 120
	_btn = Button.new()
	_btn.text = "LOG"
	_btn.custom_minimum_size = Vector2(110.0, 64.0)
	_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_btn.position = Vector2(-130.0, 110.0)
	_btn.pressed.connect(_toggle)
	add_child(_btn)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 60.0
	_panel.offset_right = -60.0
	_panel.offset_top = 30.0
	_panel.offset_bottom = -30.0
	_panel.visible = false
	add_child(_panel)
	var vb := VBoxContainer.new()
	_panel.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var b1 := Button.new()
	b1.text = "Refresh"
	b1.custom_minimum_size = Vector2(160.0, 60.0)
	b1.pressed.connect(_refresh)
	hb.add_child(b1)
	var b2 := Button.new()
	b2.text = "Copy all"
	b2.custom_minimum_size = Vector2(160.0, 60.0)
	b2.pressed.connect(_copy)
	hb.add_child(b2)
	var b3 := Button.new()
	b3.text = "Close"
	b3.custom_minimum_size = Vector2(160.0, 60.0)
	b3.pressed.connect(_toggle)
	hb.add_child(b3)
	_text = TextEdit.new()
	_text.editable = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("font_size", 15)
	vb.add_child(_text)

func _toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_refresh()

func _read_log() -> String:
	var path: String = "user://logs/godot.log"
	if not FileAccess.file_exists(path):
		return "(no log file: " + path + ")"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "(cannot open log)"
	var s: String = f.get_as_text()
	f.close()
	var lines: PackedStringArray = s.split("\n")
	var from: int = maxi(0, lines.size() - 250)
	return "\n".join(lines.slice(from))

func _refresh() -> void:
	var head: String = "iko " + str(ProjectSettings.get_setting("application/config/name", "")) + "\n"
	head += "renderer: " + str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) + "\n"
	head += "gpu: " + RenderingServer.get_video_adapter_name() + "\n"
	head += info + "\n----- godot.log (tail) -----\n"
	_text.text = head + _read_log()
	_text.scroll_vertical = 1000000.0

func _copy() -> void:
	DisplayServer.clipboard_set(_text.text)
