extends Node
## Niveles gráficos y ajuste automático de complejidad según los FPS reales.

signal quality_changed(level: int)

enum { LOW, MEDIUM, HIGH }

const PRESETS := {
	LOW: {"name": "Bajo", "active_leaves": 350, "leaf_distance": 32.0, "lod_distance": 14.0, "shadows": false, "scale": 0.7, "particles": 0.4, "props_distance": 60.0},
	MEDIUM: {"name": "Medio", "active_leaves": 750, "leaf_distance": 46.0, "lod_distance": 20.0, "shadows": true, "scale": 0.85, "particles": 0.7, "props_distance": 90.0},
	HIGH: {"name": "Alto", "active_leaves": 1300, "leaf_distance": 64.0, "lod_distance": 28.0, "shadows": true, "scale": 1.0, "particles": 1.0, "props_distance": 140.0},
}

var level := MEDIUM
var auto := true
var fps_smoothed := 60.0
var _window := 0.0
var _frames := 0
var _low_streak := 0
var _high_streak := 0
var _grace := 4.0


func _ready() -> void:
	EventBus.settings_changed.connect(_from_settings)
	_from_settings()


func _from_settings() -> void:
	var g: String = SettingsManager.get_value("graphics", "auto")
	var prev := level
	auto = g == "auto"
	match g:
		"low": level = LOW
		"medium": level = MEDIUM
		"high": level = HIGH
		_:
			if not auto:
				level = MEDIUM
	if prev != level or not auto:
		quality_changed.emit(level)


func preset() -> Dictionary:
	return PRESETS[level]


func get_param(key: String) -> Variant:
	return PRESETS[level][key]


func target_fps() -> float:
	var f := int(SettingsManager.get_value("fps", 60))
	return 60.0 if f <= 0 else float(f)


func _process(delta: float) -> void:
	_frames += 1
	_window += delta
	if _window < 1.0:
		return
	var fps := _frames / _window
	_frames = 0
	_window = 0.0
	fps_smoothed = lerpf(fps_smoothed, fps, 0.5)
	if not auto or not GameManager.in_game or get_tree().paused:
		return
	if _grace > 0.0:
		_grace -= 1.0
		return
	var target := target_fps()
	if fps_smoothed < target * 0.82:
		_low_streak += 1
		_high_streak = 0
	elif fps_smoothed > target * 0.97:
		_high_streak += 1
		_low_streak = 0
	else:
		_low_streak = 0
		_high_streak = 0
	if _low_streak >= 3 and level > LOW:
		level -= 1
		_low_streak = 0
		_grace = 5.0
		quality_changed.emit(level)
	elif _high_streak >= 20 and level < HIGH:
		level += 1
		_high_streak = 0
		_grace = 8.0
		quality_changed.emit(level)
