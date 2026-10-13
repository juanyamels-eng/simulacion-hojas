class_name GuideMarkers
extends Control
## Guías del HUD: marcadores proyectados sobre objetivos del mundo.
## - Contenedor de reciclaje más cercano cuando llevas una bolsa cerrada o la bolsa está llena.
## - La siguiente puerta cuyo requisito ya cumples y que puedes pagar.
## - La bolsa olvidada más cercana (si lanzaste una y no entró en el contenedor).
## Si el objetivo queda fuera de cámara se fija al borde de la pantalla con una flecha.
## Los objetivos se recalculan 4 veces por segundo; el dibujo por fotograma solo proyecta.

enum { BIN, GATE, BAG }

const COLORS := [Color(0.2, 0.55, 0.3), Color(0.89, 0.47, 0.16), Color(0.55, 0.33, 0.18)]
const RADIUS := 21.0

var targets: Array[Dictionary] = []   # {"pos": Vector3, "kind": int, "label": String, "urgent": bool, "hide": float}
var player: PlayerController
var _refresh_t := 0.0
var _t := 0.0
var _font: Font
var _had := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = get_theme_default_font()


func update_markers(delta: float, p: PlayerController) -> void:
	player = p
	_t += delta
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.25
		refresh()
	var has := not targets.is_empty()
	if has or _had:
		queue_redraw()
	_had = has


func refresh() -> void:
	targets.clear()
	if player == null or not GameManager.in_game or GameManager.is_time_attack():
		return
	var w := GameManager.world as World
	if w == null or not is_instance_valid(w):
		return
	var pp := player.global_position
	var g: Dictionary = GameData.GUIDES
	var carrying := player.bags.is_carrying()
	if carrying or player.bags.is_full():
		var bin := nearest_bin(w, pp)
		if bin:
			targets.append({"pos": bin.global_position + Vector3(0, 2.5, 0), "kind": BIN, "label": "Reciclaje",
				"urgent": true, "hide": float(g["bin_hide_dist"])})
	else:
		var bag := nearest_loose_bag(pp, float(g["loose_bag_dist"]))
		if bag:
			targets.append({"pos": bag.global_position + Vector3(0, 0.9, 0), "kind": BAG, "label": "Bolsa (%d)" % bag.leaves,
				"urgent": false, "hide": 1.6})
	var gate := next_gate(w, pp)
	if gate:
		var zb := GameData.zone_by_id(gate.gate["b"])
		targets.append({"pos": gate.global_position + Vector3(0, 2.9, 0), "kind": GATE, "label": "Abrir: %s" % zb["name"],
			"urgent": false, "hide": float(g["gate_hide_dist"])})


## Contenedor más cercano en una zona desbloqueada y al mismo nivel que el jugador.
static func nearest_bin(w: World, pp: Vector3) -> RecycleBin:
	var best: RecycleBin = null
	var best_d := INF
	for b in w.builder.bins:
		if not is_instance_valid(b):
			continue
		var bp := b.global_position
		if absf(bp.y - pp.y) > 6.0:
			continue
		var z := AreaManager.zone_at(bp)
		if z != "" and not AreaManager.is_unlocked(z):
			continue
		var d := bp.distance_squared_to(pp)
		if d < best_d:
			best_d = d
			best = b
	return best


## Puerta más cercana cuyo requisito se cumple y que se puede pagar ya.
static func next_gate(w: World, pp: Vector3) -> GateDoor:
	var best: GateDoor = null
	var best_d := INF
	for id in w.gates:
		var gd: GateDoor = w.gates[id]
		if gd.opened or gd.gate.get("auto", false):
			continue
		if not gd.requirement_met() or not EconomyManager.can_afford(float(gd.gate["cost"])):
			continue
		var d := gd.global_position.distance_squared_to(pp)
		if d < best_d:
			best_d = d
			best = gd
	return best


static func nearest_loose_bag(pp: Vector3, max_dist: float) -> LeafBag:
	var best: LeafBag = null
	var best_d := max_dist * max_dist
	var tree := Engine.get_main_loop() as SceneTree
	for n in tree.get_nodes_in_group("leaf_bags"):
		var b := n as LeafBag
		if b == null or b.consumed or not b.is_inside_tree():
			continue
		var zid := AreaManager.zone_at(b.global_position)
		if zid != "" and not AreaManager.is_unlocked(zid) and b.global_position.distance_to(pp) > 3.0:
			continue
		var d := b.global_position.distance_squared_to(pp)
		if d < best_d and absf(b.global_position.y - pp.y) < 4.0:
			best_d = d
			best = b
	return best


## Zona de la pantalla donde se fijan los marcadores fuera de cámara (evita el HUD y los botones).
var area := Rect2()   # zona libre de paneles (la fija el HUD cada fotograma)


func edge_rect() -> Rect2:
	if area.size.x > 10.0 and area.size.y > 10.0:
		return area
	var vs := get_viewport_rect().size
	return Rect2(Vector2(70, 132), Vector2(vs.x - 140, vs.y * 0.62 - 132))


