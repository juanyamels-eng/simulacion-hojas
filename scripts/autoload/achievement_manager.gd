extends Node
## Logros internos guardados localmente (globales a todas las partidas).
## report_platform() es el punto de conexión para Google Play Games en el futuro.

const PATH := "user://achievements.cfg"

var unlocked := {}


func _ready() -> void:
	_load()
	EventBus.stat_changed.connect(_on_stat)
	EventBus.upgrade_purchased.connect(_on_upgrade)
	EventBus.zone_completed.connect(func(_z): _check_zones())
	EventBus.bag_delivered.connect(_on_bag_delivered)
	EventBus.pile_created.connect(_on_pile)
	EventBus.duct_repaired.connect(func(_d): unlock("duct"))


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func unlock(id: String) -> void:
	if unlocked.has(id) or GameManager.is_zen():
		return
	var def := _def(id)
	if def.is_empty():
		return
	unlocked[id] = Time.get_unix_time_from_system()
	_save()
	EventBus.achievement_unlocked.emit(id)
	EventBus.toast.emit("Logro desbloqueado", "%s — %s" % [def["name"], def["desc"]], "achievement")
	AudioManager.play_ui("achievement")
	HapticManager.pulse(50, 0.6)
	report_platform(id)


func report_platform(_id: String) -> void:
	# Integración futura: si existe un plugin de Play Games, aquí se enviaría el logro.
	pass


func _def(id: String) -> Dictionary:
	for a in GameData.ACHIEVEMENTS:
		if a["id"] == id:
			return a
	return {}


func _on_stat(key: String, v: float) -> void:
	match key:
		"leaves_collected":
			if v >= 1: unlock("first_leaf")
			if v >= 1000: unlock("leaves_1k")
			if v >= 10000: unlock("leaves_10k")
			if v >= 30000: unlock("leaves_30k")
		"bags_delivered":
			if v >= 1: unlock("first_bag")
		"bags_used":
			if v >= 50: unlock("bags_50")
		"money_earned":
			if v >= 10000: unlock("money_10k")
			if v >= 100000: unlock("money_100k")
		"upgrades_bought":
			if v >= 10: unlock("upgrades_10")
			if v >= 40: unlock("upgrades_40")
		"leaves_blown":
			if v >= 5000: unlock("blown_5k")
		"leaves_vacuumed":
			if v >= 5000: unlock("vacuumed_5k")
		"postcards":
			if v >= 1: unlock("postcard_1")
			if v >= 12: unlock("postcards_12")
		"tools_used":
			if v >= GameData.TOOLS.size(): unlock("all_tools")
		"zones_no_blower":
			if v >= 1: unlock("no_blower_zone")
		"play_time":
			if v >= 3600: unlock("play_hour")
		"dog_pets":
			if v >= 1: unlock("pet_dog")
			if v >= 25: unlock("pet_dog_25")


func _on_upgrade(id: String, _lvl: int) -> void:
	match id:
		"tool_rake": unlock("got_rake")
		"tool_blower": unlock("got_blower")
		"tool_vacuum": unlock("got_vacuum")
		"tool_industrial": unlock("got_industrial")


func _on_bag_delivered(_leaves: int, _money: float, dist: float) -> void:
	if dist >= 8.0:
		unlock("long_throw")


func _on_pile(size: int) -> void:
	if size >= 200: unlock("pile_200")
	if size >= 500: unlock("pile_500")


func _check_zones() -> void:
	var n := AreaManager.completed_main_count()
	if n >= 1: unlock("zone_100")
	if n >= 5: unlock("zones_5")
	if n >= 10: unlock("zones_10")


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in unlocked:
		cfg.set_value("unlocked", k, unlocked[k])
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK or not cfg.has_section("unlocked"):
		return
	for k in cfg.get_section_keys("unlocked"):
		unlocked[k] = cfg.get_value("unlocked", k)
