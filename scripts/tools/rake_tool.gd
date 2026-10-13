class_name RakeTool
extends BaseTool
## Rastrillo: el cabezal barre las hojas que atraviesa y las acumula delante formando montones.
## Al caminar se arrastran como una pala; parado, el rastrillo hace pasadas hacia el jugador.

var _head: Node3D
var _bar: MeshInstance3D
var _handle: MeshInstance3D
var _tines: Array[MeshInstance3D] = []
var _reach := 1.3
var _prev_head := Vector3.INF
var _stroke := 0.0
var _session_moved := 0
var _seed := 0
var _sound := 0.0
var _haptic_acc := 0
var _shown_width := -1.0


func _init() -> void:
	tool_id = "rake"


func attach_parent() -> Node3D:
	return player.body_anchor


func build_model() -> void:
	add_child(model)
	_handle = _vis(MeshFactory.prefab("rake_handle", _handle_parts), model)
	_head = Node3D.new()
	model.add_child(_head)
	_bar = _vis(MeshFactory.prefab("rake_bar", _bar_parts), _head)
	_bar.position = Vector3(0, 0.05, 0)
	_rebuild_tines()


## Pieza visual con el material estilizado (color por vértice, patrones en espacio de objeto).
func _vis(mesh: Mesh, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MeshFactory.prop_mat(true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Mango (eje Y local, de las manos en -Y al cabezal en +Y): madera, empuñadura, tapón y virola.
func _handle_parts() -> Array:
	return [
		MeshFactory.part("cyl6", Vector3.ZERO, Vector3(0.044, 1.0, 0.044), MeshFactory.pc(Color(0.66, 0.45, 0.26), MeshFactory.PAT_WOOD, true)),
		MeshFactory.part("cyl6", Vector3(0, -0.36, 0), Vector3(0.054, 0.2, 0.054), MeshFactory.pc(Color(0.2, 0.42, 0.3), MeshFactory.PAT_PLAIN)),
		MeshFactory.part("cyl6", Vector3(0, -0.5, 0), Vector3(0.058, 0.03, 0.058), MeshFactory.pc(Color(0.15, 0.15, 0.15), MeshFactory.PAT_PLAIN)),
		MeshFactory.part("cyl6", Vector3(0, 0.46, 0), Vector3(0.052, 0.08, 0.052), MeshFactory.pc(Color(0.62, 0.63, 0.66), MeshFactory.PAT_METAL)),
	]


## Barra del cabezal (1 m, se escala con el ancho): perfil metálico con canto superior.
func _bar_parts() -> Array:
	return [
		MeshFactory.part("box", Vector3.ZERO, Vector3(1.0, 0.045, 0.05), MeshFactory.pc(Color(0.33, 0.34, 0.37), MeshFactory.PAT_METAL)),
		MeshFactory.part("box", Vector3(0, 0.026, 0.004), Vector3(1.0, 0.012, 0.058), MeshFactory.pc(Color(0.5, 0.52, 0.55), MeshFactory.PAT_METAL)),
	]


## Púas curvadas y tirantes del cabezal para un ancho dado, fusionados en una sola malla.
func _tine_parts(width: float, copper: bool) -> Array:
	var col := Color(0.85, 0.5, 0.25) if copper else Color(0.5, 0.52, 0.55)
	var pcol := MeshFactory.pc(col, MeshFactory.PAT_METAL)
	var p := []
	var n := int(width / 0.09)
	for k in n + 1:
		var x := -width * 0.5 + k * width / n
		p.append(MeshFactory.part("box", Vector3(x, -0.005, 0.03), Vector3(0.016, 0.11, 0.016), pcol, Basis(Vector3.RIGHT, 0.35)))
		p.append(MeshFactory.part("box", Vector3(x, -0.06, 0.06), Vector3(0.015, 0.05, 0.015), pcol, Basis(Vector3.RIGHT, 0.95)))
	for sx in [-1.0, 1.0]:
		var a := Vector3(sx * width * 0.45, 0.05, 0.0)
		var b := Vector3(0, 0.16, -0.02)
		var d := b - a
		var mid := (a + b) * 0.5
		p.append(MeshFactory.part("box", mid, Vector3(d.length(), 0.014, 0.014), MeshFactory.pc(Color(0.33, 0.34, 0.37), MeshFactory.PAT_METAL), Basis(Vector3.BACK, atan2(d.y, d.x))))
	p.append(MeshFactory.part("cyl6", Vector3(0, 0.12, 0), Vector3(0.05, 0.12, 0.05), MeshFactory.pc(Color(0.33, 0.34, 0.37), MeshFactory.PAT_METAL)))
	return p


func _rebuild_tines() -> void:
	var width := float(UpgradeManager.get_value("rake_width"))
	if is_equal_approx(width, _shown_width):
		return
	_shown_width = width
	for t in _tines:
		t.queue_free()
	_tines.clear()
	_bar.scale.x = width
	var copper := ProgressManager.has_flag("copper_rake")
	var id := "rake_tines_%d_%d" % [int(round(width * 100.0)), int(copper)]
	_tines.append(_vis(MeshFactory.prefab(id, _tine_parts.bind(width, copper)), _head))


func equip() -> void:
	super.equip()
	_rebuild_tines()
	_prev_head = Vector3.INF


func speed_factor() -> float:
	return (0.78 * float(UpgradeManager.get_value("rake_speed"))) if using else 1.0


func stop_use() -> void:
	if using and _session_moved > 25:
		var size := lm.sim.count_in_radius(_head_world(), 1.6)
		if size >= 50:
			EventBus.pile_created.emit(size)
			ProgressManager.set_max("max_pile", size)
	_session_moved = 0
	using = false
	AudioManager.set_loop("rake_loop", 0.0)


func _head_world() -> Vector3:
	var fwd := -player.global_transform.basis.z
	var p := player.global_position + fwd * _reach
	p.y = lm.sim.height_at(p.x, p.z)
	return p


func process_tool(delta: float, held: bool, pressed: bool) -> void:
	var max_reach := float(UpgradeManager.get_value("rake_reach"))
	var speed_mult := float(UpgradeManager.get_value("rake_speed"))
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.5
	if held and not player.bags.is_carrying():
		if not using:
			using = true
			_seed = randi() % 100000
			ProgressManager.mark_tool_used("rake")
		if moving:
			_reach = move_toward(_reach, max_reach, delta * 3.0)
			_stroke = 0.0
		else:
			_stroke += delta * 1.5 * speed_mult
			_reach = lerpf(max_reach, max_reach * 0.42, 0.5 - 0.5 * cos(_stroke * TAU))
	else:
		if using:
			stop_use()
		_reach = move_toward(_reach, max_reach, delta * 2.0)
	var head := _head_world()
	var moved := 0
	if using and _prev_head != Vector3.INF:
		var dist := _prev_head.distance_to(head)
		if dist > 0.0005 and dist < 1.5:
			var right := player.global_transform.basis.x
			moved = lm.sim.rake_sweep(_prev_head, head, right, float(UpgradeManager.get_value("rake_width")),
				int(UpgradeManager.get_value("rake_capacity")), float(UpgradeManager.get_value("rake_grip")), _seed)
			_session_moved += moved
			if moved > 0:
				ProgressManager.add_stat("leaves_raked", moved)
	_prev_head = head
	# Sonido y vibración proporcionales a las hojas arrastradas.
	_sound = lerpf(_sound, clampf(float(moved) / 25.0, 0.0, 1.0) * 0.9 + (0.15 if using else 0.0), minf(delta * 10.0, 1.0))
	AudioManager.set_loop("rake_loop", _sound if using else 0.0, 0.9 + _sound * 0.25)
	_haptic_acc += moved
	if _haptic_acc > 12:
		_haptic_acc = 0
		HapticManager.tick(0.18)
	# Modelo: el cabezal toca el suelo, el mango va hasta las manos.
	var local_head := player.body_anchor.to_local(head)
	var hands := Vector3(0.42, 0.78 - equip_offset(delta), -0.32)
	if using and not moving:
		local_head.y += maxf(sin(_stroke * TAU), 0.0) * 0.08
	_head.position = local_head
	_head.rotation.y = 0.0
	var mid := (hands + local_head) * 0.5
	_handle.position = mid
	var dir := (hands - local_head)
	_handle.scale = Vector3(1.0, dir.length(), 1.0)
	_handle.basis = Basis.looking_at(dir.normalized(), Vector3.FORWARD if absf(dir.normalized().y) > 0.99 else Vector3.UP).rotated(Vector3.UP, 0.0) * Basis(Vector3.RIGHT, PI * 0.5)
	_handle.scale = Vector3(1.0, dir.length(), 1.0)


func status_text() -> String:
	return "Ancho %.1f m · arrastra hasta %d hojas" % [float(UpgradeManager.get_value("rake_width")), int(UpgradeManager.get_value("rake_capacity"))]
