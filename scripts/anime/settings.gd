extends RefCounted
# Saved player settings (user://settings.cfg).

const PATH := "user://settings.cfg"

static var shadows: bool = false
static var quality: int = 1       # 0 low, 1 medium, 2 high
static var music: float = 0.6     # 0..1
static var sfx: float = 1.0       # 0..1
static var vibrate: bool = true
static var debug: bool = false
static var auto_perf: bool = true

static func load_cfg() -> void:
	var mobile: bool = OS.has_feature("mobile")
	shadows = not mobile
	quality = 1 if mobile else 2
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	shadows = bool(cf.get_value("g", "shadows", shadows))
	quality = clampi(int(cf.get_value("g", "quality", quality)), 0, 2)
	music = clampf(float(cf.get_value("a", "music", music)), 0.0, 1.0)
	sfx = clampf(float(cf.get_value("a", "sfx", sfx)), 0.0, 1.0)
	vibrate = bool(cf.get_value("g", "vibrate", vibrate))
	debug = bool(cf.get_value("g", "debug", debug))
	auto_perf = bool(cf.get_value("g", "auto_perf", auto_perf))

static func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("g", "shadows", shadows)
	cf.set_value("g", "quality", quality)
	cf.set_value("a", "music", music)
	cf.set_value("a", "sfx", sfx)
	cf.set_value("g", "vibrate", vibrate)
	cf.set_value("g", "debug", debug)
	cf.set_value("g", "auto_perf", auto_perf)
	cf.save(PATH)
