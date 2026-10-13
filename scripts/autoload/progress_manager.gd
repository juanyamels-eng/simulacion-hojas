extends Node
## Estadísticas, banderas de progreso y tutorial contextual.

var stats := {}
var flags := {}
var tools_used := {}
var tutorial_step := 0

const STAT_NAMES := {
	"leaves_collected": "Hojas recogidas",
	"leaves_blown": "Hojas sopladas",
	"leaves_vacuumed": "Hojas aspiradas",
	"leaves_raked": "Hojas rastrilladas",
	"bags_used": "Bolsas utilizadas",
	"bags_delivered": "Bolsas entregadas",
	"money_earned": "Dinero conseguido",
	"zones_completed": "Zonas completadas",
	"upgrades_bought": "Mejoras compradas",
	"max_pile": "Mayor montón",
	"long_throws": "Canastas lejanas",
	"ducts_repaired": "Conductos reparados",
	"postcards": "Postales encontradas",
	"play_time": "Tiempo jugado",
}


func _ready() -> void:
	SaveManager.register("progress", self)


func reset() -> void:
	stats.clear()
	flags.clear()
	tools_used.clear()
	tutorial_step = 0


func get_stat(key: String) -> float:
	return float(stats.get(key, 0.0))


func add_stat(key: String, amount: float) -> void:
	set_stat(key, get_stat(key) + amount)


func set_stat(key: String, value: float) -> void:
	stats[key] = value
	EventBus.stat_changed.emit(key, value)


func set_max(key: String, value: float) -> void:
	if value > get_stat(key):
		set_stat(key, value)


func has_flag(f: String) -> bool:
	return flags.get(f, false)


func set_flag(f: String) -> void:
	flags[f] = true


func mark_tool_used(tool_id: String) -> void:
	if tools_used.has(tool_id):
		return
	tools_used[tool_id] = true
	set_stat("tools_used", tools_used.size())


func to_save() -> Dictionary:
	return {"stats": stats, "flags": flags, "tools": tools_used, "tutorial": tutorial_step}


func from_save(d: Dictionary) -> void:
	reset()
	stats = d.get("stats", {})
	flags = d.get("flags", {})
	tools_used = d.get("tools", {})
	tutorial_step = int(d.get("tutorial", 0))


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d h %02d min" % [s / 3600, (s / 60) % 60]
