extends Node
## Dinero, multiplicadores y transacciones.

var money := 0.0
var total_earned := 0.0
var value_bonus := 0.0   # bonificaciones permanentes por recompensas de zona


func _ready() -> void:
	SaveManager.register("economy", self)


func reset() -> void:
	money = 0.0
	total_earned = 0.0
	value_bonus = 0.0
	EventBus.money_changed.emit(money)


func multiplier() -> float:
	return float(UpgradeManager.get_value("leaf_value")) * (1.0 + value_bonus) * GameManager.reward_multiplier()


## Convierte el valor base de unas hojas en dinero. Devuelve lo ganado.
func deposit_leaves(base_value: float, world_pos: Vector3 = Vector3.INF) -> float:
	var amount := base_value * multiplier()
	add_money(amount, world_pos)
	return amount


func add_money(amount: float, world_pos: Vector3 = Vector3.INF) -> void:
	if amount <= 0.0:
		return
	money += amount
	total_earned += amount
	ProgressManager.set_stat("money_earned", total_earned)
	EventBus.money_changed.emit(money)
	EventBus.money_earned.emit(amount, world_pos)


func can_afford(cost: float) -> bool:
	return GameManager.is_zen() or money >= cost


func spend(cost: float) -> bool:
	if GameManager.is_zen():
		return true
	if money < cost:
		return false
	money -= cost
	EventBus.money_changed.emit(money)
	SaveManager.request_save()
	return true


static func format_money(v: float) -> String:
	var n := int(floor(v))
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out + " $"


func to_save() -> Dictionary:
	return {"money": money, "total": total_earned, "bonus": value_bonus}


func from_save(d: Dictionary) -> void:
	money = float(d.get("money", 0.0))
	total_earned = float(d.get("total", 0.0))
	value_bonus = float(d.get("bonus", 0.0))
	EventBus.money_changed.emit(money)
