extends Node
## Árbol de mejoras. Los niveles se guardan; los valores salen de GameData.UPGRADES.

var levels := {}


func _ready() -> void:
	SaveManager.register("upgrades", self)


func reset() -> void:
	levels.clear()


func get_level(id: String) -> int:
	return int(levels.get(id, 0))


func max_level(id: String) -> int:
	return GameData.UPGRADES[id]["costs"].size()


func get_value(id: String) -> Variant:
	var def: Dictionary = GameData.UPGRADES[id]
	var vals: Array = def["values"]
	return vals[clampi(get_level(id), 0, vals.size() - 1)]


func next_cost(id: String) -> int:
	var lvl := get_level(id)
	var costs: Array = GameData.UPGRADES[id]["costs"]
	if lvl >= costs.size():
		return -1
	return int(round(costs[lvl] * GameManager.cost_multiplier()))


func is_maxed(id: String) -> bool:
	return get_level(id) >= max_level(id)


## Devuelve "" si se puede comprar (aparte del dinero) o el motivo del bloqueo.
func lock_reason(id: String) -> String:
	var def: Dictionary = GameData.UPGRADES[id]
	if def.has("requires") and get_level(def["requires"]) <= 0:
		return "Requiere: " + GameData.UPGRADES[def["requires"]]["name"]
	if def.has("requires_zone") and not AreaManager.is_unlocked(def["requires_zone"]):
		return "Desbloquea: " + GameData.zone_by_id(def["requires_zone"])["name"]
	if def.has("requires_flag") and not ProgressManager.has_flag(def["requires_flag"]):
		return "Encuentra algo escondido en la finca…"
	return ""


func can_buy(id: String) -> bool:
	return not is_maxed(id) and lock_reason(id) == "" and EconomyManager.can_afford(next_cost(id))


func buy(id: String) -> bool:
	if is_maxed(id) or lock_reason(id) != "":
		return false
	var cost := next_cost(id)
	if not EconomyManager.spend(cost):
		return false
	levels[id] = get_level(id) + 1
	ProgressManager.add_stat("upgrades_bought", 1)
	EventBus.upgrade_purchased.emit(id, levels[id])
	for t in GameData.TOOLS:
		if t["unlock"] == id:
			EventBus.tool_unlocked.emit(t["id"])
	AudioManager.play_ui("purchase")
	HapticManager.pulse(40, 0.6)
	SaveManager.request_save()
	return true


func has_tool(tool_id: String) -> bool:
	for t in GameData.TOOLS:
		if t["id"] == tool_id:
			return t["unlock"] == "" or get_level(t["unlock"]) > 0
	return false


func owned_tools() -> Array:
	var out := []
	for t in GameData.TOOLS:
		if has_tool(t["id"]):
			out.append(t["id"])
	return out


## Pone todas las mejoras al máximo (modo Zen).
func max_all() -> void:
	for id in GameData.UPGRADES:
		if GameData.UPGRADES[id].get("requires_flag", "") != "":
			continue
		levels[id] = max_level(id)


## Texto legible del valor de una mejora en un nivel.
func format_value(id: String, lvl: int) -> String:
	var def: Dictionary = GameData.UPGRADES[id]
	var vals: Array = def["values"]
	var v: Variant = vals[clampi(lvl, 0, vals.size() - 1)]
	var fmt: String = def["fmt"]
	match fmt:
		"tool":
			return "Conseguido" if int(v) > 0 else "—"
		"pct":
			return "%d %%" % int(round(float(v) * 100.0))
		"stamina":
			return "Infinita" if float(v) > 900.0 else "%.0f s" % float(v)
		"hand":
			if lvl >= 5:
				return "12 · radio x2"
			if lvl >= 4:
				return "12 · continuo"
			return "%d hojas" % int(v)
	return fmt % v


func to_save() -> Dictionary:
	return levels.duplicate()


func from_save(d: Dictionary) -> void:
	levels.clear()
	for k in d:
		if GameData.UPGRADES.has(k):
			levels[k] = clampi(int(d[k]), 0, max_level(k))
