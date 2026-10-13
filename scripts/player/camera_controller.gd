class_name CameraController
extends Node3D
## Cámara en primera persona: giro con el dedo, sensibilidad X/Y, eje Y invertible,
## balanceo al caminar opcional, FOV configurable, giroscopio opcional y pequeñas sacudidas.

const LOOK_SCALE := 0.0042

var player: CharacterBody3D
var camera: Camera3D
var pitch := 0.0
var bob_phase := 0.0
var shake := 0.0
var sink := 0.0
var _bob_offset := Vector3.ZERO


func setup(p: CharacterBody3D) -> void:
	player = p
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 420.0
	add_child(camera)
	camera.make_current()
	EventBus.settings_changed.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	camera.fov = float(SettingsManager.get_value("fov", 72.0))


func apply_look(delta: float) -> void:
	var d := InputState.look_delta
	var sx := float(SettingsManager.get_value("sens_x", 1.0))
	var sy := float(SettingsManager.get_value("sens_y", 1.0))
	var inv := -1.0 if SettingsManager.get_value("invert_y", false) else 1.0
	player.rotation.y -= d.x * LOOK_SCALE * sx
	pitch -= d.y * LOOK_SCALE * sy * inv
	if SettingsManager.get_value("gyro", false):
		var g := Input.get_gyroscope()
		# Horizontal: giro sobre el eje vertical del teléfono en apaisado.
		player.rotation.y += g.x * delta * 1.2 * sx
		pitch += g.y * delta * 1.0 * sy * inv
	pitch = clampf(pitch, deg_to_rad(-82.0), deg_to_rad(80.0))
	rotation.x = pitch


func update_effects(delta: float, speed: float, on_floor: bool, pile_h: float) -> void:
	var bob_on: bool = SettingsManager.get_value("head_bob", true)
	if bob_on and on_floor and speed > 0.5:
		bob_phase += delta * speed * 1.9
		_bob_offset = Vector3(cos(bob_phase * 0.5) * 0.025, absf(sin(bob_phase)) * 0.035, 0.0)
	else:
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, minf(delta * 8.0, 1.0))
	sink = lerpf(sink, clampf(pile_h * 0.45, 0.0, 0.5), minf(delta * 4.0, 1.0))
	shake = maxf(shake - delta * 3.0, 0.0)
	var sh := Vector3.ZERO
	if shake > 0.0:
		sh = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.02
	camera.position = _bob_offset + sh + Vector3(0, -sink, 0)


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


func forward() -> Vector3:
	return -camera.global_transform.basis.z
