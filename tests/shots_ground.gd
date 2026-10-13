extends Node
## Capturas de QA del suelo, el césped y las hojas (montón, zona limpia seca y verde, hojas en vuelo).
## Uso: xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 res://tests/shots_ground.tscn

var out_dir := "user://shots"
var main: Node


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + name + ".png")
	print("captura: ", name)


func _ready() -> void:
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
	world.day_t = 0.2
	p.teleport(GameData.START_POS, 0.0)
	p.cam.pitch = -0.12
	await frames(60)
	await shot("g01_inicio")
	p.cam.pitch = -0.8
	await frames(15)
	await shot("g02_hojas_cerca")

	# Montón en el jardín delantero: se juntan las hojas de alrededor.
	var pc := Vector3(10.0, 0.0, 30.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in sim.n:
		if sim.state[i] != LeafSimulationSystem.S_SLEEP:
			continue
		var q := sim.pos[i]
		if Vector2(q.x - pc.x, q.z - pc.z).length() < 4.0:
			var r := sqrt(rng.randf()) * 1.1
			var a := rng.randf() * TAU
			var x := pc.x + cos(a) * r
			var z := pc.z + sin(a) * r
			sim.move_sleeping(i, Vector3(x, sim.height_at(x, z) + 0.015, z))
	lm.cluster.flush(sim, true)
	p.teleport(Vector3(pc.x + 0.6, 0.6, pc.z + 3.6), 0.15)
	await frames(30)
	p.cam.pitch = -0.42
	await frames(15)
	await shot("g03_monton")

	# Claro limpio en una zona aún sucia: césped seco destapado.
	var cl := Vector3(-9.0, 0.0, 26.0)
	for i in sim.n:
		if sim.state[i] == LeafSimulationSystem.S_REMOVED:
			continue
		var q := sim.pos[i]
		if Vector2(q.x - cl.x, q.z - cl.z).length() < 4.5:
			sim.remove_leaf(i)
	lm.cluster.flush(sim, true)
	p.teleport(Vector3(cl.x, 0.6, cl.z + 5.0), 0.0)
	await frames(30)
	p.cam.pitch = -0.38
	await frames(15)
	await shot("g04_claro_seco")

	# Entrada limpia del todo: el césped reverdece, salen flores y se ven las losas.
	for i in sim.n:
		if sim.state[i] == LeafSimulationSystem.S_REMOVED:
			continue
		var c := sim.cell[i]
		if c >= 0 and sim.cell_zone[c] == 1:
			sim.remove_leaf(i)
	lm.cluster.flush(sim, true)
	lm.push_counts()
	p.teleport(GameData.START_POS, 0.0)
	await frames(150)
	p.cam.pitch = -0.2
	await frames(15)
	await shot("g05_entrada_verde")
	p.teleport(Vector3(3.0, 0.6, 52.0), -0.9)
	p.cam.pitch = -0.55
	await frames(20)
	await shot("g06_camino_cesped")

	# Hojas en vuelo a contraluz (mirando hacia el sol) junto a la verja del jardín delantero.
	p.teleport(Vector3(-6.0, 0.6, 34.5), PI)
	p.cam.pitch = 0.05
	await frames(10)
	sim.max_active = 1300
	sim.kick(Vector3(-6.0, 0.0, 37.5), 2.5, Vector3(0.3, 0, -0.6), 4.0, 600, 1.5)
	await frames(4)
	await shot("g07_vuelo")

	# Huerto (tierra y surcos) y vista aérea.
	p.teleport(Vector3(-44.0, 0.6, 2.0), 0.0)
	p.cam.pitch = -0.35
	await frames(25)
	await shot("g08_huerto")
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.global_position = Vector3(0, 60, 80)
	cam.look_at(Vector3(0, 0, 25))
	cam.far = 500
	cam.make_current()
	await frames(20)
	await shot("g09_aerea")
	p.cam.camera.make_current()
	# Calidad baja: sin detalle procedural del suelo y menos césped.
	SettingsManager.set_value("graphics", "low")
	p.teleport(Vector3(-9.0, 0.6, 33.0), 0.0)
	p.cam.pitch = -0.3
	await frames(30)
	await shot("g10_calidad_baja")
	print("fps (render real en CPU): ", Engine.get_frames_per_second())
	get_tree().quit()
