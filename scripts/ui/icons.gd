class_name Icons
## Iconos vectoriales originales dibujados con primitivas (sin imágenes externas).


static func draw(ci: CanvasItem, icon: String, c: Vector2, s: float, col: Color) -> void:
	match icon:
		"hand": _hand(ci, c, s, col)
		"rake": _rake(ci, c, s, col)
		"blower": _blower(ci, c, s, col)
		"industrial": _blower(ci, c, s * 1.15, col, true)
		"vacuum": _vacuum(ci, c, s, col)
		"jump": _jump(ci, c, s, col)
		"interact": _interact(ci, c, s, col)
		"pause": _pause(ci, c, s, col)
		"leaf": leaf(ci, c, s, col, -0.6)
		"coin": _coin(ci, c, s, col)
		"bag": _bag(ci, c, s, col)
		"journal": _journal(ci, c, s, col)
		"swap": _swap(ci, c, s, col)
		"throw": _throw(ci, c, s, col)


static func leaf(ci: CanvasItem, c: Vector2, s: float, col: Color, angle: float = 0.0) -> void:
	var pts := PackedVector2Array()
	var shape := [Vector2(0, -1), Vector2(0.35, -0.55), Vector2(0.62, -0.62), Vector2(0.5, -0.2), Vector2(0.8, 0.05), Vector2(0.45, 0.2), Vector2(0.4, 0.55), Vector2(0.1, 0.45), Vector2(0, 0.7)]
	for p in shape:
		pts.append(c + (p * s * 0.5).rotated(angle))
	for k in range(shape.size() - 2, 0, -1):
		pts.append(c + (Vector2(-shape[k].x, shape[k].y) * s * 0.5).rotated(angle))
	ci.draw_colored_polygon(pts, col)
	ci.draw_line(c + (Vector2(0, -0.8) * s * 0.5).rotated(angle), c + (Vector2(0, 0.95) * s * 0.5).rotated(angle), col.darkened(0.35), maxf(1.5, s * 0.05))


static func _hand(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	ci.draw_rect(Rect2(c + Vector2(-2.6, -0.5) * u, Vector2(5.2, 4.5) * u), col)
	ci.draw_circle(c + Vector2(0, 4.0) * u, 2.6 * u, col)
	for k in 4:
		var x := -2.25 + k * 1.5
		var h: float = [3.4, 4.2, 4.0, 3.2][k]
		ci.draw_rect(Rect2(c + Vector2(x - 0.6, -0.5 - h) * u, Vector2(1.2, h + 0.5) * u), col)
		ci.draw_circle(c + Vector2(x, -0.5 - h) * u, 0.6 * u, col)
	ci.draw_line(c + Vector2(-2.4, 1.5) * u, c + Vector2(-4.4, -1.2) * u, col, 1.3 * u)
	ci.draw_circle(c + Vector2(-4.4, -1.2) * u, 0.65 * u, col)


static func _rake(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	ci.draw_line(c + Vector2(3.5, 4.5) * u, c + Vector2(-1.5, -2.5) * u, col, 1.0 * u)
	var a := c + Vector2(-4.5, -1.5) * u
	var b := c + Vector2(0.5, -5.0) * u
	ci.draw_line(a, b, col, 1.0 * u)
	for k in 6:
		var p := a.lerp(b, k / 5.0)
		ci.draw_line(p, p + Vector2(-0.9, -1.4).normalized() * 2.2 * u, col, 0.6 * u)


static func _blower(ci: CanvasItem, c: Vector2, s: float, col: Color, big: bool = false) -> void:
	var u := s / 10.0
	ci.draw_rect(Rect2(c + Vector2(-4.5, -2.0) * u, Vector2(4.0, 3.6) * u), col)
	ci.draw_line(c + Vector2(-0.5, -0.2) * u, c + Vector2(4.0, -0.2) * u, col, 1.4 * u)
	ci.draw_line(c + Vector2(-3.0, 1.6) * u, c + Vector2(-3.0, 3.8) * u, col, 1.0 * u)
	for k in (4 if big else 3):
		var y := -2.0 + k * (1.6 if not big else 1.3)
		ci.draw_line(c + Vector2(4.8, y) * u, c + Vector2(6.0, y - 0.3) * u, col, 0.5 * u)


static func _vacuum(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	ci.draw_rect(Rect2(c + Vector2(0.5, -4.5) * u, Vector2(3.5, 4.0) * u), col)
	ci.draw_line(c + Vector2(1.5, -0.5) * u, c + Vector2(-3.5, 4.0) * u, col, 1.3 * u)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5.0, 3.0) * u, c + Vector2(-2.2, 5.6) * u, c + Vector2(-4.0, 5.8) * u, c + Vector2(-5.6, 4.6) * u]), col)
	ci.draw_circle(c + Vector2(-2.0, 0.0) * u, 0.5 * u, col)
	ci.draw_circle(c + Vector2(-3.5, -1.5) * u, 0.4 * u, col)


