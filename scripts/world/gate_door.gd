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
	# Cada hoja y el par de postes son una sola malla fusionada (3 llamadas de dibujo por puerta).
	for side in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 1.6, 0, 0)
		add_child(pivot)
		var leaf := MeshInstance3D.new()
		leaf.mesh = MeshFactory.prefab("gate_leaf_%d" % side, _leaf_parts.bind(side))
		leaf.material_override = MeshFactory.prop_mat(true)
		pivot.add_child(leaf)
		if side < 0:
			_left = pivot
		else:
			_right = pivot
	var posts := MeshInstance3D.new()
	posts.mesh = MeshFactory.prefab("gate_posts", _post_parts)
	posts.material_override = MeshFactory.prop_mat(true)
	add_child(posts)
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


## Hoja de puerta: tablas con punta en arco, travesaños, tornapuntas, bisagras de hierro y aldaba.
func _leaf_parts(side: int) -> Array:
	var wood := MeshFactory.pc(Color(0.52, 0.33, 0.18), MeshFactory.PAT_WOOD, true)
	var dark := MeshFactory.pc(Color(0.3, 0.2, 0.12), MeshFactory.PAT_WOOD)
	var iron := MeshFactory.pc(Color(0.15, 0.15, 0.16), MeshFactory.PAT_METAL)
	var p := []
	var s := float(side)
	for k in 5:
		var h := 1.5 + 0.07 * k
		var tint := 0.92 + 0.08 * float((k * 7) % 3) / 2.0
		p.append(MeshFactory.part("picket", Vector3(-s * (0.18 + k * 0.29), 0.1 + h * 0.5, 0), Vector3(0.27, h, 0.07),
			Color(wood.r * tint, wood.g * tint, wood.b * tint, wood.a)))
	for y in [0.42, 1.25]:
		p.append(MeshFactory.part("box", Vector3(-s * 0.78, y, 0.065), Vector3(1.5, 0.11, 0.07), dark))
	var ang := atan2(0.78, -s * 1.2)
	p.append(MeshFactory.part("box", Vector3(-s * 0.8, 0.835, 0.065), Vector3(1.43, 0.1, 0.06), dark, Basis(Vector3.BACK, ang)))
	for y in [0.42, 1.25]:
		p.append(MeshFactory.part("box", Vector3(-s * 0.28, y, 0.105), Vector3(0.5, 0.06, 0.02), iron))
		p.append(MeshFactory.part("cyl", Vector3(-s * 0.02, y, 0.05), Vector3(0.06, 0.16, 0.06), iron))
	if side > 0:
		p.append(MeshFactory.part("ring", Vector3(-1.3, 0.95, 0.12), Vector3(0.22, 0.25, 0.22), iron, Basis(Vector3.RIGHT, PI * 0.5)))
		p.append(MeshFactory.part("cyl", Vector3(-1.3, 1.03, 0.1), Vector3(0.05, 0.05, 0.05), iron, Basis(Vector3.RIGHT, PI * 0.5)))
	return p


func _post_parts() -> Array:
	var post := MeshFactory.pc(Color(0.3, 0.2, 0.12), MeshFactory.PAT_WOOD, true)
	var cap := MeshFactory.pc(Color(0.26, 0.17, 0.1), MeshFactory.PAT_PLAIN)
	var p := []
	for side in [-1.0, 1.0]:
		var x: float = side * 1.75
		p.append(MeshFactory.part("box", Vector3(x, 1.05, 0), Vector3(0.3, 2.1, 0.3), post))
		p.append(MeshFactory.part("box", Vector3(x, 2.12, 0), Vector3(0.38, 0.06, 0.38), cap))
		p.append(MeshFactory.part("cone4", Vector3(x, 2.25, 0), Vector3(0.42, 0.2, 0.42), cap, Basis(Vector3.UP, PI * 0.25)))
		p.append(MeshFactory.part("sph", Vector3(x, 2.38, 0), Vector3(0.1, 0.1, 0.1), cap))
		p.append(MeshFactory.part("box", Vector3(x, 0.08, 0), Vector3(0.36, 0.16, 0.36), MeshFactory.pc(Color(0.55, 0.52, 0.47), MeshFactory.PAT_STONE)))
	return p


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
