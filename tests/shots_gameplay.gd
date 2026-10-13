extends Node
## Capturas de QA de los sistemas de juego añadidos: Bellota, guías del HUD, insignia de mejora,
## respuesta al recoger y celebración de zona. Requiere render real:
## xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 res://tests/shots_gameplay.tscn

var out_dir := "user://shots"
var main: Node


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + shot_name + ".png")
	print("captura: ", shot_name)


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
	var hud: HUD = main.ui.hud
	var sim := world.leaf_manager.sim
	var dog := world.get_node_or_null("Bellota") as Companion
	SettingsManager.set_value("graphics", "high")
	ProgressManager.tutorial_step = 7
	ProgressManager.set_flag("met_bellota")
	await frames(30)
	# 1) Bellota sentada a un lado, mirándote.
	p.teleport(GameData.START_POS, 0.0)
	p.cam.pitch = -0.3
	var fwd := -p.global_transform.basis.z
	var right := p.global_transform.basis.x
	var spot := Vector3.ZERO
	dog.place_near_player(true)
	dog._pile_cd = 999.0
	dog._sniff_cd = 999.0
	await frames(70)
	await shot("g01_bellota")
	# 2) Acariciarla de cerca: corazones.
	spot = p.global_position + fwd * 1.5 + right * 0.15
	dog.global_position = Vector3(spot.x, sim.height_at(spot.x, spot.z), spot.z)
	p.cam.pitch = -0.5
	await frames(20)
	InputState.interact_pressed = true
	await frames(6)
	await shot("g02_caricia")
	# 3) Se lanza a un montón.
	await frames(40)
	var pile_c := p.global_position + fwd * 5.0 - right * 1.2
	var moved := 0
	for i in sim.n:
		if moved >= 600:
			break
		if sim.state[i] == LeafSimulationSystem.S_SLEEP and sim.zone_origin[i] == 0:
			var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)).limit_length(1.0) * 0.9
			sim.move_sleeping(i, Vector3(pile_c.x + off.x, sim.height_at(pile_c.x + off.x, pile_c.z + off.y) + 0.015, pile_c.z + off.y))
			moved += 1
	world.leaf_manager.cluster.flush(sim, true)
	p.cam.pitch = -0.3
	dog._pile_cd = 0.0
	dog._think = 0.0
	dog._set_state(Companion.IDLE)
	var guard := 0
	while dog.state != Companion.PLAY and guard < 400:
		await frames(1)
		guard += 1
	await frames(4)
	await shot("g03_monton")
	# 4) Bolsa cerrada en la mano: guía al contenedor (en pantalla).
	dog._pile_cd = 999.0
	var bin: RecycleBin = world.builder.bins[0]
	var bp := bin.global_position
	p.teleport(bp + Vector3(-10.0, 0.3, 4.0), 0.0)
	var to := bp - p.global_position
	p.rotation.y = atan2(-to.x, -to.z) + 0.25
	p.cam.pitch = -0.08
	p.bags.count = 30
	p.bags.close_bag()
	await frames(40)
	await shot("g04_guia_contenedor")
	# 5) De espaldas al contenedor: marcador en el borde; puerta asequible; insignia del diario y aviso.
	p.rotation.y += PI * 0.85
	for i in sim.n:
		if sim.zone_origin[i] == 0 and sim.state[i] == LeafSimulationSystem.S_SLEEP and randf() < 0.45:
			sim.remove_leaf(i)
	world.leaf_manager.push_counts()
	await frames(70)
	EconomyManager.add_money(400)
	await frames(14)
	await shot("g05_guia_borde_insignia")
	# 6) Recoger con la mano: estallido de hojas, "+N" y pulso de la bolsa.
	p.bags.deposit_held(bin)
	await frames(10)
	var best := -1
	var best_c := 0
	var pp := p.global_position
	for dz in range(-24, 25, 2):
		for dx in range(-24, 25, 2):
			var c := sim.cell_index(pp.x + dx * 0.5, pp.z + dz * 0.5)
			if c >= 0 and sim.cell_count[c] > best_c and sim.cell_zone[c] == 1:
				best_c = sim.cell_count[c]
				best = c
	if best >= 0:
		var target := Vector3(sim.ox + (best % sim.gw + 0.5) * 0.5, 0, sim.oz + (best / sim.gw + 0.5) * 0.5)
		var dir := Vector3(target.x - pp.x, 0, target.z - pp.z).normalized()
		var stand := target - dir * 2.0
		p.teleport(Vector3(stand.x, sim.height_at(stand.x, stand.z) + 0.1, stand.z), atan2(-dir.x, -dir.z))
		p.cam.pitch = -0.62
	UpgradeManager.levels["hand"] = 3
	await frames(20)
	for k in 3:
		InputState.action_pressed = true
		InputState.action_held = true
		await frames(1)
		InputState.action_held = false
		await frames(22)
	InputState.action_pressed = true
	guard = 0
	while hud._gain_t < 0.95 and guard < 30:
		await frames(1)
		guard += 1
	await shot("g06_recoger")
	# 7) Celebración de zona restaurada.
	p.cam.pitch = 0.0
	hud.celebrate("¡Zona restaurada!", "Entrada vuelve a lucir como antes")
	await frames(32)
	await shot("g07_celebracion")
	await frames(300)
	print("fps (render real en CPU): ", Engine.get_frames_per_second())
	SaveManager.delete_slot("campaign")
	get_tree().quit()
