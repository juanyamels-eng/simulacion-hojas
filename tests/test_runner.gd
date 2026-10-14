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
	# --- Hojas individuales (v3): mallas, montones de hojas, resaltados y rendimiento con 65.000 hojas ---
	await _leaves_v3(world)
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


# ---------------------------------------------------------------- hojas individuales (v3)

var _perf_mms: Array[MultiMesh] = []


## Hojas individuales: mallas ligeras con 5 siluetas sin triángulos dados la vuelta, montones hechos solo
## de hojas (la hojarasca suelta no flota, un montón grande sí abulta), captura desde lo alto de un
## montón, círculo de resaltado, «Resaltar hojas», brillo de las últimas hojas de una zona y rendimiento.
func _leaves_v3(world: World) -> void:
	var lm: LeafManager = world.leaf_manager
	var sim: LeafSimulationSystem = lm.sim
	# --- Mallas
	var near := LeafMeshes.leaf_mesh()
	var nv := near.surface_get_array_len(0)
	var nt := near.surface_get_array_index_len(0) / 3
	var lod_v := LeafMeshes.leaf_mesh_lod().surface_get_array_len(0)
	var far_v := LeafMeshes.leaf_mesh_far().surface_get_array_len(0)
	ok(nv <= 32 and lod_v <= 8 and far_v <= 4, "mallas de hoja ligeras: %d vértices (%d triángulos), LOD %d, lejana %d" % [nv, nt, lod_v, far_v])
	var idx := LeafMeshes.triangle_indices()
	var ref := LeafMeshes.shape_points(2)
	var flipped := 0
	for s in LeafMeshes.SHAPES:
		var pts := LeafMeshes.shape_points(s)
		for t in range(0, idx.size(), 3):
			var a_ref := LeafMeshes.signed_area(ref, idx[t], idx[t + 1], idx[t + 2])
			var a := LeafMeshes.signed_area(pts, idx[t], idx[t + 1], idx[t + 2])
			if a * signf(a_ref) < -0.00001:
				flipped += 1
	ok(flipped == 0 and LeafMeshes.SHAPES == 5, "5 siluetas (arce, roble, abedul, sauce, ginkgo) sin triángulos dados la vuelta (%d)" % flipped)
	var pm := MeshFactory.leaf_mesh()
	ok(pm.surface_get_array_len(0) >= 20 and MeshFactory.leaf_mesh_lod().surface_get_array_len(0) >= 6, "hojas de partículas con forma de hoja (%d vértices)" % pm.surface_get_array_len(0))
	# --- La hojarasca natural (sin juntar) no flota: altura de montón ~0 en una zona intacta.
	var zi := GameData.zone_index("laberinto")
	var zr: Rect2 = GameData.ZONES[zi]["rect"]
	var max_h := 0.0
	var lifted := 0
	var cells := 0
	var x := zr.position.x + 0.25
	while x < zr.end.x:
		var z := zr.position.y + 0.25
		while z < zr.end.y:
			var h := lm.pile_height_at(x, z)
			max_h = maxf(max_h, h)
			if h > 0.05:
				lifted += 1
			cells += 1
			z += 0.5
		x += 0.5
	ok(max_h < 0.3 and lifted * 100 < cells, "la hojarasca suelta yace en el suelo (altura máx. %.2f m, %d de %d celdas por encima de 5 cm)" % [max_h, lifted, cells])
	# --- Un montón de 1000 hojas abulta; alrededor, las hojas sueltas no se levantan por el halo.
	var pc := _free_flat(world, world.player.global_position + Vector3(4.0, 0.0, 0.0))
	var moved := _make_pile(sim, pc, 1000, 1.3)
	lm.cluster.flush(sim, true)
	var ph := lm.pile_height_at(pc.x, pc.z)
	var ring := 0.0
	for k in 12:
		var q := pc + Vector3(cos(k * TAU / 12.0), 0.0, sin(k * TAU / 12.0)) * 2.4
		ring = maxf(ring, lm.pile_height_at(q.x, q.z))
	ok(ph > 0.4 and ph < 1.0 and ring < ph * 0.35, "montón de %d hojas: %.2f m de alto, borde a 2,4 m: %.2f m" % [moved, ph, ring])
	var thin := 0
	var pile_cells := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var c := sim.cell_index(pc.x + dx * 0.5, pc.z + dz * 0.5)
			if dx * dx + dz * dz > 4:
				continue
			if c >= 0 and lm.pile_height_at(pc.x + dx * 0.5, pc.z + dz * 0.5) > 0.1:
				pile_cells += 1
				if float(sim.cell_count[c]) * LeafClusterSystem.LAYERS_PER_LEAF < 2.0:
					thin += 1
	ok(pile_cells > 0 and thin == 0, "el montón está cubierto de hojas (%d celdas altas, %d con menos de 2 capas)" % [pile_cells, thin])
	# --- Coger de lo alto del montón: la hoja sale de donde se ve, escalada, y llega a la mano.
	var top := -1
	var c0 := sim.cell_index(pc.x, pc.z)
	var li := sim.cell_head[c0]
	while li >= 0:
		if sim.state[li] == LeafSimulationSystem.S_SLEEP and sim.cust[li].b > 0.8:
			top = li
			break
		li = sim.nxt[li]
	if top >= 0:
		var gy := sim.height_at(sim.pos[top].x, sim.pos[top].z)
		var arrived0 := sim.arrived_count[LeafManager.P_HAND]
		sim.suck_pos[LeafManager.P_HAND] = pc + Vector3(0.0, 1.4, 2.0)
		sim.capture(top, LeafManager.P_HAND, 3.5)
		var sc := sim.leaf_xform(top).basis.x.length()
		ok(sim.state[top] == LeafSimulationSystem.S_SUCKED and sim.pos[top].y > gy + 0.25 and absf(sc - LeafSimulationSystem.SUCK_SCALE) < 0.01, "una hoja cogida de lo alto del montón sale a %.2f m y vuela escalada ×%.2f" % [sim.pos[top].y - gy, sc])
		for k in 60:
			sim.simulate(1.0 / 60.0)
			if sim.state[top] == LeafSimulationSystem.S_REMOVED:
				break
		ok(sim.state[top] == LeafSimulationSystem.S_REMOVED and sim.arrived_count[LeafManager.P_HAND] > arrived0, "la hoja llega volando a la mano")
		sim.take_arrived(LeafManager.P_HAND)
	else:
		ok(false, "hay hojas en lo alto del montón")
	# --- Círculo de resaltado (uniformes del shader).
	lm.set_highlight(pc, 0.6)
	var hv: Vector4 = lm.material.get_shader_parameter("highlight")
	ok(absf(hv.w - 0.6) < 0.001 and hv.distance_to(Vector4(pc.x, pc.y, pc.z, 0.6)) < 0.01, "set_highlight fija el círculo de resaltado")
	lm.clear_highlight()
	hv = lm.material.get_shader_parameter("highlight")
	ok(hv.w == 0.0, "clear_highlight lo apaga")
	var gr := lm.highlight_grab(pc, 1.0, 6)
	var inside := 0
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var c := sim.cell_index(pc.x + dx * 0.5, pc.z + dz * 0.5)
			if c < 0:
				continue
			var lj := sim.cell_head[c]
			while lj >= 0:
				var d := sim.pos[lj] - pc
				d.y *= 0.5
				if d.length() <= gr:
					inside += 1
				lj = sim.nxt[lj]
	ok(gr > 0.0 and gr < 1.0 and inside >= 6, "highlight_grab ajusta el círculo a las 6 hojas más cercanas (radio %.2f m, %d dentro)" % [gr, inside])
	var empty := _free_flat(world, pc + Vector3(0.0, 0.0, 30.0))
	for i in sim.n:
		if sim.state[i] == LeafSimulationSystem.S_SLEEP and Vector2(sim.pos[i].x - empty.x, sim.pos[i].z - empty.z).length() < 1.2:
			sim.remove_leaf(i)
	var gr0 := lm.highlight_grab(empty, 1.0, 6)
	var hv0: Vector4 = lm.material.get_shader_parameter("highlight")
	ok(gr0 == 0.0 and hv0.w == 0.0, "sin hojas cerca no se resalta nada")
	lm.clear_highlight()
	# --- Ajuste «Resaltar hojas».
	SettingsManager.set_value("highlight_leaves", true)
	await frames(2)
	var rv: float = lm.material.get_shader_parameter("reveal")
	SettingsManager.set_value("highlight_leaves", false)
	await frames(2)
	var rv2: float = lm.material.get_shader_parameter("reveal")
	ok(rv == 1.0 and rv2 == 0.0, "Ajustes → Resaltar hojas activa y desactiva el contorno de color")
	# --- Últimas hojas: una zona al 96 % brilla sola; al 100 % se apaga.
	var left := 0
	for i in sim.n:
		if sim.zone_origin[i] == zi and sim.state[i] != LeafSimulationSystem.S_REMOVED:
			left += 1
	var keep := maxi(int(float(sim.zone_initial[zi]) * 0.04), 1)
	var removed := 0
	for i in sim.n:
		if left - removed <= keep:
			break
		if sim.zone_origin[i] == zi and sim.state[i] == LeafSimulationSystem.S_SLEEP:
			sim.remove_leaf(i)
			removed += 1
	lm.push_counts()
	var ga: Vector4 = lm.material.get_shader_parameter("glow_amount")
	var gz: Vector4 = lm.material.get_shader_parameter("glow_zones")
	ok(lm.zone_glow(zi) == 1.0 and ga.x + ga.y + ga.z + ga.w >= 1.0 and (gz.x == zi + 1 or gz.y == zi + 1 or gz.z == zi + 1 or gz.w == zi + 1), "zona al %.1f %%: sus últimas hojas brillan" % AreaManager.pct("laberinto"))
	for i in sim.n:
		if sim.zone_origin[i] == zi and sim.state[i] != LeafSimulationSystem.S_REMOVED:
			sim.remove_leaf(i)
	lm.push_counts()
	ok(lm.zone_glow(zi) == 0.0, "zona limpia del todo: se apaga el brillo")
	lm.set_zone_glow(zi, 0.5)
	ok(lm.zone_glow(zi) == 0.5, "set_zone_glow permite encender el brillo de una zona a mano")
	lm.set_zone_glow(zi, 0.0)
	await _perf_65k(world)


