extends Node
## Bot de playtest (QA): juega la Campaña desde una partida NUEVA como lo haría una persona.
##
## Solo maneja el juego a través de InputState (joystick, arrastrar para mirar, botón de usar,
## botón de interactuar —tocar o mantener—, saltar y rueda de herramientas). Las mejoras se compran
## con UpgradeManager.buy(), que equivale a tocar el botón de la tienda del diario.
## Solo "ve" lo que vería un jugador: hojas a ~15 m (40 m si no hay nada cerca, la distancia de
## dibujado de las hojas es 46 m), contenedores, puertas, conductos y el texto de interacción del
## HUD (player.prompt). Navega con A* sobre una rejilla de 0,5 m sondeada con la física
## (los obstáculos que el jugador ve), igual que alguien que esquiva vallas y árboles.
##
## Registra una línea de tiempo, el estado de cada minuto, compras, errores/avisos del motor,
## atascos y métricas de ritmo; al final imprime un informe y lo guarda en user://playtest_report.json.
##
## Uso (headless, va más rápido que el tiempo real):
##   XDG_DATA_HOME=/tmp/vh_bot godot --headless --fixed-fps 60 res://tests/playtest_bot.tscn
## Variables de entorno:
##   BOT_MINUTES      minutos de juego (25 por defecto)
##   BOT_WALL_LIMIT   segundos reales máximos (1140 por defecto)
##   BOT_PROFILE      "casual": toques más lentos, giros lentos, pausas para pensar, sin lanzar ni correr
##   BOT_RAKE=0       no usa el rastrillo (comparación A/B del ritmo)
##   BOT_FINISH=zona  se queda en esa zona hasta dejarla al 100 % (mide lo pesado del final de zona)
##   BOT_THROW_EVERY  lanzar 1 de cada N bolsas al contenedor (3; 0 = siempre a mano)
##   BOT_SHOTS=1      capturas en momentos clave (solo con render real: xvfb-run + --rendering-driver opengl3)
##   BOT_DEBUG=1      traza de estados, toques vacíos y atascos

class BotLogger extends Logger:
	var mutex := Mutex.new()
	var lines: Array[String] = []
	var errors := 0
	var warnings := 0
	var stamp := "--:--"

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind := "ERROR"
		if error_type == 1:
			kind = "WARNING"
		elif error_type == 2:
			kind = "SCRIPT ERROR"
		elif error_type == 3:
			kind = "SHADER ERROR"
		var text := "[%s] %s: %s %s (%s:%d %s)" % [stamp, kind, code, rationale, file, line, function]
		mutex.lock()
		if error_type == 1:
			warnings += 1
		else:
			errors += 1
		if lines.size() < 300:
			lines.append(text)
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


enum St { BOOT, SEEK, GATHER, RAKE, CLOSE, DELIVER, THROW_WAIT, PICKUP, USE, END }
const ST_NAMES := ["BOOT", "SEEK", "GATHER", "RAKE", "CLOSE", "DELIVER", "THROW_WAIT", "PICKUP", "USE", "END"]

# Perfil "experto" (por defecto) y "casual" (BOT_PROFILE=casual): ritmo de toques, giro y pausas.
var TURN_RATE := 6.0          # rad/s: giro rápido pero humano arrastrando el pulgar
var PITCH_RATE := 4.0
var TAP_MIN := 0.3            # s entre toques (ritmo de toques sostenible de una persona)
var THINK := 0.0              # pausa tras cada cambio de tarea (mirar, decidir)
var WALK_MAX := 1.0           # 1.0 = joystick a tope (corre); 0.85 = camina
var profile := "experto"
var use_rake := true
const SIGHT := 15.0
const SIGHT_FAR := 40.0
const RAKE_LEN := 7.0
# Interés de cada mejora para un jugador "sensato" (se divide por el precio).
const WEIGHTS := {
	"hand": 3.0, "bag_capacity": 3.0, "tool_rake": 2.5, "bag_close": 1.3, "move_speed": 1.6,
	"interact_speed": 1.4, "leaf_value": 2.2, "rake_width": 1.2, "rake_capacity": 1.0,
	"rake_speed": 0.6, "rake_grip": 0.6, "rake_reach": 0.5, "stamina": 0.8, "sprint": 0.8,
	"bag_carry": 1.0, "bag_throw": 0.4, "tool_blower": 0.45, "tool_vacuum": 3.0,
	"vacuum_radius": 1.5, "vacuum_speed": 1.5, "vacuum_capacity": 1.0, "vacuum_power": 0.8,
}

var main: Node
var world: World
var p: PlayerController
var sim: LeafSimulationSystem
var terrain: Terrain
var logger: BotLogger
var gw := 0
var gh := 0
var astar := AStarGrid2D.new()
var learned := {}                 # celdas marcadas a mano como obstáculo tras un atasco
var state := St.BOOT
var state_t := 0.0
var game_t := 0.0
var limit_t := 1500.0
var wall0 := 0
var wall_limit := 1140.0
var throw_every := 3
# Entradas de este frame.
var mv := Vector2.ZERO
var look_on := false
var look_yaw := 0.0
var look_pitch := 0.0
var act_held := false
var act_press := false
var int_held := false
var int_press := false
var jump := false
var tool_sel := ""
# Ruta.
var path := PackedVector3Array()
var path_i := 0
var path_goal := Vector3.INF
# Objetivos de hojas.
var target := Vector3.INF
var target_key := -1
var blacklist := {}
var zone_ok := PackedByteArray()
var zone_w := PackedFloat32Array()
var zone_t := 0.0
var finish_start := {}
var finish_gave_up := {}
var relaxed := false
var explore_target := Vector3.INF
# Recogida con la mano.
var tap_cd := 0.0
var tap_pending := false
var tap_before := 0
var taps := 0
var empty_taps := 0
var tap_hist: Array[int] = []
var aim_point := Vector3.INF
var aim_t := 0.0
var aim_focus := Vector3.INF
var gather_idle_t := 0.0
# Bolsas.
var closing := false
var bin_target: RecycleBin
var bin_stand := Vector3.INF
var throw_plan := false
var delivered_flag := false
var deliveries := 0
var throws := 0
var throws_ok := 0
var bag_target: LeafBag
var close_pos := Vector3.ZERO
# Interacción con puertas / conductos.
var use_node: Node3D
var use_stand := Vector3.INF
var use_look := Vector3.INF
var use_prefix := ""
var use_kind := ""
var use_cd := 0.0
# Rastrillo.
var rake_P := Vector3.INF
var rake_dirs: Array[Vector3] = []
var rake_k := 0
var rake_sub := 0
var rake_sub_t := 0.0
var rake_blocked: Array[Vector2i] = []
var rake_cycles := 0
var rake_cd_until := 0.0
var pile_sizes: Array[int] = []
var in_rake_cycle := false
var rake_cycle_t0 := 0.0
var rake_cycle_l0 := 0
# Atascos.
var stuck_anchor := Vector3.ZERO
var stuck_t := 0.0
var unstick_t := 0.0
var unstick_dir := 1.0
var unstick_tried := false
var stuck_events := 0
var nudges := 0
# Métricas e informe.
var timeline: Array[String] = []
var issues: Array[String] = []
var minute_lines: Array[String] = []
var purchases: Array[String] = []
var purchase_times: Array[float] = []
var firsts := {}
var next_minute := 60.0
var earned_last_min := 0.0
var cycle := {}
var cycles: Array[Dictionary] = []
var hints := {}
var notes_opened: Array[String] = []
var modal_frames := 0
var tut_step := -1
var shop_t := 0.0
var leaves_total := 0
var hand_time := 0.0
var hand_leaves := 0
var rake_time := 0.0
var rake_leaves := 0
var walk_bag_time := 0.0
var state_time := {}
var last_leaf_t := 0.0
var max_active := 0
var frame_wall_max := 0.0
var frame_wall_t := 0
var slow_frames := 0
var saves := 0
var issue_counts := {}
var zone_first_pct := {}
var debug := false
var save_pending := false
var income_hist: Array[Vector2] = []
var gate_req := {}
var close_block_logged := ""
var tap_eval_at := 0.0
var finish_zone := ""
var finish_marks := {}
var target_sum := 0
var throw_aim_t := 0.0
var audit_text := ""
var audit_where: Array[String] = []
var shots := false
var shot_t := 20.0
var shot_names := {}
var save_frame_max := 0.0
var save_frame_sum := 0.0
var save_frames := 0
var bad_aims := {}
var empty_streak := 0
var los_blocked := 0
var bags_closed := 0
var bag_was_thrown := false
var throw_bag: LeafBag
var throw_best := Vector3.INF
var throw_origin := Vector3.INF
var throw_dbg := ""
var bin_target_last: RecycleBin
var throw_min := 1e9
var throw_min_y := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	var env_min := OS.get_environment("BOT_MINUTES")
	if env_min != "":
		limit_t = float(env_min) * 60.0
	var env_wall := OS.get_environment("BOT_WALL_LIMIT")
	if env_wall != "":
		wall_limit = float(env_wall)
	if OS.get_environment("BOT_PROFILE") == "casual":
		profile = "casual"
		TURN_RATE = 3.0
		PITCH_RATE = 2.2
		TAP_MIN = 0.55
		THINK = 0.8
		WALK_MAX = 0.85
		throw_every = 0
	use_rake = OS.get_environment("BOT_RAKE") != "0"
	finish_zone = OS.get_environment("BOT_FINISH")
	shots = OS.get_environment("BOT_SHOTS") != "" and DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://bot_shots")
	var env_throw := OS.get_environment("BOT_THROW_EVERY")
	if env_throw != "":
		throw_every = maxi(int(env_throw), 0)
	debug = OS.get_environment("BOT_DEBUG") != ""
	logger = BotLogger.new()
	OS.add_logger(logger)
	wall0 = Time.get_ticks_msec()
	print("=== Villa Hojarasca · bot de playtest (%.0f min de juego, partida nueva, perfil %s, rastrillo %s%s) ===" % [limit_t / 60.0, profile, "sí" if use_rake else "no", (", rematar " + finish_zone) if finish_zone != "" else ""])
	for slot in ["campaign", "zen", "time_attack"]:
		SaveManager.delete_slot(slot)
	GameManager.requested_new = true
	GameManager.skip_menu = true
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	var guard := 0
	while GameManager.world == null or not GameManager.in_game:
		await get_tree().process_frame
		guard += 1
		if guard > 3000:
			print("FAIL el mundo no llegó a cargarse")
			get_tree().quit(1)
			return
	world = GameManager.world
	p = world.player
	sim = world.leaf_manager.sim
	terrain = world.terrain
	for i in 4:
		await get_tree().physics_frame
	var t0 := Time.get_ticks_msec()
	var free := _build_nav()
	print("[BOT] rejilla de navegación: %d celdas libres (%d ms)" % [free, Time.get_ticks_msec() - t0])
	zone_ok.resize(GameData.ZONES.size() + 1)
	zone_w.resize(GameData.ZONES.size() + 1)
	_refresh_zones()
	_audit_leaves_in_props()
	_connect_events()
	cycle = {"start": 0.0}
	frame_wall_t = Time.get_ticks_usec()
	_set_state(St.SEEK)


