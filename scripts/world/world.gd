class_name World
extends Node3D
## Ensambla la finca: entorno, terreno, decorado, hojas, puertas, conductos, coleccionables y jugador.
## Gestiona además el ciclo de luz, el viento, la restauración visual de zonas y el contrarreloj.

const DAY_LENGTH := 1080.0   # segundos por ciclo mañana → tarde → atardecer

var terrain: Terrain
var builder: WorldBuilder
var leaf_manager: LeafManager
var player: PlayerController
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var menu_cam: Camera3D
var falling: CPUParticles3D
var rain: CPUParticles3D
var atmosphere: Atmosphere
var gates := {}
var ducts: Array[SuctionDuct] = []
var robot: RobotSweeper
var menu_mode := false
var day_t := 0.12
var _menu_t := 0.0
var _zone_clean := PackedFloat32Array()
var _clean_timer := 0.0
var _wind_t := 0.0
var _gust_t := 20.0
var _ta_time := 0.0
var _ta_done := false
var _light_timer := 0.0


func _ready() -> void:
	GameManager.world = self
	var ta := GameManager.is_time_attack()
	if GameManager.requested_new or ta:
		GameManager.reset_managers()
		SaveManager.clear_loaded()
	elif not SaveManager.load_game():
		GameManager.reset_managers()
		GameManager.requested_new = true
	_build_environment()
	terrain = Terrain.new()
	add_child(terrain)
	terrain.setup()
	builder = WorldBuilder.new()
	builder.build(self, terrain)
	_setup_gates()
	leaf_manager = LeafManager.new()
	add_child(leaf_manager)
	var saved := PackedByteArray()
	if not GameManager.requested_new and not ta:
		saved = SaveManager.load_leaf_state()
	leaf_manager.setup(terrain, builder.density_points, saved, GameManager.time_attack_zone if ta else "")
	terrain.build(leaf_manager.cluster.tex, _noise_tex())
	for s in builder.stations:
		s.leaf_manager = leaf_manager
	_setup_ducts()
	_setup_postcards()
	player = PlayerController.new()
	add_child(player)
	player.setup(leaf_manager)
	if ta:
		var r: Rect2 = GameData.zone_by_id(GameManager.time_attack_zone)["rect"]
		var spawn := _free_spot(r.get_center())
		player.teleport(Vector3(spawn.x, terrain.height_at(spawn.x, spawn.y) + 0.2, spawn.y), 0.0)
	elif not GameManager.player_state.is_empty():
		player.apply_state(GameManager.player_state)
	else:
		player.teleport(GameData.START_POS, 0.0)
	robot = RobotSweeper.new()
	add_child(robot)
	robot.setup(leaf_manager, player)
	_zone_clean.resize(12)
	for zid in AreaManager.completed:
		_restore_zone(zid, false)
	_update_zone_clean(true)
	_setup_menu_camera()
	_setup_particles()
	EventBus.gate_opened.connect(_on_gate_opened)
	EventBus.zone_completed.connect(func(z): _restore_zone(z, true))
	EventBus.zone_unlocked.connect(func(_z): _refresh_auto_gates())
	_setup_visual_extras()
	_setup_gameplay_extras()
	SaveManager.register("world", self)
	GameManager.requested_new = false


## Punto de enganche para sistemas visuales adicionales (césped, decoración dinámica...).
func _setup_visual_extras() -> void:
	# Césped real alrededor de la cámara: oculto bajo la hojarasca, aparece al limpiar.
	var grass := GrassField.new()
	add_child(grass)
	grass.setup(terrain, leaf_manager)


## Punto de enganche para sistemas de juego adicionales (compañero, guías...).
func _setup_gameplay_extras() -> void:
	# Bellota, la perrita compañera (no en Contrarreloj: desordenaría los montones cronometrados).
	# Las guías del HUD (contenedor, puertas, mejoras) las crea el propio HUD.
	if GameManager.is_time_attack():
		return
	var dog := Companion.new()
	dog.name = "Bellota"
	add_child(dog)
	dog.setup(self, leaf_manager, player)


func _exit_tree() -> void:
	if GameManager.world == self:
		GameManager.world = null


func get_player_state() -> Dictionary:
	return player.get_state() if player else {}


func to_save() -> Dictionary:
	return {"day": day_t}


func from_save(d: Dictionary) -> void:
	day_t = float(d.get("day", day_t))


# ------------------------------------------------------------------ entorno

