class_name IconButton
extends Button
## Botón redondo de madera con icono vectorial (pausa, diario...).

var icon_name := "pause"


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_NONE
	var n := UITheme.box(Color(UITheme.WOOD, 0.9), 40, UITheme.WOOD_DARK, 4, 6, true)
	var p := UITheme.box(UITheme.WOOD_DARK, 40, UITheme.WOOD_DARK, 4, 6)
	add_theme_stylebox_override("normal", n)
	add_theme_stylebox_override("hover", n)
	add_theme_stylebox_override("pressed", p)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pressed.connect(func(): AudioManager.play_ui("click"))


func _draw() -> void:
	Icons.draw(self, icon_name, size * 0.5, minf(size.x, size.y) * 0.62, UITheme.CREAM)