# =================================================================== bucle

func _process(delta: float) -> void:
	if state == St.BOOT or state == St.END:
		return
	var now_us := Time.get_ticks_usec()
	var fw := (now_us - frame_wall_t) / 1000.0
	frame_wall_t = now_us
	if game_t > 5.0:
		frame_wall_max = maxf(frame_wall_max, fw)
		if fw > 50.0:
			slow_frames += 1
		if save_pending:
			save_pending = false
			save_frame_max = maxf(save_frame_max, fw)
			save_frame_sum += fw
			save_frames += 1
	if get_tree().paused or not InputState.enabled:
		_handle_modal()
		return
	modal_frames = 0
	game_t += delta
	state_t += delta
	logger.stamp = _ts()
	state_time[ST_NAMES[state]] = float(state_time.get(ST_NAMES[state], 0.0)) + delta
	mv = Vector2.ZERO
	look_on = false
	act_held = false
	act_press = false
	int_held = false
	int_press = false
	jump = false
	tool_sel = ""
	_poll(delta)
	if state_t < THINK and state != St.CLOSE:
		_check_stuck(delta)
		_apply_inputs(delta)
		return
	match state:
		St.SEEK:
			_st_seek(delta)
		St.GATHER:
			_st_gather(delta)
		St.RAKE:
			_st_rake(delta)
		St.CLOSE:
			_st_close(delta)
		St.DELIVER:
			_st_deliver(delta)
		St.THROW_WAIT:
			_st_throw_wait(delta)
		St.PICKUP:
			_st_pickup(delta)
		St.USE:
			_st_use(delta)
	_opportunistic()
	_check_stuck(delta)
	_apply_inputs(delta)
	var wall := (Time.get_ticks_msec() - wall0) / 1000.0
	if game_t >= limit_t or wall >= wall_limit:
		if wall >= wall_limit:
			_issue("WALL", "límite de tiempo real alcanzado (%.0f s) a los %s de juego" % [wall, _ts()])
		_finish()


func _poll(delta: float) -> void:
	if tap_pending and game_t >= tap_eval_at:
		tap_pending = false
		var now := _hand_total()
		var got := maxi(now - tap_before, 0)
		tap_hist.append(got)
		if tap_hist.size() > 10:
			tap_hist.remove_at(0)
		if got == 0:
			empty_taps += 1
			empty_streak += 1
		else:
			gather_idle_t = 0.0
			empty_streak = 0
		if debug and got == 0:
			var ht: HandTool = p.tools.tools["hand"]
			var tp: Vector3 = ht._target_point()
			print("[DBG %s] toque: %d hojas (aim %s, pitch %.2f, prompt «%s», pos %s, herr %s, punto mano %s, hojas a 0,95 m del punto %d, a 0,85 m del aim %d)" % [_ts(), got, _v(aim_point), p.cam.pitch, p.prompt, _v(p.global_position), p.tools.current.tool_id, str(tp), _dbg_count(tp, 0.95), _dbg_count(aim_point, 0.85)])
		if got == 0 and empty_streak >= 2 and aim_point != Vector3.INF:
			bad_aims[_cell(aim_point)] = game_t + 15.0
			aim_point = Vector3.INF
	if ProgressManager.tutorial_step != tut_step:
		if tut_step >= 0:
			_tl("tutorial: paso %d completado" % tut_step)
		tut_step = ProgressManager.tutorial_step
	max_active = maxi(max_active, sim.active_n)
	zone_t -= delta
	if zone_t <= 0.0:
		zone_t = 2.0
		_refresh_zones()
	shop_t -= delta
	if shop_t <= 0.0:
		shop_t = 1.0
		income_hist.append(Vector2(game_t, EconomyManager.total_earned))
		if income_hist.size() > 61:
			income_hist.remove_at(0)
		_check_gate_reqs()
		_shop()
		if state == St.SEEK or (state == St.GATHER and aim_focus == Vector3.INF):
			if not p.bags.is_carrying() and _plan_use():
				_set_state(St.USE)
	if state == St.SEEK or state == St.GATHER:
		if in_rake_cycle:
			rake_time += delta
		else:
			hand_time += delta
	elif state == St.RAKE:
		rake_time += delta
	elif state == St.DELIVER and p.bags.is_carrying():
		walk_bag_time += delta
	if shots:
		shot_t -= delta
		if shot_t <= 0.0:
			shot_t = 30.0
			_shot("t%d" % int(game_t))
		if state == St.THROW_WAIT and state_t > 0.35:
			_shot("lanzamiento")
		if state == St.GATHER and aim_focus != Vector3.INF:
			_shot("monton_rastrillo")
	if game_t >= next_minute:
		next_minute += 60.0
		_minute_report()
	if game_t - last_leaf_t > 90.0 and game_t > 60.0:
		last_leaf_t = game_t
		_issue("IDLE", "90 s sin recoger hojas (estado %s, pos %s)" % [ST_NAMES[state], _v(p.global_position)])


func _apply_inputs(delta: float) -> void:
	if unstick_t > 0.0:
		unstick_t -= delta
		mv = Vector2(unstick_dir * 0.9, -0.35)
	InputState.move = mv.limit_length(1.0)
	InputState.action_held = act_held
	if act_press:
		InputState.action_pressed = true
	InputState.interact_held = int_held
	if int_press:
		InputState.interact_pressed = true
	if jump:
		InputState.jump_pressed = true
	if tool_sel != "":
		InputState.tool_select = tool_sel
	if look_on:
		var dy := wrapf(look_yaw - p.rotation.y, -PI, PI)
		var sy := clampf(dy, -TURN_RATE * delta, TURN_RATE * delta)
		var dp := look_pitch - p.cam.pitch
		var sp := clampf(dp, -PITCH_RATE * delta, PITCH_RATE * delta)
		var sens_x := float(SettingsManager.get_value("sens_x", 1.0))
		var sens_y := float(SettingsManager.get_value("sens_y", 1.0))
		var inv := -1.0 if SettingsManager.get_value("invert_y", false) else 1.0
		InputState.look_delta = Vector2(-sy / (CameraController.LOOK_SCALE * sens_x), -sp / (CameraController.LOOK_SCALE * sens_y * inv))


func _handle_modal() -> void:
	modal_frames += 1
	var ui: UIManager = main.ui
	if modal_frames == 1 and not ui.stack.is_empty():
		var m: Control = ui.stack.back()
		var title := ""
		if m is Modal:
			title = (m as Modal).title_label.text
		notes_opened.append("%s %s" % [_ts(), title])
		print("[BOT %s] se abrió una ventana: «%s» (la cierro tras leerla)" % [_ts(), title])
	# Lee unos 2 s y toca "Cerrar".
	if modal_frames > 120:
		modal_frames = 0
		if not ui.stack.is_empty():
			ui.close_top()
		else:
			InputState.enabled = true


func _set_state(s: int) -> void:
	if s == state:
		return
	if state == St.RAKE:
		_restore_rake_cells()
	if debug:
		print("[DBG %s] %s -> %s en %s" % [_ts(), ST_NAMES[state], ST_NAMES[s], _v(p.global_position) if p else "?"])
	state = s
	state_t = 0.0
	path = PackedVector3Array()
	path_i = 0
	target = Vector3.INF
	aim_point = Vector3.INF
	closing = false
	gather_idle_t = 0.0
	unstick_tried = false
	stuck_t = 0.0


func _decide() -> void:
	if p.bags.is_carrying():
		_set_state(St.DELIVER)
	elif p.bags.count >= p.bags.capacity():
		_set_state(St.CLOSE)
	elif _plan_use():
		_set_state(St.USE)
	else:
		_set_state(St.SEEK)


# =================================================================== estados

func _st_seek(_delta: float) -> void:
	if p.bags.is_carrying():
		_set_state(St.DELIVER)
		return
	if p.bags.count >= p.bags.capacity():
		if _hand_in_flight() == 0:
			_set_state(St.CLOSE)
		return
	if target == Vector3.INF:
		var t := _scan(SIGHT, 2)
		if t == Vector3.INF:
			t = _scan(SIGHT_FAR, 1)
		if t == Vector3.INF and not blacklist.is_empty():
			blacklist.clear()
			t = _scan(SIGHT_FAR, 1)
		if t == Vector3.INF:
			t = _explore()
			if t == Vector3.INF:
				if state_t > 5.0:
					_issue("NO_LEAVES", "no veo hojas en ninguna zona desbloqueada")
					state_t = 0.0
				return
		target = t
		if not _plan(target):
			if target_key >= 0:
				blacklist[target_key] = game_t + 30.0
			target = Vector3.INF
			return
	if state_t > 60.0:
		_issue("SEEK_TIMEOUT", "60 s caminando hacia hojas en %s sin llegar (pos %s)" % [_v(target), _v(p.global_position)])
		if target_key >= 0:
			blacklist[target_key] = game_t + 60.0
		target = Vector3.INF
		state_t = 0.0
		return
	if _follow(2.0, 1.0):
		_set_state(St.GATHER)


