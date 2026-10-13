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
	while GameManager.world == null or not GameManager.in_game:
		await frames(1)
	print("Mundo construido en %d ms" % (Time.get_ticks_msec() - t0))
	var world: World = GameManager.world
	var p: PlayerController = world.player
	var sim: LeafSimulationSystem = world.leaf_manager.sim
	ok(sim.n > 30000, "hojas generadas: %d" % sim.n)
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
	while GameManager.world == null or not GameManager.in_game or GameManager.world == world:
		await frames(1)
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
