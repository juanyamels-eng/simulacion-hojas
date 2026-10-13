class_name HandTool
extends BaseTool
## Manos: recogen un puñado de hojas, que vuelan hasta la mano y entran en la bolsa.

const GLOVE := Color(0.93, 0.62, 0.22)

var _cooldown := 0.0
var _anim := 0.0
var _fingers: Array[Node3D] = []
var _last_count := 0


func _init() -> void:
	tool_id = "hand"


func build_model() -> void:
	add_child(model)
	model.position = Vector3(0.28, -0.3, -0.5)
	model.rotation = Vector3(-0.35, 0.2, 0.0)
	part(MeshFactory.box(Vector3(0.11, 0.035, 0.12)), GLOVE, Vector3.ZERO)
	part(MeshFactory.cyl(0.045, 0.05, 0.12, 8), Color(0.35, 0.25, 0.2), Vector3(0, 0, 0.1)).rotation.x = PI * 0.5
	for k in 4:
		var f := Node3D.new()
		f.position = Vector3(-0.04 + k * 0.027, 0.0, -0.06)
		model.add_child(f)
		part(MeshFactory.box(Vector3(0.022, 0.025, 0.07)), GLOVE, Vector3(0, 0, -0.035), f)
		_fingers.append(f)
	var thumb := Node3D.new()
	thumb.position = Vector3(-0.06, 0.0, -0.01)
	thumb.rotation.y = 0.8
	model.add_child(thumb)
	part(MeshFactory.box(Vector3(0.024, 0.025, 0.06)), GLOVE, Vector3(0, 0, -0.03), thumb)


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
		_grab(level)
	_anim = maxf(_anim - delta * 3.5, 0.0)
	var a := sin(_anim * PI)
	model.position = Vector3(0.28, -0.3 - equip_offset(delta) - a * 0.08, -0.5 - a * 0.12)
	for f in _fingers:
		f.rotation.x = -a * 1.1


func _grab(level: int) -> void:
	var speed := float(UpgradeManager.get_value("interact_speed"))
	_cooldown = (0.32 if level < 4 else 0.2) / speed
	var space := player.bags.space()
	if space <= 0:
		_cooldown = 0.6
		AudioManager.play_ui("error", -6.0)
		EventBus.hint.emit("La bolsa está llena: mantén INTERACTUAR para cerrarla.")
		return
	var point := _target_point()
	var radius := 0.95 if level < 5 else 1.7
	var count := mini(int(UpgradeManager.get_value("hand")), space)
	var n := lm.sim.capture_nearest(point, radius, count, LeafManager.P_HAND, 3.5)
	_anim = 1.0
	_last_count = n
	if n > 0:
		AudioManager.play_sfx("grab", Vector3.INF, -4.0 + minf(n, 12) * 0.3, 0.15, 3)
		HapticManager.tick(0.2 + n * 0.02)
		ProgressManager.mark_tool_used("hand")
	else:
		AudioManager.play_sfx("swish", Vector3.INF, -16.0, 0.2)


## Punto del suelo al que mira el jugador (máx. ~3 m), o cerca de los pies si mira al horizonte.
func _target_point() -> Vector3:
	var cam := player.cam.camera
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 3.4, Interactable.LAYER_WORLD)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var hp: Vector3 = hit["position"]
		hp.y = lm.sim.height_at(hp.x, hp.z) + lm.pile_height_at(hp.x, hp.z) * 0.5
		return hp
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var p := player.global_position + flat * 1.6
	p.y = lm.sim.height_at(p.x, p.z)
	return p


func status_text() -> String:
	var level := UpgradeManager.get_level("hand")
	return "%d hojas por puñado%s" % [int(UpgradeManager.get_value("hand")), " · mantener" if level >= 4 else ""]