func _st_gather(delta: float) -> void:
	if p.bags.is_carrying():
		_set_state(St.DELIVER)
		return
	if p.bags.count >= p.bags.capacity():
		if _hand_in_flight() == 0 and sim.in_flight[LeafManager.P_VACUUM] == 0:
			_end_rake_cycle()
			_set_state(St.CLOSE)
		return
	var h := int(UpgradeManager.get_value("hand"))
	if UpgradeManager.has_tool("vacuum"):
		_vacuum_gather(delta)
		return
	if GameManager.current_tool != "hand":
		tool_sel = "hand"
		return
	tap_cd -= delta
	aim_t -= delta
	gather_idle_t += delta
	if gather_idle_t > 20.0:
		_issue("GATHER_STALL", "20 s apuntando sin recoger nada en %s" % _v(p.global_position))
		_blacklist_around(p.global_position, 3.0, 40.0)
		_set_state(St.SEEK)
		return
	if aim_point == Vector3.INF or aim_t <= 0.0:
		# Si vine expresamente a por un grupo pequeño de hojas, me conformo con lo que hay.
		var need := mini(_need(h), maxi(1, target_sum / 2))
		var best := Vector4(0, 0, 0, -1)
		for attempt in 6:
			best = _best_aim(h, aim_focus)
			if aim_focus != Vector3.INF and best.z < need:
				_end_rake_cycle()
				best = _best_aim(h, Vector3.INF)
			if best.w < 0.5 or best.z < need:
				break
			# ¿Se ve el suelo ahí o hay un banco/valla delante? (lo mismo que comprueba el ojo)
			var ap := Vector3(best.x, sim.height_at(best.x, best.y) + 0.05, best.y)
			if _ray_ok(ap):
				break
			los_blocked += 1
			for oz in range(-1, 2):
				for ox in range(-1, 2):
					bad_aims[_cell(ap) + Vector2i(ox, oz)] = game_t + 20.0
			best = Vector4(0, 0, 0, -1)
		if best.w < 0.5 or best.z < need:
			_leave_spot(h)
			return
		aim_point = Vector3(best.x, sim.height_at(best.x, best.y) + 0.05, best.y)
		aim_t = 1.5
	var err := _look_at(aim_point)
	if p.bags.space() <= 0:
		return
	var continuous := UpgradeManager.get_level("hand") >= 4
	var interval := maxf(TAP_MIN, (0.32 if not continuous else 0.2) / float(UpgradeManager.get_value("interact_speed")) + 0.02)
	if err < 0.07:
		if continuous:
			act_held = true
			if tap_cd <= 0.0:
				_count_tap(interval, true)
		elif tap_cd <= 0.0:
			act_press = true
			act_held = true
			_count_tap(interval)


func _count_tap(interval: float, continuous: bool = false) -> void:
	tap_cd = interval
	tap_pending = true
	tap_eval_at = game_t + (interval * 0.95 if continuous else 0.0)
	tap_before = _hand_total()
	taps += 1
	aim_t = 0.0


func _vacuum_gather(_delta: float) -> void:
	if GameManager.current_tool != "vacuum":
		tool_sel = "vacuum"
		return
	var best := _best_aim(12, Vector3.INF)
	if best.w < 0.5 or best.z < 2.0:
		_leave_spot(12)
		return
	var tp := Vector3(best.x, sim.height_at(best.x, best.y), best.y)
	_look_at(tp)
	look_pitch = -0.55
	act_held = p.bags.space() > 0
	var d := tp - p.global_position
	d.y = 0.0
	if d.length() > 1.4:
		_walk_dir(d.normalized(), 0.35, false)


func _leave_spot(h: int) -> void:
	target_sum = 999
	if _try_start_rake(h):
		return
	_blacklist_around(p.global_position, 3.0, 25.0)
	relaxed = false
	_set_state(St.SEEK)


func _st_close(_delta: float) -> void:
	if p.bags.is_carrying():
		_set_state(St.DELIVER)
		return
	if p.bags.count <= 0:
		_decide()
		return
	look_on = true
	look_yaw = p.rotation.y
	look_pitch = -1.25
	if p.prompt.begins_with("Cerrar bolsa"):
		if not closing:
			closing = true
			int_press = true
		int_held = true
		return
	closing = false
	# Algo se interpone en el rayo (otra cosa interactuable): mirar al frente, girar y, si no, apartarse.
	if state_t > 0.4:
		if close_block_logged != p.prompt:
			close_block_logged = p.prompt
			_issue("CLOSE_BLOCKED", "no aparece «Cerrar bolsa» al mirar al suelo: el rayo de interacción da con «%s» en %s" % [p.prompt, _v(p.global_position)])
		look_pitch = 0.15
		look_yaw = p.rotation.y + 0.8
	if state_t > 2.5:
		var a := game_t * 1.7
		_walk_dir(Vector3(cos(a), 0, sin(a)), 0.7, false)
	if state_t > 10.0:
		_issue("CLOSE_TIMEOUT", "10 s intentando cerrar la bolsa (prompt «%s»)" % p.prompt)
		state_t = 0.0


func _st_deliver(_delta: float) -> void:
	if not p.bags.is_carrying():
		bin_target = null
		_decide()
		return
	if bin_target == null:
		throw_aim_t = 0.0
		throw_plan = throw_every > 0 and bags_closed % throw_every == 0 and not bag_was_thrown
		if not _choose_bin(throw_plan):
			if throw_plan:
				throw_plan = false
				if _choose_bin(false):
					return
			if state_t > 3.0:
				_issue("NO_BIN", "no encuentro un contenedor alcanzable desde %s" % _v(p.global_position))
				state_t = 0.0
		return
	var bc := bin_target.global_position
	var pos := p.global_position
	if state_t > 120.0:
		_issue("DELIVER_TIMEOUT", "120 s sin llegar al contenedor %s (pos %s)" % [_v(bc), _v(pos)])
		bin_target = null
		state_t = 0.0
		return
	var at_stand := _flat(pos, bin_stand) <= 0.6
	if throw_plan:
		if not at_stand and not _follow(0.5, 1.0):
			return
		var cp := p.cam.camera.global_position
		var dist := Vector2(bc.x - cp.x, bc.z - cp.z).length()
		var pitch := _throw_pitch(dist, bc.y + 1.95 - cp.y)
		var d := bc - cp
		look_on = true
		look_yaw = atan2(-d.x, -d.z)
		look_pitch = pitch
		var err := absf(wrapf(look_yaw - p.rotation.y, -PI, PI)) + absf(look_pitch - p.cam.pitch)
		throw_aim_t += _delta
		if throw_aim_t > 4.0:
			if debug:
				print("[DBG %s] apuntado de lanzamiento fallido: err %.3f vel %s pitch %.2f/%.2f dist %.1f" % [_ts(), err, str(p.velocity), look_pitch, p.cam.pitch, dist])
			_issue("THROW_AIM", "no consigo apuntar el lanzamiento en 4 s (err %.2f, vel %.2f): lo llevo en mano" % [err, p.velocity.length()])
			throw_plan = false
			throw_aim_t = 0.0
			bag_was_thrown = true
			bin_target = null
			return
		if err < 0.03 and Vector2(p.velocity.x, p.velocity.z).length() < 0.3:
			act_press = true
			throws += 1
			delivered_flag = false
			bag_was_thrown = true
			throw_origin = p.global_position
			throw_dbg = "dist %.1f pitch %.2f fuerza %.0f" % [dist, pitch, float(UpgradeManager.get_value("bag_throw"))]
			bin_target_last = bin_target
			bin_target = null
			_tl_first("first_throw", "primer lanzamiento de bolsa (%.1f m)" % dist)
			_set_state(St.THROW_WAIT)
		return
	var near := _flat(pos, bc) <= 2.9
	if not near and not at_stand:
		_follow(0.5, 1.0)
		return
	var e := _look_at(bc + Vector3(0, 0.9, 0))
	if p.prompt == "Depositar bolsa" and e < 0.25:
		int_press = true
	elif state_t > 3.0 and fmod(state_t, 2.0) < _delta_safe():
		if p.prompt != "Depositar bolsa":
			_walk_dir((bc - pos).normalized(), 0.3, false)


func _st_throw_wait(_delta: float) -> void:
	if delivered_flag:
		throws_ok += 1
		_decide()
		return
	if state_t < 0.05:
		throw_bag = null
		throw_min = 1e9
	if throw_bag == null:
		throw_bag = _nearest_bag(3.0)
	elif is_instance_valid(throw_bag) and bin_target_last != null:
		var bc := bin_target_last.global_position
		var d := _flat(throw_bag.global_position, bc)
		if d < throw_min:
			throw_min = d
			throw_min_y = throw_bag.global_position.y - bc.y
	if state_t > 3.5:
		var b := _nearest_bag(30.0)
		var where := _v(b.global_position) if b else "?"
		_issue("THROW_MISS", "bolsa lanzada desde %.1f m que no entró (cayó en %s; %s; pasó a %.2f m del centro a %.2f m de altura)" % [_flat(throw_origin, bin_target_last.global_position) if bin_target_last else -1.0, where, throw_dbg, throw_min, throw_min_y])
		bag_target = b
		_set_state(St.PICKUP)