## Proyecta un punto del mundo: devuelve (x, y, 1) si se ve en pantalla o (x, y, 0) fijado al borde.
func project(cam: Camera3D, wp: Vector3) -> Vector3:
	var vs := get_viewport_rect().size
	var area := edge_rect()
	var behind := cam.is_position_behind(wp)
	var c := area.get_center()
	var dir := Vector2.ZERO
	if not behind:
		var sp := cam.unproject_position(wp)
		if Rect2(Vector2(36, 96), vs - Vector2(72, 140)).has_point(sp):
			return Vector3(sp.x, sp.y, 1.0)
		dir = sp - c
	else:
		# Detrás de la cámara: al borde izquierdo o derecho, según hacia dónde haya que girar.
		var local := cam.global_transform.affine_inverse() * wp
		dir = Vector2(1.0 if local.x >= 0.0 else -1.0, 0.0)
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	var hx := area.size.x * 0.5
	var hy := area.size.y * 0.5
	var k := minf(hx / maxf(absf(dir.x), 0.0001), hy / maxf(absf(dir.y), 0.0001))
	var pt := c + dir * k
	# A la derecha, por debajo, están los botones grandes: no los tapamos.
	if pt.x > vs.x * 0.74:
		pt.y = minf(pt.y, vs.y * 0.36)
	return Vector3(pt.x, pt.y, 0.0)


func _draw() -> void:
	if targets.is_empty() or player == null or not is_instance_valid(player):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var pp := player.global_position
	var center := edge_rect().get_center()
	for tg in targets:
		var wp: Vector3 = tg["pos"]
		var dist := Vector2(wp.x - pp.x, wp.z - pp.z).length()
		var hide_d: float = tg["hide"]
		var a := clampf((dist - hide_d) / 2.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		var pr := project(cam, wp)
		var pt := Vector2(pr.x, pr.y)
		var on := pr.z > 0.5
		var kind: int = tg["kind"]
		var col: Color = COLORS[kind]
		var c := pt + Vector2(0, sin(_t * 3.0 + kind) * 3.0 if on else 0.0)
		var r := RADIUS
		if on:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, r - 5), c + Vector2(8, r - 5), c + Vector2(0, r + 11)]), _fade(UITheme.CREAM, a))
		draw_circle(c + Vector2(0, 3), r + 3, Color(0, 0, 0, 0.22 * a))
		draw_circle(c, r + 3, _fade(UITheme.CREAM, a))
		draw_circle(c, r, _fade(col, a))
		if tg["urgent"]:
			var u := fmod(_t, 1.3) / 1.3
			draw_arc(c, r + 5 + u * 16.0, 0, TAU, 32, _fade(col.lightened(0.3), (1.0 - u) * a), 3.0, true)
		match kind:
			BIN: _icon_bin(c, r * 1.15, _fade(UITheme.CREAM, a))
			GATE: _icon_gate(c, r * 1.2, _fade(UITheme.CREAM, a))
			BAG: Icons.draw(self, "bag", c, r * 1.25, _fade(UITheme.CREAM, a))
		var dtxt := "%d m" % int(round(dist))
		if on:
			_text(c + Vector2(0, -r - 10), "%s · %s" % [tg["label"], dtxt], 18, a)
		else:
			var dir := (pt - center).normalized()
			var tip := c + dir * (r + 15)
			var perp := Vector2(-dir.y, dir.x)
			var tri := PackedVector2Array([tip, c + dir * (r + 4) + perp * 9, c + dir * (r + 4) - perp * 9])
			draw_colored_polygon(tri, _fade(UITheme.CREAM, a))
			# El texto, hacia el interior de la pantalla.
			_text(c - dir * (r + 22) + Vector2(0, 6), dtxt, 18, a)


func _fade(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, col.a * a)


func _text(at: Vector2, text: String, fs: int, a: float) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := at - Vector2(w * 0.5, 0)
	pos.x = clampf(pos.x, 8.0, get_viewport_rect().size.x - w - 8.0)
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.2, 0.12, 0.06, 0.9 * a))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _fade(UITheme.CREAM, a))


## Contenedor visto de frente con la flecha circular de reciclaje.
func _icon_bin(c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(-4.2, -2.2) * u, c + Vector2(4.2, -2.2) * u, c + Vector2(3.4, 4.6) * u, c + Vector2(-3.4, 4.6) * u]), col)
	draw_rect(Rect2(c + Vector2(-4.8, -3.8) * u, Vector2(9.6, 1.2) * u), col)
	var bg := COLORS[BIN] as Color
	draw_arc(c + Vector2(0, 1.2) * u, 1.9 * u, 0.4, TAU - 0.6, 14, Color(bg, col.a), 0.8 * u)
	draw_colored_polygon(PackedVector2Array([c + Vector2(1.9, 0.0) * u, c + Vector2(3.0, 1.8) * u, c + Vector2(0.8, 1.6) * u]), Color(bg, col.a))


## Puerta de madera con dos postes.
func _icon_gate(c: Vector2, s: float, col: Color) -> void:
	var u := s / 10.0
	draw_rect(Rect2(c + Vector2(-4.6, -3.6) * u, Vector2(1.4, 8.0) * u), col)
	draw_rect(Rect2(c + Vector2(3.2, -3.6) * u, Vector2(1.4, 8.0) * u), col)
	for y in [-1.4, 1.8]:
		draw_rect(Rect2(c + Vector2(-3.2, y - 0.45) * u, Vector2(6.4, 0.9) * u), col)
	for x in [-1.8, 0.0, 1.8]:
		draw_rect(Rect2(c + Vector2(x - 0.45, -2.6) * u, Vector2(0.9, 6.2) * u), col)
	draw_arc(c + Vector2(0, -1.2) * u, 4.0 * u, PI + 0.15, TAU - 0.15, 14, col, 0.9 * u)
