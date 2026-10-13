extends Node
## QA del atrezo (modelos, materiales, herramientas).
## Capturas con recuento de llamadas de dibujo (requiere render real):
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 res://tests/shots_props.tscn
##   Variables: SHOTS_TAG (prefijo de los archivos), SHOTS_ONLY (lista de vistas separadas por comas).
## Comprobación rápida sin render (lotes, triángulos, paso libre y herramientas):
##   PROPS_CHECK=1 godot --headless --fixed-fps 60 res://tests/shots_props.tscn

var out_dir := "user://shots"
var main: Node
var tag := ""
var only: PackedStringArray = []


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func wanted(name: String) -> bool:
	return only.is_empty() or only.has(name)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + tag + name + ".png")
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var ob := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var pr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("captura: %s%s  DRAW calls=%d objetos=%d primitivas=%d" % [tag, name, dc, ob, pr])


func view(p: PlayerController, name: String, pos: Vector3, look_at_xz: Vector2, pitch: float, wait: int = 40) -> void:
	if not wanted(name):
		return
	var dir := Vector2(look_at_xz.x - pos.x, look_at_xz.y - pos.z)
	var yaw := atan2(-dir.x, -dir.y)
	p.teleport(pos, yaw)
	p.cam.pitch = pitch
	await frames(wait)
	await shot(name)


func _ready() -> void:
	var check := OS.get_environment("PROPS_CHECK") == "1"
	DirAccess.make_dir_recursive_absolute(out_dir)
	tag = OS.get_environment("SHOTS_TAG")
	var o := OS.get_environment("SHOTS_ONLY")
	if o != "":
		only = o.split(",")
	SaveManager.delete_slot("campaign")
	GameManager.requested_new = true
	GameManager.skip_menu = true
	var t0 := Time.get_ticks_msec()
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	var guard := 0
	while GameManager.world == null or not GameManager.in_game:
		await frames(1)
		guard += 1
		if guard > 900:
			print("CHECK FAIL: el mundo no se construyó")
			get_tree().quit(1)
			return
	var world: World = GameManager.world
	print("CHECK mundo construido en %d ms" % (Time.get_ticks_msec() - t0))
	_stats(world)
	if check:
		await frames(2)
		_walkability(world)
		await _tools_check(world)
		print("CHECK fin")
		get_tree().quit(0)
		return
	SettingsManager.set_value("graphics", "high")
	await frames(30)
	var p: PlayerController = world.player
	await view(p, "a_entrada", GameData.START_POS, Vector2(0, 40), -0.08, 60)
	await view(p, "b_taller", Vector3(-3, 0.5, 57), Vector2(-12, 50), -0.05)
	await view(p, "c_delantero", Vector3(8, 0.5, 34), Vector2(-4, 20), -0.1)
	if wanted("n_detalle"):
		var bag := LeafBag.new()
		bag.setup(300, 1.0)
		world.add_child(bag)
		bag.global_position = Vector3(1.6, world.terrain.height_at(1.6, 42.4) + 0.5, 42.4)
		await view(p, "n_detalle", Vector3(3.6, 0.5, 44.6), Vector2(0, 40), -0.2)
	await view(p, "d_casa", Vector3(0, 0.5, 6), Vector2(0, -18), 0.05)
	await view(p, "e_piscina", Vector3(29, 0.5, 2), Vector2(44, -10), -0.25)
	await view(p, "f_garaje", Vector3(30, 0.5, 18), Vector2(44, 24), -0.05)
	await view(p, "g_infantil", Vector3(-38, 0.5, 24), Vector2(-48, 30), -0.05)
	await view(p, "h_huerto", Vector3(-28, 0.5, 0), Vector2(-44, -10), -0.15)
	await view(p, "i_trasero", Vector3(6, 2.5, -32), Vector2(0, -46), -0.05)
	await view(p, "j_invernadero", Vector3(46, 0.5, -30), Vector2(40, -46), -0.05)
	await view(p, "k_laberinto", Vector3(-22, 0.5, -30), Vector2(-40, -42), -0.05)
	await view(p, "o_secreto", Vector3(74.0, Terrain.SECRET_FLOOR + 0.2, -28.5), Vector2(86, -40), -0.1)
	await view(p, "p_conducto", Vector3(-4.6, 0.5, 6.8), Vector2(-8, 4), -0.35)
	await view(p, "q_muro", Vector3(-8.0, 0.5, 54.0), Vector2(-20, 58), -0.05)
	if wanted("l_aerea"):
		var cam := Camera3D.new()
		world.add_child(cam)
		cam.global_position = Vector3(0, 70, 70)
		cam.look_at(Vector3(0, 0, 5))
		cam.far = 500
		cam.make_current()
		await frames(20)
		await shot("l_aerea")
		p.cam.camera.make_current()
		cam.queue_free()
	# Herramientas.
	UpgradeManager.levels["tool_rake"] = 1
	UpgradeManager.levels["rake_width"] = 2
	UpgradeManager.levels["tool_blower"] = 1
	UpgradeManager.levels["tool_vacuum"] = 1
	UpgradeManager.levels["tool_industrial"] = 1
	for t in ["rake", "blower", "vacuum", "industrial"]:
		if not wanted("m_" + t):
			continue
		p.tools.select(t)
		p.teleport(Vector3(8, 0.5, 52), PI * 0.5)
		p.cam.pitch = -0.35 if t != "vacuum" else -0.45
		await frames(40)
		await shot("m_" + t)
	print("fps (render real en CPU): ", Engine.get_frames_per_second())
	get_tree().quit()


