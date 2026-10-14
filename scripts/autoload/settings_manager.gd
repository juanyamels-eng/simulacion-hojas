extends Node
## Ajustes del jugador (independientes de la partida). Se guardan en user://settings.cfg.

const PATH := "user://settings.cfg"

var values := {
	"graphics": "auto",      # low, medium, high, auto
	"fps": 60,               # 30, 60 o 0 (sin límite)
	"sens_x": 1.0,
	"sens_y": 1.0,
	"invert_y": false,
	"head_bob": true,
	"fov": 72.0,
	"gyro": false,
	"music": 0.6,
	"sfx": 0.85,
	"ambient": 0.7,
	"haptics": true,
	"show_fps": false,
	"highlight_leaves": false,   # «Resaltar hojas»: contorno de color intenso en todas las hojas
	"joystick_size": 1.0,
}


func _ready() -> void:
	_ensure_buses()
	load_settings()
	apply()


func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func get_value(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	apply()
	save_settings()
	EventBus.settings_changed.emit()


func apply() -> void:
	Engine.max_fps = int(values["fps"])
	_set_bus("Music", float(values["music"]))
	_set_bus("SFX", float(values["sfx"]))
	_set_bus("Ambient", float(values["ambient"]))


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in values.keys():
		if cfg.has_section_key("settings", k):
			var v: Variant = cfg.get_value("settings", k)
			if typeof(v) == typeof(values[k]) or (typeof(values[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				values[k] = v
