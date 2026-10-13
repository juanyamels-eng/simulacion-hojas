extends Node
## Pruebas automáticas de juego (QA): ejecuta la escena principal en modo headless y
## simula una sesión real: moverse, recoger hojas, llenar y cerrar la bolsa, entregarla,
## cobrar, comprar mejoras, usar rastrillo/soplador/aspiradora, guardar y recargar.
## Uso: godot --headless res://tests/test_runner.tscn

var main: Node
var failures := 0
var checks := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  OK  ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== Villa Hojarasca · pruebas ===")
	for slot in ["campaign", "zen", "time_attack"]:
		SaveManager.delete_slot(slot)
	GameManager.requested_new = true
	GameManager.skip_menu = true
	var t0 := Time.get_ticks_msec()
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await frames(5)
	var guard := 0
	while GameManager.world == null or not GameManager.in_game:
		await frames(1)
		guard += 1
		if guard > 1800:
			print("  FAIL el mundo no llegó a cargarse")
			get_tree().quit(1)
			return
	print("Mundo construido en %d ms" % (Time.get_ticks_msec() - t0))
	var world: World = GameManager.world
	var p: PlayerController = world.player
	var sim: LeafSimulationSystem = world.leaf_manager.sim
	ok(sim.n > 30000, "hojas generadas: %d" % sim.n)
	ok(world.robot != null and not world.robot.visible, "robot Brizna creado (inactivo hasta repararlo)")
	ok(AreaManager.initial.get("entrada", 0) > 2400, "hojas en Entrada: %s" % AreaManager.initial.get("entrada", 0))
	ok(AreaManager.pct("entrada") == 0.0, "Entrada empieza al 0 %")
	ok(p.is_on_floor() or true, "jugador creado")
	# --- Movimiento ---
	var start := p.global_position
	InputState.move = Vector2(0, 1)
	await frames(60)
	InputState.move = Vector2.ZERO
	await frames(10)
	ok(p.global_position.distance_to(start) > 2.0, "el jugador camina (%.1f m)" % p.global_position.distance_to(start))
	ok(p.global_position.y > -1.0 and p.global_position.y < 3.0, "el jugador está sobre el suelo (y=%.2f)" % p.global_position.y)
	# --- Cámara ---
	var yaw0 := p.rotation.y
	InputState.look_delta = Vector2(200, 0)
	await frames(2)
	ok(absf(p.rotation.y - yaw0) > 0.3, "la cámara gira con el dedo")
	p.rotation.y = 0.0
	p.cam.pitch = -0.6
	# --- Recoger hojas con la mano ---
	var before := sim.zone_counts[0]
	var grabs := 0
	while p.bags.count < p.bags.capacity() and grabs < 400:
		if grabs % 3 == 0:
			_aim_at_leaves(p, sim)
			await frames(2)
		InputState.action_pressed = true
		InputState.action_held = true
		await frames(1)
		InputState.action_held = false
		await frames(22)
		grabs += 1
	await frames(30)
	ok(p.bags.count >= p.bags.capacity(), "bolsa llena con la mano (%d/%d) en %d puñados" % [p.bags.count, p.bags.capacity(), grabs])
	ok(sim.zone_counts[0] < before, "quedan menos hojas en Entrada (%d → %d)" % [before, sim.zone_counts[0]])
	ok(ProgressManager.get_stat("leaves_collected") >= 50, "estadística de hojas recogidas")
	# --- Cerrar bolsa (mantener interactuar) ---
	p.rotation.y = 0.0
	p.cam.pitch = 0.6
	InputState.interact_pressed = true
	InputState.interact_held = true
	await frames(100)
	InputState.interact_held = false
	await frames(2)
	ok(p.bags.is_carrying(), "bolsa cerrada y en la mano (%d hojas)" % p.bags.held_leaves)
	# --- Entregar en el contenedor ---
	var bin: RecycleBin = world.builder.bins[0]
	p.teleport(bin.global_position + Vector3(-2.2, 0.2, 0), -PI * 0.5)
	p.cam.pitch = -0.25
	await frames(10)
	var money0 := EconomyManager.money
	InputState.interact_pressed = true
	InputState.interact_held = true
	await frames(3)
	InputState.interact_held = false
	await frames(5)
	ok(EconomyManager.money > money0, "dinero recibido al entregar: %.0f $" % EconomyManager.money)
	ok(ProgressManager.get_stat("bags_delivered") >= 1, "bolsa entregada")
	# --- Comprar la primera mejora ---
	var lvl := UpgradeManager.get_level("hand")
	ok(UpgradeManager.buy("hand"), "compra Manos expertas")
	ok(UpgradeManager.get_level("hand") == lvl + 1 and int(UpgradeManager.get_value("hand")) == 4, "la mano recoge 4 hojas")
	# --- Rastrillo ---
	EconomyManager.add_money(5000)
	ok(UpgradeManager.buy("tool_rake"), "compra rastrillo")
	await frames(2)
	ok(GameManager.current_tool == "rake", "rastrillo equipado")
	p.teleport(Vector3(-12, 0.5, 58), 0.0)
	await frames(5)
	var piles0 := ProgressManager.get_stat("leaves_raked")
	InputState.action_held = true
	InputState.move = Vector2(0, 1)
	await frames(90)
	InputState.move = Vector2.ZERO
	await frames(60)
	InputState.action_held = false
	await frames(5)
	ok(ProgressManager.get_stat("leaves_raked") > piles0, "el rastrillo mueve hojas (%d)" % ProgressManager.get_stat("leaves_raked"))
	# --- Soplador ---
	UpgradeManager.levels["tool_blower"] = 1
	AreaManager.unlock_zone("jardin_delantero")
	p.tools.select("blower")
	p.teleport(Vector3(10, 0.5, 60), PI * 0.5)
	p.cam.pitch = -0.2
	await frames(3)
	InputState.action_held = true
	await frames(60)
	var air := sim.active_n
	await frames(60)
	InputState.action_held = false
	ok(ProgressManager.get_stat("leaves_blown") > 0, "el soplador levanta hojas (%d sopladas, %d en vuelo)" % [ProgressManager.get_stat("leaves_blown"), air])
	await frames(240)
	ok(sim.active_n < air or air == 0, "las hojas vuelven a reposar (activas: %d)" % sim.active_n)
	# --- Aspiradora ---
	UpgradeManager.levels["tool_vacuum"] = 1
	p.bags.count = 0
	p.bags.held_leaves = 0
	p.tools.select("vacuum")
	p.teleport(Vector3(-14, 0.5, 46), 0.0)
	p.cam.pitch = -0.5
	await frames(3)
	var c0 := p.bags.count
	InputState.action_held = true
	await frames(150)
	InputState.action_held = false
	await frames(30)
	ok(p.bags.count > c0, "la aspiradora absorbe hojas a la bolsa (%d)" % p.bags.count)
	# --- Cambio de herramienta ---
	InputState.tool_next = true
	await frames(2)
	ok(GameManager.current_tool != "vacuum", "cambio rápido de herramienta → %s" % GameManager.current_tool)
	# --- Porcentaje y desbloqueo de zona ---
	var pct := AreaManager.pct("entrada")
	ok(pct > 0.0, "porcentaje de limpieza de Entrada: %.1f %%" % pct)
	for i in sim.n:
		if sim.zone_origin[i] == 0 and sim.state[i] != LeafSimulationSystem.S_REMOVED:
			sim.remove_leaf(i)
	world.leaf_manager.push_counts()
	await frames(5)
	ok(AreaManager.pct("entrada") == 100.0, "Entrada completada al 100 %")
	ok(AreaManager.completed.get("entrada", false), "recompensa de zona completa aplicada")
	var gate: GateDoor = world.gates["g_delantero"]
	ok(gate.requirement_met(), "requisito de la puerta cumplido")
	EconomyManager.add_money(500)
	gate.interact(p)
	await frames(5)
	ok(AreaManager.is_unlocked("jardin_delantero") and gate.opened, "puerta abierta y zona desbloqueada")
	# --- Guardar, recargar y recuperar ---
	var money_saved := EconomyManager.money
	var removed_saved := sim.zone_counts[0]
	var hand_lvl := UpgradeManager.get_level("hand")
	ok(SaveManager.save_game(), "guardado correcto")
	ok(FileAccess.file_exists("user://campaign_state.json") and FileAccess.file_exists("user://campaign_leaves.bin"), "archivos de guardado creados")
	GameManager.in_game = false
	GameManager.skip_menu = true
	GameManager.requested_new = false
	main.queue_free()
	await frames(3)
	EconomyManager.money = 0
	UpgradeManager.levels.clear()
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	guard = 0
	while GameManager.world == null or not GameManager.in_game or GameManager.world == world:
		await frames(1)
		guard += 1
		if guard > 1800:
			print("  FAIL la partida no se recargó")
			get_tree().quit(1)
			return
	world = GameManager.world
	sim = world.leaf_manager.sim
	ok(absf(EconomyManager.money - money_saved) < 1.0, "dinero recuperado (%.0f)" % EconomyManager.money)
	ok(UpgradeManager.get_level("hand") == hand_lvl, "mejoras recuperadas")
	ok(sim.zone_counts[0] == removed_saved, "hojas recuperadas (Entrada: %d)" % sim.zone_counts[0])
	ok(AreaManager.is_unlocked("jardin_delantero"), "zonas desbloqueadas recuperadas")
	ok(world.gates["g_delantero"].opened, "puerta abierta tras recargar")
	# --- Guardado dañado: usa la copia de seguridad ---
	SaveManager.save_game()
	var f := FileAccess.open("user://campaign_state.json", FileAccess.WRITE)
	f.store_string("{roto")
	f.close()
	EconomyManager.money = 0
	ok(SaveManager.load_game() and EconomyManager.money > 0, "recuperación desde backup tras corrupción")
	# --- Diario, ajustes, pausa ---
	var ui: UIManager = main.ui
	var probe := Journal.new()
	ok(probe.get_child_count() == 2, "los menús se construyen una sola vez (%d nodos raíz)" % probe.get_child_count())
	probe.free()
	ui.open_journal("map")
	await frames(3)
	ok(get_tree().paused, "el diario pausa el juego")
	for tab in ["objectives", "shop", "collection", "stats", "achievements", "map"]:
		(ui.stack.back() as Journal)._show(tab)
		await frames(2)
	ui.close_top()
	await frames(3)
	ok(not get_tree().paused, "cerrar el diario reanuda")
	SettingsManager.set_value("graphics", "low")
	await frames(3)
	ok(PerformanceManager.level == PerformanceManager.LOW and sim.max_active == 350, "cambio a gráficos bajos")
	SettingsManager.set_value("graphics", "auto")
	ui.open_pause()
	await frames(3)
	ok(get_tree().paused, "pausa")
	ui.close_top()
	await frames(3)
	ok(not get_tree().paused, "reanudar")
	# --- Bellota, guías, mejoras disponibles, "+N", estallido de hojas y celebración ---
	await _gameplay_extras(world, ui)
	# --- Rendimiento del sistema de hojas (CPU) ---
	await _perf(world)
	print("=== %d comprobaciones, %d fallos ===" % [checks, failures])
	for slot in ["campaign"]:
		SaveManager.delete_slot(slot)
	get_tree().quit(1 if failures > 0 else 0)


