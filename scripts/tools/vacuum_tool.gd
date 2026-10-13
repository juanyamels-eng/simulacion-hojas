class_name VacuumTool
extends BaseTool
## Aspiradora: las hojas del radio se desplazan primero hacia la boquilla y luego se absorben.

var _tube: MeshInstance3D
var _mouth: MeshInstance3D
var _budget := 0.0
var _load := 0.0
var _swirl: CPUParticles3D


func _init() -> void:
	tool_id = "vacuum"


func attach_parent() -> Node3D:
	return player.body_anchor


func build_model() -> void:
	add_child(model)
	var body := _vis(MeshFactory.prefab("vacuum_body", _body_parts), model)
	body.position = Vector3(0.3, 1.0, -0.15)
	_tube = _vis(MeshFactory.prefab("vacuum_hose", _hose_parts), model)
	_mouth = _vis(MeshFactory.prefab("vacuum_mouth", _mouth_parts), model)
	_swirl = CPUParticles3D.new()
	_swirl.amount = 20
	_swirl.lifetime = 0.5
	_swirl.local_coords = false
	_swirl.mesh = MeshFactory.leaf_mesh_lod()
	_swirl.material_override = MeshFactory.mat(Color(0.9, 0.55, 0.2))
	_swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_swirl.emission_sphere_radius = 0.9
	_swirl.radial_accel_min = -18.0
	_swirl.radial_accel_max = -12.0
	_swirl.gravity = Vector3.ZERO
	_swirl.angular_velocity_min = -500.0
	_swirl.angular_velocity_max = 500.0
	_swirl.emitting = false
	_mouth.add_child(_swirl)


