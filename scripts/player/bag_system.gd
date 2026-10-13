class_name BagSystem
extends Node
## Bolsa abierta (se llena al recoger), bolsa cerrada en mano (se lleva o se lanza)
## y bolsas sueltas por el mundo. También se encarga de guardarlas.

var player: Node
var count := 0
var value := 0.0
var held_leaves := 0
var held_value := 0.0
var _full_warned := false
var _held_visual: MeshInstance3D


func setup(p: Node) -> void:
	player = p
	_held_visual = MeshInstance3D.new()
	_held_visual.mesh = MeshFactory.bag_mesh()
	_held_visual.material_override = MeshFactory.mat(Color(0.16, 0.32, 0.18), 0.55)
	_held_visual.position = Vector3(0.0, -0.55, -0.85)
	_held_visual.visible = false
	_held_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.cam.camera.add_child(_held_visual)
	SaveManager.register("bags", self)


func capacity() -> int:
	return int(UpgradeManager.get_value("bag_capacity"))


func in_flight() -> int:
	var sim: LeafSimulationSystem = player.leaf_manager.sim
	return sim.in_flight[LeafManager.P_HAND] + sim.in_flight[LeafManager.P_VACUUM]


func space() -> int:
	return maxi(capacity() - count - in_flight(), 0)


func is_full() -> bool:
	return count >= capacity()


func is_carrying() -> bool:
	return held_leaves > 0


func add(n: int, v: float, source: String) -> void:
	if n <= 0:
		return
	count += n
	value += v
	ProgressManager.add_stat("leaves_collected", n)
	if source == "vacuum":
		ProgressManager.add_stat("leaves_vacuumed", n)
	EventBus.leaves_collected.emit(n, source)
	EventBus.bag_changed.emit(count, capacity())
	if count >= capacity() and not _full_warned:
		_full_warned = true
		AudioManager.play_ui("bag_full")
		HapticManager.pulse(30, 0.5)
		EventBus.hint.emit("¡Bolsa llena! Mantén INTERACTUAR para cerrarla.")


func close_bag() -> void:
	if count <= 0 or is_carrying():
		return
	held_leaves = count
	held_value = value
	count = 0
	value = 0.0
	_full_warned = false
	ProgressManager.add_stat("bags_used", 1)
	EventBus.bag_closed.emit(held_leaves)
	EventBus.bag_changed.emit(count, capacity())
	AudioManager.play_sfx("bag_close", Vector3.INF, -2.0)
	HapticManager.pulse(35, 0.55)
	_update_visual()
	SaveManager.request_save()


func throw_bag(strength: float = 1.0) -> void:
	if not is_carrying():
		return
	var cam: Camera3D = player.cam.camera
	var fwd := -cam.global_transform.basis.z
	var bag := _spawn(cam.global_position + fwd * 0.9 + Vector3(0, -0.2, 0), held_leaves, held_value)
	var force := float(UpgradeManager.get_value("bag_throw")) * strength
	bag.linear_velocity = fwd * force + Vector3(0, 2.5, 0) + player.velocity * 0.5
	bag.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	bag.thrown_from = player.global_position
	held_leaves = 0
	held_value = 0.0
	AudioManager.play_sfx("bag_throw", Vector3.INF, -3.0)
	HapticManager.pulse(25, 0.4)
	_update_visual()


func drop_bag() -> void:
	if not is_carrying():
		return
	var cam: Camera3D = player.cam.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	var bag := _spawn(player.global_position + fwd.normalized() * 1.0 + Vector3(0, 1.0, 0), held_leaves, held_value)
	bag.linear_velocity = player.velocity * 0.5
	held_leaves = 0
	held_value = 0.0
	_update_visual()


func pick_up(bag: LeafBag) -> void:
	if is_carrying() or bag.consumed:
		return
	held_leaves = bag.leaves
	held_value = bag.value
	bag.consumed = true
	bag.queue_free()
	AudioManager.play_sfx("bag_close", Vector3.INF, -6.0, 0.15)
	_update_visual()


func deposit_held(bin: RecycleBin) -> void:
	if not is_carrying():
		return
	bin.accept(held_leaves, held_value, 0.0)
	held_leaves = 0
	held_value = 0.0
	_update_visual()


func _spawn(pos: Vector3, n: int, v: float) -> LeafBag:
	var bag := LeafBag.new()
	bag.setup(n, v)
	player.get_parent().add_child(bag)
	bag.global_position = pos
	return bag


func _update_visual() -> void:
	_held_visual.visible = is_carrying()
	if is_carrying():
		_held_visual.scale = Vector3.ONE * clampf(0.55 + held_leaves / 600.0, 0.6, 1.3) * 0.8


func to_save() -> Dictionary:
	var ground := []
	for b in player.get_tree().get_nodes_in_group("leaf_bags"):
		if is_instance_valid(b) and not b.consumed:
			ground.append(b.to_dict())
	return {"count": count, "value": value, "held": held_leaves, "held_value": held_value, "ground": ground}


func from_save(d: Dictionary) -> void:
	count = int(d.get("count", 0))
	value = float(d.get("value", 0.0))
	held_leaves = int(d.get("held", 0))
	held_value = float(d.get("held_value", 0.0))
	for g in d.get("ground", []):
		var bag := _spawn(Vector3(g["x"], float(g["y"]) + 0.3, g["z"]), int(g["n"]), float(g["v"]))
		bag.sleeping = true
	_update_visual()
	EventBus.bag_changed.emit(count, capacity())
