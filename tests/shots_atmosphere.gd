extends Node
## Capturas de QA de atmósfera/iluminación: menú, mañana, mediodía, tarde, atardecer y cielo.
## Uso: TAG=antes xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 res://tests/shots_atmosphere.tscn

var out_dir := "user://shots"
var tag := "x"
var main: Node
var world: World


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/atm_" + tag + "_" + shot_name + ".png")
	print("captura: ", shot_name)


func measure(label: String) -> void:
	await frames(25)
	var t0 := Time.get_ticks_usec()
	await frames(50)
	var ms := (Time.get_ticks_usec() - t0) / 50000.0
	print("PERFATM %-28s %.1f ms/frame" % [label, ms])


## Coste relativo de cada efecto (render por CPU: solo sirve para comparar entre sí).
func perf(p: PlayerController) -> void:
	set_day(0.3)
	p.teleport(GameData.START_POS, 0.0)
	p.cam.pitch = 0.0
	var atm: Atmosphere = world.atmosphere
	var env: Environment = world.env
	await measure("alto")
	await measure("alto (2)")
	SettingsManager.set_value("graphics", "medium")
	await frames(5)
	await measure("preset MEDIO")
	SettingsManager.set_value("graphics", "low")
	await frames(5)
	await measure("preset BAJO")
	SettingsManager.set_value("graphics", "high")
	await frames(5)
	await measure("alto (3)")
	env.adjustment_enabled = false
	await measure("alto sin ajustes")
	atm.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	await measure("+ sombra ortogonal")
	atm.sky_mat.set_shader_parameter("cloud_alpha", 0.0)
	await measure("+ sin nubes")
	atm.vignette.visible = false
	atm.dust.visible = false
	atm.falling.visible = false
	await measure("+ sin vineta/polvo/hojas")


## Llovizna tras completar la campaña: el cielo se encapota poco a poco.
func rain_shot(p: PlayerController) -> void:
	ProgressManager.set_flag("campaign_done")
	set_day(0.79)
	p.teleport(Vector3(-3, 0.5, 8), 0.25)
	p.cam.pitch = 0.1
	await frames(140)
	await shot("13_llovizna")
	SettingsManager.set_value("graphics", "low")
	set_day(0.6)
	await frames(60)
	await shot("14_bajo_tarde")


func set_day(t: float) -> void:
	world.day_t = t
	world._update_light(true)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var e := OS.get_environment("TAG")
	if e != "":
		tag = e
	SaveManager.delete_slot("campaign")
	SettingsManager.set_value("graphics", "high")
	GameManager.requested_new = true
	GameManager.skip_menu = false
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await frames(10)
	while GameManager.world == null:
		await frames(1)
	world = GameManager.world
	var perf_mode := OS.get_environment("PERF") != ""
	await frames(150)
	if not perf_mode:
		await shot("01_menu")
		await frames(120)
		await shot("01b_menu_luego")
	main.ui.start_game()
	await frames(30)
	var p: PlayerController = world.player
	if perf_mode:
		await perf(p)
		get_tree().quit()
		return
	if OS.get_environment("ONLY") == "lluvia":
		await rain_shot(p)
		get_tree().quit()
		return
	set_day(0.1)
	p.teleport(GameData.START_POS, 0.0)
	p.cam.pitch = -0.08
	await frames(50)
	await shot("02_manana")
	p.cam.pitch = -0.7
	await frames(20)
	await shot("03_hojas_cerca")
	set_day(0.35)
	p.teleport(Vector3(-3, 0.5, 8), 0.25)
	p.cam.pitch = 0.08
	await frames(40)
	await shot("04_casa_mediodia")
	set_day(0.62)
	p.teleport(Vector3(29, 0.5, 2), -2.3)
	p.cam.pitch = -0.2
	await frames(40)
	await shot("05_piscina_tarde")
	set_day(0.88)
	p.teleport(Vector3(-8, 0.5, 30), -1.2)
	p.cam.pitch = 0.05
	await frames(40)
	await shot("06_atardecer")
	p.teleport(Vector3(-8, 0.5, 30), 1.9)
	p.cam.pitch = 0.3
	await frames(30)
	await shot("07_cielo_atardecer")
	set_day(0.45)
	p.teleport(Vector3(0, 0.5, 55), 3.0)
	p.cam.pitch = 0.25
	await frames(30)
	await shot("08_cielo_dia")
	# Remolino de hojas de una ráfaga, delante de la cámara.
	set_day(0.2)
	p.teleport(GameData.START_POS, 0.0)
	p.cam.pitch = -0.1
	await frames(20)
	world.atmosphere.gust(p.global_position + Vector3(0.5, 0.0, -5.0))
	await frames(22)
	await shot("09_remolino")
	# Crepúsculo: farolas encendidas y luciérnagas.
	set_day(0.958)
	p.teleport(Vector3(0, 0.5, 61), 0.0)
	p.cam.pitch = 0.02
	await frames(40)
	await shot("10_crepusculo")
	# Mismo encuadre de la casa con los niveles gráficos Medio y Bajo.
	set_day(0.35)
	p.teleport(Vector3(-3, 0.5, 8), 0.25)
	p.cam.pitch = 0.08
	SettingsManager.set_value("graphics", "medium")
	await frames(40)
	await shot("11_casa_medio")
	SettingsManager.set_value("graphics", "low")
	await frames(40)
	await shot("12_casa_bajo")
	SettingsManager.set_value("graphics", "high")
	if OS.get_environment("POSTTEST") != "":
		var env: Environment = world.env
		env.glow_enabled = false
		await frames(5)
		await shot("zz_sin_glow")
		env.adjustment_saturation = 0.0
		await frames(5)
		await shot("zz_sat0")
		env.adjustment_enabled = false
		env.glow_enabled = false
		await frames(5)
		await shot("zz_sin_post")
	print("fps (render real en CPU): ", Engine.get_frames_per_second())
	get_tree().quit()