func _st_pickup(_delta: float) -> void:
	if p.bags.is_carrying():
		_set_state(St.DELIVER)
		return
	if bag_target == null or not is_instance_valid(bag_target) or bag_target.consumed:
		bag_target = _nearest_bag(40.0)
		if bag_target == null:
			_decide()
			return
		path = PackedVector3Array()
	var bp := bag_target.global_position
	if state_t > 45.0:
		_issue("BAG_LOST", "no consigo recoger la bolsa en %s (¿encima de algo?)" % _v(bp))
		bag_target = null
		_decide()
		return
	if _flat(p.global_position, bp) > 2.2:
		if path.is_empty() or _flat(path_goal, bp) > 1.0:
			if not _plan(bp):
				_issue("BAG_UNREACHABLE", "bolsa inalcanzable en %s" % _v(bp))
				bag_target = null
				_decide()
				return
		if _follow(1.9, 0.9) or (path_i >= path.size() - 1 and _flat(p.global_position, path[path.size() - 1]) < 0.5):
			if debug and fmod(state_t, 3.0) < _delta_safe():
				print("[DBG %s] no llego a la bolsa %s: fin de ruta en %s (yo %s)" % [_ts(), _v(bp), _v(path[path.size() - 1]), _v(p.global_position)])
		return
	var err := _look_at(bp + Vector3(0, 0.15, 0))
	if p.prompt.begins_with("Coger bolsa") and err < 0.3:
		int_press = true
	elif debug and fmod(state_t, 3.0) < _delta_safe():
		print("[DBG %s] recoger bolsa en %s (y %.2f): prompt «%s», err %.2f, objetivo %s, yo %s" % [_ts(), _v(bp), bp.y, p.prompt, err, str(p.target), _v(p.global_position)])
	elif state_t > 6.0 and fmod(state_t, 1.5) < _delta_safe():
		_walk_dir((bp - p.global_position).normalized(), 0.3, false)


func _st_use(_delta: float) -> void:
	use_cd -= _delta
	if use_node == null or not is_instance_valid(use_node):
		_decide()
		return
	var done := false
	if use_kind == "gate":
		var g := use_node as GateDoor
		done = g.opened or not g.is_available(p)
	elif use_kind == "duct":
		var dct := use_node as SuctionDuct
		done = dct.repaired or not dct.is_available(p)
	if done:
		use_node = null
		_decide()
		return
	if state_t > 90.0:
		_issue("USE_TIMEOUT", "90 s sin poder usar %s (prompt «%s», pos %s)" % [use_kind, p.prompt, _v(p.global_position)])
		use_node = null
		_decide()
		return
	if _flat(p.global_position, use_stand) > 0.6:
		if path.is_empty() and not _plan(use_stand):
			_issue("USE_UNREACHABLE", "%s inalcanzable" % use_kind)
			use_node = null
			_decide()
			return
		if not _follow(0.5, 1.0):
			return
	var err := _look_at(use_look)
	if p.prompt.begins_with(use_prefix) and err < 0.2 and use_cd <= 0.0:
		int_press = true
		use_cd = 1.0


# =================================================================== rastrillo

func _try_start_rake(h: int) -> bool:
	if not use_rake or not UpgradeManager.has_tool("rake") or h < 4 or game_t < rake_cd_until:
		return false
	var pos := p.global_position
	var f := -p.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var pc := _free_near(_cell(pos + f * 2.0), 2)
	if pc.x < 0:
		return false
	var P := _center(pc)
	var w := float(UpgradeManager.get_value("rake_width"))
	var cand: Array = []
	for k in 16:
		var a := k * TAU / 16.0
		var u := Vector3(cos(a), 0.0, sin(a))
		var s := _strip_count(P, u, RAKE_LEN, w)
		if s > 0:
			cand.append([s, u])
	cand.sort_custom(_cmp_desc)
	rake_dirs.clear()
	var total := 0
	for cnd in cand:
		var u: Vector3 = cnd[1]
		var ok := true
		for d in rake_dirs:
			if d.dot(u) > 0.6:
				ok = false
		if ok:
			rake_dirs.append(u)
			total += int(cnd[0])
		if rake_dirs.size() >= 3:
			break
	if total < h * 3:
		rake_cd_until = game_t + 20.0
		return false
	rake_P = P
	rake_k = 0
	rake_sub = 0
	rake_sub_t = 0.0
	_set_state(St.RAKE)
	_block_rake_cells()
	rake_cycles += 1
	in_rake_cycle = true
	rake_cycle_t0 = game_t
	rake_cycle_l0 = leaves_total
	_tl_first("first_rake", "primer montón con el rastrillo (3 pasadas hacia %s, %d hojas en las franjas)" % [_v(P), total])
	return true


func _strip_count(P: Vector3, u: Vector3, length: float, w: float) -> int:
	var right := Vector3(-u.z, 0.0, u.x)
	var cc := sim.cell_count
	var cz := terrain.cell_zone
	var sum := 0
	var t := 0.5
	while t <= length:
		var c0 := _cell(P + u * t)
		if t > 1.4 and not _free(c0):
			return -1
		var o := -w * 0.5
		while o <= w * 0.5 + 0.01:
			var c := _cell(P + u * t + right * o)
			if _inb(c):
				var ci := c.y * gw + c.x
				if zone_ok[cz[ci]] == 1:
					sum += cc[ci]
			o += 0.5
		t += 0.5
	if not _free(_cell(P + u * length)):
		return -1
	return sum


func _cmp_desc(a: Array, b: Array) -> bool:
	return int(a[0]) > int(b[0])


func _block_rake_cells() -> void:
	rake_blocked.clear()
	var c0 := _cell(rake_P)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dz * dz > 5:
				continue
			var c := c0 + Vector2i(dx, dz)
			if _free(c) and c != _cell(p.global_position):
				astar.set_point_solid(c, true)
				rake_blocked.append(c)


func _restore_rake_cells() -> void:
	for c in rake_blocked:
		astar.set_point_solid(c, false)
	rake_blocked.clear()


func _st_rake(delta: float) -> void:
	if p.bags.is_carrying() or p.bags.count >= p.bags.capacity():
		_decide()
		return
	if rake_k >= rake_dirs.size():
		_finish_rake()
		return
	if state_t > 70.0:
		_issue("RAKE_TIMEOUT", "ciclo de rastrillo de más de 70 s")
		_finish_rake()
		return
	var reach := float(UpgradeManager.get_value("rake_reach"))
	var u: Vector3 = rake_dirs[rake_k]
	var S := rake_P + u * RAKE_LEN
	var pos := p.global_position
	rake_sub_t += delta
	match rake_sub:
		0:
			if _flat(pos, S) <= 0.7:
				rake_sub = 1
				rake_sub_t = 0.0
				path = PackedVector3Array()
				return
			if path.is_empty():
				if not _plan(S):
					rake_k += 1
					return
			if _follow(0.6, 1.0) or rake_sub_t > 25.0:
				rake_sub = 1
				rake_sub_t = 0.0
				path = PackedVector3Array()
		1:
			if GameManager.current_tool != "rake":
				tool_sel = "rake"
			var d := rake_P - pos
			look_on = true
			look_yaw = atan2(-d.x, -d.z)
			look_pitch = -0.35
			var err := absf(wrapf(look_yaw - p.rotation.y, -PI, PI))
			if err < 0.08 and rake_sub_t > 0.35 and GameManager.current_tool == "rake":
				rake_sub = 2
				rake_sub_t = 0.0
		2:
			var d := rake_P - pos
			d.y = 0.0
			if d.length() <= reach + 0.1 or rake_sub_t > 8.0:
				rake_k += 1
				rake_sub = 0
				rake_sub_t = 0.0
				path = PackedVector3Array()
				return
			act_held = true
			look_on = true
			look_yaw = atan2(-d.x, -d.z)
			look_pitch = -0.35
			_walk_dir(d.normalized(), 0.85, false)


func _finish_rake() -> void:
	_restore_rake_cells()
	var pile := sim.count_in_radius(rake_P, 1.5)
	pile_sizes.append(pile)
	aim_focus = rake_P
	rake_cd_until = game_t + 4.0
	_set_state(St.GATHER)


func _end_rake_cycle() -> void:
	aim_focus = Vector3.INF
	in_rake_cycle = false


# =================================================================== percepción

func _refresh_zones() -> void:
	zone_ok.fill(0)
	zone_w.fill(0.0)
	for i in GameData.ZONES.size():
		var z: Dictionary = GameData.ZONES[i]
		var zid: String = z["id"]
		if z.get("secret", false) or not AreaManager.is_unlocked(zid):
			continue
		zone_ok[i + 1] = 1
		var w := float(z["value"])
		for g in GameData.GATES:
			var gd: Dictionary = g
			if gd.get("auto", false) or AreaManager.gates_open.get(gd["id"], false):
				continue
			if String(gd["req"]) == zid and AreaManager.pct(zid) < float(gd["pct"]):
				w *= 2.0
				break
		var pc := AreaManager.pct(zid)
		if finish_zone != "":
			if zid == finish_zone:
				for mark in [50, 75, 90, 95, 98, 99, 100]:
					if pc >= float(mark) and not finish_marks.has(mark):
						finish_marks[mark] = game_t
						_tl("rematar %s: %d %% a los %s (quedan %d hojas)" % [zid, mark, _ts(), int(AreaManager.remaining.get(zid, 0))])
			if AreaManager.is_unlocked(finish_zone) and not AreaManager.completed.get(finish_zone, false):
				zone_w[i + 1] = 1.0 if zid == finish_zone else 0.0
				continue
		if pc >= 90.0 and pc < 100.0:
			if not finish_start.has(zid):
				finish_start[zid] = game_t
				_tl("%s llega al 90 %% (empiezo a rematarla)" % z["name"])
			elif game_t - float(finish_start[zid]) > 300.0 and not finish_gave_up.has(zid):
				finish_gave_up[zid] = true
				_issue("FINISH_TEDIOUS", "%s: más de 5 min del 90 %% al 100 %% (quedan %d hojas); lo dejo" % [z["name"], int(AreaManager.remaining.get(zid, 0))])
				_dump_remaining(zid)
			if not finish_gave_up.has(zid):
				w *= 3.0
		zone_w[i + 1] = w


func _need(h: int) -> int:
	if finish_zone != "" and AreaManager.is_unlocked(finish_zone) and not AreaManager.completed.get(finish_zone, false) and AreaManager.pct(finish_zone) >= 85.0:
		return 1
	var zid := AreaManager.zone_at(p.global_position)
	if zid != "" and finish_start.has(zid) and not finish_gave_up.has(zid):
		return 1
	return maxi(1, int(ceil(h * 0.5)))


