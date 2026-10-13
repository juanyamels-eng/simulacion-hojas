class_name MapView
extends Control
## Mapa dibujado de la finca: zonas coloreadas por % limpio, bloqueadas en gris, y tu posición.

const BOUNDS := Rect2(-62, -64, 124, 130)


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(400, 300)


func _process(_d: float) -> void:
	queue_redraw()


func _to_map(p: Vector2, origin: Vector2, k: float) -> Vector2:
	return origin + (p - BOUNDS.position) * k


func _draw() -> void:
	var k := minf(size.x / BOUNDS.size.x, size.y / BOUNDS.size.y)
	var origin := (size - BOUNDS.size * k) * 0.5
	draw_rect(Rect2(origin - Vector2(8, 8), BOUNDS.size * k + Vector2(16, 16)), Color(0.85, 0.76, 0.6))
	var font := get_theme_default_font()
	# La casa va debajo de los rótulos para no taparlos.
	draw_rect(Rect2(_to_map(Vector2(-11, -23), origin, k), Vector2(22, 9) * k), Color(0.92, 0.85, 0.72, 0.55))
	for z in GameData.ZONES:
		if z.get("secret", false) and not ProgressManager.has_flag("secret_found"):
			continue
		var r: Rect2 = z["rect"]
		if z.get("secret", false):
			r = Rect2(Vector2(38, 44), Vector2(20, 16))
		var mr := Rect2(_to_map(r.position, origin, k), r.size * k)
		var unlocked := AreaManager.is_unlocked(z["id"])
		var pct := AreaManager.pct(z["id"]) / 100.0
		var col := Color(0.62, 0.58, 0.52)
		if unlocked:
			col = Color(0.78, 0.48, 0.18).lerp(Color(0.38, 0.62, 0.3), pct)
		draw_rect(mr.grow(-2), col)
		draw_rect(mr.grow(-2), Color(0.3, 0.2, 0.12), false, 2.0)
		var zname: String = z["name"]
		# El tamaño del rótulo se ajusta para que el nombre quepa entero en su recuadro.
		var fs := int(clampf(k * 3.2, 12, 22))
		while fs > 10 and font.get_string_size(zname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > mr.size.x - 14:
			fs -= 1
		draw_string(font, mr.position + Vector2(8, fs + 6), zname, HORIZONTAL_ALIGNMENT_LEFT, mr.size.x - 12, fs, Color(1, 0.97, 0.9))
		var sub := ("%.1f %%" % (pct * 100.0)).replace(".", ",") if unlocked else "Cerrada"
		var sub_col := Color(1, 0.95, 0.75) if unlocked else Color(0.95, 0.9, 0.85, 0.75)
		draw_string(font, mr.position + Vector2(8, fs * 2 + 12), sub, HORIZONTAL_ALIGNMENT_LEFT, mr.size.x - 12, fs + (4 if unlocked else 0), sub_col)
	var p: Node3D = GameManager.world.player if GameManager.world else null
	if p:
		var pp := Vector2(p.global_position.x, p.global_position.z)
		if pp.x > 62.0:
			pp = Vector2(48, 52)
		var mp := _to_map(pp, origin, k)
		var fwd := -p.global_transform.basis.z
		var dir := Vector2(fwd.x, fwd.z).normalized()
		draw_circle(mp, 13, Color(1, 1, 1, 0.85))
		draw_colored_polygon(PackedVector2Array([mp + dir * 18, mp + dir.rotated(2.5) * 11, mp + dir.rotated(-2.5) * 11]), Color(0.85, 0.15, 0.1))
		draw_circle(mp, 5, Color(0.85, 0.15, 0.1))
