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
var sky_mat: ProceduralSkyMaterial
var menu_cam: Camera3D
var falling: CPUParticles3D
var rain: CPUParticles3D
var gates := {}
var ducts: Array[SuctionDuct] = []
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
	_zone_clean.resize(12)
	for zid in AreaManager.completed:
		_restore_zone(zid, false)
	_update_zone_clean(true)
	_setup_menu_camera()
	_setup_particles()
	EventBus.gate_opened.connect(_on_gate_opened)
	EventBus.zone_completed.connect(func(z): _restore_zone(z, true))
	EventBus.zone_unlocked.connect(func(_z): _refresh_auto_gates())
	SaveManager.register("world", self)
	GameManager.requested_new = false


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
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.55, 0.78)
	sky_mat.sky_horizon_color = Color(0.95, 0.8, 0.62)
	sky_mat.ground_horizon_color = Color(0.7, 0.6, 0.45)
	sky_mat.ground_bottom_color = Color(0.3, 0.25, 0.18)
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.92, 0.78, 0.6)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.25
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.88, 0.7)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 42.0
	sun.shadow_blur = 1.5
	add_child(sun)
	PerformanceManager.quality_changed.connect(_apply_quality)
	_apply_quality(PerformanceManager.level)
	_update_light(true)


func _apply_quality(level: int) -> void:
	var p: Dictionary = PerformanceManager.PRESETS[level]
	sun.shadow_enabled = p["shadows"]
	get_viewport().scaling_3d_scale = float(p["scale"])
	if falling:
		falling.amount = int(60 * float(p["particles"]))


func _noise_tex() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	var img := noise.get_seamless_image(256, 256)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _update_light(force: bool = false) -> void:
	# Mañana dorada → tarde clara → atardecer rosado, y vuelta a empezar.
	var keys := [
		[0.0, 18.0, Color(1.0, 0.8, 0.6), Color(0.45, 0.6, 0.8), Color(1.0, 0.78, 0.6), 0.95],
		[0.33, 52.0, Color(1.0, 0.95, 0.85), Color(0.36, 0.56, 0.82), Color(0.92, 0.85, 0.72), 1.2],
		[0.7, 26.0, Color(1.0, 0.82, 0.62), Color(0.42, 0.52, 0.75), Color(1.0, 0.72, 0.5), 1.05],
		[0.92, 9.0, Color(1.0, 0.55, 0.38), Color(0.4, 0.4, 0.6), Color(1.0, 0.55, 0.45), 0.8],
		[1.0, 18.0, Color(1.0, 0.8, 0.6), Color(0.45, 0.6, 0.8), Color(1.0, 0.78, 0.6), 0.95],
	]
	var a: Array = keys[0]
	var b: Array = keys[1]
	for k in keys.size() - 1:
		if day_t >= float(keys[k][0]) and day_t <= float(keys[k + 1][0]):
			a = keys[k]
			b = keys[k + 1]
			break
	var t := inverse_lerp(float(a[0]), float(b[0]), day_t)
	var elev := deg_to_rad(lerpf(a[1], b[1], t))
	var az := deg_to_rad(-35.0 + day_t * 120.0)
	sun.rotation = Vector3(-elev, az, 0.0)
	sun.light_color = (a[2] as Color).lerp(b[2], t)
	sun.light_energy = lerpf(a[5], b[5], t)
	sky_mat.sky_top_color = (a[3] as Color).lerp(b[3], t)
	sky_mat.sky_horizon_color = (a[4] as Color).lerp(b[4], t)
	env.fog_light_color = sky_mat.sky_horizon_color.lerp(Color(0.9, 0.8, 0.65), 0.4)


func _setup_particles() -> void:
	falling = CPUParticles3D.new()
	falling.amount = int(60 * float(PerformanceManager.preset()["particles"]))
	falling.lifetime = 9.0
	falling.preprocess = 9.0
	falling.local_coords = false
	falling.mesh = MeshFactory.leaf_mesh_lod()
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	falling.material_override = fm
	falling.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	falling.emission_box_extents = Vector3(18, 1, 18)
	falling.direction = Vector3(0.3, -1, 0.1)
	falling.spread = 25.0
	falling.gravity = Vector3(0.4, -0.6, 0.2)
	falling.initial_velocity_min = 0.3
	falling.initial_velocity_max = 0.8
	falling.angular_velocity_min = -120.0
	falling.angular_velocity_max = 120.0
	falling.scale_amount_min = 0.8
	falling.scale_amount_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(0.95, 0.55, 0.15))
	grad.set_color(1, Color(0.85, 0.3, 0.1))
	grad.add_point(0.5, Color(0.98, 0.78, 0.2))
	falling.color_initial_ramp = grad
	falling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(falling)
	rain = CPUParticles3D.new()
	rain.amount = 160
	rain.lifetime = 1.0
	rain.local_coords = false
	rain.mesh = MeshFactory.box(Vector3(0.01, 0.35, 0.01))
	rain.material_override = MeshFactory.mat(Color(0.75, 0.82, 0.9), 0.2, 0.3)
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(14, 1, 14)
	rain.direction = Vector3(0, -1, 0)
	rain.spread = 3.0
	rain.gravity = Vector3(0, -20, 0)
	rain.initial_velocity_min = 8.0
	rain.initial_velocity_max = 10.0
	rain.emitting = false
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)


func _setup_menu_camera() -> void:
	menu_cam = Camera3D.new()
	menu_cam.fov = 60.0
	menu_cam.far = 420.0
	add_child(menu_cam)


func set_menu_mode(on: bool) -> void:
	menu_mode = on
	if on:
		menu_cam.make_current()
	else:
		player.cam.camera.make_current()


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
	var focus := menu_cam.global_position if menu_mode else player.global_position
	falling.global_position = focus + Vector3(0, 9, 0)
	rain.global_position = focus + Vector3(0, 10, 0)
	if menu_mode:
		_menu_t += delta
		var a := _menu_t * 0.04
		menu_cam.global_position = Vector3(sin(a) * 9.0 + 4.0, 3.2 + sin(_menu_t * 0.2) * 0.4, 42.0 + cos(a) * 5.0)
		menu_cam.look_at(Vector3(0, 3.0, 8.0))
		return
	_gust_t -= delta
	if _gust_t <= 0.0:
		_gust_t = randf_range(25.0, 55.0)
		var center := player.global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		var n := leaf_manager.sim.kick(center, 4.0, wind.normalized() * 2.2, 1.2, 25)
		if n > 0:
			AudioManager.play_sfx("gust", Vector3.INF, -8.0)
	# Llovizna ligera tras completar la campaña.
	if ProgressManager.has_flag("campaign_done"):
		rain.emitting = day_t > 0.75 and day_t < 0.85
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
