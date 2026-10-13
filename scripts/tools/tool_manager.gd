class_name ToolManager
extends Node
## Gestiona las herramientas desbloqueadas y el cambio rápido entre ellas.

var player: PlayerController
var tools := {}
var current: BaseTool


func setup(p: PlayerController) -> void:
	player = p
	for t in [HandTool.new(), RakeTool.new(), BlowerTool.new(), VacuumTool.new(), IndustrialBlowerTool.new()]:
		t.setup(p)
		t.attach_parent().add_child(t)
		tools[t.tool_id] = t
	EventBus.tool_unlocked.connect(_on_unlocked)
	var start := GameManager.current_tool
	select(start if UpgradeManager.has_tool(start) else "hand", false)


func _on_unlocked(tool_id: String) -> void:
	select(tool_id)
	EventBus.toast.emit("Nueva herramienta", _tool_name(tool_id), "reward")


func _tool_name(id: String) -> String:
	for t in GameData.TOOLS:
		if t["id"] == id:
			return t["name"]
	return id


func select(tool_id: String, sound: bool = true) -> void:
	if not tools.has(tool_id) or not UpgradeManager.has_tool(tool_id):
		return
	if current and current.tool_id == tool_id:
		return
	if current:
		current.unequip()
	current = tools[tool_id]
	current.equip()
	GameManager.current_tool = tool_id
	EventBus.tool_changed.emit(tool_id)
	if sound:
		AudioManager.play_ui("tool")
		HapticManager.pulse(15, 0.3)


func next_tool() -> void:
	var owned := UpgradeManager.owned_tools()
	if owned.size() <= 1:
		return
	var i := owned.find(current.tool_id)
	select(owned[(i + 1) % owned.size()])


func speed_factor() -> float:
	return current.speed_factor() if current else 1.0


func process_tools(delta: float) -> void:
	if InputState.tool_select != "":
		select(InputState.tool_select)
	elif InputState.tool_next:
		next_tool()
	var held := InputState.action_held and InputState.enabled
	var pressed := InputState.action_pressed and InputState.enabled
	# Con una bolsa en la mano, el botón principal la lanza.
	if player.bags.is_carrying() and pressed:
		player.bags.throw_bag()
		pressed = false
		held = false
	for id in tools:
		var t: BaseTool = tools[id]
		if t == current:
			t.process_tool(delta, held, pressed)
		elif t.tool_id == "hand":
			# Las hojas en vuelo hacia la mano siguen llegando aunque cambies de herramienta.
			var got := player.leaf_manager.sim.take_arrived(LeafManager.P_HAND)
			if got.x > 0:
				player.bags.add(int(got.x), got.y, "hand")
		elif t.tool_id == "vacuum":
			var got2 := player.leaf_manager.sim.take_arrived(LeafManager.P_VACUUM)
			if got2.x > 0:
				player.bags.add(int(got2.x), got2.y, "vacuum")
