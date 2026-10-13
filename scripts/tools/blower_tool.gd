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
	var body := MeshInstance3D.new()
	body.mesh = MeshFactory.prefab(_model_id(), _model_parts)
	body.material_override = MeshFactory.prop_mat(true)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(body)
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


func _model_id() -> String:
	return "blower_model"


## Soplador de mano: carcasa brillante, voluta con rejilla, asa superior con gatillo, tubo con
## refuerzos y boquilla naranja. Una sola malla (una llamada de dibujo).
func _model_parts() -> Array:
	var orange := MeshFactory.pc(Color(0.93, 0.5, 0.15), MeshFactory.PAT_METAL)
	var grey := MeshFactory.pc(Color(0.24, 0.25, 0.27), MeshFactory.PAT_METAL)
	var black := MeshFactory.pc(Color(0.08, 0.08, 0.09), MeshFactory.PAT_PLAIN)
	var cream := MeshFactory.pc(Color(0.95, 0.92, 0.84), MeshFactory.PAT_PLAIN)
	var side := Basis(Vector3.BACK, PI * 0.5)
	var along := Basis(Vector3.RIGHT, PI * 0.5)
	var p := []
	p.append(MeshFactory.part("box", Vector3(0, 0, 0.08), Vector3(0.17, 0.16, 0.3), orange))
	p.append(MeshFactory.part("sph", Vector3(0, 0.07, 0.08), Vector3(0.17, 0.11, 0.3), orange))
	p.append(MeshFactory.part("cyl", Vector3(-0.11, -0.01, 0.07), Vector3(0.25, 0.1, 0.25), grey, side))
	p.append(MeshFactory.part("cyl", Vector3(-0.163, -0.01, 0.07), Vector3(0.19, 0.012, 0.19), black, side))
	for k in 4:
		p.append(MeshFactory.part("box", Vector3(-0.17, -0.01, 0.07), Vector3(0.008, 0.19, 0.014), grey, Basis(Vector3.RIGHT, k * PI / 4.0)))
	p.append(MeshFactory.part("cyl", Vector3(-0.172, -0.01, 0.07), Vector3(0.05, 0.012, 0.05), orange, side))
	# Depósito lateral con tapón y empuñadura de pistola con gatillo.
	p.append(MeshFactory.part("box", Vector3(0.1, -0.05, 0.15), Vector3(0.05, 0.09, 0.14), grey))
	p.append(MeshFactory.part("cyl", Vector3(0.1, 0.0, 0.2), Vector3(0.035, 0.025, 0.035), MeshFactory.pc(Color(0.8, 0.18, 0.12), MeshFactory.PAT_PLAIN)))
	p.append(MeshFactory.part("box", Vector3(0, -0.15, 0.15), Vector3(0.04, 0.15, 0.05), black, Basis(Vector3.RIGHT, 0.25)))
	p.append(MeshFactory.part("box", Vector3(0, -0.1, 0.1), Vector3(0.018, 0.045, 0.03), MeshFactory.pc(Color(0.85, 0.2, 0.15), MeshFactory.PAT_PLAIN)))
	# Franjas decorativas.
	p.append(MeshFactory.part("box", Vector3(0.087, 0.01, 0.08), Vector3(0.004, 0.03, 0.22), cream))
	p.append(MeshFactory.part("box", Vector3(0.087, -0.025, 0.08), Vector3(0.004, 0.012, 0.22), black))
	# Tubo con refuerzos y boquilla.
	p.append(MeshFactory.part("cyl", Vector3(0, -0.02, -0.3), Vector3(0.088, 0.56, 0.088), grey, along))
	for z in [-0.08, -0.15]:
		p.append(MeshFactory.part("cyl", Vector3(0, -0.02, z), Vector3(0.1, 0.02, 0.1), black, along))
	p.append(MeshFactory.part("cyl", Vector3(0, -0.02, -0.6), Vector3(0.08, 0.08, 0.08), orange, along))
	p.append(MeshFactory.part("cyl", Vector3(0, -0.02, -0.642), Vector3(0.086, 0.014, 0.086), black, along))
	return p


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
