class_name BlowerTool
extends BaseTool
## Soplador: proyecta un cono de aire. Despierta las hojas del cono (de cerca a lejos)
## y les aplica fuerza mientras vuelan; también empuja las bolsas.

var _nozzle: Node3D
var _air: CPUParticles3D
var _spin := 0.0
var _haptic_t := 0.0
var power_mult := 1.0
var range_mult := 1.0
var angle_mult := 1.0
var shove := false
var loop_name := "blower_loop"


func _init() -> void:
	tool_id = "blower"


func build_model() -> void:
	add_child(model)
	model.position = Vector3(0.3, -0.32, -0.45)
	var orange := Color(0.92, 0.48, 0.15)
	part(MeshFactory.box(Vector3(0.16, 0.18, 0.3)), orange, Vector3(0, 0, 0.08))
	part(MeshFactory.cyl(0.1, 0.1, 0.08, 12), Color(0.2, 0.2, 0.22), Vector3(-0.1, 0, 0.1)).rotation.z = PI * 0.5
	var tube := part(MeshFactory.cyl(0.035, 0.05, 0.6, 10), Color(0.25, 0.25, 0.27), Vector3(0, -0.02, -0.3))
	tube.rotation.x = PI * 0.5
	part(MeshFactory.box(Vector3(0.04, 0.14, 0.04)), Color(0.2, 0.2, 0.22), Vector3(0, -0.14, 0.12))
	_nozzle = Node3D.new()
	_nozzle.position = Vector3(0, -0.02, -0.62)
	model.add_child(_nozzle)
	_air = CPUParticles3D.new()
	_air.amount = 36
	_air.lifetime = 0.35
	_air.local_coords = false
	_air.mesh = MeshFactory.box(Vector3(0.01, 0.01, 0.18))
	_air.material_override = MeshFactory.mat(Color(1, 1, 1), 1.0, 0.6)
	_air.direction = Vector3(0, 0, -1)
	_air.spread = 9.0
	_air.gravity = Vector3.ZERO
	_air.initial_velocity_min = 14.0
	_air.initial_velocity_max = 22.0
	_air.scale_amount_min = 0.5
	_air.scale_amount_max = 1.2
	_air.emitting = false
	_air.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_nozzle.add_child(_air)


func process_tool(delta: float, held: bool, _pressed: bool) -> void:
	var on := held and not player.bags.is_carrying()
	if on and not using:
		ProgressManager.mark_tool_used(tool_id)
	using = on
	_air.emitting = on
	var shake_base := 0.0
	model.position = Vector3(0.3, -0.32 - equip_offset(delta), -0.45)
	if not on:
		AudioManager.set_loop(loop_name, 0.0)
		return
	var cam := player.cam.camera
	var dir := (-cam.global_transform.basis.z - cam.global_transform.basis.y * 0.18).normalized()
	var origin := _nozzle.global_position
	var power := _power()
	var rng := float(UpgradeManager.get_value("blower_range")) * range_mult
	var half := deg_to_rad(float(UpgradeManager.get_value("blower_width")) * 0.5 * angle_mult)
	var stability := float(UpgradeManager.get_value("blower_stability"))
	var turb := (1.0 - stability) * 2.5 + 0.4
	lm.sim.add_wind(origin, dir, rng, cos(half), power * 2.2, turb)
	var budget := int(clampf(power * 2.2 * (2.0 if shove else 1.0), 6.0, 90.0))
	var woke := lm.sim.blow_wake(origin, dir, rng, half, power, budget)
	if shove:
		woke += lm.sim.shove_cone(origin, dir, rng, half, delta * power * 0.32, 420)
	if woke > 0:
		ProgressManager.add_stat("leaves_blown", woke)
		AreaManager.mark_blower_used(zone_id())
	_push_bags(origin, dir, rng, cos(half), power, delta)
	AudioManager.set_loop(loop_name, 0.75, 0.9 + power / 40.0)
	player.cam.add_shake(0.08 + shake_base)
	_haptic_t -= delta
	if _haptic_t <= 0.0:
		_haptic_t = 0.18
		HapticManager.tick(0.15 + minf(woke, 40) * 0.006)


func _power() -> float:
	return float(UpgradeManager.get_value("blower_power")) * power_mult


func _push_bags(origin: Vector3, dir: Vector3, rng: float, cos_half: float, power: float, delta: float) -> void:
	for b in player.get_tree().get_nodes_in_group("leaf_bags"):
		var bag := b as LeafBag
		if bag == null or bag.consumed:
			continue
		var rel := bag.global_position - origin
		var d := rel.length()
		if d < rng and d > 0.1 and rel.dot(dir) / d > cos_half * 0.9:
			bag.apply_central_impulse(dir * power * 0.9 * (1.0 - d / rng) * delta * 10.0)


func status_text() -> String:
	return "Potencia %.0f · alcance %.1f m" % [_power(), float(UpgradeManager.get_value("blower_range")) * range_mult]