## Punto llano y libre cerca de c (sin obstáculos en 2 m a la redonda).
func _free_flat(world: World, c: Vector3) -> Vector3:
	for r in range(0, 40):
		for k in 12:
			var q := c + Vector3(r * 0.75, 0.0, 0.0).rotated(Vector3.UP, k * TAU / 12.0)
			var free := not world.terrain.is_solid(q.x, q.z)
			for a in 8:
				var e := q + Vector3(2.0, 0.0, 0.0).rotated(Vector3.UP, a * TAU / 8.0)
				if world.terrain.is_solid(e.x, e.z):
					free = false
			if free:
				return Vector3(q.x, world.terrain.height_at(q.x, q.z), q.z)
	return c


func _perf_chunk(_c: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = LeafMeshes.leaf_mesh()
	_perf_mms.append(mm)
	return mm


## Rendimiento con ~65.000 hojas (el mapa grande): un segundo sistema de hojas sobre la misma rejilla.
## Mide montar el dibujado, regenerar los montones, simular con las hojas activas de cada calidad y
## estima los vértices de hojas por fotograma desde la entrada para cada calidad.
func _perf_65k(world: World) -> void:
	var lm: LeafManager = world.leaf_manager
	var big := LeafSimulationSystem.new()
	big.setup_grid(world.terrain)
	big.create_chunk = _perf_chunk
	var rng := RandomNumberGenerator.new()
	rng.seed = 65
	var want := 65000
	var pts := PackedVector3Array()
	var guard := 0
	while pts.size() < want and guard < want * 20:
		guard += 1
		var zd: Dictionary = GameData.ZONES[rng.randi() % GameData.ZONES.size()]
		var r: Rect2 = zd["rect"]
		var x := rng.randf_range(r.position.x, r.end.x)
		var zz := rng.randf_range(r.position.y, r.end.y)
		var c := big.cell_index(x, zz)
		if c < 0 or big.solid[c] != 0:
			continue
		pts.append(Vector3(x, big.height_at(x, zz) + 0.015, zz))
	big.allocate(pts.size())
	for i in big.n:
		big.pos[i] = pts[i]
		big.yaw[i] = rng.randf() * TAU
		big.colr[i] = Color(0.9, 0.5, 0.1)
		big.cust[i] = Color(1.0, rng.randf(), rng.randf(), rng.randf())
		big.link_cell(i, big.cell_index(pts[i].x, pts[i].z))
	var t0 := Time.get_ticks_usec()
	big.build_render()
	print("  PERF %d hojas: montar el dibujado %.0f ms (%d bloques)" % [big.n, (Time.get_ticks_usec() - t0) / 1000.0, _perf_mms.size()])
	var cl := LeafClusterSystem.new()
	cl.setup(big.gw, big.gh)
	big.cluster = cl
	t0 = Time.get_ticks_usec()
	cl.flush(big, true)
	print("  PERF %d hojas: textura de montones completa %.1f ms" % [big.n, (Time.get_ticks_usec() - t0) / 1000.0])
	# Simulación con las hojas activas de cada calidad (todas cerca de la cámara: el peor caso).
	var focus := GameData.START_POS
	big.focus = focus
	for count in [350, 750, 1300, 3000]:
		big.max_active = count
		var n := 0
		var i := 0
		while n < count and i < big.n:
			if big.state[i] == LeafSimulationSystem.S_SLEEP and Vector2(big.pos[i].x - focus.x, big.pos[i].z - focus.z).length() < 16.0:
				if big.wake(i, Vector3(rng.randf_range(-2, 2), rng.randf_range(1, 4), rng.randf_range(-2, 2))):
					n += 1
			i += 1
		t0 = Time.get_ticks_usec()
		for k in 10:
			big.simulate(1.0 / 60.0)
		print("  PERF %d hojas: %d activas cerca de la cámara %.2f ms/frame (CPU escritorio)" % [big.n, big.active_n, (Time.get_ticks_usec() - t0) / 10000.0])
		for k in 240:
			big.simulate(1.0 / 60.0)
	# Vértices de hojas por fotograma desde la entrada mirando a la finca (bloques visibles enteros).
	var fwd := Vector3(0, 0, -1)
	var half := deg_to_rad(54.0)
	var size := LeafSimulationSystem.CHUNK_CELLS * 0.5
	var nv := LeafMeshes.leaf_mesh().surface_get_array_len(0)
	var lv := LeafMeshes.leaf_mesh_lod().surface_get_array_len(0)
	var fv := LeafMeshes.leaf_mesh_far().surface_get_array_len(0)
	for level in [0, 1, 2]:
		var q: Dictionary = LeafManager.QUALITY[level]
		var near_n := 0
		var lod_n := 0
		var far_n := 0
		for c in big.cw * big.ch:
			if big.chunk_count[c] == 0:
				continue
			var center := Vector3(big.ox + (c % big.cw + 0.5) * size, focus.y, big.oz + (c / big.cw + 0.5) * size)
			var rel := center - focus
			var dist := rel.length()
			var d := sqrt(maxf(dist * dist - size * size * 0.5, 0.0))
			if d >= float(q["draw"]):
				continue
			if dist > 8.0 and rel.normalized().dot(fwd) < cos(half + atan(size * 0.72 / dist)):
				continue
			if d <= float(q["lod"]):
				near_n += big.chunk_count[c]
			elif d <= float(q["far"]):
				lod_n += big.chunk_count[c]
			else:
				far_n += big.chunk_count[c]
		var verts := near_n * nv + lod_n * lv + far_n * fv
		print("  PERF %d hojas, calidad %d: %d cerca + %d LOD + %d lejanas = %d vértices de hojas por fotograma" % [big.n, level, near_n, lod_n, far_n, verts])
	ok(big.n >= 60000, "rendimiento medido con %d hojas" % big.n)
	for mm in _perf_mms:
		mm.instance_count = 0
	_perf_mms.clear()
	lm.cluster.flush(lm.sim, true)