## Mejor punto del suelo al alcance de la mano (0,9–2,9 m): cuenta las hojas reales que hay
## dentro del radio de captura de la mano alrededor de cada punto candidato (lo que se ve).
func _best_aim(h: int, focus: Vector3) -> Vector4:
	var pos := p.global_position
	var ci := _cell(pos)
	var cc := sim.cell_count
	var cz := terrain.cell_zone
	var heads := sim.cell_head
	var nxt := sim.nxt
	var st := sim.state
	var lp := sim.pos
	var radius := 0.85 if UpgradeManager.get_level("hand") < 5 else 1.55
	var r2 := radius * radius
	var span := 2 if radius < 1.0 else 3
	var best := Vector4(0, 0, 0, -1)
	var best_s := -1e9
	var cur_yaw := p.rotation.y
	for dz in range(-6, 7):
		for dx in range(-6, 7):
			var dist := sqrt(float(dx * dx + dz * dz)) * 0.5
			if dist < 0.7 or dist > 2.8:
				continue
			var x0 := ci.x + dx
			var z0 := ci.y + dz
			if x0 < 4 or z0 < 4 or x0 >= gw - 4 or z0 >= gh - 4:
				continue
			if bad_aims.has(Vector2i(x0, z0)) and float(bad_aims[Vector2i(x0, z0)]) > game_t:
				continue
			var cx := terrain.origin.x + (x0 + 0.5) * 0.5
			var czz := terrain.origin.y + (z0 + 0.5) * 0.5
			var cnt := 0
			var sx := 0.0
			var sz := 0.0
			for oz in range(-span, span + 1):
				for ox in range(-span, span + 1):
					var c := (z0 + oz) * gw + x0 + ox
					if cc[c] == 0 or zone_ok[cz[c]] != 1:
						continue
					var li := heads[c]
					while li >= 0:
						var s0 := st[li]
						if s0 == LeafSimulationSystem.S_SLEEP or s0 == LeafSimulationSystem.S_AIR:
							var lv := lp[li]
							var ddx := lv.x - cx
							var ddz := lv.z - czz
							if ddx * ddx + ddz * ddz <= r2:
								cnt += 1
								sx += lv.x
								sz += lv.z
						li = nxt[li]
			if cnt <= 0:
				continue
			var ax := sx / cnt
			var az := sz / cnt
			# El rayo de la mano mide 3,4 m desde los ojos: más allá de ~2,6 m en llano no llega al suelo.
			var adist := Vector2(ax - pos.x, az - pos.z).length()
			var cam_h := p.cam.camera.global_position.y - sim.height_at(ax, az)
			if adist < 0.7 or adist * adist + cam_h * cam_h > 3.15 * 3.15:
				continue
			var yaw := atan2(-(ax - pos.x), -(az - pos.z))
			var turn := absf(wrapf(yaw - cur_yaw, -PI, PI))
			var s := float(mini(cnt, h)) * 10.0 + minf(cnt, h * 3) * 0.5 - turn * 3.0 - absf(adist - 1.6) * 2.0
			if focus != Vector3.INF:
				s -= Vector2(ax - focus.x, az - focus.z).length() * 8.0
			if s > best_s:
				best_s = s
				best = Vector4(ax, az, float(cnt), 1.0)
	return best


## Busca el bloque de 2x2 m con más hojas "interesantes" (valor de la zona / distancia).
func _scan(radius: float, min_sum: int) -> Vector3:
	var pos := p.global_position
	var ci := _cell(pos)
	var cc := sim.cell_count
	var cz := terrain.cell_zone
	var rb := int(radius * 2.0 / 4.0) + 1
	var bx0 := ci.x / 4
	var bz0 := ci.y / 4
	var best := Vector3.INF
	var best_s := 0.0
	target_key = -1
	for bz in range(bz0 - rb, bz0 + rb + 1):
		for bx in range(bx0 - rb, bx0 + rb + 1):
			if bx < 0 or bz < 0 or bx * 4 + 4 > gw or bz * 4 + 4 > gh:
				continue
			var key := bz * 1000 + bx
			if blacklist.has(key) and float(blacklist[key]) > game_t:
				continue
			var sum := 0
			var sx := 0.0
			var sz := 0.0
			var wsum := 0.0
			for j in range(bz * 4, bz * 4 + 4):
				for i in range(bx * 4, bx * 4 + 4):
					var c := j * gw + i
					var n := cc[c]
					if n > 0:
						var zv := cz[c]
						if zone_ok[zv] == 1:
							sum += n
							sx += float(i * n)
							sz += float(j * n)
							wsum += zone_w[zv] * n
			if sum < min_sum:
				continue
			var cx := terrain.origin.x + (sx / sum + 0.5) * 0.5
			var czz := terrain.origin.y + (sz / sum + 0.5) * 0.5
			var d := Vector2(cx - pos.x, czz - pos.z).length()
			if d > radius:
				continue
			var s := minf(float(sum), 40.0) * (wsum / sum) / (d + 4.0)
			if s > best_s:
				best_s = s
				best = Vector3(cx, terrain.height_at(cx, czz), czz)
				target_key = key
				target_sum = sum
	return best


func _explore() -> Vector3:
	# Sin hojas a la vista: ir hacia el centro de la zona desbloqueada con más hojas pendientes.
	var best := Vector3.INF
	var best_s := 0.0
	for i in GameData.ZONES.size():
		if zone_ok[i + 1] != 1:
			continue
		var z: Dictionary = GameData.ZONES[i]
		var rem := int(AreaManager.remaining.get(z["id"], 0))
		if rem <= 0:
			continue
		var r: Rect2 = z["rect"]
		var c := r.get_center()
		var d := Vector2(p.global_position.x, p.global_position.z).distance_to(c)
		var s := float(rem) * zone_w[i + 1] / (d + 20.0)
		if s > best_s:
			best_s = s
			best = Vector3(c.x, terrain.height_at(c.x, c.y), c.y)
	if best != Vector3.INF and explore_target.distance_to(best) > 1.0:
		explore_target = best
		print("[BOT %s] no veo hojas cerca: exploro hacia %s" % [_ts(), _v(best)])
	return best


func _blacklist_around(pos: Vector3, radius: float, secs: float) -> void:
	var ci := _cell(pos)
	var rb := int(radius * 2.0 / 4.0) + 1
	for bz in range(ci.y / 4 - rb, ci.y / 4 + rb + 1):
		for bx in range(ci.x / 4 - rb, ci.x / 4 + rb + 1):
			var cx := terrain.origin.x + (bx * 4 + 2) * 0.5
			var cz := terrain.origin.y + (bz * 4 + 2) * 0.5
			if Vector2(cx - pos.x, cz - pos.z).length() <= radius + 1.0:
				blacklist[bz * 1000 + bx] = game_t + secs


func _nearest_bag(max_d: float) -> LeafBag:
	var best: LeafBag = null
	var bd := max_d
	for b in get_tree().get_nodes_in_group("leaf_bags"):
		var lb := b as LeafBag
		if lb == null or lb.consumed or not is_instance_valid(lb):
			continue
		var d := _flat(p.global_position, lb.global_position)
		if d < bd:
			bd = d
			best = lb
	return best


## Rayo de la cámara al punto (el mismo que usa la mano): true si el punto de agarre resultante
## queda lo bastante cerca de las hojas a las que se apunta.
func _ray_ok(ap: Vector3) -> bool:
	var cp := p.cam.camera.global_position
	var dir := (ap - cp)
	var q := PhysicsRayQueryParameters3D.create(cp, cp + dir.normalized() * 3.4, Interactable.LAYER_WORLD)
	q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var hp: Vector3 = hit["position"]
	return Vector2(hp.x - ap.x, hp.z - ap.z).length() < 0.7


## Auditoría inicial: hojas generadas DENTRO de objetos con colisión (invisibles o inalcanzables).
func _audit_leaves_in_props() -> void:
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.06
	q.shape = sph
	q.collision_mask = Interactable.LAYER_WORLD
	var ground := terrain.get_node_or_null("GroundBody") as CollisionObject3D
	if ground:
		q.exclude = [ground.get_rid()]
	var per_zone := {}
	var where := {}
	var total := 0
	for c in sim.cell_count.size():
		if sim.cell_count[c] == 0:
			continue
		var li := sim.cell_head[c]
		while li >= 0:
			var lv := sim.pos[li]
			q.transform = Transform3D(Basis.IDENTITY, lv + Vector3(0, 0.08, 0))
			var hits := space.intersect_shape(q, 1)
			if not hits.is_empty():
				total += 1
				var zid := AreaManager.zone_at(lv)
				per_zone[zid] = int(per_zone.get(zid, 0)) + 1
				var col: Object = hits[0]["collider"]
				var cname := "?"
				if col is Node:
					cname = String((col as Node).name)
				if col is SuctionDuct:
					cname = "conducto " + String((col as SuctionDuct).def["id"])
				var key := "%s @ %s" % [cname, _v(Vector3(snappedf(lv.x, 2.0), 0, snappedf(lv.z, 2.0)))]
				where[key] = int(where.get(key, 0)) + 1
			li = sim.nxt[li]
	audit_text = "%d hojas generadas dentro de objetos con colisión; por zona %s" % [total, str(per_zone)]
	print("[BOT] AUDITORÍA: ", audit_text)
	var arr: Array = []
	for k in where:
		arr.append([int(where[k]), k])
	arr.sort_custom(_cmp_desc)
	for e in arr.slice(0, 12):
		print("[BOT]   %3d × %s" % [int(e[0]), e[1]])
		audit_where.append("%d × %s" % [int(e[0]), e[1]])


