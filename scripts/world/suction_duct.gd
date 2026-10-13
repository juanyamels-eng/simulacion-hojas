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
	# Base, rejilla, armario y tubería en una malla; las aspas en otra (giran).
	var base := MeshInstance3D.new()
	base.mesh = MeshFactory.prefab("duct_base", _base_parts)
	base.material_override = MeshFactory.prop_mat(true)
	add_child(base)
	_fan = Node3D.new()
	_fan.position.y = 0.3
	add_child(_fan)
	var fan := MeshInstance3D.new()
	fan.mesh = MeshFactory.prefab("duct_fan", _fan_parts)
	fan.material_override = MeshFactory.prop_mat(true)
	_fan.add_child(fan)
	_lamp = MeshInstance3D.new()
	_lamp.mesh = MeshFactory.sphere(0.09, 8, 5)
	_lamp.position = Vector3(1.3, 0.9, 0)
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


func _base_parts() -> Array:
	var metal := MeshFactory.pc(Color(0.46, 0.49, 0.5), MeshFactory.PAT_METAL)
	var light := MeshFactory.pc(Color(0.62, 0.64, 0.64), MeshFactory.PAT_METAL)
	var dark := MeshFactory.pc(Color(0.13, 0.13, 0.14), MeshFactory.PAT_METAL)
	var paint := MeshFactory.pc(Color(0.36, 0.45, 0.38), MeshFactory.PAT_METAL)
	var stripe := MeshFactory.pc(Color(0.95, 0.7, 0.15), MeshFactory.PAT_PLAIN)
	var p := []
	p.append([MeshFactory.cyl(0.9, 1.0, 0.25, 16), Transform3D(Basis.IDENTITY, Vector3(0, 0.125, 0)), metal])
	p.append(MeshFactory.part("cyl", Vector3(0, 0.255, 0), Vector3(1.86, 0.03, 1.86), light))
	p.append(MeshFactory.part("cyl", Vector3(0, 0.265, 0), Vector3(1.5, 0.03, 1.5), dark))
	for k in 7:
		p.append(MeshFactory.part("box", Vector3(0, 0.285, -0.54 + k * 0.18), Vector3(1.5 - absf(k - 3) * 0.16, 0.025, 0.04), metal))
	for k in 8:
		var a := k * TAU / 8.0
		p.append(MeshFactory.part("box", Vector3(cos(a) * 0.86, 0.2, sin(a) * 0.86), Vector3(0.1, 0.06, 0.03), stripe, Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, -0.35)))
	# Armario de control con panel, manómetro y tubería hasta la base.
	p.append(MeshFactory.part("box", Vector3(1.3, 0.42, 0), Vector3(0.56, 0.78, 0.46), paint))
	p.append(MeshFactory.part("box", Vector3(1.3, 0.83, 0), Vector3(0.64, 0.05, 0.54), dark))
	p.append(MeshFactory.part("box", Vector3(1.3, 0.04, 0), Vector3(0.62, 0.08, 0.52), dark))
	p.append(MeshFactory.part("box", Vector3(1.585, 0.42, 0), Vector3(0.02, 0.6, 0.36), MeshFactory.pc(Color(0.32, 0.4, 0.34), MeshFactory.PAT_METAL)))
	p.append(MeshFactory.part("box", Vector3(1.585, 0.66, 0), Vector3(0.025, 0.06, 0.38), stripe))
	p.append(MeshFactory.part("cyl", Vector3(1.6, 0.48, 0.08), Vector3(0.12, 0.02, 0.12), Color(0.95, 0.93, 0.85), Basis(Vector3.BACK, PI * 0.5)))
	p.append(MeshFactory.part("box", Vector3(1.61, 0.48, 0.1), Vector3(0.01, 0.045, 0.008), dark, Basis(Vector3.RIGHT, 0.6)))
	p.append(MeshFactory.part("box", Vector3(1.6, 0.3, -0.1), Vector3(0.03, 0.04, 0.12), dark))
	p.append(MeshFactory.part("cyl", Vector3(0.88, 0.14, 0), Vector3(0.14, 0.5, 0.14), metal, Basis(Vector3.BACK, PI * 0.5)))
	p.append(MeshFactory.part("cyl", Vector3(1.0, 0.14, 0), Vector3(0.18, 0.05, 0.18), light, Basis(Vector3.BACK, PI * 0.5)))
	p.append(MeshFactory.part("cyl", Vector3(1.3, 0.87, 0), Vector3(0.14, 0.04, 0.14), dark))
	return p


func _fan_parts() -> Array:
	var blade := MeshFactory.pc(Color(0.6, 0.62, 0.62), MeshFactory.PAT_METAL)
	var p := []
	for k in 3:
		p.append(MeshFactory.part("box", Vector3.ZERO, Vector3(1.3, 0.025, 0.17), blade, Basis(Vector3.UP, k * PI / 3.0) * Basis(Vector3.RIGHT, 0.35)))
	p.append(MeshFactory.part("cyl", Vector3(0, 0.02, 0), Vector3(0.22, 0.08, 0.22), MeshFactory.pc(Color(0.85, 0.55, 0.15), MeshFactory.PAT_METAL)))
	return p


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
