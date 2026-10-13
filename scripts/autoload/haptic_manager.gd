extends Node
## Vibración sutil con limitación de frecuencia para no saturar.

var _cooldown := 0.0


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


## duration_ms: duración; strength: 0..1 (amplitud en Android 8+).
func pulse(duration_ms: int, strength: float = 0.5, min_gap: float = 0.06) -> void:
	if not SettingsManager.get_value("haptics", true) or _cooldown > 0.0:
		return
	if not OS.has_feature("mobile"):
		return
	_cooldown = min_gap
	Input.vibrate_handheld(duration_ms, clampf(strength, 0.05, 1.0))


## Vibración muy ligera para contacto continuo (rastrillo tocando hojas).
func tick(strength: float = 0.25) -> void:
	pulse(12, strength, 0.11)
