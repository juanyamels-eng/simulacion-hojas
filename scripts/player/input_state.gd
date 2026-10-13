class_name InputState
## Estado de entrada compartido. Lo rellena TouchInputManager (táctil o teclado/ratón)
## y lo consume el jugador. Evita dependencias directas entre la UI y el jugador.

static var move := Vector2.ZERO          # x: derecha, y: adelante (0..1)
static var look_delta := Vector2.ZERO    # píxeles acumulados desde el último frame
static var action_held := false
static var action_pressed := false       # flanco de pulsación
static var interact_held := false
static var interact_pressed := false
static var interact_released := false
static var jump_pressed := false
static var sprint_held := false
static var tool_next := false
static var tool_select := ""             # herramienta elegida en la rueda
static var enabled := true


static func consume_frame() -> void:
	look_delta = Vector2.ZERO
	action_pressed = false
	interact_pressed = false
	interact_released = false
	tool_next = false
	tool_select = ""


static func reset() -> void:
	consume_frame()
	jump_pressed = false
	move = Vector2.ZERO
	action_held = false
	interact_held = false
	sprint_held = false
