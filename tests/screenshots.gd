extends Node
## Capturas automáticas para QA visual (requiere renderizado real: xvfb-run + opengl3).
## Uso: xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 res://tests/screenshots.tscn

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
	var only := OS.get_environment("SHOTS")
	SaveManager.delete_slot("campaign")
	GameManager.requested_new = true
	GameManager.skip_menu = only != "menu" and only != ""
	if only == "":
		GameManager.skip_menu = false
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await frames(10)
	while GameManager.world == null:
		await frames(1)
	var world: World = GameManager.world
	await frames(90)
	if not GameManager.in_game:
		await shot("01_menu")
		main.ui.start_game()
		await frames(30)
	var p: PlayerController = world.player
	SettingsManager.set_value("graphics", "high")
	p.teleport(GameData.START_POS, 0.0)
	p.cam.pitch = -0.08
	await frames(60)
	await shot("02_inicio")
	p.cam.pitch = -0.75
	await frames(20)
	await shot("03_hojas_cerca")
	# Rastrillo creando un montón.
	UpgradeManager.levels["tool_rake"] = 1
	UpgradeManager.levels["rake_width"] = 3
	UpgradeManager.levels["rake_capacity"] = 4
	p.tools.select("rake")
	p.teleport(Vector3(-15, 0.3, 61), 0.0)
	p.cam.pitch = -0.35
	InputState.action_held = true
	InputState.move = Vector2(0, 1)
	await frames(200)
	InputState.move = Vector2.ZERO
	await frames(40)
	await shot("04_rastrillo")
	InputState.action_held = false
	p.teleport(p.global_position + Vector3(2.5, 0, 1.5), 0.9)
	p.cam.pitch = -0.4
	await frames(30)
	await shot("05_monton")
	# Soplador.
	UpgradeManager.levels["tool_blower"] = 2
	UpgradeManager.levels["blower_power"] = 3
	p.tools.select("blower")
	p.teleport(Vector3(12, 0.3, 58), PI * 0.6)
	p.cam.pitch = -0.2
	InputState.action_held = true
	await frames(45)
	await shot("06_soplador")
	InputState.action_held = false
	# Vista desde la casa y la piscina (zonas desbloqueadas para ver el mapa).
	p.tools.select("hand")
	p.teleport(Vector3(0, 0.5, 6), 0.0)
	p.cam.pitch = 0.05
	await frames(40)
	await shot("07_casa")
	p.teleport(Vector3(29, 0.5, 2), -2.3)
	p.cam.pitch = -0.25
	await frames(40)
	await shot("08_piscina")
	# Vista aérea.
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.global_position = Vector3(0, 95, 75)
	cam.look_at(Vector3(0, 0, -5))
	cam.far = 500
	cam.make_current()
	await frames(20)
	await shot("09_aerea")
	p.cam.camera.make_current()
	# Diario y tienda.
	main.ui.open_journal("map")
	await frames(20)
	await shot("10_diario_mapa")
	main.ui.close_top()
	main.ui.open_journal("shop", "Taller de Brizna")
	await frames(20)
	await shot("11_tienda")
	main.ui.close_top()
	await frames(5)
	print("fps (render real en CPU): ", Engine.get_frames_per_second())
	get_tree().quit()
