class_name RecycleBin
extends Interactable
## Contenedor de reciclaje: acepta bolsas lanzadas o entregadas en mano y paga por ellas.

var _burst: CPUParticles3D


func _ready() -> void:
	collision_layer = LAYER_WORLD | LAYER_INTERACT
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = LAYER_BAG
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 1.0, 1.3)
	cs.shape = bs
	cs.position = Vector3(0, 1.75, 0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body)
	_burst = CPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 26
	_burst.lifetime = 1.1
	_burst.explosiveness = 0.9
	_burst.mesh = MeshFactory.leaf_mesh()
	_burst.direction = Vector3.UP
	_burst.spread = 40.0
	_burst.initial_velocity_min = 2.5
	_burst.initial_velocity_max = 5.0
	_burst.angular_velocity_min = -400.0
	_burst.angular_velocity_max = 400.0
	_burst.scale_amount_min = 0.9
	_burst.scale_amount_max = 1.5
	_burst.color = Color(0.95, 0.55, 0.15)
	_burst.position = Vector3(0, 1.8, 0)
	var pm := MeshFactory.mat(Color(0.95, 0.6, 0.2))
	_burst.material_override = pm
	add_child(_burst)


func get_prompt(player: Node) -> String:
	if player.bags.is_carrying():
		return "Depositar bolsa"
	if player.bags.count > 0:
		return "Cierra la bolsa primero"
	return "Contenedor de reciclaje"


func is_available(player: Node) -> bool:
	return player.bags.is_carrying()


func interact(player: Node) -> void:
	player.bags.deposit_held(self)


func _on_body(body: Node) -> void:
	if body is LeafBag and not body.consumed:
		var dist := 0.0
		if body.thrown_from != Vector3.INF:
			var a := Vector2(body.thrown_from.x, body.thrown_from.z)
			dist = a.distance_to(Vector2(global_position.x, global_position.z))
		accept(body.leaves, body.value, dist)
		body.consumed = true
		body.queue_free()


func accept(leaves: int, base_value: float, distance: float) -> void:
	var money := EconomyManager.deposit_leaves(base_value, global_position + Vector3(0, 2.2, 0))
	ProgressManager.add_stat("bags_delivered", 1)
	if distance >= 8.0:
		ProgressManager.add_stat("long_throws", 1)
		EventBus.toast.emit("¡Canasta!", "Lanzamiento de %.1f m" % distance, "reward")
	EventBus.bag_delivered.emit(leaves, money, distance)
	AudioManager.play_sfx("bin_deposit", global_position, 0.0, 0.05)
	AudioManager.play_ui("cash", -3.0)
	HapticManager.pulse(45, 0.55)
	_burst.restart()
	SaveManager.request_save()