## Dónde quedan las hojas de una zona (bloques de 2 m), y si el bot puede llegar ahí.
func _dump_remaining(zid: String) -> void:
	var zi := GameData.zone_index(zid)
	var blocks := {}
	var pts := sim.remaining_in_zone(zi, 5000)
	for v in pts:
		var key := Vector2i(int(floor(v.x / 2.0)), int(floor(v.z / 2.0)))
		blocks[key] = int(blocks.get(key, 0)) + 1
	var arr: Array = []
	for k in blocks:
		arr.append([int(blocks[k]), k])
	arr.sort_custom(_cmp_desc)
	print("\n-- Hojas restantes en %s: %d (bloques de 2 m con más hojas) --" % [zid, pts.size()])
	for e in arr.slice(0, 10):
		var k: Vector2i = e[1]
		var c := Vector3(k.x * 2.0 + 1.0, 0.0, k.y * 2.0 + 1.0)
		var reach := not _path_to(c).is_empty()
		var near_free := _free_near(_cell(c), 5)
		var d := _flat(_center(near_free), c) if near_free.x >= 0 else -1.0
		print("  %3d hojas en %s · ruta: %s · celda libre más cercana a %.1f m · bloqueada en lista negra: %s" % [int(e[0]), _v(c), "sí" if reach else "NO", d, str(blacklist.has(_cell(c).y / 4 * 1000 + _cell(c).x / 4))])


func _dbg_count(c: Vector3, r: float) -> int:
	if c == Vector3.INF:
		return -1
	var n := 0
	for i in sim.n:
		var s0 := sim.state[i]
		if s0 == LeafSimulationSystem.S_SLEEP or s0 == LeafSimulationSystem.S_AIR:
			var d := sim.pos[i] - c
			d.y *= 0.5
			if d.length() <= r:
				n += 1
	return n


func _hand_total() -> int:
	return sim.in_flight[LeafManager.P_HAND] + sim.arrived_count[LeafManager.P_HAND] + p.bags.count


func _hand_in_flight() -> int:
	return sim.in_flight[LeafManager.P_HAND] + sim.arrived_count[LeafManager.P_HAND]


# =================================================================== contenedores, puertas, conductos

func _choose_bin(throw: bool) -> bool:
	var best_len := 1e9
	var best_bin: RecycleBin = null
	var best_stand := Vector3.INF
	for b in world.builder.bins:
		var bp := b.global_position
		var bc := _cell(bp)
		if not _inb(bc) or zone_ok[terrain.cell_zone[bc.y * gw + bc.x]] != 1:
			continue
		var bas := b.global_transform.basis
		var offs: Array[Vector3] = [Vector3(2.35, 0, 0), Vector3(-2.35, 0, 0), Vector3(0, 0, 1.9), Vector3(0, 0, -1.9)]
		if throw:
			offs = [Vector3(0, 0, 5.0), Vector3(0, 0, -5.0), Vector3(5.2, 0, 0), Vector3(-5.2, 0, 0)]
		for o in offs:
			var sp := bp + bas * o
			var sc := _cell(sp)
			if not _free(sc):
				continue
			if throw and not _line_free(sp, bp + (sp - bp).normalized() * 1.6):
				continue
			var pts := _path_to(sp)
			if pts.is_empty():
				continue
			var L := _path_len(pts)
			if L < best_len:
				best_len = L
				best_bin = b
				best_stand = sp
	if best_bin == null:
		return false
	bin_target = best_bin
	bin_stand = best_stand
	_plan(best_stand)
	return true


func _plan_use() -> bool:
	if p.bags.is_carrying():
		return false
	# Puertas: cuando se cumple el requisito y hay dinero.
	for g in GameData.GATES:
		var gd: Dictionary = g
		if gd.get("auto", false):
			continue
		var node: GateDoor = world.gates.get(gd["id"])
		if node == null or node.opened or not node.is_available(p):
			continue
		var gp: Vector2 = gd["pos"]
		var n := Vector2(0, 1) if gd["axis"] == "x" else Vector2(1, 0)
		var ra: Rect2 = GameData.zone_by_id(gd["a"])["rect"]
		var s := gp + n * 2.2
		if not ra.has_point(s):
			s = gp - n * 2.2
		use_node = node
		use_stand = Vector3(s.x, terrain.height_at(s.x, s.y), s.y)
		use_look = node.global_position + Vector3(0, 1.0, 0)
		use_prefix = "Abrir"
		use_kind = "gate"
		return true
	# Conductos de aspiración: automatización, cuando sobra dinero.
	if EconomyManager.money - _reserve() >= 2000.0:
		for duct in world.ducts:
			if duct.repaired or not AreaManager.is_unlocked(String(duct.def["zone"])):
				continue
			var cost := float(duct.def["cost"])
			if EconomyManager.money - _reserve() < cost * 1.3:
				continue
			for o in [Vector3(-2.0, 0, 0), Vector3(0, 0, 2.0), Vector3(0, 0, -2.0), Vector3(3.2, 0, 0)]:
				var sp: Vector3 = duct.global_position + o
				if _free(_cell(sp)):
					use_node = duct
					use_stand = sp
					use_look = duct.global_position + Vector3(0, 0.25, 0)
					use_prefix = "Reparar conducto"
					use_kind = "duct"
					return true
	return false


func _income_60s() -> float:
	if income_hist.size() < 2:
		return 0.0
	var a: Vector2 = income_hist[0]
	var b: Vector2 = income_hist[income_hist.size() - 1]
	return (b.y - a.y) * 60.0 / maxf(b.x - a.x, 1.0)


func _check_gate_reqs() -> void:
	for g in GameData.GATES:
		var gd: Dictionary = g
		var gid: String = gd["id"]
		if gd.get("auto", false) or gate_req.has(gid) or AreaManager.gates_open.get(gid, false):
			continue
		var node: GateDoor = world.gates.get(gid)
		if node != null and node.requirement_met():
			gate_req[gid] = game_t
			_tl("requisito cumplido para %s (%s al %d %%); dinero %d / %d $" % [gid, gd["req"], int(gd["pct"]), int(EconomyManager.money), int(gd["cost"])])


func _reserve() -> float:
	var r := 0.0
	for g in GameData.GATES:
		var gd: Dictionary = g
		if gd.get("auto", false) or AreaManager.gates_open.get(gd["id"], false):
			continue
		if not AreaManager.is_unlocked(gd["a"]):
			continue
		if AreaManager.pct(gd["req"]) >= float(gd["pct"]) - 10.0:
			var c := float(gd["cost"])
			if r == 0.0 or c < r:
				r = c
	return r


func _shop() -> void:
	var spend := EconomyManager.money - _reserve()
	# Ingresos del último minuto: lo que un jugador "sabe" que ganará pronto.
	var soon := spend + maxf(_income_60s(), 150.0) * 0.75
	var best_id := ""
	var best_s := 0.0
	var best_soon := 0.0
	for id in WEIGHTS:
		var uid: String = id
		if not GameData.UPGRADES.has(uid) or UpgradeManager.is_maxed(uid) or UpgradeManager.lock_reason(uid) != "":
			continue
		if not use_rake and uid.begins_with("rake_"):
			continue
		var cost := UpgradeManager.next_cost(uid)
		if cost <= 0:
			continue
		var s := float(WEIGHTS[uid]) / float(cost)
		if float(cost) <= soon:
			best_soon = maxf(best_soon, s)
		if float(cost) > spend:
			continue
		if s > best_s:
			best_s = s
			best_id = uid
	# Si algo bastante mejor estará al alcance en ~1 min, se ahorra para eso.
	if best_id == "" or best_s < best_soon * 0.5:
		return
	var price := UpgradeManager.next_cost(best_id)
	if UpgradeManager.buy(best_id):
		var lvl := UpgradeManager.get_level(best_id)
		var txt := "%s COMPRA %s → nivel %d (%d $) [%s]" % [_ts(), GameData.UPGRADES[best_id]["name"], lvl, price, UpgradeManager.format_value(best_id, lvl)]
		purchases.append(txt)
		purchase_times.append(game_t)
		print("[BOT] ", txt)


## Busca el ángulo de lanzamiento: se prefiere una parábola alta ("globo") que caiga dentro del
## contenedor por encima del borde, como haría alguien tras un par de intentos.
func _throw_pitch(dist: float, dy: float) -> float:
	var F := float(UpgradeManager.get_value("bag_throw"))
	var best := 0.6
	var best_err := 1e9
	var dt := 1.0 / 60.0
	for k in 166:
		var th := 1.35 - k * 0.01
		var vx := F * cos(th)
		var vy := F * sin(th) + 2.5
		var x := 0.9 * cos(th)
		var y := 0.9 * sin(th) - 0.2
		for s in 400:
			vy -= 9.8 * dt
			vx *= 1.0 - 0.15 * dt
			vy *= 1.0 - 0.15 * dt
			x += vx * dt
			y += vy * dt
			if x >= dist:
				var e := absf(y - dy)
				# Mejor que caiga desde arriba (ángulo de bajada > 25°): no choca con el borde.
				if vy > -vx * 0.47:
					e += 0.25
				if e < best_err - 0.01:
					best_err = e
					best = th
				break
	return best


# =================================================================== navegación

func _build_nav() -> int:
	gw = terrain.gw
	gh = terrain.gh
	astar.region = Rect2i(0, 0, gw, gh)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	return _probe_rect(Rect2i(0, 0, gw, gh))


## Celda libre = una cápsula como la del jugador cabe ahí (dos esferas contra la capa del mundo).
func _probe_rect(r: Rect2i) -> int:
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s1 := SphereShape3D.new()
	s1.radius = 0.31
	q.shape = s1
	q.collision_mask = Interactable.LAYER_WORLD
	var q2 := PhysicsShapeQueryParameters3D.new()
	var s2 := SphereShape3D.new()
	s2.radius = 0.28
	q2.shape = s2
	q2.collision_mask = Interactable.LAYER_WORLD
	var secret := GameData.zone_index("taller_secreto") + 1
	var free := 0
	var x0 := maxi(r.position.x, 0)
	var z0 := maxi(r.position.y, 0)
	var x1 := mini(r.end.x, gw)
	var z1 := mini(r.end.y, gh)
	for j in range(z0, z1):
		for i in range(x0, x1):
			var c := j * gw + i
			var zc := terrain.cell_zone[c]
			var blocked := true
			if zc != 0 and zc != secret:
				var x := terrain.origin.x + (i + 0.5) * 0.5
				var z := terrain.origin.y + (j + 0.5) * 0.5
				var h := terrain.height_at(x, z)
				q.transform = Transform3D(Basis.IDENTITY, Vector3(x, h + 1.0, z))
				if space.intersect_shape(q, 1).is_empty():
					q2.transform = Transform3D(Basis.IDENTITY, Vector3(x, h + 0.48, z))
					blocked = not space.intersect_shape(q2, 1).is_empty()
			if learned.has(Vector2i(i, j)):
				blocked = true
			# Escalones de terreno demasiado empinados para subir (paredes de la piscina vacía...).
			if not blocked and i > 0 and j > 0 and i < gw - 1 and j < gh - 1:
				var hc := terrain.heights[j * terrain.hw + i]
				for nb in [1, -1, terrain.hw, -terrain.hw]:
					if absf(terrain.heights[j * terrain.hw + i + int(nb)] - hc) > 0.42:
						blocked = true
						break
			astar.set_point_solid(Vector2i(i, j), blocked)
			if not blocked:
				free += 1
	return free