## Lotes, instancias y triángulos del decorado estático (total, con sombra y por malla).
func _stats(world: World) -> void:
	var props := world.get_node_or_null("StaticProps")
	if props == null:
		return
	var tris := 0
	var inst := 0
	var shadow_tris := 0
	var by_mesh := {}
	for c in props.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null:
			continue
		var mm := mmi.multimesh
		inst += mm.instance_count
		var m := mm.mesh
		var t := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var vtx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			t += (idx.size() if idx.size() > 0 else vtx.size()) / 3
		tris += t * mm.instance_count
		var key := "%d" % m.get_instance_id()
		for id in world.builder.meshes:
			if world.builder.meshes[id] == m:
				key = id
		by_mesh[key] = int(by_mesh.get(key, 0)) + t * mm.instance_count
		if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_tris += t * mm.instance_count
	print("PROPS lotes=%d instancias=%d triangulos=%d (con sombra %d)" % [props.get_child_count(), inst, tris, shadow_tris])
	var st: Dictionary = world.builder.batch_stats
	var keys := st.keys()
	keys.sort_custom(func(a, b): return int(st[a]) > int(st[b]))
	var line := ""
	for k in keys:
		line += "%s:%d " % [k, st[k]]
	print("CHECK LOTES ", line)
	var tk := by_mesh.keys()
	tk.sort_custom(func(a, b): return int(by_mesh[a]) > int(by_mesh[b]))
	line = ""
	for k in tk:
		line += "%s:%dk " % [k, int(by_mesh[k]) / 1000]
	print("CHECK TRIS ", line)


func _tools_check(world: World) -> void:
	var p: PlayerController = world.player
	UpgradeManager.levels["tool_rake"] = 1
	UpgradeManager.levels["tool_blower"] = 1
	UpgradeManager.levels["tool_vacuum"] = 1
	UpgradeManager.levels["tool_industrial"] = 1
	for t in ["rake", "blower", "vacuum", "industrial", "hand"]:
		p.tools.select(t)
		InputState.action_held = true
		await frames(20)
		InputState.action_held = false
		await frames(5)
		print("CHECK herramienta ", t, " -> ", GameManager.current_tool)


