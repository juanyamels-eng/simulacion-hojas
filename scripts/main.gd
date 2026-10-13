extends Node
## Punto de entrada: pantalla de carga, construcción del mundo y menú principal.

var world: World
var ui: UIManager


func _ready() -> void:
	ui = UIManager.new()
	add_child(ui)
	ui.show_loading()
	await get_tree().process_frame
	await get_tree().process_frame
	world = World.new()
	add_child(world)
	move_child(ui, -1)
	ui.bind_world(world)
	if GameManager.skip_menu:
		ui.start_game()
	else:
		ui.show_main_menu()
	ui.hide_loading()
