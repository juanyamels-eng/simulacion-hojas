class_name SuctionDuct
extends Interactable
## Conducto de aspiración averiado. Al repararlo absorbe automáticamente las hojas cercanas.

var def: Dictionary
var point := 2
var leaf_manager: LeafManager
var repaired := false
var _fan: Node3D
var _lamp: MeshInstance3D
var _budget := 0.0
var _swirl: CPUParticles3D
static var _near := {}


func setup(d: Dictionary, idx: int, lm: LeafManager) -> void:
	def = d
	point = LeafManager.P_DUCT0 + idx
	leaf_manager = lm
	collision_layer = LAYER_WORLD | LAYER_INTERACT
	var metal := MeshFactory.mat(Color(0.42, 0.45, 0.47), 0.5)
	var dark := MeshFactory.mat(Color(0.15, 0.15, 0.16), 0.7)
	var base := MeshInstance3D.new()
	base.mesh = MeshFactory.cyl(0.9, 1.0, 0.25, 14)
	base.material_override = metal
	base.position.y = 0.12
	add_child(base)
	var grate := MeshInstance3D.new()
	grate.mesh = MeshFactory.cyl(0.75, 0.75, 0.05, 14)
	grate.material_override = dark
	grate.position.y = 0.26
	add_child(grate)
	_fan = Node3D.new()
	_fan.position.y = 0.3
	add_child(_fan)
	for k in 3:
		var blade := MeshInstance3D.new()
		blade.mesh = MeshFactory.box(Vector3(1.3, 0.03, 0.16))
		blade.material_override = metal
		blade.rotation.y = k * PI / 3.0
		_fan.add_child(blade)
	var box := MeshInstance3D.new()
	box.mesh = MeshFactory.box(Vector3(0.6, 0.8, 0.5))
	box.material_override = MeshFactory.mat(Color(0.55, 0.3, 0.18))
	box.position = Vector3(1.3, 0.4, 0)
	add_child(box)
	_lamp = MeshInstance3D.new()
	_lamp.mesh = MeshFactory.sphere(0.09, 6, 4)
	_lamp.position = Vector3(1.3, 0.88, 0)
	add_child(_lamp)
	make_shape(self, Vector3(2.4, 0.5, 2.0), Vector3(0.3, 0.25, 0))
	_swirl = CPUParticles3D.new()
	_swirl.amount = 16
	_swirl.lifetime = 0.8
	_swirl.mesh = MeshFactory.sphere(0.025, 4, 2)
	_swirl.material_override = MeshFactory.mat(Color(0.9, 0.85, 0.7), 1.0, 0.5)
	_swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_swirl.emission_ring_axis = Vector3.UP
	_swirl.emission_ring_radius = 1.6
	_swirl.emission_ring_inner_radius = 1.0
	_swirl.emission_ring_height = 0.1
	_swirl.radial_accel_min = -6.0
	_swirl.radial_accel_max = -4.0
	_swirl.tangential_accel_min = 3.0
	_swirl.tangential_accel_max = 5.0
	_swirl.gravity = Vector3.ZERO
	_swirl.position.y = 0.4
	_swirl.emitting = false
	add_child(_swirl)
	set_repaired(AreaManager.ducts.get(def["id"], false), false)


func set_repaired(on: bool, animated: bool) -> void:
	repaired = on
	_lamp.material_override = MeshFactory.mat(Color(0.3, 1.0, 0.4) if on else Color(1.0, 0.25, 0.15), 0.4, 2.0)
	_swirl.emitting = on
	if on and animated:
		AudioManager.play_sfx("duct_on", global_position)


func get_prompt(_player: Node) -> String:
	if repaired:
		return "Conducto funcionando"
	return "Reparar conducto · " + EconomyManager.format_money(def["cost"])


func is_available(_player: Node) -> bool:
	return not repaired and EconomyManager.can_afford(def["cost"])


func interact(_player: Node) -> void:
	if repaired:
		return
	if not EconomyManager.spend(def["cost"]):
		AudioManager.play_ui("error")
		return
	AreaManager.ducts[def["id"]] = true
	ProgressManager.set_stat("ducts_repaired", AreaManager.ducts.size())
	EventBus.duct_repaired.emit(def["id"])
	EventBus.toast.emit("Conducto reparado", "Absorbe hojas cercanas automáticamente", "reward")
	set_repaired(true, true)
	SaveManager.request_save()


func _process(delta: float) -> void:
	if not repaired:
		return
	_fan.rotation.y += delta * 9.0
	var sim := leaf_manager.sim
	var center := global_position + Vector3(0, 0.3, 0)
	sim.suck_pos[point] = center
	sim.suck_acc[point] = 14.0
	_budget += float(UpgradeManager.get_value("duct_rate")) * delta
	var n := int(_budget)
	if n > 0:
		_budget -= n
		sim.capture_radius(center, float(UpgradeManager.get_value("duct_radius")), n, point, 1.0)
	var got := sim.take_arrived(point)
	if got.x > 0:
		EconomyManager.deposit_leaves(got.y)
		ProgressManager.add_stat("leaves_collected", got.x)
	var near := 0.0
	if GameManager.world and GameManager.world.player:
		near = clampf(1.0 - GameManager.world.player.global_position.distance_to(global_position) / 14.0, 0.0, 1.0)
	_near[point] = near
	var loudest := 0.0
	for v in _near.values():
		loudest = maxf(loudest, v)
	AudioManager.set_loop("duct_loop", loudest * 0.5)