func _cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor((pos.x - terrain.origin.x) * 2.0)), int(floor((pos.z - terrain.origin.y) * 2.0)))


func _inb(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < gw and c.y < gh


func _free(c: Vector2i) -> bool:
	return _inb(c) and not astar.is_point_solid(c)


func _center(c: Vector2i) -> Vector3:
	var x := terrain.origin.x + (c.x + 0.5) * 0.5
	var z := terrain.origin.y + (c.y + 0.5) * 0.5
	return Vector3(x, terrain.height_at(x, z), z)


func _free_near(c: Vector2i, rmax: int) -> Vector2i:
	if _free(c):
		return c
	for r in range(1, rmax + 1):
		var best := Vector2i(-1, -1)
		var bd := 1e9
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var cc := c + Vector2i(dx, dz)
				if _free(cc):
					var d := float(dx * dx + dz * dz)
					if d < bd:
						bd = d
						best = cc
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _path_to(to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a := _free_near(_cell(p.global_position), 4)
	var b := _free_near(_cell(to), 5)
	if a.x < 0 or b.x < 0:
		return out
	var ids: Array[Vector2i] = astar.get_id_path(a, b)
	for id in ids:
		out.append(_center(id))
	return out


func _path_len(pts: PackedVector3Array) -> float:
	var L := 0.0
	for k in range(1, pts.size()):
		L += _flat(pts[k - 1], pts[k])
	return L


func _plan(to: Vector3) -> bool:
	path = _path_to(to)
	path_i = 0
	path_goal = to
	return not path.is_empty()


func _line_free(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var length := d.length()
	var steps := int(length / 0.25) + 1
	for k in range(2, steps + 1):
		var t := float(k) / steps
		if not _free(_cell(Vector3(a.x + d.x * t, 0.0, a.z + d.y * t))):
			return false
	return true


## Sigue la ruta con "mirada adelantada" (el waypoint visible más lejano a < 7 m). true al llegar.
func _follow(arrive_r: float, speed: float) -> bool:
	var pos := p.global_position
	if _flat(pos, path_goal) <= arrive_r:
		return true
	if path.is_empty():
		return false
	# Avanza el índice hasta el waypoint más cercano por delante (nunca hacia atrás).
	var best_i := path_i
	var best_d := _flat(pos, path[path_i])
	for k in range(path_i + 1, mini(path.size(), path_i + 40)):
		var dk := _flat(pos, path[k])
		if dk < best_d:
			best_d = dk
			best_i = k
	path_i = best_i
	if path_i < path.size() - 1 and best_d < 0.7:
		path_i += 1
	if path_i >= path.size() - 1 and _flat(pos, path[path.size() - 1]) < 0.45:
		return true
	var ti := path_i
	for k in range(path_i, mini(path.size(), path_i + 18)):
		if _flat(pos, path[k]) <= 7.0 and _line_free(pos, path[k]):
			ti = k
	var wp := path[ti]
	var d := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	if d.length() < 0.05:
		return path_i >= path.size() - 1
	var remaining := _flat(pos, path_goal)
	_walk_dir(d.normalized(), speed if remaining > 3.0 else minf(speed, 0.6), true)
	return false


func _walk_dir(dir: Vector3, speed: float, face: bool) -> void:
	if face:
		look_on = true
		look_yaw = atan2(-dir.x, -dir.z)
		look_pitch = -0.2
	var b := p.global_transform.basis
	mv = Vector2(dir.dot(b.x), dir.dot(-b.z)) * minf(speed, WALK_MAX)


func _look_at(t: Vector3) -> float:
	var cp := p.cam.camera.global_position
	var d := t - cp
	look_on = true
	look_yaw = atan2(-d.x, -d.z)
	look_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), deg_to_rad(-80.0), deg_to_rad(78.0))
	return absf(wrapf(look_yaw - p.rotation.y, -PI, PI)) + absf(look_pitch - p.cam.pitch)


## Atascos: sin avanzar 6 s mientras se pide moverse → paso lateral + salto y aprender el obstáculo;
## 12 s → se registra STUCK y se da un empujón mínimo a la celda libre más cercana.
func _check_stuck(delta: float) -> void:
	var pos := p.global_position
	if mv.length() < 0.25 and unstick_t <= 0.0:
		stuck_t = 0.0
		stuck_anchor = pos
		unstick_tried = false
		return
	if _flat(pos, stuck_anchor) > 0.8:
		stuck_anchor = pos
		stuck_t = 0.0
		unstick_tried = false
		return
	stuck_t += delta
	if stuck_t > 6.0 and not unstick_tried:
		unstick_tried = true
		stuck_events += 1
		unstick_t = 0.9
		unstick_dir = 1.0 if randf() < 0.5 else -1.0
		jump = true
		var fwd := Vector3(InputState.move.x, 0, -InputState.move.y)
		var ahead := pos + p.global_transform.basis * fwd.normalized() * 0.6 if fwd.length() > 0.1 else pos - p.global_transform.basis.z * 0.6
		var ac := _cell(ahead)
		if _inb(ac) and ac != _cell(pos):
			learned[ac] = true
			astar.set_point_solid(ac, true)
		print("[BOT %s] sin avanzar 6 s en %s (estado %s): paso lateral + salto, recalculo ruta" % [_ts(), _v(pos), ST_NAMES[state]])
		if debug:
			var wp := path[path_i] if path_i < path.size() else Vector3.INF
			print("[DBG] ruta %d/%d wp %s meta %s mv %s vel %s yaw %.2f→%.2f suelo %s y %.2f" % [path_i, path.size(), _v(wp), _v(path_goal), str(InputState.move), str(p.velocity), p.rotation.y, look_yaw, str(p.is_on_floor()), p.global_position.y])
			for k in p.get_slide_collision_count():
				var col := p.get_slide_collision(k)
				var cobj := col.get_collider()
				print("[DBG]   choca con %s (%s) normal %s en %s" % [str(cobj), (cobj as Node).name if cobj is Node else "", str(col.get_normal()), str(col.get_position())])
		if path_goal != Vector3.INF and not path.is_empty():
			_plan(path_goal)
	elif stuck_t > 12.0:
		_issue("STUCK", "atascado >12 s en %s (estado %s, prompt «%s»)" % [_v(pos), ST_NAMES[state], p.prompt])
		var fc := _free_near(_cell(pos), 6)
		var cand := _center(fc) if fc.x >= 0 else pos
		if fc == _cell(pos) and not path.is_empty():
			cand = path[mini(path_i + 1, path.size() - 1)]
		p.global_position = Vector3(cand.x, terrain.height_at(cand.x, cand.z) + 0.15, cand.z)
		p.velocity = Vector3.ZERO
		nudges += 1
		stuck_t = 0.0
		unstick_tried = false
		stuck_anchor = p.global_position
		if path_goal != Vector3.INF:
			_plan(path_goal)


func _opportunistic() -> void:
	# Como un jugador: si al apuntar aparece una postal destapada, se recoge.
	if p.prompt == "Recoger postal" and not int_held:
		int_press = true


# =================================================================== eventos y registro

func _connect_events() -> void:
	EventBus.leaves_collected.connect(_on_leaves)
	EventBus.bag_changed.connect(_on_bag_changed)
	EventBus.bag_closed.connect(_on_bag_closed)
	EventBus.bag_delivered.connect(_on_bag_delivered)
	EventBus.upgrade_purchased.connect(_on_upgrade)
	EventBus.gate_opened.connect(_on_gate_opened)
	EventBus.zone_unlocked.connect(_on_zone_unlocked)
	EventBus.zone_reward.connect(_on_zone_reward)
	EventBus.zone_completed.connect(_on_zone_completed)
	EventBus.objective_completed.connect(_on_objective)
	EventBus.achievement_unlocked.connect(_on_achievement)
	EventBus.collectible_found.connect(_on_collectible)
	EventBus.hint.connect(_on_hint)
	EventBus.pile_created.connect(_on_pile)
	EventBus.tool_unlocked.connect(_on_tool_unlocked)
	EventBus.duct_repaired.connect(_on_duct)
	EventBus.game_saved.connect(_on_saved)


func _on_leaves(n: int, _source: String) -> void:
	leaves_total += n
	last_leaf_t = game_t
	_tl_first("first_leaf", "primer puñado de hojas (%d)" % n)
	if in_rake_cycle:
		rake_leaves += n
	else:
		hand_leaves += n


func _on_bag_changed(count: int, capacity: int) -> void:
	if count >= capacity and count > 0 and not cycle.has("full"):
		cycle["full"] = game_t
		_tl_first("first_full", "primera bolsa llena (%d hojas)" % count)


func _on_bag_closed(n: int) -> void:
	bags_closed += 1
	bag_was_thrown = false
	cycle["closed"] = game_t
	cycle["leaves"] = n
	close_pos = p.global_position
	_tl_first("first_close", "primera bolsa cerrada (%d hojas)" % n)


func _on_bag_delivered(n: int, money: float, distance: float) -> void:
	deliveries += 1
	delivered_flag = true
	cycle["delivered"] = game_t
	cycle["money"] = money
	cycle["leaves"] = n
	cycle["throw"] = distance
	cycle["walk"] = _flat(close_pos, p.global_position)
	cycles.append(cycle)
	_tl_first("first_delivery", "primera entrega: %d hojas → +%d $" % [n, int(money)])
	print("[BOT %s] entrega #%d: %d hojas → +%d $ %s" % [_ts(), deliveries, n, int(money), ("(lanzada %.1f m)" % distance) if distance > 0.0 else ""])
	cycle = {"start": game_t}


func _on_upgrade(id: String, level: int) -> void:
	_tl_first("first_upgrade", "primera mejora: %s nv %d" % [id, level])
	if id == "tool_rake":
		_tl("rastrillo comprado")


func _on_tool_unlocked(tool_id: String) -> void:
	_tl("herramienta desbloqueada: %s" % tool_id)


func _on_gate_opened(gate_id: String) -> void:
	var wait := ""
	if gate_req.has(gate_id):
		wait = " (%d s después de cumplir el requisito)" % int(game_t - float(gate_req[gate_id]))
	_tl("puerta abierta: %s%s" % [gate_id, wait])
	var g := GameData.gate_by_id(gate_id)
	if g.is_empty():
		return
	var gp: Vector2 = g["pos"]
	# La puerta deja de bloquear: volver a sondear la zona en el siguiente frame de física.
	_reprobe_later(gp)


func _reprobe_later(gp: Vector2) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var c := _cell(Vector3(gp.x, 0, gp.y))
	_probe_rect(Rect2i(c.x - 8, c.y - 8, 17, 17))


func _on_zone_unlocked(zid: String) -> void:
	_tl("zona desbloqueada: %s" % zid)
	_refresh_zones()


func _on_zone_reward(zid: String, threshold: int, text: String) -> void:
	_tl("%s al %d %%: %s" % [zid, threshold, text])


func _on_zone_completed(zid: String) -> void:
	var extra := ""
	if finish_start.has(zid):
		extra = " (del 90 %% al 100 %% en %d s)" % int(game_t - float(finish_start[zid]))
	_tl("ZONA COMPLETADA: %s%s" % [zid, extra])


func _on_objective(id: String) -> void:
	_tl("objetivo cumplido: %s" % id)


func _on_achievement(id: String) -> void:
	_tl("logro: %s" % id)


func _on_collectible(id: String) -> void:
	_tl("postal encontrada: %s" % id)


func _on_pile(size: int) -> void:
	_tl_first("first_pile", "primer montón reconocido por el juego (%d hojas)" % size)


func _on_duct(id: String) -> void:
	_tl("conducto reparado: %s" % id)


func _on_saved() -> void:
	saves += 1
	save_pending = true


func _on_hint(text: String) -> void:
	var n := int(hints.get(text, 0)) + 1
	hints[text] = n
	if n == 1:
		print("[BOT %s] aviso del juego: «%s»" % [_ts(), text])


func _ts() -> String:
	var t := int(game_t)
	return "%02d:%02d" % [t / 60, t % 60]


func _v(v: Vector3) -> String:
	return "(%.1f, %.1f)" % [v.x, v.z]


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _delta_safe() -> float:
	return 1.0 / 60.0 + 0.001


func _tl(text: String) -> void:
	var line := "%s %s" % [_ts(), text]
	timeline.append(line)
	print("[BOT] ", line)


func _tl_first(key: String, text: String) -> void:
	if firsts.has(key):
		return
	firsts[key] = game_t
	_tl(text)
	if key in ["first_leaf", "first_full", "first_rake", "first_delivery"]:
		_shot(key)


## Captura de lo que ve el jugador (solo con BOT_SHOTS=1 y render real: xvfb-run + opengl3).
func _shot(name: String) -> void:
	if not shots or shot_names.has(name):
		return
	shot_names[name] = true
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("user://bot_shots/%s_%s.png" % [_ts().replace(":", ""), name])
		print("[BOT %s] captura: %s" % [_ts(), name])


func _issue(kind: String, text: String) -> void:
	var n := int(issue_counts.get(kind, 0)) + 1
	issue_counts[kind] = n
	var line := "%s %s: %s" % [_ts(), kind, text]
	if n <= 6:
		issues.append(line)
	print("[BOT] ISSUE ", line)


func _zone_summary() -> String:
	var parts: Array[String] = []
	for z in GameData.ZONES:
		var zd: Dictionary = z
		if zd.get("secret", false) or not AreaManager.is_unlocked(zd["id"]):
			continue
		parts.append("%s %.1f%%" % [zd["id"], AreaManager.pct(zd["id"])])
	return ", ".join(parts)


func _minute_report() -> void:
	var earned := EconomyManager.total_earned
	var line := "min %02d · dinero %d $ (ganado %d, +%d este min) · hojas %d · bolsas %d · mano %d/toque · bolsa %d/%d · %s · herr. %s · estado %s · pos %s · %.0f s reales" % [
		int(game_t / 60.0), int(EconomyManager.money), int(earned), int(earned - earned_last_min), leaves_total, deliveries,
		int(UpgradeManager.get_value("hand")), p.bags.count, p.bags.capacity(), _zone_summary(), GameManager.current_tool,
		ST_NAMES[state], _v(p.global_position), (Time.get_ticks_msec() - wall0) / 1000.0]
	earned_last_min = earned
	minute_lines.append(line)
	print("[BOT] ", line)


# =================================================================== informe final

func _avg(key_a: String, key_b: String) -> float:
	var s := 0.0
	var n := 0
	for c in cycles:
		if c.has(key_a) and c.has(key_b):
			s += float(c[key_b]) - float(c[key_a])
			n += 1
	return s / n if n > 0 else 0.0


func _finish() -> void:
	state = St.END
	InputState.reset()
	print("\n==================== INFORME DEL BOT DE PLAYTEST ====================")
	print("Tiempo de juego: %s · tiempo real: %.0f s" % [_ts(), (Time.get_ticks_msec() - wall0) / 1000.0])
	print("Dinero: %d $ · ganado en total: %d $ · hojas recogidas: %d · bolsas entregadas: %d" % [int(EconomyManager.money), int(EconomyManager.total_earned), leaves_total, deliveries])
	print("Zonas: %s" % _zone_summary())
	print("\n-- Línea de tiempo --")
	for l in timeline:
		print("  ", l)
	print("\n-- Compras (%d) --" % purchases.size())
	for l in purchases:
		print("  ", l)
	var gaps: Array[String] = []
	var prev := 0.0
	var max_gap := 0.0
	for t in purchase_times:
		max_gap = maxf(max_gap, t - prev)
		gaps.append("%d" % int(t - prev))
		prev = t
	print("  intervalos entre compras (s): %s · mayor: %d s · desde la última: %d s" % [", ".join(gaps), int(max_gap), int(game_t - prev)])
	print("\n-- Cada minuto --")
	for l in minute_lines:
		print("  ", l)
	print("\n-- Ciclo de bolsa (medias) --")
	print("  llenar: %.1f s · cerrar: %.1f s · llevar al contenedor: %.1f s · bolsas: %d" % [_avg("start", "full"), _avg("full", "closed"), _avg("closed", "delivered"), cycles.size()])
	var walk := 0.0
	for c in cycles:
		walk += float(c.get("walk", 0.0))
	print("  distancia media hasta el contenedor: %.1f m · lanzamientos: %d (aciertos %d)" % [walk / maxf(cycles.size(), 1), throws, throws_ok])
	print("  toques de mano: %d (vacíos %d) · puntos descartados por obstáculo delante (banco, valla...): %d · últimos 10 toques: %s" % [taps, empty_taps, los_blocked, str(tap_hist)])
	print("  ritmo solo mano: %.1f hojas/min (%d hojas en %.0f s) · con rastrillo: %.1f hojas/min (%d hojas en %.0f s, %d ciclos, montones %s)" % [
		hand_leaves / maxf(hand_time / 60.0, 0.01), hand_leaves, hand_time, rake_leaves / maxf(rake_time / 60.0, 0.01), rake_leaves, rake_time, rake_cycles, str(pile_sizes)])
	print("  tiempo por estado (s): %s" % str(state_time))
	print("\n-- Avisos del juego (veces) --")
	for k in hints:
		print("  %3d × %s" % [int(hints[k]), k])
	print("  ventanas abiertas: %s" % str(notes_opened))
	print("\n-- Incidencias (%s) --" % str(issue_counts))
	for l in issues:
		print("  ", l)
	print("  atascos (6 s): %d · empujones (12 s): %d · celdas aprendidas como obstáculo: %d" % [stuck_events, nudges, learned.size()])
	print("\n-- Auditoría de hojas dentro de objetos --")
	print("  ", audit_text)
	for l in audit_where:
		print("  ", l)
	print("\n-- Motor --")
	print("  errores: %d · avisos: %d · guardados: %d (frame con guardado: media %.1f ms, máx %.1f ms) · máx. hojas activas: %d · frame más lento (headless): %.1f ms · frames > 50 ms: %d" % [logger.errors, logger.warnings, saves, save_frame_sum / maxf(save_frames, 1), save_frame_max, max_active, frame_wall_max, slow_frames])
	for l in logger.lines:
		print("  ", l)
	if finish_zone != "":
		_dump_remaining(finish_zone)
	var report := {
		"game_time": game_t, "money": EconomyManager.money, "earned": EconomyManager.total_earned,
		"leaves": leaves_total, "deliveries": deliveries, "zones": _zone_summary(), "timeline": timeline,
		"purchases": purchases, "minutes": minute_lines, "issues": issues, "issue_counts": issue_counts,
		"errors": logger.lines, "hints": hints, "stuck": stuck_events, "nudges": nudges,
		"hand_rate": hand_leaves / maxf(hand_time / 60.0, 0.01), "rake_rate": rake_leaves / maxf(rake_time / 60.0, 0.01),
		"cycle_fill": _avg("start", "full"), "cycle_close": _avg("full", "closed"), "cycle_deliver": _avg("closed", "delivered"),
		"throws": throws, "throws_ok": throws_ok, "state_time": state_time, "audit": audit_text, "audit_where": audit_where,
	}
	var f := FileAccess.open("user://playtest_report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("=== PLAYTEST FIN: %d errores, %d avisos, %d atascos ===" % [logger.errors, logger.warnings, nudges])
	get_tree().quit(0)