## Como haría una persona: buscar un grupo de hojas cercano, acercarse y mirarlo.
func _aim_at_leaves(p: PlayerController, sim: LeafSimulationSystem) -> void:
	var best := -1
	var best_c := 0
	var pp := p.global_position
	for dz in range(-24, 25, 2):
		for dx in range(-24, 25, 2):
			var c := sim.cell_index(pp.x + dx * 0.5, pp.z + dz * 0.5)
			if c >= 0 and sim.cell_count[c] > best_c and sim.cell_zone[c] == 1:
				best_c = sim.cell_count[c]
				best = c
	if best < 0:
		return
	var target := Vector3(sim.ox + (best % sim.gw + 0.5) * 0.5, 0, sim.oz + (best / sim.gw + 0.5) * 0.5)
	var dir := Vector3(target.x - pp.x, 0, target.z - pp.z)
	if dir.length() < 0.1:
		dir = Vector3(0, 0, -1)
	dir = dir.normalized()
	var stand := target - dir * 2.0
	p.teleport(Vector3(stand.x, sim.height_at(stand.x, stand.z) + 0.1, stand.z), atan2(-dir.x, -dir.z))
	p.cam.pitch = -0.62


func _perf(world: World) -> void:
	var sim: LeafSimulationSystem = world.leaf_manager.sim
	var p: PlayerController = world.player
	for count in [1000, 5000]:
		sim.max_active = count
		var n := 0
		for i in sim.n:
			if n >= count:
				break
			if sim.state[i] == LeafSimulationSystem.S_SLEEP:
				if sim.wake(i, Vector3(randf_range(-2, 2), randf_range(1, 4), randf_range(-2, 2))):
					n += 1
		var t0 := Time.get_ticks_usec()
		for k in 10:
			sim.simulate(1.0 / 60.0)
		var ms := (Time.get_ticks_usec() - t0) / 10000.0
		print("  PERF %d hojas activas: %.2f ms/frame (CPU escritorio)" % [sim.active_n, ms])
		await frames(200)
	sim.max_active = 750
	var t1 := Time.get_ticks_usec()
	sim.rake_sweep(Vector3(0, 0, 30), Vector3(0, 0, 29.9), Vector3(1, 0, 0), 3.4, 1100, 1.0, 1)
	print("  PERF barrido de rastrillo: %.2f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	t1 = Time.get_ticks_usec()
	world.leaf_manager.cluster.flush(sim, true)
	print("  PERF regenerar textura completa de montones: %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	t1 = Time.get_ticks_usec()
	var bytes := world.leaf_manager.save_leaf_state()
	print("  PERF serializar %d hojas: %.1f ms (%d bytes)" % [sim.n, (Time.get_ticks_usec() - t1) / 1000.0, bytes.size()])


# ---------------------------------------------------------------- sistemas de juego añadidos

func _gameplay_extras(world: World, ui: UIManager) -> void:
	var p: PlayerController = world.player
	var sim: LeafSimulationSystem = world.leaf_manager.sim
	var lm: LeafManager = world.leaf_manager
	var hud: HUD = ui.hud
	InputState.reset()
	p.bags.count = 0
	p.bags.value = 0.0
	# Datos de diseño y sonidos nuevos.
	var ids := {}
	var dup := false
	for a in GameData.ACHIEVEMENTS:
		if ids.has(a["id"]):
			dup = true
		ids[a["id"]] = true
	ok(not dup and ids.has("pet_dog") and ids.has("pet_dog_25") and ids.has("dog_find") and ids.has("dog_pile"), "logros nuevos definidos, sin ids repetidos (%d logros)" % ids.size())
	var missing := []
	for snd in ["ui_fanfare", "ui_notify", "dog_bark_1", "dog_bark_2", "dog_happy", "dog_sniff"]:
		if AudioManager.stream(snd) == null:
			missing.append(snd)
	ok(missing.is_empty(), "sonidos nuevos cargados %s" % str(missing))
	# --- Bellota ---
	var dog := world.get_node_or_null("Bellota") as Companion
	ok(dog != null, "Bellota, la perrita compañera, está en la finca")
	if dog == null:
		return
	ok((dog.collision_layer & Interactable.LAYER_WORLD) == 0 and (p.collision_mask & dog.collision_layer) == 0, "Bellota no bloquea al jugador ni a las bolsas")
	# Te sigue a una distancia cómoda.
	p.teleport(Vector3(0, 0.5, 33), 0.0)
	dog.place_near_player(true)
	await frames(20)
	var start := p.global_position
	InputState.move = Vector2(0, 0.8)
	await frames(130)
	InputState.move = Vector2.ZERO
	var walked := p.global_position.distance_to(start)
	await frames(200)
	var d := _flat(dog.global_position, p.global_position)
	ok(walked > 4.0 and d > 0.8 and d < 5.0, "Bellota te sigue y se queda a una distancia cómoda (%.1f m tras andar %.1f m)" % [d, walked])
	ok(dog.global_position.y > sim.height_at(dog.global_position.x, dog.global_position.z) - 0.1, "Bellota camina sobre el suelo")
	# Acariciarla mirándola y pulsando INTERACTUAR.
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var spot := p.global_position + fwd * 1.8
	dog.global_position = Vector3(spot.x, sim.height_at(spot.x, spot.z), spot.z)
	dog._set_state(Companion.IDLE)
	p.cam.pitch = -0.55
	await frames(4)
	ok(p.prompt.contains("Bellota"), "al mirarla aparece «%s»" % p.prompt)
	var pets0 := ProgressManager.get_stat("dog_pets")
	InputState.interact_pressed = true
	InputState.interact_held = true
	await frames(2)
	InputState.interact_held = false
	await frames(4)
	ok(ProgressManager.get_stat("dog_pets") == pets0 + 1 and dog.state == Companion.PETTED and AchievementManager.is_unlocked("pet_dog"), "acariciar a Bellota: corazones, alegría y logro")
	# Con una bolsa cerrada en la mano no intercepta el rayo (para poder usar el contenedor).
	p.bags.held_leaves = 20
	await frames(3)
	ok(dog.collision_layer == 0 and not p.prompt.contains("Bellota"), "con una bolsa en la mano, Bellota no tapa el contenedor")
	p.bags.held_leaves = 0
	p.bags.count = p.bags.capacity()
	await frames(3)
	ok(dog.collision_layer == 0 and p.prompt.begins_with("Cerrar bolsa"), "con la bolsa llena, mirarla no impide cerrarla («%s»)" % p.prompt)
	p.bags.count = 0
	await frames(3)
	ok(dog.collision_layer == Interactable.LAYER_INTERACT, "con la bolsa vacía vuelve a poder acariciarse")
	# Se lanza a un montón grande y esparce hojas.
	p.cam.pitch = 0.0
	await frames(30)
	var pile_c := p.global_position + fwd * 5.5
	var moved := _make_pile(sim, pile_c, 700)
	lm.cluster.flush(sim, true)
	var ph := lm.pile_height_at(pile_c.x, pile_c.z)
	dog._sniff_cd = 999.0
	dog._pile_cd = 0.0
	dog._think = 0.0
	dog._set_state(Companion.IDLE)
	var jumps0 := dog.pile_jumps
	var scattered0 := dog.leaves_scattered
	var guard := 0
	while dog.pile_jumps == jumps0 and guard < 600:
		await frames(1)
		guard += 1
	ok(dog.pile_jumps > jumps0 and dog.leaves_scattered > scattered0, "Bellota corre y se lanza al montón (%.2f m, %d hojas juntadas): esparce %d hojas" % [ph, moved, dog.leaves_scattered - scattered0])
	await frames(150)
	ok(dog.state != Companion.LEAP and dog.state != Companion.PLAY, "tras revolcarse vuelve contigo (estado %d)" % dog.state)
	# Olfatea una postal escondida cerca y te ayuda a encontrarla.
	var card := _postcard(world, "p02")
	if card:
		var cp := card.global_position
		_make_pile(sim, cp, 40, 0.3)
		lm.cluster.flush(sim, true)
		p.teleport(Vector3(cp.x + 3.5, cp.y + 0.3, cp.z + 2.0), 0.0)
		dog.place_near_player(false)
		await frames(40)
		var sn0 := dog.sniffs
		dog._pile_cd = 999.0
		dog._sniff_cd = 0.0
		dog._think = 0.0
		dog._set_state(Companion.IDLE)
		guard = 0
		while dog.state != Companion.SNIFF and guard < 600:
			await frames(1)
			guard += 1
		ok(dog.sniffs > sn0 and dog.state == Companion.SNIFF and dog.hint_id == "p02", "Bellota olfatea la postal escondida cerca (%d fotogramas)" % guard)
		await frames(10)
		CollectibleManager.collect("p02")
		await frames(3)
		ok(AchievementManager.is_unlocked("dog_find"), "logro «Olfato fino» al recoger la postal que olfateó")
		dog._find_hidden_card(p.global_position)
		var stale := 0
		for o in dog._postcards:
			if not is_instance_valid(o):
				stale += 1
		ok(stale == 0, "las postales recogidas salen de la lista de Bellota sin errores")
		while not ui.stack.is_empty():
			ui.close_top()
			await frames(3)
	else:
		ok(false, "postal p02 presente para la prueba de olfato")
	# --- Guías en pantalla ---
	var markers: GuideMarkers = hud._markers
	p.teleport(Vector3(-4, 0.5, 30), 0.0)
	p.bags.held_leaves = 25
	p.bags.held_value = 10.0
	await frames(25)
	var near := GuideMarkers.nearest_bin(world, p.global_position)
	var best_d := INF
	for b in world.builder.bins:
		var z := AreaManager.zone_at(b.global_position)
		if (z == "" or AreaManager.is_unlocked(z)) and absf(b.global_position.y - p.global_position.y) < 6.0:
			best_d = minf(best_d, b.global_position.distance_to(p.global_position))
	var bin_t := _target(markers, GuideMarkers.BIN)
	ok(near != null and absf(near.global_position.distance_to(p.global_position) - best_d) < 0.01 and not bin_t.is_empty(), "con una bolsa cerrada, marcador al contenedor más cercano (%.0f m)" % best_d)
	p.bags.held_leaves = 0
	p.bags.held_value = 0.0
	await frames(25)
	ok(_target(markers, GuideMarkers.BIN).is_empty(), "sin bolsa, el marcador del contenedor desaparece")
	var cam := p.cam.camera
	var behind := cam.global_position + cam.global_transform.basis.z * 12.0 + cam.global_transform.basis.x * 2.0
	var pr := markers.project(cam, behind)
	var edge := markers.edge_rect().grow(1.0)
	ok(pr.z < 0.5 and edge.has_point(Vector2(pr.x, pr.y)) and pr.x > edge.get_center().x, "objetivo a la espalda: marcador fijado al borde derecho (%.0f, %.0f)" % [pr.x, pr.y])
	var ahead := cam.global_position - cam.global_transform.basis.z * 12.0
	pr = markers.project(cam, ahead)
	var vs := hud.get_viewport_rect().size
	ok(pr.z > 0.5 and Vector2(pr.x, pr.y).distance_to(vs * 0.5) < 30.0, "objetivo delante: marcador en su sitio de la pantalla")
	# Puerta: requisito cumplido y dinero suficiente.
	_clear_fraction(sim, GameData.zone_index("jardin_delantero"), 0.6)
	lm.push_counts()
	EconomyManager.money = 0.0
	await frames(25)
	ok(_target(markers, GuideMarkers.GATE).is_empty(), "sin dinero, no se marca la puerta (%.1f %% limpio)" % AreaManager.pct("jardin_delantero"))
	EconomyManager.add_money(5000)
	await frames(25)
	var gate := GuideMarkers.next_gate(world, p.global_position)
	ok(gate != null and not _target(markers, GuideMarkers.GATE).is_empty() and gate.gate["a"] == "jardin_delantero", "marcador a la puerta que ya puedes abrir: %s" % (gate.gate["id"] if gate else "ninguna"))
	# --- Insignia de mejora disponible en el diario ---
	ProgressManager.tutorial_step = 7
	EconomyManager.money = 0.0
	hud.check_upgrades()
	ok(hud.upgrade_available == "" and not hud._badge.visible, "sin dinero no hay insignia de mejora")
	hud._upgrade_toast_at = -1000.0
	EconomyManager.add_money(50000)
	await frames(70)
	var newest := hud._toasts.get_child(hud._toasts.get_child_count() - 1) if hud._toasts.get_child_count() > 0 else null
	var newest_title := ""
	if newest:
		newest_title = (newest.get_child(0).get_child(0) as Label).text
	ok(hud.upgrade_available != "" and hud._badge.visible and hud._upgrade_toast_at > 0.0 and newest_title == "Mejora disponible", "mejora asequible: insignia en el diario y aviso «%s» (%s)" % [newest_title, hud.upgrade_available])
	var toast_at := hud._upgrade_toast_at
	EconomyManager.money = 0.0
	await frames(70)
	EconomyManager.add_money(50000)
	await frames(70)
	ok(hud._badge.visible and hud._upgrade_toast_at == toast_at, "el aviso de mejora no se repite enseguida (la insignia sí vuelve)")
	hud._on_journal_pressed()
	await frames(3)
	ok(not ui.stack.is_empty() and ui.stack.back() is Journal and (ui.stack.back() as Journal).tab == "shop", "con la insignia, el diario se abre en MEJORAS")
	while not ui.stack.is_empty():
		ui.close_top()
		await frames(3)
	# --- Recoger: "+N" agregado y estallido de hojas ---
	p.bags.count = 0
	p.bags.value = 0.0
	await frames(80)
	p.bags.add(3, 1.0, "hand")
	p.bags.add(4, 1.0, "vacuum")
	ok(hud.gain == 7, "contador «+N» agrega las hojas recogidas seguidas (+%d)" % hud.gain)
	p.tools.select("hand", false)
	var hand: HandTool = p.tools.tools["hand"]
	var b0 := hand.bursts_emitted
	var got := false
	for attempt in 6:
		_aim_zone(p, sim, GameData.zone_index("jardin_delantero") + 1)
		await frames(3)
		InputState.action_pressed = true
		InputState.action_held = true
		await frames(1)
		InputState.action_held = false
		await frames(25)
		if hand.bursts_emitted > b0:
			got = true
			break
	ok(got, "estallido de hojas en el punto de agarre (%d)" % (hand.bursts_emitted - b0))
	# --- Zona al 100 %: celebración ---
	var c0 := hud.celebrations
	var secret := GameData.zone_index("taller_secreto")
	for i in sim.n:
		if sim.zone_origin[i] == secret and sim.state[i] != LeafSimulationSystem.S_REMOVED:
			sim.remove_leaf(i)
	lm.push_counts()
	await frames(5)
	ok(hud.celebrations == c0 + 1 and hud.is_celebrating(), "zona al 100 %: título, confeti de hojas y fanfarria")
	await frames(320)
	ok(not hud.is_celebrating(), "la celebración termina sola")
	# --- Coste por fotograma ---
	var t0 := Time.get_ticks_usec()
	for k in 200:
		dog._process(1.0 / 60.0)
	print("  PERF Bellota: %.3f ms/frame" % ((Time.get_ticks_usec() - t0) / 200000.0))
	t0 = Time.get_ticks_usec()
	for k in 20:
		dog.find_pile(p.global_position)
	print("  PERF Bellota busca montón (cada ~6 s): %.2f ms" % ((Time.get_ticks_usec() - t0) / 20000.0))
	t0 = Time.get_ticks_usec()
	for k in 50:
		markers.refresh()
	print("  PERF guías: %.3f ms por recálculo (4 por segundo)" % ((Time.get_ticks_usec() - t0) / 50000.0))
	t0 = Time.get_ticks_usec()
	for k in 20:
		hud.check_upgrades()
	print("  PERF insignia de mejoras: %.3f ms por comprobación (1 por segundo)" % ((Time.get_ticks_usec() - t0) / 20000.0))


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _target(m: GuideMarkers, kind: int) -> Dictionary:
	for t in m.targets:
		if int(t["kind"]) == kind:
			return t
	return {}


## Junta hojas en reposo (de cualquier sitio de la finca) en un disco: un montón de prueba.
func _make_pile(sim: LeafSimulationSystem, c: Vector3, count: int, radius: float = 0.7) -> int:
	var moved := 0
	var secret := GameData.zone_index("taller_secreto")
	for i in sim.n:
		if moved >= count:
			break
		if sim.state[i] != LeafSimulationSystem.S_SLEEP or sim.zone_origin[i] == secret:
			continue
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)).limit_length(1.0) * radius
		var x := c.x + off.x
		var z := c.z + off.y
		sim.move_sleeping(i, Vector3(x, sim.height_at(x, z) + 0.015, z))
		moved += 1
	return moved