func _vis(mesh: Mesh, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MeshFactory.prop_mat(true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Depósito a la cadera: bidón brillante con motor, asa, bandas, toma de la manguera y saco de hojas.
func _body_parts() -> Array:
	var teal := MeshFactory.pc(Color(0.22, 0.5, 0.6), MeshFactory.PAT_METAL)
	var dark := MeshFactory.pc(Color(0.12, 0.13, 0.15), MeshFactory.PAT_PLAIN)
	var grey := MeshFactory.pc(Color(0.4, 0.42, 0.45), MeshFactory.PAT_METAL)
	var p := []
	p.append(MeshFactory.part("cyl", Vector3.ZERO, Vector3(0.26, 0.3, 0.26), teal))
	p.append(MeshFactory.part("sph", Vector3(0, 0.15, 0), Vector3(0.26, 0.12, 0.26), teal))
	for y in [-0.1, 0.08]:
		p.append(MeshFactory.part("cyl", Vector3(0, y, 0), Vector3(0.272, 0.025, 0.272), dark))
	p.append(MeshFactory.part("cyl", Vector3(0, 0.22, 0), Vector3(0.12, 0.05, 0.12), grey))
	p.append(MeshFactory.part("box", Vector3(0, 0.27, 0), Vector3(0.03, 0.03, 0.18), dark))
	for z in [-0.08, 0.08]:
		p.append(MeshFactory.part("box", Vector3(0, 0.245, z), Vector3(0.025, 0.05, 0.025), dark))
	p.append(MeshFactory.part("cyl", Vector3(0, -0.1, -0.15), Vector3(0.1, 0.08, 0.1), grey, Basis(Vector3.RIGHT, PI * 0.5)))
	p.append(MeshFactory.part("sph_lo", Vector3(0.02, -0.16, 0.17), Vector3(0.26, 0.3, 0.2), MeshFactory.pc(Color(0.45, 0.5, 0.36), MeshFactory.PAT_STRAW)))
	p.append(MeshFactory.part("box", Vector3(0.0, 0.0, 0.0), Vector3(0.3, 0.035, 0.035), dark, Basis(Vector3.BACK, 0.9)))
	p.append(MeshFactory.part("box", Vector3(0.135, 0.02, 0), Vector3(0.004, 0.05, 0.12), MeshFactory.pc(Color(0.95, 0.92, 0.84), MeshFactory.PAT_PLAIN)))
	return p


## Manguera corrugada (1 m en Y; se estira con la distancia): tubo y anillos.
func _hose_parts() -> Array:
	var p := []
	p.append(MeshFactory.part("cyl", Vector3.ZERO, Vector3(0.11, 1.0, 0.11), MeshFactory.pc(Color(0.2, 0.22, 0.24), MeshFactory.PAT_PLAIN)))
	for k in 10:
		p.append(MeshFactory.part("cyl", Vector3(0, -0.45 + k * 0.1, 0), Vector3(0.128, 0.03, 0.128), MeshFactory.pc(Color(0.13, 0.14, 0.16), MeshFactory.PAT_METAL)))
	return p


## Boquilla: cono ancho hacia el suelo (-Y), parachoques de goma y asidero.
func _mouth_parts() -> Array:
	var teal := MeshFactory.pc(Color(0.17, 0.4, 0.48), MeshFactory.PAT_METAL)
	var dark := MeshFactory.pc(Color(0.1, 0.1, 0.11), MeshFactory.PAT_PLAIN)
	var p := []
	p.append([MeshFactory.cyl(0.07, 0.17, 0.22, 14), Transform3D.IDENTITY, teal])
	p.append(MeshFactory.part("ring", Vector3(0, -0.11, 0), Vector3(0.46, 0.3, 0.46), dark))
	p.append(MeshFactory.part("cyl", Vector3(0, 0.13, 0), Vector3(0.15, 0.05, 0.15), dark))
	p.append(MeshFactory.part("box", Vector3(0.12, 0.05, 0), Vector3(0.03, 0.14, 0.03), dark, Basis(Vector3.BACK, -0.5)))
	p.append(MeshFactory.part("box", Vector3(0, -0.02, 0.16), Vector3(0.1, 0.02, 0.02), MeshFactory.pc(Color(0.95, 0.7, 0.15), MeshFactory.PAT_PLAIN)))
	return p


func _mouth_local() -> Vector3:
	var pitch := player.cam.pitch
	var dist := clampf(1.15 + pitch * 0.9, 0.7, 2.0)
	return Vector3(0.0, 0.18, -dist)


func process_tool(delta: float, held: bool, _pressed: bool) -> void:
	var sim := lm.sim
	var mouth_local := _mouth_local()
	var mouth := player.body_anchor.to_global(mouth_local)
	mouth.y = sim.height_at(mouth.x, mouth.z) + 0.2
	var on := held and not player.bags.is_carrying()
	sim.suck_pos[LeafManager.P_VACUUM] = mouth
	sim.suck_acc[LeafManager.P_VACUUM] = float(UpgradeManager.get_value("vacuum_power")) * 3.0
	var got := sim.take_arrived(LeafManager.P_VACUUM)
	if got.x > 0:
		player.bags.add(int(got.x), got.y, "vacuum")
		HapticManager.tick(0.12 + minf(got.x, 20) * 0.01)
	var captured := 0
	if on:
		if not using:
			ProgressManager.mark_tool_used("vacuum")
		using = true
		_budget += float(UpgradeManager.get_value("vacuum_speed")) * delta
		var cap := int(UpgradeManager.get_value("vacuum_capacity")) - sim.in_flight[LeafManager.P_VACUUM]
		var room := player.bags.space()
		var n := mini(mini(int(_budget), cap), room)
		if room <= 0 and int(_budget) > 0:
			EventBus.hint.emit("La bolsa está llena: mantén INTERACTUAR para cerrarla.")
		if n > 0:
			_budget -= n
			captured = sim.capture_radius(mouth, float(UpgradeManager.get_value("vacuum_radius")), n, LeafManager.P_VACUUM, 1.5)
		_budget = minf(_budget, 40.0)
	else:
		using = false
		_budget = 0.0
	_load = lerpf(_load, clampf(float(sim.in_flight[LeafManager.P_VACUUM]) / 40.0, 0.0, 1.0), minf(delta * 4.0, 1.0))
	AudioManager.set_loop("vacuum_loop", (0.6 + _load * 0.3) if on else 0.0, 0.85 + _load * 0.35)
	_swirl.emitting = on and captured > 0
	# Modelo: tubo desde la cadera hasta la boquilla.
	var hip := Vector3(0.3, 0.95 - equip_offset(delta), -0.2)
	var ml := player.body_anchor.to_local(mouth)
	_mouth.position = ml
	var dir := hip - ml
	_tube.position = (hip + ml) * 0.5
	_tube.basis = Basis.looking_at(dir.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
	_tube.scale = Vector3(1.0, dir.length(), 1.0)
	_mouth.basis = _tube.basis.orthonormalized()
	if on:
		player.cam.add_shake(0.05)


func status_text() -> String:
	return "Radio %.1f m · %d hojas/s" % [float(UpgradeManager.get_value("vacuum_radius")), int(UpgradeManager.get_value("vacuum_speed"))]
