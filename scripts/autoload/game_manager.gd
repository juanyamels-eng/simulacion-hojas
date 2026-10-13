extends Node
## Estado global de la partida, modos de juego y ciclo de vida Android (pausa, reanudar, guardar).

const MODES := ["campaign", "zen", "time_attack", "ngplus"]

var mode := "campaign"
var in_game := false
var requested_new := false
var skip_menu := false
var time_attack_zone := ""
var ngplus_level := 0
var player_state := {}       # posición/rotación guardadas
var current_tool := "hand"
var world: Node = null       # referencia al mundo activo (la asigna World)
var _pending_upgrades := {}
var _time_acc := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.register("game", self)
	get_tree().set_auto_accept_quit(false)
	if not SaveManager.has_save("campaign"):
		requested_new = true


func is_zen() -> bool:
	return mode == "zen"


func is_time_attack() -> bool:
	return mode == "time_attack"


func reward_multiplier() -> float:
	return 1.0 + 1.0 * ngplus_level


func cost_multiplier() -> float:
	return 1.0


func leaf_multiplier() -> float:
	return 1.0 + 0.5 * ngplus_level


func slot_for_mode(m: String) -> String:
	match m:
		"zen": return "zen"
		"time_attack": return "time_attack"
	return "campaign"


## Prepara una partida y recarga la escena principal.
func launch(new_mode: String, new_game: bool, zone: String = "") -> void:
	if in_game:
		SaveManager.save_game()
	in_game = false
	mode = new_mode
	time_attack_zone = zone
	SaveManager.slot = slot_for_mode(new_mode)
	if new_game:
		var keep_upgrades := {}
		if new_mode == "ngplus":
			keep_upgrades = UpgradeManager.levels.duplicate()
		SaveManager.delete_slot(SaveManager.slot)
		if new_mode == "ngplus":
			ngplus_level += 1
			_pending_upgrades = keep_upgrades
			mode = "campaign"
	requested_new = new_game or not SaveManager.has_save()
	skip_menu = true
	get_tree().paused = false
	get_tree().reload_current_scene()


## Reinicia todos los gestores para una partida nueva.
func reset_managers() -> void:
	EconomyManager.reset()
	UpgradeManager.reset()
	AreaManager.reset()
	ProgressManager.reset()
	ObjectiveManager.reset()
	CollectibleManager.reset()
	player_state = {}
	current_tool = "hand"
	if not _pending_upgrades.is_empty():
		UpgradeManager.levels = _pending_upgrades
		_pending_upgrades = {}
	if mode == "zen":
		UpgradeManager.max_all()
		for z in GameData.ZONES:
			if not z.get("secret", false):
				AreaManager.unlocked[z["id"]] = true
		for g in GameData.GATES:
			AreaManager.gates_open[g["id"]] = true
		EconomyManager.money = 999999.0
	elif mode == "time_attack":
		for id in ["hand", "bag_capacity", "bag_close", "tool_rake", "rake_width", "rake_capacity", "tool_blower", "blower_power", "blower_range", "tool_vacuum", "vacuum_radius", "move_speed", "sprint", "stamina"]:
			UpgradeManager.levels[id] = mini(2, UpgradeManager.max_level(id))
		for id in ["tool_rake", "tool_blower", "tool_vacuum", "hand"]:
			UpgradeManager.levels[id] = UpgradeManager.max_level(id)
		AreaManager.unlocked[time_attack_zone] = true


func start_playing() -> void:
	in_game = true
	skip_menu = false
	ObjectiveManager.recheck()
	AudioManager.start_ambience()


func _process(delta: float) -> void:
	if not in_game or get_tree().paused:
		return
	_time_acc += delta
	if _time_acc >= 1.0:
		ProgressManager.add_stat("play_time", _time_acc)
		_time_acc = 0.0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if in_game:
				SaveManager.save_game()
				EventBus.open_menu.emit("pause_if_playing")
		NOTIFICATION_WM_CLOSE_REQUEST:
			if in_game:
				SaveManager.save_game()
			get_tree().quit()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			EventBus.open_menu.emit("back")


func quit_game() -> void:
	if in_game:
		SaveManager.save_game()
	get_tree().quit()


func to_save() -> Dictionary:
	if world != null and is_instance_valid(world) and world.has_method("get_player_state"):
		player_state = world.get_player_state()
	return {"mode": mode, "ngplus": ngplus_level, "player": player_state, "tool": current_tool}


func from_save(d: Dictionary) -> void:
	ngplus_level = int(d.get("ngplus", 0))
	player_state = d.get("player", {})
	current_tool = String(d.get("tool", "hand"))