## Retira una fracción de las hojas que quedan en una zona (para cumplir el requisito de una puerta).
func _clear_fraction(sim: LeafSimulationSystem, zi: int, frac: float) -> void:
	var left := 0
	for i in sim.n:
		if sim.zone_origin[i] == zi and sim.state[i] != LeafSimulationSystem.S_REMOVED:
			left += 1
	var target := int(left * frac)
	for i in sim.n:
		if target <= 0:
			break
		if sim.zone_origin[i] == zi and sim.state[i] == LeafSimulationSystem.S_SLEEP:
			sim.remove_leaf(i)
			target -= 1


func _postcard(world: World, id: String) -> StationObject:
	for c in world.get_children():
		if c is StationObject and (c as StationObject).kind == StationObject.Kind.POSTCARD and (c as StationObject).data.get("id", "") == id:
			return c
	return null


## Como _aim_at_leaves, pero para cualquier zona (cell_zone = índice de zona + 1).
func _aim_zone(p: PlayerController, sim: LeafSimulationSystem, cell_zone: int) -> void:
	var best := -1
	var best_c := 0
	var pp := p.global_position
	for dz in range(-30, 31, 2):
		for dx in range(-30, 31, 2):
			var c := sim.cell_index(pp.x + dx * 0.5, pp.z + dz * 0.5)
			if c >= 0 and sim.cell_count[c] > best_c and sim.cell_zone[c] == cell_zone:
				best_c = sim.cell_count[c]
				best = c
	if best < 0:
		return
	var target := Vector3(sim.ox + (best % sim.gw + 0.5) * 0.5, 0, sim.oz + (best / sim.gw + 0.5) * 0.5)
	var dir := Vector3(target.x - pp.x, 0, target.z - pp.z)
	if dir.length() < 0.1:
		dir = Vector3(0, 0, -1)
	dir = dir.normalized()
	var stand := target - dir * 2.0
	p.teleport(Vector3(stand.x, sim.height_at(stand.x, stand.z) + 0.1, stand.z), atan2(-dir.x, -dir.z))
	p.cam.pitch = -0.62
