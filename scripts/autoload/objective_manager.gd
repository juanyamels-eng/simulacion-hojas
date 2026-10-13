extends Node
## Objetivos secundarios: se comprueban al cambiar estadísticas y dan dinero al completarse.

var done := {}


func _ready() -> void:
	SaveManager.register("objectives", self)
	EventBus.stat_changed.connect(_on_stat)


func reset() -> void:
	done.clear()


func progress(obj: Dictionary) -> float:
	return clampf(ProgressManager.get_stat(obj["stat"]) / float(obj["target"]), 0.0, 1.0)


func _on_stat(key: String, _value: float) -> void:
	if not GameManager.in_game or GameManager.is_zen() or GameManager.is_time_attack():
		return
	for obj in GameData.OBJECTIVES:
		if obj["stat"] != key or done.get(obj["id"], false):
			continue
		if ProgressManager.get_stat(key) >= float(obj["target"]):
			done[obj["id"]] = true
			var reward := float(obj["reward"]) * GameManager.reward_multiplier()
			EconomyManager.add_money(reward)
			EventBus.objective_completed.emit(obj["id"])
			EventBus.toast.emit("Objetivo cumplido", "%s  +%s" % [obj["name"], EconomyManager.format_money(reward)], "objective")
			AudioManager.play_ui("reward")
			SaveManager.request_save()


## Siguientes objetivos pendientes (para el HUD y el diario).
func pending(limit: int = 3) -> Array:
	var out := []
	for obj in GameData.OBJECTIVES:
		if not done.get(obj["id"], false):
			out.append(obj)
			if out.size() >= limit:
				break
	return out


func to_save() -> Dictionary:
	return done.duplicate()


func from_save(d: Dictionary) -> void:
	done = d.duplicate()
