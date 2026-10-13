class_name HandTool
extends BaseTool
## Manos: recogen un puñado de hojas, que vuelan hasta la mano y entran en la bolsa.
## Cada puñado levanta un pequeño estallido de trocitos de hoja en el punto de agarre.

const GLOVE := Color(0.93, 0.62, 0.22)
const GLOVE_DARK := Color(0.76, 0.45, 0.15)
const CUFF := Color(0.33, 0.55, 0.36)
const CUFF_DARK := Color(0.22, 0.4, 0.26)
const SLEEVE := Color(0.5, 0.25, 0.2)
const SLEEVE_LIGHT := Color(0.62, 0.34, 0.26)

var _cooldown := 0.0
var _anim := 0.0
var _fingers: Array[Node3D] = []
var _last_count := 0
var _bursts: Array[CPUParticles3D] = []
var _burst_next := 0
var bursts_emitted := 0


func _init() -> void:
	tool_id = "hand"


## Guante de jardinería redondeado con puño elástico y manga de punto (6 mallas, 1 material).
func build_model() -> void:
	add_child(model)
	model.position = Vector3(0.28, -0.3, -0.5)
	model.rotation = Vector3(-0.35, 0.2, 0.0)
	var m := Companion.vertex_color_material()
	var down := Vector3(PI * 0.5, 0, 0)
	_mesh(model, Companion.merge_parts([
		[MeshFactory.sphere(0.064, 14, 8), Companion.part_xf(Vector3(0, 0, -0.008), Vector3(1.0, 0.46, 1.08)), GLOVE],
		[MeshFactory.sphere(0.034, 10, 6), Companion.part_xf(Vector3(0, 0.02, -0.03), Vector3(1.55, 0.45, 0.9)), GLOVE_DARK],
		[MeshFactory.cyl(0.05, 0.055, 0.05, 14), Companion.part_xf(Vector3(0, -0.002, 0.062), Vector3(1, 1, 0.66), down), CUFF],
		[MeshFactory.cyl(0.057, 0.057, 0.013, 14), Companion.part_xf(Vector3(0, -0.002, 0.084), Vector3(1, 1, 0.66), down), CUFF_DARK],
		[MeshFactory.cyl(0.06, 0.06, 0.034, 14), Companion.part_xf(Vector3(0, 0.0, 0.108), Vector3(1, 1, 0.8), down), SLEEVE_LIGHT],
		[MeshFactory.cyl(0.053, 0.056, 0.09, 14), Companion.part_xf(Vector3(0, 0.0, 0.168), Vector3(1, 1, 0.8), down), SLEEVE],
	]), m)
	var finger := Companion.merge_parts([
		[MeshFactory.cyl(0.0125, 0.0145, 0.05, 8), Companion.part_xf(Vector3(0, 0, -0.025), Vector3.ONE, down), GLOVE],
		[MeshFactory.sphere(0.0128, 8, 5), Companion.part_xf(Vector3(0, 0, -0.05), Vector3.ONE), GLOVE],
	])
	var lengths := [0.92, 1.05, 1.0, 0.8]
	for k in 4:
		var f := Node3D.new()
		f.position = Vector3(-0.037 + k * 0.025, 0.004, -0.058 + absf(k - 1.5) * 0.006)
		f.scale = Vector3(1, 1, float(lengths[k]))
		model.add_child(f)
		_mesh(f, finger, m)
		_fingers.append(f)
	var thumb := Node3D.new()
	thumb.position = Vector3(-0.056, -0.004, -0.008)
	thumb.rotation = Vector3(0.0, 0.85, 0.25)
	thumb.scale = Vector3(1.15, 1.1, 0.95)
	model.add_child(thumb)
	_mesh(thumb, finger, m)


