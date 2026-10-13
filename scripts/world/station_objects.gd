class_name StationObject
extends Interactable
## Objetos de interacción simples: taller (tienda), notas, postales y trampilla secreta.

enum Kind { SHOP, NOTE, POSTCARD, HATCH, LADDER, ROBOT }

var kind := Kind.SHOP
var data := {}
var leaf_manager: LeafManager
var _covered := true
var _check_timer := 0.0
var _sparkle: CPUParticles3D


func setup(k: Kind, d: Dictionary = {}) -> void:
	kind = k
	data = d
	if kind == Kind.POSTCARD or kind == Kind.HATCH:
		_sparkle = CPUParticles3D.new()
		_sparkle.amount = 6
		_sparkle.lifetime = 1.2
		_sparkle.mesh = MeshFactory.sphere(0.03, 4, 2)
		_sparkle.material_override = MeshFactory.mat(Color(1.0, 0.95, 0.6), 0.5, 3.0)
		_sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_sparkle.emission_sphere_radius = 0.35
		_sparkle.direction = Vector3.UP
		_sparkle.gravity = Vector3(0, 0.4, 0)
		_sparkle.initial_velocity_min = 0.1
		_sparkle.initial_velocity_max = 0.4
		_sparkle.position = Vector3(0, 0.15, 0)
		_sparkle.emitting = false
		add_child(_sparkle)


func _process(delta: float) -> void:
	if leaf_manager == null:
		return
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = 0.5
	var p := global_position
	_covered = leaf_manager.sim.count_in_radius(p, 0.7 if kind == Kind.POSTCARD else 1.2) > 2
	if _sparkle:
		_sparkle.emitting = not _covered


func get_prompt(_player: Node) -> String:
	match kind:
		Kind.SHOP: return "Abrir el taller (mejoras)"
		Kind.NOTE: return "Leer: " + String(data.get("title", "nota"))
		Kind.POSTCARD: return "Hay algo bajo las hojas…" if _covered else "Recoger postal"
		Kind.HATCH: return "Hay algo bajo las hojas…" if _covered else "Abrir trampilla"
		Kind.LADDER: return "Subir al jardín"
		Kind.ROBOT: return "Brizna (sin batería)" if not ProgressManager.has_flag("robot_found") else "Brizna espera en el taller"
	return ""


func is_available(_player: Node) -> bool:
	if kind == Kind.POSTCARD or kind == Kind.HATCH:
		return not _covered
	return true


func interact(player: Node) -> void:
	match kind:
		Kind.SHOP:
			EventBus.open_menu.emit("shop")
		Kind.NOTE:
			CollectibleManager.read_note(data.get("id", ""))
			EventBus.note_read.emit(data.get("title", ""), data.get("text", ""))
			AudioManager.play_ui("paper")
		Kind.POSTCARD:
			CollectibleManager.collect(data["id"])
			queue_free()
		Kind.HATCH:
			ProgressManager.set_flag("secret_found")
			AreaManager.unlock_zone("taller_secreto")
			AchievementManager.unlock("secret")
			AudioManager.play_sfx("gate_open", global_position)
			player.teleport(Vector3(73.0, Terrain.SECRET_FLOOR + 0.2, -30.0), PI)
		Kind.LADDER:
			player.teleport(Vector3(8.0, 0.0, -53.5), 0.0)
		Kind.ROBOT:
			if not ProgressManager.has_flag("robot_found"):
				ProgressManager.set_flag("robot_found")
				EventBus.note_read.emit("Brizna", "Un pequeño robot barrendero, dormido y cubierto de polvo. En su pecho, una etiqueta: «Propiedad de C. Albor. Si me encuentras, cárgame en el taller (Automatización)».")
				AudioManager.play_ui("collect")
