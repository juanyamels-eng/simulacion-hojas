class_name GateDoor
extends Interactable
## Puerta entre zonas. Se compra cuando la zona anterior alcanza el porcentaje requerido.

var gate: Dictionary
var opened := false
var _left: Node3D
var _right: Node3D
var _shape: CollisionShape3D
var _label: Label3D


func setup(def: Dictionary) -> void:
	gate = def
	collision_layer = LAYER_WORLD | LAYER_INTERACT
	var along_x: bool = def["axis"] == "x"
	var wood := MeshFactory.mat(Color(0.45, 0.28, 0.15))
	var dark := MeshFactory.mat(Color(0.25, 0.17, 0.1))
	for side in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 1.6, 0, 0)
		add_child(pivot)
		for k in 5:
			var plank := MeshInstance3D.new()
			plank.mesh = MeshFactory.box(Vector3(0.26, 1.5, 0.08))
			plank.material_override = wood
			plank.position = Vector3(-side * (0.18 + k * 0.29), 0.85, 0)
			pivot.add_child(plank)
		for y in [0.45, 1.3]:
			var rail := MeshInstance3D.new()
			rail.mesh = MeshFactory.box(Vector3(1.5, 0.12, 0.1))
			rail.material_override = dark
			rail.position = Vector3(-side * 0.78, y, 0.06)
			pivot.add_child(rail)
		if side < 0:
			_left = pivot
		else:
			_right = pivot
	for side in [-1, 1]:
		var post := MeshInstance3D.new()
		post.mesh = MeshFactory.box(Vector3(0.3, 2.0, 0.3))
		post.material_override = dark
		post.position = Vector3(side * 1.75, 1.0, 0)
		add_child(post)
	_shape = make_shape(self, Vector3(3.2, 2.0, 0.4), Vector3(0, 1.0, 0))
	if not def.get("auto", false):
		_label = Label3D.new()
		_label.position = Vector3(0, 2.35, 0)
		_label.pixel_size = 0.0055
		_label.font_size = 48
		_label.outline_size = 12
		_label.modulate = Color(1.0, 0.95, 0.85)
		_label.outline_modulate = Color(0.25, 0.14, 0.07)
		_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_label.double_sided = true
		add_child(_label)
	if not along_x:
		rotation.y = PI * 0.5
	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	var zb := GameData.zone_by_id(gate["b"])
	_label.text = "%s\n%s" % [zb["name"], EconomyManager.format_money(gate["cost"])]


func requirement_met() -> bool:
	if gate.get("auto", false):
		return false
	return AreaManager.is_unlocked(gate["a"]) and AreaManager.pct(gate["req"]) >= float(gate["pct"])


func get_prompt(_player: Node) -> String:
	if opened:
		return ""
	if gate.get("auto", false):
		return "Atajo cerrado"
	var zr := GameData.zone_by_id(gate["req"])
	if not requirement_met():
		return "Limpia %s al %d %%" % [zr["name"], int(gate["pct"])]
	return "Abrir %s · %s" % [GameData.zone_by_id(gate["b"])["name"], EconomyManager.format_money(gate["cost"])]


func is_available(_player: Node) -> bool:
	return not opened and requirement_met() and EconomyManager.can_afford(gate["cost"])


func interact(_player: Node) -> void:
	if not is_available(_player):
		AudioManager.play_ui("error")
		return
	if EconomyManager.spend(gate["cost"]):
		AreaManager.open_gate(gate["id"])
		EventBus.toast.emit("Nueva zona", GameData.zone_by_id(gate["b"])["name"], "reward")


func open_visual(animated: bool) -> void:
	if opened:
		return
	opened = true
	_shape.disabled = true
	collision_layer = 0
	if _label:
		_label.visible = false
	if animated:
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_left, "rotation:y", -1.75, 1.2)
		tw.tween_property(_right, "rotation:y", 1.75, 1.2)
		AudioManager.play_sfx("gate_open", global_position)
	else:
		_left.rotation.y = -1.75
		_right.rotation.y = 1.75