## Comprueba con esferas de colisión que el atrezo no bloquea el paso por las puertas, los caminos
## principales ni el acceso a contenedores, conductos y objetos interactivos.
func _walkability(world: World) -> void:
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.32
	q.shape = sph
	q.collision_mask = Interactable.LAYER_WORLD
	var exclude: Array[RID] = []
	for g in world.gates.values():
		exclude.append((g as GateDoor).get_rid())
	q.exclude = exclude
	var blocked := []
	var probes := 0
	var t := world.terrain
	# Pasos por las puertas (a ambos lados, en la línea de cruce).
	for g in GameData.GATES:
		var gp: Vector2 = g["pos"]
		var cross := Vector2(0, 1) if g["axis"] == "x" else Vector2(1, 0)
		for d in [-2.6, -2.0, -1.4, -0.8, 0.8, 1.4, 2.0, 2.6]:
			for lateral in [-0.6, 0.0, 0.6]:
				var p2: Vector2 = gp + cross * float(d) + Vector2(cross.y, cross.x) * float(lateral)
				probes += 1
				if _hit(space, q, Vector3(p2.x, t.height_at(p2.x, p2.y) + 0.9, p2.y)):
					blocked.append("puerta %s (%.1f, %.1f)" % [g["id"], p2.x, p2.y])
	# Caminos principales.
	var paths := [[Vector2(0, 62), Vector2(0, 41)], [Vector2(0, 39), Vector2(0, 30.5)], [Vector2(0, 19.5), Vector2(0, 11)],
		[Vector2(-19, 25), Vector2(-5.5, 25)], [Vector2(5.5, 25), Vector2(19, 25)], [Vector2(0, 9), Vector2(0, 0)],
		[Vector2(-19, -6.2), Vector2(19, -6.2)], [Vector2(16, -6), Vector2(16, -24)], [Vector2(-16, -6), Vector2(-16, -24)],
		[Vector2(16, -26), Vector2(4.5, -41)], [Vector2(-16, -26), Vector2(-4.5, -41)], [Vector2(21, 25.5), Vector2(36, 31.5)]]
	for pth in paths:
		var a: Vector2 = pth[0]
		var b: Vector2 = pth[1]
		var n := int(a.distance_to(b) / 0.8)
		for k in n + 1:
			var p2 := a.lerp(b, float(k) / n)
			probes += 1
			if _hit(space, q, Vector3(p2.x, t.height_at(p2.x, p2.y) + 0.9, p2.y)):
				blocked.append("camino (%.1f, %.1f)" % [p2.x, p2.y])
	# Acceso a contenedores, conductos y estaciones: al menos cuatro puntos libres a 1,6-2,4 m.
	var targets := []
	for bn in world.builder.bins:
		targets.append(["contenedor", (bn as Node3D).global_position])
	for du in world.ducts:
		targets.append(["conducto", (du as Node3D).global_position])
	for st in world.builder.stations:
		targets.append(["estación", (st as Node3D).global_position])
	for tg in targets:
		var c: Vector3 = tg[1]
		var free := 0
		for k in 12:
			var a := k * TAU / 12.0
			for r in [1.6, 2.4]:
				var p2 := Vector2(c.x + cos(a) * r, c.z + sin(a) * r)
				var y := t.height_at(p2.x, p2.y) if c.y > -10.0 else c.y
				if not _hit(space, q, Vector3(p2.x, y + 0.9, p2.y)):
					free += 1
		probes += 1
		if free < 4:
			blocked.append("%s sin acceso en (%.1f, %.1f): %d huecos" % [tg[0], c.x, c.z, free])
	print("CHECK PASO sondas=%d bloqueadas=%d" % [probes, blocked.size()])
	for b in blocked:
		print("CHECK BLOQUEO ", b)


func _hit(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D, pos: Vector3) -> bool:
	q.transform = Transform3D(Basis.IDENTITY, pos)
	return not space.intersect_shape(q, 1).is_empty()