static func _jump(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5) * u, c + Vector2(4.5, 0) * u, c + Vector2(1.6, 0) * u, c + Vector2(1.6, 4) * u, c + Vector2(-1.6, 4) * u, c + Vector2(-1.6, 0) * u, c + Vector2(-4.5, 0) * u]), col)


static func _interact(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	ci.draw_arc(c, 4.2 * u, 0, TAU, 28, col, 1.0 * u, true)
	ci.draw_circle(c, 1.6 * u, col)


static func _pause(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	ci.draw_rect(Rect2(c + Vector2(-3.0, -3.8) * u, Vector2(2.0, 7.6) * u), col)
	ci.draw_rect(Rect2(c + Vector2(1.0, -3.8) * u, Vector2(2.0, 7.6) * u), col)


static func _coin(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	ci.draw_circle(c, 4.6 * u, col.darkened(0.25))
	ci.draw_circle(c, 3.8 * u, col)
	leaf(ci, c, 5.0 * u, col.darkened(0.35), 0.5)


static func _bag(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	ci.draw_circle(c + Vector2(0, 1.2) * u, 4.0 * u, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-1.5, -2.0) * u, c + Vector2(1.5, -2.0) * u, c + Vector2(2.8, -4.6) * u, c + Vector2(-2.8, -4.6) * u]), col)


static func _journal(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	ci.draw_rect(Rect2(c + Vector2(-4, -4.5) * u, Vector2(8, 9) * u), col)
	ci.draw_rect(Rect2(c + Vector2(-2.5, -3) * u, Vector2(5, 0.8) * u), col.darkened(0.4))
	ci.draw_rect(Rect2(c + Vector2(-2.5, -1.2) * u, Vector2(5, 0.8) * u), col.darkened(0.4))
	ci.draw_rect(Rect2(c + Vector2(-2.5, 0.6) * u, Vector2(3, 0.8) * u), col.darkened(0.4))


static func _swap(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	ci.draw_arc(c, 3.6 * u, -2.6, 0.6, 16, col, 1.1 * u)
	ci.draw_arc(c, 3.6 * u, 0.55, 3.75, 16, col, 1.1 * u)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(3.0, 2.0) * u, c + Vector2(5.4, 1.0) * u, c + Vector2(3.6, 4.0) * u]), col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-3.0, -2.0) * u, c + Vector2(-5.4, -1.0) * u, c + Vector2(-3.6, -4.0) * u]), col)


static func _throw(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	_bag(ci, c + Vector2(-1.5, 1.5) * u, s * 0.65, col)
	ci.draw_arc(c + Vector2(-1.0, 2.0) * u, 5.0 * u, -1.6, -0.3, 10, col, 0.8 * u)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(4.6, -1.4) * u, c + Vector2(3.0, -3.2) * u, c + Vector2(5.4, -3.6) * u]), col)
