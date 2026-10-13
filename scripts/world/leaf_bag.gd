class_name LeafBag
extends RigidBody3D
## Bolsa cerrada con hojas: se puede levantar, lanzar y llevar al contenedor.

var leaves := 0
var value := 0.0
var thrown_from := Vector3.INF
var consumed := false
var _mesh: MeshInstance3D
var _last_sound := 0.0


func setup(count: int, base_value: float) -> void:
	leaves = count
	value = base_value
	collision_layer = Interactable.LAYER_BAG | Interactable.LAYER_INTERACT
	collision_mask = Interactable.LAYER_WORLD | Interactable.LAYER_BAG
	mass = 1.5 + count * 0.004
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	angular_damp = 1.5
	linear_damp = 0.15
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.15
	physics_material_override = pm
	var fill := clampf(0.55 + count / 600.0, 0.6, 1.35)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = MeshFactory.bag_mesh()
	_mesh.material_override = MeshFactory.mat(Color(0.16, 0.32, 0.18), 0.55)
	_mesh.scale = Vector3.ONE * fill
	add_child(_mesh)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.38 * fill
	cs.shape = sh
	add_child(cs)
	body_entered.connect(_on_hit)
	add_to_group("leaf_bags")


func _on_hit(_body: Node) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t - _last_sound > 0.25 and linear_velocity.length() > 1.5:
		_last_sound = t
		AudioManager.play_sfx("bag_thud", global_position, -4.0, 0.1)


func get_prompt(_player: Node) -> String:
	return "Coger bolsa (%d hojas)" % leaves


func to_dict() -> Dictionary:
	var p := global_position
	return {"x": p.x, "y": p.y, "z": p.z, "n": leaves, "v": value}