func _mesh(parent: Node3D, mesh: Mesh, m: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func process_tool(delta: float, held: bool, pressed: bool) -> void:
	var sim := lm.sim
	var hand_pos := model.global_position + (-player.cam.camera.global_transform.basis.z) * 0.1
	sim.suck_pos[LeafManager.P_HAND] = hand_pos
	sim.suck_acc[LeafManager.P_HAND] = 38.0
	var got := sim.take_arrived(LeafManager.P_HAND)
	if got.x > 0:
		player.bags.add(int(got.x), got.y, "hand")
	_cooldown = maxf(_cooldown - delta, 0.0)
	var level := UpgradeManager.get_level("hand")
	var continuous := level >= 4
	var want := pressed or (continuous and held)
	if want and _cooldown <= 0.0 and not player.bags.is_carrying():
		_grab(level, pressed)
	_anim = maxf(_anim - delta * 3.5, 0.0)
	var a := sin(_anim * PI)
	model.position = Vector3(0.28, -0.3 - equip_offset(delta) - a * 0.08, -0.5 - a * 0.12)
	for f in _fingers:
		f.rotation.x = -a * 1.1


func _grab(level: int, fresh: bool = true) -> void:
	var speed := float(UpgradeManager.get_value("interact_speed"))
	_cooldown = (0.32 if level < 4 else 0.4) / speed
	var space := player.bags.space()
	if space <= 0:
		_cooldown = 0.6
		if fresh:
			AudioManager.play_ui("error", -6.0)
			EventBus.hint.emit("La bolsa está llena: mantén INTERACTUAR para cerrarla.")
		return
	var point := _target_point()
	var zid := AreaManager.zone_at(point)
	if zid != "" and not AreaManager.is_unlocked(zid):
		if fresh:
			EventBus.hint.emit("Esa zona aún está cerrada: abre su puerta primero.")
		return
	# Hojas sueltas: se cogen de una en una en un radio pequeño. En un montón se cogen brazadas,
	# así que rastrillar primero (y mejorar la mano) compensa de verdad.
	var radius := 0.62
	if level >= 5:
		radius = 1.15
	var count := int(UpgradeManager.get_value("hand"))
	if lm.sim.count_in_radius(point, 0.9) >= 22:
		count *= 4
		radius *= 1.6
	count = mini(count, space)
	var n := lm.sim.capture_nearest(point, radius, count, LeafManager.P_HAND, 3.5)
	_anim = 1.0
	_last_count = n
	if n > 0:
		AudioManager.play_sfx("grab", Vector3.INF, -4.0 + minf(n, 12) * 0.3, 0.15, 3)
		HapticManager.tick(0.2 + n * 0.02)
		ProgressManager.mark_tool_used("hand")
		_burst(point, n)
	else:
		AudioManager.play_sfx("swish", Vector3.INF, -16.0, 0.2)


## Estallido de trocitos de hoja (2 emisores alternos para no cortar el anterior).
func _burst(point: Vector3, n: int) -> void:
	if _bursts.is_empty():
		for k in 2:
			var b := _make_burst()
			lm.add_child(b)
			_bursts.append(b)
	var b := _bursts[_burst_next]
	_burst_next = (_burst_next + 1) % _bursts.size()
	b.global_position = point + Vector3(0, 0.05, 0)
	b.scale_amount_max = 0.8 + minf(n, 12) * 0.04
	b.restart()
	bursts_emitted += 1


static func _make_burst() -> CPUParticles3D:
	var b := CPUParticles3D.new()
	b.emitting = false
	b.one_shot = true
	b.amount = maxi(int(14 * float(PerformanceManager.preset()["particles"])), 5)
	b.lifetime = 0.75
	b.explosiveness = 0.92
	b.local_coords = false
	b.mesh = MeshFactory.leaf_mesh_lod()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	b.material_override = m
	b.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	b.emission_sphere_radius = 0.25
	b.direction = Vector3.UP
	b.spread = 55.0
	b.gravity = Vector3(0, -6.5, 0)
	b.initial_velocity_min = 1.3
	b.initial_velocity_max = 2.8
	b.angular_velocity_min = -540.0
	b.angular_velocity_max = 540.0
	b.damping_min = 1.0
	b.damping_max = 2.0
	b.scale_amount_min = 0.55
	b.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.9))
	curve.add_point(Vector2(1.0, 0.0))
	b.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.97, 0.74, 0.2))
	grad.set_color(1, Color(0.82, 0.28, 0.1))
	grad.add_point(0.5, Color(0.95, 0.5, 0.14))
	b.color_initial_ramp = grad
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return b


## Punto del suelo al que mira el jugador (máx. ~3 m), o cerca de los pies si mira al horizonte.
func _target_point() -> Vector3:
	var cam := player.cam.camera
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	# Se marcha el rayo contra el suelo y los montones (no contra bancos o vallas bajas que haya
	# delante): lo que ves sobre la hierba es lo que coges.
	var t := 0.3
	while t <= 3.6:
		var q := origin + fwd * t
		var ground := lm.sim.height_at(q.x, q.z) + lm.pile_height_at(q.x, q.z) * 0.5
		if q.y <= ground + 0.05:
			return Vector3(q.x, ground, q.z)
		t += 0.12
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var p := player.global_position + flat * 1.6
	p.y = lm.sim.height_at(p.x, p.z)
	return p


func status_text() -> String:
	var level := UpgradeManager.get_level("hand")
	return "%d hojas por puñado%s" % [int(UpgradeManager.get_value("hand")), " · mantener" if level >= 4 else ""]
