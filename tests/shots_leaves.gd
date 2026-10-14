extends Node
## Capturas de QA del sistema de hojas: hojas sueltas sobre el césped y la piedra, montón hecho con el
## rastrillo, montón grande, hojas en vuelo, recogida con la mano, círculo de resaltado, filtro
## «Resaltar hojas», zona al 96 %, vista amplia/lejana (LOD) y calidad baja.
## Uso: xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 res://tests/shots_leaves.tscn
## (SHOTS_PREFIX=b → antes / a → después: prefijo de los archivos).

var out_dir := "user://shots"
var prefix := "l"
var main: Node


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + prefix + "_" + shot_name + ".png")
	print("captura: ", prefix, "_", shot_name)


func _ready() -> void:
	var env_prefix := OS.get_environment("SHOTS_PREFIX")
	if env_prefix != "":
		prefix = env_prefix
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveManager.delete_slot("campaign")
	GameManager.requested_new = true
	GameManager.skip_menu = true
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await frames(10)
	while GameManager.world == null or not GameManager.in_game:
		await frames(1)
	var world: World = GameManager.world
	var p: PlayerController = world.player
	var lm: LeafManager = world.leaf_manager
	var sim: LeafSimulationSystem = lm.sim
	SettingsManager.set_value("graphics", "high")
	ProgressManager.tutorial_step = 7
	var dog := world.get_node_or_null("Bellota") as Companion
	if dog:
		dog.visible = false
		dog.process_mode = Node.PROCESS_MODE_DISABLED
	world.day_t = 0.2
	print("hojas: ", sim.n)

	# 1) Vista amplia desde la entrada.
	p.teleport(GameData.START_POS, 0.0)
	p.cam.pitch = -0.14
	await frames(60)
	await shot("01_amplia")

	# 2) Césped con hojas sueltas, de cerca.
	p.teleport(Vector3(-8.0, 0.6, 57.0), 0.0)
	p.cam.pitch = -0.78
	await frames(25)
	await shot("02_cesped_cerca")

	# 3) Hojas sobre las losas del camino.
	p.teleport(Vector3(0.6, 0.6, 50.0), 0.0)
	p.cam.pitch = -0.62
	await frames(25)
	await shot("03_camino")

	# 4) Montón hecho con el rastrillo real: barridos desde 8 direcciones hacia un centro.
	var pc := Vector3(7.5, 0.0, 55.5)
	for k in 20:
		var a := k * TAU / 20.0 + 0.2
		var dir := Vector3(cos(a), 0.0, sin(a))
		var right := Vector3(-dir.z, 0.0, dir.x)
		var prev := pc + dir * 7.0
		var t := 7.0
		while t > 0.15:
			t -= 0.06
			var cur := pc + dir * t
			cur.y = sim.height_at(cur.x, cur.z)
			sim.rake_sweep(prev, cur, right, 2.4, 1100, 0.95, 7 + k)
			prev = cur
	await frames(30)
	lm.cluster.flush(sim, true)
	print("montón rastrillado: ", sim.count_in_radius(pc, 1.6), " hojas, altura ", lm.pile_height_at(pc.x, pc.z))
	p.teleport(Vector3(pc.x + 0.5, 0.6, pc.z + 3.4), 0.12)
	p.cam.pitch = -0.4
	await frames(25)
	await shot("04_monton_rastrillo")

	# 5) Montón grande (mil hojas juntas) en el jardín delantero.
	var pc2 := Vector3(10.0, 0.0, 30.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var moved := 0
	for i in sim.n:
		if moved >= 1000:
			break
		if sim.state[i] != LeafSimulationSystem.S_SLEEP:
			continue
		var q := sim.pos[i]
		if Vector2(q.x - pc2.x, q.z - pc2.z).length() < 9.0:
			var r := sqrt(rng.randf()) * 1.3
			var ang := rng.randf() * TAU
			var x := pc2.x + cos(ang) * r
			var z := pc2.z + sin(ang) * r
			sim.move_sleeping(i, Vector3(x, sim.height_at(x, z) + 0.015, z))
			moved += 1
	lm.cluster.flush(sim, true)
	print("montón grande: ", moved, " hojas, altura ", lm.pile_height_at(pc2.x, pc2.z))
	p.teleport(Vector3(pc2.x + 0.8, 0.6, pc2.z + 3.8), 0.18)
	p.cam.pitch = -0.36
	await frames(25)
	await shot("05_monton_grande")
	# Desde muy cerca y casi a ras de suelo.
	p.teleport(Vector3(pc2.x + 0.3, 0.6, pc2.z + 2.3), 0.1)
	p.cam.pitch = -0.2
	await frames(20)
	await shot("06_monton_ras")

	# 7) Saltar en el montón: hojas en vuelo.
	sim.max_active = 1300
	sim.kick(pc2, 1.8, Vector3.ZERO, 4.0, 400, 2.0)
	await frames(10)
	await shot("07_salto_vuelo")
	await frames(240)
	await shot("08_tras_salto")

	# 9) Círculo de resaltado de la mano (API nueva) y recogida en vuelo hacia la mano.
	p.teleport(Vector3(-6.0, 0.6, 55.0), 0.0)
	p.cam.pitch = -0.7
	await frames(20)
	# El grupo de hojas más denso entre 1,2 y 2,4 m por delante.
	var hl := p.global_position + Vector3(0.0, 0.0, -1.6)
	var best_c := -1
	for dz in range(-5, -1):
		for dx in range(-2, 3):
			var q := p.global_position + Vector3(dx * 0.5, 0.0, dz * 0.5)
			var c := sim.cell_index(q.x, q.z)
			if c >= 0 and sim.cell_count[c] > best_c:
				best_c = sim.cell_count[c]
				hl = q
	hl.y = sim.height_at(hl.x, hl.z)
	if lm.has_method("set_highlight"):
		lm.call("set_highlight", hl, 0.62)
	await frames(8)
	await shot("09_resaltado_mano")
	if lm.has_method("highlight_grab"):
		print("radio de las 8 más cercanas: ", lm.call("highlight_grab", hl, 0.9, 8))
		await frames(8)
		await shot("09b_resaltado_8_hojas")
	if lm.has_method("clear_highlight"):
		lm.call("clear_highlight")
	var got := sim.capture_nearest(hl, 0.9, 14, LeafManager.P_HAND, 3.5)
	sim.suck_pos[LeafManager.P_HAND] = p.cam.camera.global_position + (-p.cam.camera.global_transform.basis.z) * 0.6 + Vector3(0.25, -0.25, 0.0)
	sim.suck_acc[LeafManager.P_HAND] = 38.0
	print("recogidas: ", got)
	await frames(5)
	await shot("10_recogida_vuelo")
	await frames(40)
	sim.take_arrived(LeafManager.P_HAND)

	# 11) Filtro «Resaltar hojas» (ajuste nuevo) sobre césped y piedra.
	SettingsManager.set_value("highlight_leaves", true)
	p.teleport(Vector3(1.5, 0.6, 52.0), -0.5)
	p.cam.pitch = -0.4
	await frames(20)
	await shot("11_filtro_resaltar")
	SettingsManager.set_value("highlight_leaves", false)

	# 12) Zona casi limpia (96 %): las últimas hojas brillan solas.
	var left_keep := 0
	for i in sim.n:
		if sim.zone_origin[i] != 0 or sim.state[i] == LeafSimulationSystem.S_REMOVED:
			continue
		var q := sim.pos[i]
		left_keep += 1
		if left_keep % 25 != 0 or q.z < 44.0:
			sim.remove_leaf(i)
	lm.cluster.flush(sim, true)
	lm.push_counts()
	await frames(40)
	print("Entrada: ", AreaManager.pct("entrada"), " %")
	p.teleport(Vector3(-4.0, 0.6, 62.0), 0.0)
	p.cam.pitch = -0.32
	await frames(30)
	await shot("12_zona_96")

	# 13) Vista lejana elevada (LOD y distancia de dibujado).
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.global_position = Vector3(-14.0, 7.0, 40.0)
	cam.look_at(Vector3(4.0, 0.0, 14.0))
	cam.far = 500
	cam.fov = 70
	cam.make_current()
	await frames(25)
	await shot("13_lejos")
	p.cam.camera.make_current()

	# 14) Calidad baja.
	SettingsManager.set_value("graphics", "low")
	p.teleport(Vector3(pc2.x + 0.8, 0.6, pc2.z + 3.8), 0.18)
	p.cam.pitch = -0.36
	await frames(30)
	await shot("14_calidad_baja")
	print("fps (render real en CPU): ", Engine.get_frames_per_second())
	get_tree().quit()
