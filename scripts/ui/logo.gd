class_name Logo
extends Control
## Logotipo original: "Villa Hojarasca" con hojas que giran suavemente.

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var c1 := UITheme.GOLD
	var out := Color(0.28, 0.13, 0.05)
	var leaves := [[Vector2(18, 40), UITheme.ACCENT, 0.0], [Vector2(400, 30), UITheme.RED, 1.7], [Vector2(380, 150), Color(0.96, 0.76, 0.18), 3.1]]
	for lf in leaves:
		var p: Vector2 = lf[0]
		Icons.leaf(self, p + Vector2(0, sin(_t * 1.3 + float(lf[2])) * 5.0), 46.0, lf[1], sin(_t * 0.8 + float(lf[2])) * 0.6)
	draw_string_outline(font, Vector2(40, 70), "Villa", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, 14, out)
	draw_string(font, Vector2(40, 70), "Villa", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, UITheme.CREAM)
	draw_string_outline(font, Vector2(30, 150), "Hojarasca", HORIZONTAL_ALIGNMENT_LEFT, -1, 84, 18, out)
	draw_string(font, Vector2(30, 150), "Hojarasca", HORIZONTAL_ALIGNMENT_LEFT, -1, 84, c1)
	draw_string(font, Vector2(44, 184), "una finca, un otoño, un millón de hojas", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.93, 0.8, 0.9))