func _build_environment() -> void:
	# Cielo, sol, niebla, etalonado y viñeta viven en Atmosphere (scripts/world/atmosphere.gd).
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.build()
	env = atmosphere.env
	sun = atmosphere.sun
	sky_mat = atmosphere.sky_mat
	PerformanceManager.quality_changed.connect(_apply_quality)
	_apply_quality(PerformanceManager.level)
	_update_light(true)


func _apply_quality(level: int) -> void:
	atmosphere.apply_quality(level)


func _noise_tex() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	var img := noise.get_seamless_image(256, 256)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _update_light(_force: bool = false) -> void:
	# Amanecer → mañana dorada → mediodía claro → tarde → atardecer → crepúsculo breve, y vuelta a empezar.
	# El menú principal usa siempre la luz dorada de media tarde.
	atmosphere.update_light(Atmosphere.MENU_DAY if menu_mode else day_t)


func _setup_particles() -> void:
	atmosphere.build_particles()
	falling = atmosphere.falling
	rain = atmosphere.rain


func _setup_menu_camera() -> void:
	menu_cam = Camera3D.new()
	menu_cam.fov = 50.0
	menu_cam.near = 0.1
	menu_cam.far = 420.0
	add_child(menu_cam)
	_place_menu_cam()


func set_menu_mode(on: bool) -> void:
	menu_mode = on
	if on:
		_place_menu_cam()
		menu_cam.make_current()
	else:
		player.cam.camera.make_current()
	_update_light(true)


## Plano lento desde el jardín delantero: setos y valla en primer término, la fuente y la casa al fondo
## (a la derecha, porque el menú ocupa la izquierda), bajo la luz dorada de la tarde. Va y vuelve sin cortes.
func _place_menu_cam() -> void:
	var s := sin(_menu_t * 0.04)
	var pos := Vector3(-9.0 + s * 2.0, 4.3 + sin(_menu_t * 0.1) * 0.2, 23.5 - s * 1.0)
	menu_cam.global_position = pos
	menu_cam.look_at(Vector3(-8.5 + s * 1.6, 3.3, -14.0))


# ------------------------------------------------------------------ puertas, conductos, postales

func _setup_gates() -> void:
	for g in GameData.GATES:
		var gd := GateDoor.new()
		gd.position = Vector3(g["pos"].x, terrain.height_at(g["pos"].x, g["pos"].y), g["pos"].y)
		add_child(gd)
		gd.setup(g)
		gates[g["id"]] = gd
		if AreaManager.gates_open.get(g["id"], false):
			gd.open_visual(false)
		else:
			_gate_solid(g, 1)


func _gate_solid(g: Dictionary, value: int) -> void:
	var half := Vector2(1.7, 0.3) if g["axis"] == "x" else Vector2(0.3, 1.7)
	terrain.add_solid_box(g["pos"], half, 0.0, value)


func _on_gate_opened(gate_id: String) -> void:
	var gd: GateDoor = gates.get(gate_id)
	if gd == null:
		return
	gd.open_visual(true)
	_gate_solid(gd.gate, 0)
	leaf_manager.refresh_solid()


func _refresh_auto_gates() -> void:
	for id in gates:
		if AreaManager.gates_open.get(id, false) and not gates[id].opened:
			_on_gate_opened(id)


func _setup_ducts() -> void:
	for k in GameData.DUCTS.size():
		var d: Dictionary = GameData.DUCTS[k]
		var duct := SuctionDuct.new()
		duct.position = Vector3(d["pos"].x, terrain.height_at(d["pos"].x, d["pos"].y), d["pos"].y)
		add_child(duct)
		duct.setup(d, k, leaf_manager)
		ducts.append(duct)


func _setup_postcards() -> void:
	for p in GameData.POSTCARDS:
		if CollectibleManager.is_found(p["id"]):
			continue
		var pos := Vector3(p["pos"].x, terrain.height_at(p["pos"].x, p["pos"].y), p["pos"].y)
		var s := StationObject.new()
		s.position = pos
		s.collision_layer = Interactable.LAYER_INTERACT
		Interactable.make_shape(s, Vector3(0.9, 0.5, 0.9), Vector3(0, 0.25, 0))
		s.setup(StationObject.Kind.POSTCARD, p)
		s.leaf_manager = leaf_manager
		var card := MeshInstance3D.new()
		card.mesh = MeshFactory.box(Vector3(0.32, 0.01, 0.22))
		card.material_override = MeshFactory.mat(Color(0.98, 0.95, 0.85))
		card.position.y = 0.02
		card.rotation.y = randf() * TAU
		s.add_child(card)
		var stamp := MeshInstance3D.new()
		stamp.mesh = MeshFactory.box(Vector3(0.06, 0.012, 0.07))
		stamp.material_override = MeshFactory.mat(Color(0.8, 0.25, 0.2))
		stamp.position = Vector3(0.1, 0.006, -0.05)
		card.add_child(stamp)
		add_child(s)


