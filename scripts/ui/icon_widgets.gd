class_name IconView
extends Control
## Icono vectorial como Control.

var icon := "leaf":
	set(v):
		icon = v
		queue_redraw()
var color := UITheme.INK:
	set(v):
		color = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	Icons.draw(self, icon, size * 0.5, minf(size.x, size.y) * 0.9, color)
