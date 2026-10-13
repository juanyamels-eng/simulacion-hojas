extends Node
## Estado de las zonas: desbloqueos, hojas restantes, porcentaje y recompensas por umbral.

var unlocked := {}
var initial := {}        # zona -> hojas iniciales
var remaining := {}      # zona -> hojas restantes (lo actualiza el LeafManager)
var claimed := {}        # zona -> Array de umbrales cobrados
var gates_open := {}
var ducts := {}
var blower_used := {}
var completed := {}
var current_zone := ""
var speed_bonus := 0.0


func _ready() -> void:
	SaveManager.register("areas", self)
	reset()


func reset() -> void:
	unlocked = {"entrada": true}
	claimed.clear()
	gates_open.clear()
	ducts.clear()
	blower_used.clear()
	completed.clear()
	speed_bonus = 0.0
	current_zone = ""


func is_unlocked(zone_id: String) -> bool:
	return unlocked.get(zone_id, false)


func pct(zone_id: String) -> float:
	var init := int(initial.get(zone_id, 0))
	if init <= 0:
		return 100.0
	var rem := int(remaining.get(zone_id, init))
	if rem <= 0:
		return 100.0
	# Nunca mostrar 100 % mientras quede una sola hoja.
	return minf(floor((1.0 - float(rem) / float(init)) * 1000.0) / 10.0, 99.9)


func zone_at(pos: Vector3) -> String:
	var p := Vector2(pos.x, pos.z)
	for z in GameData.ZONES:
		if (z["rect"] as Rect2).has_point(p):
			return z["id"]
	return ""


## Llamado periódicamente por el LeafManager con el recuento por zona.
func update_counts(counts: PackedInt32Array, initial_counts: PackedInt32Array) -> void:
	for i in GameData.ZONES.size():
		var zid: String = GameData.ZONES[i]["id"]
		initial[zid] = initial_counts[i]
		var before := int(remaining.get(zid, -1))
		remaining[zid] = counts[i]
		if before != counts[i]:
			EventBus.zone_progress.emit(zid, pct(zid))
			_check_rewards(zid)


func _check_rewards(zid: String) -> void:
	if not GameManager.in_game or GameManager.is_time_attack():
		return
	var p := pct(zid)
	var done: Array = claimed.get(zid, [])
	for threshold in [25, 50, 75, 100]:
		if done.has(threshold):
			continue
		var reached: bool = (int(remaining.get(zid, 1)) <= 0) if threshold == 100 else p >= float(threshold)
		if not reached:
			continue
		done.append(threshold)
		claimed[zid] = done
		_apply_reward(zid, threshold)


func _apply_reward(zid: String, threshold: int) -> void:
	var r: Dictionary = GameData.ZONE_REWARDS[threshold]
	var z := GameData.zone_by_id(zid)
	var text: String = r["text"]
	match r["type"]:
		"money":
			var amount: float = float(z["leaves"]) * float(z["value"]) * float(r["mult"]) * GameManager.reward_multiplier()
			EconomyManager.add_money(amount)
			text = "%s: +%s" % [text, EconomyManager.format_money(amount)]
		"value":
			EconomyManager.value_bonus += float(r["amount"])
		"speed":
			speed_bonus += float(r["amount"])
	if threshold == 100:
		completed[zid] = true
		ProgressManager.set_stat("zones_completed", float(completed_main_count()))
		if not blower_used.get(zid, false):
			ProgressManager.add_stat("zones_no_blower", 1)
		EventBus.zone_completed.emit(zid)
	EventBus.zone_reward.emit(zid, threshold, text)
	EventBus.toast.emit("%s · %d %%" % [z["name"], threshold], text, "reward")
	AudioManager.play_ui("reward")
	HapticManager.pulse(60, 0.7)
	SaveManager.request_save()


func completed_main_count() -> int:
	var n := 0
	for z in GameData.ZONES:
		if not z.get("secret", false) and completed.get(z["id"], false):
			n += 1
	return n


func mark_blower_used(zid: String) -> void:
	if zid != "":
		blower_used[zid] = true


func unlock_zone(zid: String) -> void:
	if unlocked.get(zid, false):
		return
	unlocked[zid] = true
	EventBus.zone_unlocked.emit(zid)


func open_gate(gate_id: String) -> void:
	if gates_open.get(gate_id, false):
		return
	gates_open[gate_id] = true
	var g := GameData.gate_by_id(gate_id)
	if not g.is_empty():
		unlock_zone(g["b"])
	EventBus.gate_opened.emit(gate_id)
	# Los atajos se abren solos cuando sus dos zonas están desbloqueadas.
	for other in GameData.GATES:
		if other.get("auto", false) and not gates_open.get(other["id"], false):
			if is_unlocked(other["a"]) and is_unlocked(other["b"]):
				gates_open[other["id"]] = true
				EventBus.gate_opened.emit(other["id"])
	SaveManager.request_save()


func set_current_zone(zid: String) -> void:
	if zid != current_zone:
		current_zone = zid
		EventBus.zone_entered.emit(zid)


func to_save() -> Dictionary:
	return {"unlocked": unlocked, "claimed": claimed, "gates": gates_open, "ducts": ducts,
		"blower": blower_used, "completed": completed, "speed": speed_bonus}


func from_save(d: Dictionary) -> void:
	reset()
	unlocked = d.get("unlocked", {"entrada": true})
	claimed = d.get("claimed", {})
	# JSON devuelve números como float: normalizamos los umbrales.
	for k in claimed:
		var arr := []
		for v in claimed[k]:
			arr.append(int(v))
		claimed[k] = arr
	gates_open = d.get("gates", {})
	ducts = d.get("ducts", {})
	blower_used = d.get("blower", {})
	completed = d.get("completed", {})
	speed_bonus = float(d.get("speed", 0.0))