func _free_spot(c: Vector2) -> Vector2:
	for r in range(0, 40):
		for k in 12:
			var p := c + Vector2(r * 0.5, 0).rotated(k * TAU / 12.0)
			if not terrain.is_solid(p.x, p.y) and not terrain.is_solid(p.x + 0.5, p.y) and not terrain.is_solid(p.x, p.y + 0.5):
				return p
	return c


# ------------------------------------------------------------------ restauración

func _restore_zone(zid: String, animated: bool) -> void:
	var r: Node3D = builder.restore_nodes.get(zid)
	var d: Node3D = builder.debris_nodes.get(zid)
	if r:
		r.visible = true
		if animated:
			r.scale = Vector3(1, 0.01, 1)
			create_tween().tween_property(r, "scale", Vector3.ONE, 1.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if d:
		if animated:
			var tw := create_tween()
			tw.tween_property(d, "scale", Vector3(1, 0.01, 1), 0.8)
			tw.tween_callback(func(): d.visible = false)
		else:
			d.visible = false
	if animated:
		AudioManager.play_ui("restore")
		HapticManager.pulse(120, 0.8)
		EventBus.toast.emit("¡Zona restaurada!", GameData.zone_by_id(zid)["name"] + " vuelve a lucir como antes.", "reward")
		if AreaManager.completed_main_count() >= 10:
			ProgressManager.set_flag("campaign_done")


func _update_zone_clean(immediate: bool) -> void:
	for i in GameData.ZONES.size():
		var target := AreaManager.pct(GameData.ZONES[i]["id"]) / 100.0
		target = clampf((target - 0.3) / 0.7, 0.0, 1.0)
		_zone_clean[i] = target if immediate else lerpf(_zone_clean[i], target, 0.25)
	terrain.set_zone_clean(_zone_clean)


func reset_zone(zid: String) -> void:
	leaf_manager.reset_zone(GameData.zone_index(zid))
	EventBus.toast.emit("Zona reiniciada", GameData.zone_by_id(zid)["name"], "reward")


# ------------------------------------------------------------------ bucle

func _process(delta: float) -> void:
	day_t = fposmod(day_t + delta / DAY_LENGTH, 1.0)
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.5
		_update_light()
	_clean_timer -= delta
	if _clean_timer <= 0.0:
		_clean_timer = 0.5
		_update_zone_clean(false)
	# Viento ambiental suave y ráfagas ocasionales que mueven unas pocas hojas.
	_wind_t += delta
	var wind := Vector3(sin(_wind_t * 0.05) * 0.6 + 0.3, 0.0, cos(_wind_t * 0.037) * 0.5)
	leaf_manager.sim.ambient_wind = wind
	atmosphere.update_wind(wind, delta)
	if menu_mode:
		_menu_t += delta
		_place_menu_cam()
		atmosphere.follow(menu_cam.global_position, delta)
		return
	atmosphere.follow(player.global_position, delta)
	_gust_t -= delta
	if _gust_t <= 0.0:
		_gust_t = randf_range(25.0, 55.0)
		# Por delante de quien juega, para que vea el remolino que levanta.
		var fwd := player.cam.forward()
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
		var center := player.global_position + fwd * randf_range(3.0, 8.0) + fwd.cross(Vector3.UP) * randf_range(-4.0, 4.0)
		var n := leaf_manager.sim.kick(center, 4.0, wind.normalized() * 2.2, 1.2, 25)
		if n > 0:
			AudioManager.play_sfx("gust", Vector3.INF, -8.0)
			atmosphere.gust(Vector3(center.x, terrain.height_at(center.x, center.z), center.z))
	# Llovizna ligera tras completar la campaña.
	if ProgressManager.has_flag("campaign_done"):
		atmosphere.set_rain(day_t > 0.75 and day_t < 0.85)
	if GameManager.is_time_attack() and not _ta_done and GameManager.in_game:
		_ta_time += delta
		var zid := GameManager.time_attack_zone
		if int(AreaManager.remaining.get(zid, 1)) <= 0:
			_ta_done = true
			var ui: UIManager = get_parent().ui if get_parent().get("ui") else null
			if ui:
				ui.time_attack_finished(zid, _ta_time)


func time_attack_seconds() -> float:
	return _ta_time
