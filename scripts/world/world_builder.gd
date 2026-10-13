class_name WorldBuilder
extends RefCounted
## Construye toda la finca de forma procedural: muros, vallas, casa, árboles, atrezo de cada zona,
## objetos interactivos y decoración que aparece al restaurar cada zona.
## La geometría repetida se agrupa en MultiMesh por región y color (pocas llamadas de dibujo).

const C_TRUNK := Color(0.4, 0.27, 0.17)
const C_BIRCH := Color(0.88, 0.86, 0.8)
const C_STONE := Color(0.7, 0.67, 0.6)
const C_STONE_DARK := Color(0.55, 0.52, 0.47)
const C_WOOD := Color(0.55, 0.36, 0.2)
const C_WOOD_DARK := Color(0.36, 0.23, 0.13)
const C_PAINT := Color(0.93, 0.89, 0.8)
const C_HEDGE := Color(0.22, 0.4, 0.2)
const C_IRON := Color(0.16, 0.16, 0.17)
const CANOPY := [Color(0.93, 0.5, 0.13), Color(0.95, 0.74, 0.2), Color(0.8, 0.24, 0.1), Color(0.88, 0.4, 0.12), Color(0.72, 0.45, 0.13)]
const FLOWERS := [Color(0.95, 0.45, 0.6), Color(0.62, 0.42, 0.85), Color(1.0, 0.96, 0.9), Color(1.0, 0.82, 0.25), Color(0.92, 0.25, 0.2)]

var root: Node3D
var terrain: Terrain
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var batches := {}
var units := {}
var density_points := []
var bins: Array[RecycleBin] = []
var gates: Array[GateDoor] = []
var ducts_defs := []
var stations: Array[StationObject] = []
var restore_nodes := {}     # zona -> Node3D que aparece al 100 %
var debris_nodes := {}      # zona -> Node3D que desaparece al 100 %
var _toggle := {}           # zona -> {"flowers": [...], "debris": [...]}


func build(r: Node3D, t: Terrain) -> void:
	root = r
	terrain = t
	rng.seed = 20241013
	body = StaticBody3D.new()
	body.name = "StaticWorld"
	body.collision_layer = Interactable.LAYER_WORLD
	root.add_child(body)
	units = {
		"box": MeshFactory.box(Vector3.ONE),
		"cyl": MeshFactory.cyl(0.5, 0.5, 1.0, 10),
		"cyl6": MeshFactory.cyl(0.5, 0.5, 1.0, 6),
		"trunk": MeshFactory.cyl(0.36, 0.5, 1.0, 7),
		"sph": MeshFactory.sphere(0.5, 9, 6),
		"blob": MeshFactory.sphere(0.5, 7, 4),
		"cone": MeshFactory.cyl(0.0, 0.5, 1.0, 8),
		"prism": MeshFactory.roof(Vector3.ONE),
	}
	_paint_paths()
	_boundaries()
	_zone_entrada()
	_zone_delantero()
	_zone_patio()
	_zone_garaje()
	_zone_infantil()
	_zone_huerto()
	_zone_trasero()
	_zone_piscina()
	_zone_laberinto()
	_zone_invernadero()
	_zone_secret()
	_outside()
	for z in GameData.ZONES:
		_zone_decor(z)
	_flush()


# ------------------------------------------------------------------ utilidades

func gy(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func add(shape: String, color: Color, pos: Vector3, size: Vector3, rot_y: float = 0.0, shadow: bool = true) -> void:
	add_basis(shape, color, pos, Basis(Vector3.UP, rot_y) * Basis.from_scale(size), shadow)


func add_basis(shape: String, color: Color, pos: Vector3, basis: Basis, shadow: bool = true) -> void:
	var region := int(floor((pos.x + 80.0) / 40.0)) * 100 + int(floor((pos.z + 80.0) / 40.0))
	var key := "%s|%s|%d|%d" % [shape, color.to_html(), region, int(shadow)]
	if not batches.has(key):
		batches[key] = {"shape": shape, "color": color, "x": [], "shadow": shadow}
	batches[key]["x"].append(Transform3D(basis, pos))


## Caja apoyada en el suelo (pos = centro de la base).
func block(color: Color, x: float, z: float, size: Vector3, rot_y: float = 0.0, collide: bool = true, leaf_solid: bool = true, y_off: float = 0.0) -> void:
	var y := gy(x, z) + y_off
	add("box", color, Vector3(x, y + size.y * 0.5, z), size, rot_y)
	if collide:
		collider(Vector3(x, y + size.y * 0.5, z), size, rot_y)
	if leaf_solid:
		terrain.add_solid_box(Vector2(x, z), Vector2(size.x, size.z) * 0.5, rot_y)


func collider(center: Vector3, size: Vector3, rot_y: float = 0.0) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	cs.rotation.y = rot_y
	body.add_child(cs)


func label(text: String, pos: Vector3, size: int = 64, rot_y: float = 0.0, color: Color = Color(0.98, 0.93, 0.82)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color(0.24, 0.14, 0.07)
	l.position = pos
	l.rotation.y = rot_y
	l.double_sided = true
	root.add_child(l)
	return l


func tree(x: float, z: float, scale: float = 1.0, kind: int = -1, collide: bool = true) -> void:
	if kind < 0:
		kind = 0 if rng.randf() < 0.65 else (1 if rng.randf() < 0.6 else 2)
	var y := gy(x, z)
	var s := scale * rng.randf_range(0.85, 1.15)
	if kind == 2:
		add("trunk", C_TRUNK, Vector3(x, y + 1.0 * s, z), Vector3(0.35, 2.0, 0.35) * s)
		for k in 3:
			var w := (3.2 - k * 0.8) * s
			add("cone", Color(0.17, 0.33, 0.22).lerp(Color(0.25, 0.42, 0.26), k * 0.3), Vector3(x, y + (2.0 + k * 1.3) * s, z), Vector3(w, 2.2 * s, w))
	else:
		var birch := kind == 1
		var h := (2.8 if birch else 3.2) * s
		var rad := (0.32 if birch else 0.5) * s
		add("trunk", C_BIRCH if birch else C_TRUNK, Vector3(x, y + h * 0.5, z), Vector3(rad, h, rad), rng.randf() * TAU)
		var base: Color = CANOPY[rng.randi() % CANOPY.size()]
		if birch:
			base = Color(0.96, 0.8, 0.25)
		var blobs := 5 if not birch else 3
		for k in blobs:
			var off := Vector3(rng.randf_range(-1.3, 1.3), rng.randf_range(-0.3, 0.9), rng.randf_range(-1.3, 1.3)) * s
			if k == 0:
				off = Vector3.ZERO
			var size := (3.6 if k == 0 else rng.randf_range(1.8, 2.6)) * s
			var col: Color = base if (k == 0 or birch) else CANOPY[rng.randi() % CANOPY.size()]
			var sz := Vector3(size, size * (1.25 if birch else 0.9), size)
			add_basis("blob", col, Vector3(x, y + h + 0.9 * s, z) + off, Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(sz))
		density_points.append([Vector2(x, z), 4.2 * s, 2.0])
	if collide:
		collider(Vector3(x, y + 1.5, z), Vector3(0.6, 3.0, 0.6) * s)
		terrain.add_solid_circle(Vector2(x, z), 0.28 * s)


func bench(x: float, z: float, rot_y: float) -> void:
	var y := gy(x, z)
	var b := Basis(Vector3.UP, rot_y)
	add_basis("box", C_WOOD, Vector3(x, y + 0.45, z), b * Basis.from_scale(Vector3(1.6, 0.07, 0.45)))
	add_basis("box", C_WOOD, Vector3(x, y + 0.75, z) + b * Vector3(0, 0, -0.22), b * Basis.from_scale(Vector3(1.6, 0.4, 0.05)))
	for sx in [-0.7, 0.7]:
		add_basis("box", C_IRON, Vector3(x, y + 0.22, z) + b * Vector3(sx, 0, 0), b * Basis.from_scale(Vector3(0.06, 0.45, 0.45)))
	collider(Vector3(x, y + 0.45, z), Vector3(1.6, 0.9, 0.5), rot_y)


func lamp(x: float, z: float) -> void:
	var y := gy(x, z)
	add("cyl", C_IRON, Vector3(x, y + 1.4, z), Vector3(0.1, 2.8, 0.1))
	add("box", C_IRON, Vector3(x, y + 2.85, z), Vector3(0.36, 0.08, 0.36))
	add("sph", Color(1.0, 0.86, 0.55), Vector3(x, y + 3.0, z), Vector3(0.32, 0.32, 0.32), 0.0, false)
	collider(Vector3(x, y + 1.4, z), Vector3(0.2, 2.8, 0.2))
	terrain.add_solid_circle(Vector2(x, z), 0.15)


func bin(x: float, z: float, rot_y: float) -> void:
	var b := RecycleBin.new()
	b.position = Vector3(x, gy(x, z), z)
	b.rotation.y = rot_y
	var green := MeshFactory.mat(Color(0.2, 0.47, 0.27), 0.6)
	var parts := [
		[Vector3(2.6, 0.12, 1.4), Vector3(0, 0.1, 0)],
		[Vector3(2.6, 1.45, 0.1), Vector3(0, 0.82, 0.65)],
		[Vector3(2.6, 1.45, 0.1), Vector3(0, 0.82, -0.65)],
		[Vector3(0.1, 1.45, 1.4), Vector3(1.25, 0.82, 0)],
		[Vector3(0.1, 1.45, 1.4), Vector3(-1.25, 0.82, 0)],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshFactory.box(p[0])
		mi.material_override = green
		mi.position = p[1]
		b.add_child(mi)
	var lid := MeshInstance3D.new()
	lid.mesh = MeshFactory.box(Vector3(2.7, 0.08, 1.2))
	lid.material_override = MeshFactory.mat(Color(0.15, 0.36, 0.2), 0.6)
	lid.position = Vector3(0, 1.85, -1.1)
	lid.rotation.x = -1.1
	b.add_child(lid)
	var inner := MeshInstance3D.new()
	inner.mesh = MeshFactory.box(Vector3(2.4, 0.1, 1.2))
	inner.material_override = MeshFactory.mat(Color(0.6, 0.35, 0.12))
	inner.position = Vector3(0, 1.2, 0)
	b.add_child(inner)
	var l := Label3D.new()
	l.text = "RECICLAJE"
	l.font_size = 40
	l.pixel_size = 0.006
	l.outline_size = 10
	l.outline_modulate = Color(0.08, 0.2, 0.1)
	l.position = Vector3(0, 0.95, 0.72)
	b.add_child(l)
	Interactable.make_shape(b, Vector3(2.6, 1.5, 1.4), Vector3(0, 0.75, 0))
	root.add_child(b)
	terrain.add_solid_box(Vector2(x, z), Vector2(1.35, 0.75), rot_y)
	bins.append(b)


func station(kind: StationObject.Kind, pos: Vector3, size: Vector3, data: Dictionary = {}, blocks: bool = false) -> StationObject:
	var s := StationObject.new()
	s.position = pos
	s.collision_layer = Interactable.LAYER_INTERACT | (Interactable.LAYER_WORLD if blocks else 0)
	Interactable.make_shape(s, size, Vector3(0, size.y * 0.5, 0))
	s.setup(kind, data)
	root.add_child(s)
	stations.append(s)
	return s


func house_box(color: Color, center: Vector3, size: Vector3, collide: bool = true) -> void:
	add("box", color, center, size)
	if collide:
		collider(center, size)


# ------------------------------------------------------------------ caminos y límites

func _paint_paths() -> void:
	terrain.paint_line(Vector2(0, 64), Vector2(0, 10), 4.2, 0)
	terrain.paint_circle(Vector2(0, 25), 5.0, 0)
	terrain.paint_circle(Vector2(0, 25), 2.6, 1)
	terrain.paint_line(Vector2(0, 10), Vector2(0, -13), 4.0, 0)
	terrain.paint_circle(Vector2(0, -3), 4.6, 0)
	terrain.paint_line(Vector2(-20, -5), Vector2(20, -5), 3.0, 0)
	terrain.paint_line(Vector2(16, -5), Vector2(16, -25), 2.6, 0)
	terrain.paint_line(Vector2(-16, -5), Vector2(-16, -25), 2.6, 0)
	terrain.paint_line(Vector2(16, -25), Vector2(4, -42), 2.4, 0)
	terrain.paint_line(Vector2(-16, -25), Vector2(-4, -42), 2.4, 0)
	terrain.paint_line(Vector2(0, 25), Vector2(-20, 25), 2.6, 0)
	terrain.paint_line(Vector2(0, 25), Vector2(20, 25), 2.6, 0)
	terrain.paint_rect(Rect2(37, 27, 10, 13), 2)
	terrain.paint_line(Vector2(20, 25), Vector2(38, 32), 3.0, 2)
	terrain.paint_rect(Rect2(29, -16, 22, 17), 0)
	terrain.paint_line(Vector2(40, 10), Vector2(40, 1), 2.6, 0)
	terrain.paint_line(Vector2(40, -25), Vector2(40, -40), 2.6, 0)
	terrain.paint_rect(Rect2(33, -51, 14, 10), 0)
	terrain.paint_rect(Rect2(-50, 14, 4, 4), 2)
	terrain.paint_rect(Rect2(70, -44, 22, 18), 0)
	terrain.paint_line(Vector2(-20, -5), Vector2(-40, -5), 2.4, 0)
	terrain.paint_line(Vector2(-38, -5), Vector2(-38, -25), 2.4, 0)


func _zone_index_at(p: Vector2) -> int:
	for i in GameData.ZONES.size():
		if not GameData.ZONES[i].get("secret", false) and (GameData.ZONES[i]["rect"] as Rect2).has_point(p):
			return i
	return -1


func _gate_at(p: Vector2) -> bool:
	for g in GameData.GATES:
		if p.distance_to(g["pos"]) < 1.75:
			return true
	return false


func _boundaries() -> void:
	var done := {}
	for zi in GameData.ZONES.size():
		var z: Dictionary = GameData.ZONES[zi]
		if z.get("secret", false):
			continue
		var r: Rect2 = z["rect"]
		var edges := [
			[r.position, Vector2(r.end.x, r.position.y), Vector2(0, -1)],
			[Vector2(r.position.x, r.end.y), r.end, Vector2(0, 1)],
			[r.position, Vector2(r.position.x, r.end.y), Vector2(-1, 0)],
			[Vector2(r.end.x, r.position.y), r.end, Vector2(1, 0)],
		]
		for e in edges:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var outward: Vector2 = e[2]
			var length := a.distance_to(b)
			var dir := (b - a) / length
			var steps := int(round(length))
			var seg_type := ""
			var seg_start := 0
			for s in steps + 1:
				var typ := "end"
				if s < steps:
					var mid := a + dir * (s + 0.5)
					var key := "%d,%d" % [int(round(mid.x * 2.0)), int(round(mid.y * 2.0))]
					if done.has(key):
						typ = "skip"
					else:
						done[key] = true
						var other := _zone_index_at(mid + outward * 0.6)
						if other < 0:
							typ = "wall"
							if absf(mid.x) < 3.0 and mid.y > 63.0:
								typ = "maingate"
						else:
							var oid: String = GameData.ZONES[other]["id"]
							typ = "hedge" if (oid == "laberinto" or z["id"] == "laberinto") else "fence"
						if _gate_at(mid):
							typ = "gap"
				if typ != seg_type:
					if seg_type in ["wall", "fence", "hedge"]:
						_segment(seg_type, a + dir * seg_start, a + dir * s, dir)
					seg_type = typ
					seg_start = s
	# Portón principal decorativo (la carretera queda fuera).
	for sx in [-3.4, 3.4]:
		block(C_STONE_DARK, sx, 64, Vector3(1.0, 2.8, 1.0))
		add("sph", C_STONE, Vector3(sx, gy(sx, 64) + 3.05, 64), Vector3(0.6, 0.6, 0.6))
	for k in 13:
		var x := -2.6 + k * 0.43
		add("box", C_IRON, Vector3(x, gy(x, 64) + 1.1, 64), Vector3(0.05, 2.2, 0.05))
	add("box", C_IRON, Vector3(0, gy(0, 64) + 2.15, 64), Vector3(5.9, 0.08, 0.08))
	collider(Vector3(0, 1.2, 64), Vector3(6.0, 2.6, 0.4))
	terrain.add_solid_box(Vector2(0, 64), Vector2(3.0, 0.25))
	var title_sign := label("VILLA HOJARASCA", Vector3(0, 3.35, 64.1), 96, PI)
	title_sign.modulate = Color(1.0, 0.86, 0.55)


func _segment(kind: String, a: Vector2, b: Vector2, dir: Vector2) -> void:
	var length := a.distance_to(b)
	if length < 0.3:
		return
	var rot := -atan2(dir.y, dir.x)
	var pieces := maxi(1, int(ceil(length / 4.0)))
	for k in pieces:
		var p0 := a + dir * (length * k / pieces)
		var p1 := a + dir * (length * (k + 1) / pieces)
		var mid := (p0 + p1) * 0.5
		var plen := p0.distance_to(p1)
		var y := minf(gy(p0.x, p0.y), gy(p1.x, p1.y))
		match kind:
			"wall":
				add("box", C_STONE, Vector3(mid.x, y + 0.65, mid.y), Vector3(plen + 0.05, 2.5, 0.55), rot)
				add("box", C_STONE_DARK, Vector3(mid.x, y + 1.97, mid.y), Vector3(plen + 0.1, 0.14, 0.7), rot)
				collider(Vector3(mid.x, y + 1.2, mid.y), Vector3(plen, 3.4, 0.55), rot)
			"hedge":
				add("box", C_HEDGE, Vector3(mid.x, y + 0.9, mid.y), Vector3(plen + 0.3, 2.4, 0.9), rot)
				collider(Vector3(mid.x, y + 1.1, mid.y), Vector3(plen, 2.2, 0.9), rot)
			"fence":
				for f in [0.0, 1.0]:
					var pp := p0.lerp(p1, f)
					add("box", C_WOOD_DARK, Vector3(pp.x, gy(pp.x, pp.y) + 0.6, pp.y), Vector3(0.14, 1.3, 0.14), rot)
				for ry in [0.35, 0.85]:
					add("box", C_WOOD, Vector3(mid.x, y + ry, mid.y), Vector3(plen, 0.08, 0.05), rot)
				var pickets := int(plen / 0.24)
				for q in pickets:
					var pp := p0.lerp(p1, (q + 0.5) / pickets)
					var ph := 1.0 + 0.06 * sin(q * 1.3)
					add("box", C_PAINT, Vector3(pp.x, gy(pp.x, pp.y) + ph * 0.5 - 0.05, pp.y), Vector3(0.09, ph, 0.03), rot)
				collider(Vector3(mid.x, y + 0.75, mid.y), Vector3(plen, 1.6, 0.2), rot)
		terrain.add_solid_box(mid, Vector2(plen * 0.5 + 0.1, 0.3 if kind == "fence" else 0.45), rot)


# ------------------------------------------------------------------ zonas

func _zone_entrada() -> void:
	# Taller de Brizna (tienda de mejoras).
	var sx := -12.0
	var sz := 50.0
	var y := gy(sx, sz)
	house_box(C_WOOD, Vector3(sx - 2.0, y + 1.3, sz), Vector3(0.2, 2.6, 4.4))
	house_box(C_WOOD, Vector3(sx, y + 1.3, sz - 2.1), Vector3(4.2, 2.6, 0.2))
	house_box(C_WOOD, Vector3(sx, y + 1.3, sz + 2.1), Vector3(4.2, 2.6, 0.2))
	add_basis("prism", Color(0.62, 0.27, 0.2), Vector3(sx, y + 3.15, sz), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(5.0, 1.1, 5.0)))
	house_box(C_WOOD_DARK, Vector3(sx + 1.7, y + 0.5, sz), Vector3(0.6, 1.0, 3.6))
	add("box", Color(0.9, 0.6, 0.2), Vector3(sx + 1.72, y + 1.02, sz), Vector3(0.66, 0.06, 3.7))
	for k in 4:
		add("box", Color(0.3, 0.42, 0.55) if k % 2 == 0 else Color(0.75, 0.3, 0.2), Vector3(sx - 1.6, y + 1.2 + k * 0.35, sz - 1.0 + k * 0.6), Vector3(0.4, 0.25, 0.3))
	terrain.add_solid_box(Vector2(sx, sz), Vector2(2.2, 2.2))
	label("TALLER", Vector3(sx + 2.2, y + 2.9, sz), 72, PI * 0.5)
	station(StationObject.Kind.SHOP, Vector3(sx + 1.7, y, sz), Vector3(0.9, 1.4, 3.6))
	var nt: Dictionary = GameData.NOTES[0]
	station(StationObject.Kind.NOTE, nt["pos"] - Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 0.3), nt)
	add("box", C_PAINT, nt["pos"], Vector3(0.9, 0.6, 0.04))
	bin(9.0, 50.0, PI * 0.5)
	# Buzón con aviso del cartero.
	block(C_WOOD_DARK, 4.0, 61.0, Vector3(0.12, 1.0, 0.12))
	add("box", Color(0.75, 0.2, 0.15), Vector3(4.0, gy(4, 61) + 1.15, 61.0), Vector3(0.35, 0.3, 0.55))
	var nc: Dictionary = GameData.NOTES[1]
	station(StationObject.Kind.NOTE, Vector3(4.0, gy(4, 61), 61.0), Vector3(0.6, 1.4, 0.7), nc)
	for p in [Vector2(-15, 58), Vector2(15, 45), Vector2(-7, 44)]:
		tree(p.x, p.y, 1.1, 0)
	tree(-16, 43, 1.0, 1)
	tree(16, 60, 1.0, 2)
	for z in [56.0, 46.0]:
		lamp(-3.0, z)
		lamp(3.0, z)
	bench(13.0, 57.0, -PI * 0.5)


func _zone_delantero() -> void:
	block(C_STONE, 0, 25, Vector3(0.9, 0.5, 0.9))
	add("cyl", C_STONE, Vector3(0, gy(0, 25) + 1.0, 25), Vector3(0.35, 1.0, 0.35))
	add("cyl", C_STONE_DARK, Vector3(0, gy(0, 25) + 1.55, 25), Vector3(1.0, 0.12, 1.0))
	for side in [-1.0, 1.0]:
		for seg in [[12.0, 21.0], [29.0, 38.0]]:
			var zc: float = (seg[0] + seg[1]) * 0.5
			block(C_HEDGE, side * 2.7, zc, Vector3(0.7, 0.8, seg[1] - seg[0]))
	tree(-12, 27, 1.6, 0)
	for p in [Vector2(12, 33), Vector2(14, 15), Vector2(-14, 14), Vector2(-7, 36)]:
		tree(p.x, p.y, 1.0, 0)
	tree(8, 18, 1.0, 1)
	tree(-17, 20, 1.0, 2)
	block(C_STONE, 10, 22, Vector3(0.5, 0.9, 0.5))
	add("cyl", C_STONE, Vector3(10, gy(10, 22) + 1.0, 22), Vector3(1.2, 0.15, 1.2))
	bench(5.5, 29.5, PI)
	bench(-5.5, 20.5, 0.0)
	bin(6.0, 37.0, 0.0)
	var gnome_texts := [
		"Un gnomo de jardín. Tiene cara de saber algo. No piensa decirlo.",
		"Otro gnomo. Juraría que antes estaba mirando hacia el otro lado.",
		"El tercer gnomo sostiene un cartelito: «Los gnomos no barremos. Sindicato.»",
	]
	var gp := [Vector2(-17.5, 38.0), Vector2(17.5, 11.5), Vector2(-13.8, 30.2)]
	for k in 3:
		var g: Vector2 = gp[k]
		var y := gy(g.x, g.y)
		add("cone", Color(0.8, 0.15, 0.12), Vector3(g.x, y + 0.62, g.y), Vector3(0.22, 0.3, 0.22))
		add("sph", Color(0.95, 0.8, 0.65), Vector3(g.x, y + 0.45, g.y), Vector3(0.18, 0.18, 0.18))
		add("cyl", Color(0.25, 0.4, 0.7), Vector3(g.x, y + 0.2, g.y), Vector3(0.22, 0.4, 0.22))
		station(StationObject.Kind.NOTE, Vector3(g.x, y, g.y), Vector3(0.4, 0.8, 0.4), {"id": "gnome_%d" % k, "title": "Gnomo %d de 3" % (k + 1), "text": gnome_texts[k]})


func _zone_patio() -> void:
	# Fuente.
	var y := gy(0, -3)
	add("cyl", C_STONE, Vector3(0, y + 0.3, -3), Vector3(4.8, 0.6, 4.8))
	add("cyl", Color(0.35, 0.3, 0.25), Vector3(0, y + 0.58, -3), Vector3(4.2, 0.08, 4.2))
	add("cyl", C_STONE, Vector3(0, y + 1.1, -3), Vector3(0.5, 1.6, 0.5))
	add("cyl", C_STONE, Vector3(0, y + 1.9, -3), Vector3(1.6, 0.25, 1.6))
	add("sph", C_STONE_DARK, Vector3(0, y + 2.25, -3), Vector3(0.45, 0.45, 0.45))
	collider(Vector3(0, y + 0.5, -3), Vector3(4.6, 1.0, 4.6))
	terrain.add_solid_circle(Vector2(0, -3), 2.45)
	_house()
	for p in [Vector2(-15, 5), Vector2(15, 6), Vector2(-17, -15), Vector2(17, -13)]:
		tree(p.x, p.y, 1.1, 0)
	bench(-4.5, -7.5, 0.0)
	bench(4.5, -7.5, 0.0)
	for p in [Vector2(-4, 6), Vector2(4, 6), Vector2(-9, -9), Vector2(9, -9)]:
		lamp(p.x, p.y)
	for sx in [-6.0, 6.0]:
		block(Color(0.72, 0.4, 0.25), sx, -10.6, Vector3(0.9, 0.7, 0.9))
		add("blob", Color(0.3, 0.5, 0.22), Vector3(sx, gy(sx, -10.6) + 1.0, -10.6), Vector3(1.1, 0.8, 1.1))
	bin(5.0, 7.0, 0.0)


func _house() -> void:
	var y := 0.25
	var wall := Color(0.93, 0.86, 0.72)
	var trim := Color(0.98, 0.97, 0.93)
	var roofc := Color(0.6, 0.26, 0.2)
	var glass := Color(0.24, 0.3, 0.38)
	house_box(wall, Vector3(0, y + 3.2, -18.5), Vector3(22, 6.4, 9))
	add("box", trim, Vector3(0, y + 3.25, -18.5), Vector3(22.3, 0.2, 9.3))
	add_basis("prism", roofc, Vector3(0, y + 8.0, -18.5), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(10.4, 3.2, 23.2)))
	house_box(Color(0.6, 0.4, 0.32), Vector3(-6, y + 8.5, -20), Vector3(1.2, 4.0, 1.2), false)
	# Torreón.
	add("cyl", wall, Vector3(11, y + 4.5, -14.5), Vector3(4.4, 9.0, 4.4))
	add("cone", roofc, Vector3(11, y + 10.6, -14.5), Vector3(5.4, 3.2, 5.4))
	collider(Vector3(11, y + 4.5, -14.5), Vector3(4.2, 9.0, 4.2))
	terrain.add_solid_circle(Vector2(11, -14.5), 2.25)
	terrain.add_solid_box(Vector2(0, -18.5), Vector2(11.0, 4.5))
	# Porche con columnas.
	add("box", C_STONE, Vector3(0, y + 0.15, -12.8), Vector3(16, 0.3, 2.6))
	collider(Vector3(0, y + 0.15, -12.8), Vector3(16, 0.3, 2.6))
	add("box", trim, Vector3(0, y + 3.1, -12.8), Vector3(16.4, 0.18, 2.9))
	for k in 5:
		var x := -7.5 + k * 3.75
		add("cyl", trim, Vector3(x, y + 1.6, -11.8), Vector3(0.3, 2.9, 0.3))
		collider(Vector3(x, y + 1.6, -11.8), Vector3(0.3, 2.9, 0.3))
		terrain.add_solid_circle(Vector2(x, -11.8), 0.18)
	add("box", Color(0.2, 0.36, 0.28), Vector3(0, y + 1.3, -13.98), Vector3(1.4, 2.4, 0.1))
	add("sph", Color(0.85, 0.7, 0.3), Vector3(0.5, y + 1.3, -13.9), Vector3(0.1, 0.1, 0.1))
	for row in 2:
		for k in 6:
			var x := -9.0 + k * 3.6
			if row == 0 and absf(x) < 1.5:
				continue
			var wy := y + (1.6 if row == 0 else 4.7)
			add("box", trim, Vector3(x, wy, -13.97), Vector3(1.4, 1.7, 0.08))
			add("box", glass, Vector3(x, wy, -13.93), Vector3(1.15, 1.45, 0.06))
			add("box", Color(0.2, 0.36, 0.28), Vector3(x - 0.95, wy, -13.95), Vector3(0.38, 1.6, 0.06))
			add("box", Color(0.2, 0.36, 0.28), Vector3(x + 0.95, wy, -13.95), Vector3(0.38, 1.6, 0.06))
	for row in 2:
		for k in 3:
			var wy := y + (1.6 if row == 0 else 4.7)
			add("box", glass, Vector3(-11.03, wy, -21 + k * 3.0), Vector3(0.06, 1.45, 1.15))
	label("1907", Vector3(0, y + 6.9, -13.9), 56)


func _zone_garaje() -> void:
	var y := gy(42, 22)
	house_box(Color(0.82, 0.74, 0.62), Vector3(42, y + 2.0, 22), Vector3(12, 4.0, 10))
	add_basis("prism", Color(0.45, 0.3, 0.25), Vector3(42, y + 5.0, 22), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(11, 2.0, 13)))
	add("box", Color(0.55, 0.6, 0.62), Vector3(42, y + 1.6, 27.04), Vector3(6.0, 3.2, 0.1))
	for k in 6:
		add("box", Color(0.45, 0.5, 0.52), Vector3(42, y + 0.3 + k * 0.55, 27.1), Vector3(6.0, 0.05, 0.05))
	terrain.add_solid_box(Vector2(42, 22), Vector2(6, 5))
	# Coche antiguo.
	var cx := 30.0
	var cz := 33.0
	var cy := gy(cx, cz)
	var teal := Color(0.25, 0.55, 0.55)
	add("box", teal, Vector3(cx, cy + 0.7, cz), Vector3(4.0, 0.8, 1.8), 0.3)
	add("box", teal.darkened(0.15), Vector3(cx - 0.2, cy + 1.4, cz), Vector3(2.2, 0.7, 1.6), 0.3)
	for w in [Vector2(-1.3, -0.95), Vector2(1.3, -0.95), Vector2(-1.3, 0.95), Vector2(1.3, 0.95)]:
		var off := Vector2(w.x, w.y).rotated(-0.3)
		add_basis("cyl", Color(0.12, 0.12, 0.12), Vector3(cx + off.x, cy + 0.38, cz + off.y), Basis(Vector3.UP, 0.3) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.75, 0.25, 0.75)))
	collider(Vector3(cx, cy + 0.9, cz), Vector3(4.0, 1.8, 1.9), 0.3)
	terrain.add_solid_box(Vector2(cx, cz), Vector2(2.0, 0.95), 0.3)
	# Bidón azul del Tónico Otoñal y barriles.
	block(Color(0.2, 0.4, 0.85), 34.0, 30.0, Vector3(0.7, 0.95, 0.7))
	block(Color(0.55, 0.32, 0.18), 33.0, 29.2, Vector3(0.7, 0.95, 0.7))
	block(Color(0.5, 0.3, 0.17), 52.0, 14.0, Vector3(0.9, 0.5, 0.9))
	block(Color(0.12, 0.12, 0.12), 52.0, 14.0, Vector3(0.85, 0.9, 0.85))
	block(C_WOOD, 55.0, 21.0, Vector3(1.0, 0.9, 2.2))
	for p in [Vector2(24, 37), Vector2(57, 37), Vector2(24, 13)]:
		tree(p.x, p.y, 1.0, 0)
	tree(57, 12, 1.1, 2)
	bin(55.0, 31.0, -PI * 0.5)


func _zone_infantil() -> void:
	# Columpios.
	var sx := -47.0
	var sz := 32.0
	var y := gy(sx, sz)
	var red := Color(0.8, 0.25, 0.2)
	for ex in [-2.0, 2.0]:
		for lean in [-0.28, 0.28]:
			add_basis("cyl", red, Vector3(sx + ex, y + 1.25, sz + lean * 1.25), Basis(Vector3.RIGHT, lean) * Basis.from_scale(Vector3(0.12, 2.6, 0.12)))
	add_basis("cyl", red, Vector3(sx, y + 2.5, sz), Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.12, 4.2, 0.12)))
	for k in [-0.9, 0.9]:
		add("box", C_WOOD, Vector3(sx + k, y + 0.55, sz), Vector3(0.6, 0.06, 0.3))
		add("cyl", C_IRON, Vector3(sx + k - 0.25, y + 1.5, sz), Vector3(0.025, 1.9, 0.025))
		add("cyl", C_IRON, Vector3(sx + k + 0.25, y + 1.5, sz), Vector3(0.025, 1.9, 0.025))
	collider(Vector3(sx, y + 1.3, sz), Vector3(4.4, 2.6, 0.6))
	for ex in [-2.0, 2.0]:
		terrain.add_solid_circle(Vector2(sx + ex, sz - 0.35), 0.15)
		terrain.add_solid_circle(Vector2(sx + ex, sz + 0.35), 0.15)
	# Tobogán.
	var tx := -31.0
	var tz := 19.0
	var ty := gy(tx, tz)
	add("box", Color(0.95, 0.75, 0.2), Vector3(tx, ty + 1.0, tz - 1.6), Vector3(1.0, 2.0, 0.8))
	add_basis("box", Color(0.3, 0.6, 0.85), Vector3(tx, ty + 1.0, tz + 0.3), Basis(Vector3.RIGHT, 0.62) * Basis.from_scale(Vector3(0.8, 0.08, 3.6)))
	collider(Vector3(tx, ty + 1.0, tz - 1.6), Vector3(1.0, 2.0, 0.8))
	terrain.add_solid_box(Vector2(tx, tz - 1.6), Vector2(0.5, 0.4))
	# Arenero.
	for e in [[Vector2(-48, 14), Vector3(4.2, 0.3, 0.2)], [Vector2(-48, 18), Vector3(4.2, 0.3, 0.2)], [Vector2(-50, 16), Vector3(0.2, 0.3, 4.2)], [Vector2(-46, 16), Vector3(0.2, 0.3, 4.2)]]:
		block(C_WOOD, e[0].x, e[0].y, e[1], 0.0, true, false)
	# Balancín.
	add("box", Color(0.3, 0.55, 0.3), Vector3(-53, gy(-53, 24) + 0.5, 24), Vector3(0.3, 0.5, 0.4))
	add_basis("box", Color(0.95, 0.55, 0.2), Vector3(-53, gy(-53, 24) + 0.65, 24), Basis(Vector3.FORWARD, 0.18) * Basis.from_scale(Vector3(3.6, 0.1, 0.35)))
	collider(Vector3(-53, gy(-53, 24) + 0.5, 24), Vector3(3.6, 1.0, 0.4))
	# Casita de juegos.
	var hx := -25.0
	var hz := 21.0
	house_box(Color(0.95, 0.7, 0.7), Vector3(hx, gy(hx, hz) + 1.1, hz), Vector3(2.6, 2.2, 2.6))
	add_basis("prism", Color(0.55, 0.3, 0.55), Vector3(hx, gy(hx, hz) + 2.7, hz), Basis.from_scale(Vector3(3.0, 1.0, 3.0)))
	add("box", Color(0.35, 0.25, 0.2), Vector3(hx + 1.31, gy(hx, hz) + 0.8, hz), Vector3(0.05, 1.4, 0.8))
	terrain.add_solid_box(Vector2(hx, hz), Vector2(1.3, 1.3))
	for p in [Vector2(-35, 38), Vector2(-24, 14), Vector2(-57, 12), Vector2(-58, 27)]:
		tree(p.x, p.y, 1.0, 0)
	tree(-36, 12, 1.0, 1)
	bin(-55.0, 37.0, 0.0)


func _zone_huerto() -> void:
	for bx in [-52.0, -44.0, -36.0]:
		for bz in [-14.0, -4.0]:
			terrain.paint_rect(Rect2(bx - 2.5, bz - 3.5, 5, 7), 1)
			for e in [[Vector2(0, -3.5), Vector3(5.2, 0.35, 0.2)], [Vector2(0, 3.5), Vector3(5.2, 0.35, 0.2)], [Vector2(-2.5, 0), Vector3(0.2, 0.35, 7.2)], [Vector2(2.5, 0), Vector3(0.2, 0.35, 7.2)]]:
				block(C_WOOD, bx + e[0].x, bz + e[0].y, e[1], 0.0, true, false)
			for k in 6:
				var px: float = bx + rng.randf_range(-1.8, 1.8)
				var pz: float = bz + rng.randf_range(-2.8, 2.8)
				if rng.randf() < 0.4:
					add("blob", Color(0.95, 0.5, 0.1), Vector3(px, gy(px, pz) + 0.2, pz), Vector3(0.6, 0.42, 0.6))
				else:
					add("blob", Color(0.32, 0.5, 0.2), Vector3(px, gy(px, pz) + 0.2, pz), Vector3(0.55, 0.4, 0.55))
	# Espantapájaros.
	var y := gy(-30, -8)
	add("cyl", C_WOOD_DARK, Vector3(-30, y + 1.1, -8), Vector3(0.12, 2.2, 0.12))
	add_basis("cyl", C_WOOD_DARK, Vector3(-30, y + 1.6, -8), Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.1, 1.8, 0.1)))
	add("box", Color(0.55, 0.3, 0.45), Vector3(-30, y + 1.35, -8), Vector3(0.6, 0.7, 0.3))
	add("sph", Color(0.85, 0.75, 0.5), Vector3(-30, y + 2.0, -8), Vector3(0.4, 0.4, 0.4))
	add("cone", Color(0.4, 0.3, 0.15), Vector3(-30, y + 2.35, -8), Vector3(0.7, 0.4, 0.7))
	collider(Vector3(-30, y + 1.1, -8), Vector3(0.3, 2.2, 0.3))
	terrain.add_solid_circle(Vector2(-30, -8), 0.15)
	# Buzón calabaza.
	block(C_WOOD_DARK, -25.0, 5.0, Vector3(0.12, 0.9, 0.12))
	add("sph", Color(0.95, 0.5, 0.12), Vector3(-25, gy(-25, 5) + 1.1, 5), Vector3(0.7, 0.55, 0.7))
	add("cyl", Color(0.3, 0.45, 0.2), Vector3(-25, gy(-25, 5) + 1.42, 5), Vector3(0.08, 0.15, 0.08))
	# Cobertizo y compost.
	house_box(Color(0.5, 0.42, 0.32), Vector3(-55, gy(-55, -20) + 1.4, -20), Vector3(4.0, 2.8, 3.0))
	add_basis("prism", Color(0.35, 0.3, 0.28), Vector3(-55, gy(-55, -20) + 3.3, -20), Basis.from_scale(Vector3(4.6, 1.0, 3.6)))
	terrain.add_solid_box(Vector2(-55, -20), Vector2(2.0, 1.5))
	for k in 3:
		block(C_WOOD, -44.0 + k * 1.8, -21.5, Vector3(1.5, 1.0, 1.5))
	for p in [Vector2(-57, 7), Vector2(-23, -22), Vector2(-58, -5)]:
		tree(p.x, p.y, 0.95, 0)
	bin(-56.0, -10.0, PI * 0.5)


func _zone_trasero() -> void:
	# Cenador en lo alto de la colina.
	var y := gy(0, -45)
	add("cyl6", C_STONE, Vector3(0, y + 0.15, -45), Vector3(6.0, 0.3, 6.0))
	for k in 6:
		var a := k * TAU / 6.0
		var px := cos(a) * 2.7
		var pz := -45.0 + sin(a) * 2.7
		add("cyl", C_PAINT, Vector3(px, y + 1.5, pz), Vector3(0.18, 2.7, 0.18))
		collider(Vector3(px, y + 1.5, pz), Vector3(0.2, 2.7, 0.2))
		terrain.add_solid_circle(Vector2(px, pz), 0.12)
	add("cone", Color(0.35, 0.45, 0.4), Vector3(0, y + 3.6, -45), Vector3(7.0, 1.8, 7.0))
	bench(0, -46.8, 0.0)
	# Mesa de picnic.
	var tx := 12.0
	var tz := -35.0
	add("box", C_WOOD, Vector3(tx, gy(tx, tz) + 0.75, tz), Vector3(2.2, 0.08, 0.9))
	add("box", C_WOOD, Vector3(tx, gy(tx, tz) + 0.45, tz - 0.75), Vector3(2.2, 0.06, 0.3))
	add("box", C_WOOD, Vector3(tx, gy(tx, tz) + 0.45, tz + 0.75), Vector3(2.2, 0.06, 0.3))
	add("box", C_WOOD_DARK, Vector3(tx, gy(tx, tz) + 0.37, tz), Vector3(0.1, 0.75, 1.8))
	collider(Vector3(tx, gy(tx, tz) + 0.4, tz), Vector3(2.2, 0.8, 1.8))
	for p in [Vector2(-14, -30), Vector2(14, -58), Vector2(-15, -54), Vector2(13, -31), Vector2(-6, -60), Vector2(-12, -42), Vector2(12, -46)]:
		tree(p.x, p.y, 1.25, 0)
	tree(6, -60, 1.0, 1)
	# Trampilla secreta bajo un montón natural de hojas.
	add("box", C_WOOD_DARK, Vector3(8, gy(8, -56) + 0.03, -56), Vector3(1.3, 0.06, 1.3), 0.0, false)
	add("box", C_IRON, Vector3(8.4, gy(8, -56) + 0.08, -56), Vector3(0.1, 0.05, 0.4), 0.0, false)
	density_points.append([Vector2(8, -56), 1.4, 14.0])
	station(StationObject.Kind.HATCH, Vector3(8, gy(8, -56), -56), Vector3(1.3, 0.4, 1.3))
	bin(-17.0, -37.0, PI * 0.5)


func _zone_piscina() -> void:
	var r := Terrain.POOL
	var deck := 0.15
	var coping := Color(0.86, 0.84, 0.8)
	add("box", coping, Vector3(r.get_center().x, deck + 0.05, r.position.y - 0.25), Vector3(r.size.x + 1.0, 0.1, 0.5))
	add("box", coping, Vector3(r.get_center().x, deck + 0.05, r.end.y + 0.25), Vector3(r.size.x + 1.0, 0.1, 0.5))
	add("box", coping, Vector3(r.end.x + 0.25, deck + 0.05, r.get_center().y), Vector3(0.5, 0.1, r.size.y))
	# Paredes de azulejo (visuales) siguiendo la forma del vaso.
	var tile := Color(0.45, 0.7, 0.78)
	for side in [r.position.y + 0.05, r.end.y - 0.05]:
		for k in 9:
			var x := r.position.x + 1.0 + k * 2.0
			var depth := deck - gy(x, r.get_center().y)
			if depth > 0.2:
				add("box", tile, Vector3(x, deck - depth * 0.5, side), Vector3(2.0, depth, 0.06), 0.0, false)
	add("box", tile, Vector3(r.end.x - 0.05, deck - 1.05, r.get_center().y), Vector3(0.06, 2.1, r.size.y), 0.0, false)
	# Trampolín.
	add("box", Color(0.3, 0.55, 0.75), Vector3(r.end.x - 0.6, deck + 0.55, r.get_center().y), Vector3(2.4, 0.08, 0.6))
	block(C_STONE_DARK, r.end.x + 0.9, r.get_center().y, Vector3(0.7, 0.6, 0.7))
	# Tumbonas y sombrilla.
	for k in 3:
		var x := 36.0 + k * 3.2
		add_basis("box", Color(0.95, 0.95, 0.9), Vector3(x, deck + 0.35, 4.0), Basis(Vector3.RIGHT, -0.25) * Basis.from_scale(Vector3(0.75, 0.08, 1.9)))
		add("box", C_WOOD, Vector3(x, deck + 0.15, 4.0), Vector3(0.7, 0.3, 1.8))
		collider(Vector3(x, deck + 0.3, 4.0), Vector3(0.75, 0.6, 1.9))
	add("cyl", C_IRON, Vector3(46.0, deck + 1.2, 4.5), Vector3(0.07, 2.4, 0.07))
	add("cone", Color(0.92, 0.42, 0.35), Vector3(46.0, deck + 2.45, 4.5), Vector3(3.2, 0.6, 3.2))
	# Caseta de la piscina.
	house_box(Color(0.9, 0.92, 0.95), Vector3(54, gy(54, -20) + 1.5, -20), Vector3(6.0, 3.0, 5.0))
	add_basis("prism", Color(0.3, 0.5, 0.65), Vector3(54, gy(54, -20) + 3.5, -20), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(5.6, 1.0, 6.6)))
	terrain.add_solid_box(Vector2(54, -20), Vector2(3.0, 2.5))
	for p in [Vector2(23, 7), Vector2(57, 7), Vector2(23, -22)]:
		tree(p.x, p.y, 1.05, 0)
	bin(56.0, -6.0, -PI * 0.5)


func _zone_laberinto() -> void:
	var cols := 10
	var rows := 9
	var x0 := -60.0
	var z0 := -61.0
	var cs := 4.0
	var mrng := RandomNumberGenerator.new()
	mrng.seed = 9091
	# h_walls[r][c]: pared al sur de la celda (entre fila r y r+1). v_walls[r][c]: al este.
	var h_walls := []
	var v_walls := []
	var visited := []
	for r in rows:
		h_walls.append([])
		v_walls.append([])
		visited.append([])
		for c in cols:
			h_walls[r].append(true)
			v_walls[r].append(true)
			visited[r].append(false)
	var stack := [Vector2i(5, 8)]
	visited[8][5] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var opts := []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if nb.x >= 0 and nb.x < cols and nb.y >= 0 and nb.y < rows and not visited[nb.y][nb.x]:
				opts.append(nb)
		if opts.is_empty():
			stack.pop_back()
			continue
		var nb: Vector2i = opts[mrng.randi() % opts.size()]
		_open_wall(h_walls, v_walls, cur, nb)
		visited[nb.y][nb.x] = true
		stack.append(nb)
	# Plaza central abierta y algunos atajos para que no sea frustrante.
	_open_wall(h_walls, v_walls, Vector2i(4, 4), Vector2i(5, 4))
	_open_wall(h_walls, v_walls, Vector2i(4, 5), Vector2i(5, 5))
	_open_wall(h_walls, v_walls, Vector2i(4, 4), Vector2i(4, 5))
	_open_wall(h_walls, v_walls, Vector2i(5, 4), Vector2i(5, 5))
	for k in 10:
		var c := mrng.randi_range(0, cols - 2)
		var r := mrng.randi_range(0, rows - 2)
		if mrng.randf() < 0.5:
			_open_wall(h_walls, v_walls, Vector2i(c, r), Vector2i(c + 1, r))
		else:
			_open_wall(h_walls, v_walls, Vector2i(c, r), Vector2i(c, r + 1))
	for r in rows:
		for c in cols:
			if r < rows - 1 and h_walls[r][c]:
				var z := z0 + (r + 1) * cs
				var x := x0 + (c + 0.5) * cs
				_hedge(x, z, cs + 0.8, true)
			if c < cols - 1 and v_walls[r][c]:
				var x := x0 + (c + 1) * cs
				var z := z0 + (r + 0.5) * cs
				_hedge(x, z, cs + 0.8, false)
	# Estatua central: un rastrillo gigante de piedra.
	var sx := -40.0
	var sz := -41.0
	var y := gy(sx, sz)
	add("box", C_STONE_DARK, Vector3(sx, y + 0.4, sz), Vector3(1.4, 0.8, 1.4))
	add("cyl", C_STONE, Vector3(sx, y + 2.2, sz), Vector3(0.18, 2.8, 0.18))
	add("box", C_STONE, Vector3(sx, y + 3.6, sz), Vector3(1.6, 0.2, 0.25))
	for k in 7:
		add("box", C_STONE, Vector3(sx - 0.72 + k * 0.24, y + 3.8, sz), Vector3(0.07, 0.4, 0.07))
	collider(Vector3(sx, y + 1.5, sz), Vector3(1.4, 3.0, 1.4))
	terrain.add_solid_box(Vector2(sx, sz), Vector2(0.7, 0.7))
	bin(-36.0, -44.5, 0.0)


func _open_wall(h_walls: Array, v_walls: Array, a: Vector2i, b: Vector2i) -> void:
	if a.x == b.x:
		var r := mini(a.y, b.y)
		h_walls[r][a.x] = false
	else:
		var c := mini(a.x, b.x)
		v_walls[a.y][c] = false


func _hedge(x: float, z: float, length: float, along_x: bool) -> void:
	var size := Vector3(length, 2.2, 0.8) if along_x else Vector3(0.8, 2.2, length)
	var y := gy(x, z)
	add("box", C_HEDGE if rng.randf() < 0.5 else Color(0.26, 0.44, 0.21), Vector3(x, y + 1.0, z), size + Vector3(0, 0.2, 0))
	collider(Vector3(x, y + 1.1, z), size)
	terrain.add_solid_box(Vector2(x, z), Vector2(size.x, size.z) * 0.5)


func _zone_invernadero() -> void:
	var r := Rect2(33, -51, 14, 10)
	var y := gy(40, -46)
	var brick := Color(0.66, 0.38, 0.28)
	var frame := Color(0.95, 0.95, 0.92)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.75, 0.9, 0.95, 0.28)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.1
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var walls := [
		[Vector3(r.get_center().x, 0, r.end.y), Vector3(r.size.x, 0, 0.15)],
		[Vector3(r.position.x, 0, r.get_center().y), Vector3(0.15, 0, r.size.y)],
		[Vector3(r.end.x, 0, r.get_center().y), Vector3(0.15, 0, r.size.y)],
		[Vector3(r.position.x + 3.0, 0, r.position.y), Vector3(6.0, 0, 0.15)],
		[Vector3(r.end.x - 3.0, 0, r.position.y), Vector3(6.0, 0, 0.15)],
	]
	for w in walls:
		var c: Vector3 = w[0]
		var s: Vector3 = w[1]
		add("box", brick, Vector3(c.x, y + 0.3, c.z), Vector3(s.x, 0.6, s.z))
		var g := MeshInstance3D.new()
		g.mesh = MeshFactory.box(Vector3(maxf(s.x, 0.04), 2.4, maxf(s.z, 0.04)))
		g.material_override = glass_mat
		g.position = Vector3(c.x, y + 1.8, c.z)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(g)
		collider(Vector3(c.x, y + 1.5, c.z), Vector3(maxf(s.x, 0.2), 3.0, maxf(s.z, 0.2)))
		terrain.add_solid_box(Vector2(c.x, c.z), Vector2(maxf(s.x, 0.2), maxf(s.z, 0.2)) * 0.5)
	for k in 8:
		var x := r.position.x + k * 2.0
		for zz in [r.position.y, r.end.y]:
			add("box", frame, Vector3(x, y + 1.8, zz), Vector3(0.1, 3.6, 0.18))
	for side in [-1.0, 1.0]:
		var roof := MeshInstance3D.new()
		roof.mesh = MeshFactory.box(Vector3(r.size.x, 0.05, 5.9))
		roof.material_override = glass_mat
		roof.position = Vector3(r.get_center().x, y + 4.4, r.get_center().y + side * 2.5)
		roof.rotation.x = side * 0.55
		roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(roof)
	add("box", frame, Vector3(r.get_center().x, y + 5.85, r.get_center().y), Vector3(r.size.x, 0.15, 0.2))
	for zz in [-49.5, -42.5]:
		block(C_WOOD, 40.0, zz, Vector3(10.0, 0.8, 1.0), 0.0, true, true)
		for k in 6:
			add("blob", FLOWERS[k % FLOWERS.size()].lerp(Color(0.3, 0.55, 0.25), 0.4), Vector3(36.0 + k * 1.6, y + 1.0, zz), Vector3(0.5, 0.45, 0.5))
	block(Color(0.7, 0.4, 0.25), 40.0, -46.0, Vector3(1.4, 0.9, 1.4))
	add("cyl", Color(0.3, 0.2, 0.12), Vector3(40.0, y + 0.92, -46.0), Vector3(1.2, 0.05, 1.2))
	# Tónico derramado.
	block(Color(0.2, 0.4, 0.85), 26.0, -35.0, Vector3(0.7, 0.9, 0.7), 0.4)
	add("cyl", Color(0.35, 0.55, 1.0), Vector3(27.0, gy(27, -35) + 0.02, -34.6), Vector3(2.2, 0.02, 1.6), 0.0, false)
	for p in [Vector2(24, -58), Vector2(57, -58), Vector2(57, -39), Vector2(24, -47)]:
		tree(p.x, p.y, 1.1, 0)
	bin(30.0, -30.0, 0.0)


func _zone_secret() -> void:
	var r: Rect2 = GameData.zone_by_id("taller_secreto")["rect"]
	var y := Terrain.SECRET_FLOOR
	var wallc := Color(0.5, 0.42, 0.36)
	house_box(wallc, Vector3(r.get_center().x, y + 2.0, r.position.y - 0.3), Vector3(r.size.x + 1.2, 4.4, 0.6))
	house_box(wallc, Vector3(r.get_center().x, y + 2.0, r.end.y + 0.3), Vector3(r.size.x + 1.2, 4.4, 0.6))
	house_box(wallc, Vector3(r.position.x - 0.3, y + 2.0, r.get_center().y), Vector3(0.6, 4.4, r.size.y))
	house_box(wallc, Vector3(r.end.x + 0.3, y + 2.0, r.get_center().y), Vector3(0.6, 4.4, r.size.y))
	house_box(Color(0.35, 0.3, 0.27), Vector3(r.get_center().x, y + 4.3, r.get_center().y), Vector3(r.size.x + 1.2, 0.4, r.size.y + 1.2))
	for k in 5:
		add("box", C_WOOD_DARK, Vector3(r.position.x + 2.0 + k * 4.5, y + 3.95, r.get_center().y), Vector3(0.3, 0.3, r.size.y))
	for p in [Vector3(76, y + 3.4, -36), Vector3(86, y + 3.4, -32)]:
		var l := OmniLight3D.new()
		l.position = p
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 2.2
		l.omni_range = 14.0
		root.add_child(l)
		add("sph", Color(1.0, 0.85, 0.55), p + Vector3(0, 0.3, 0), Vector3(0.4, 0.4, 0.4), 0.0, false)
	block(C_WOOD, 80.0, -43.0, Vector3(5.0, 1.0, 1.2))
	block(C_WOOD, 91.0, -35.0, Vector3(1.2, 1.0, 5.0))
	for k in 5:
		add("box", Color(0.6, 0.45, 0.3).lerp(Color(0.3, 0.45, 0.6), k * 0.2), Vector3(78.0 + k * 0.8, y + 1.2, -43.0), Vector3(0.5, 0.4, 0.5))
	# Rastrillo de cobre colgado.
	add_basis("cyl", Color(0.85, 0.5, 0.25), Vector3(84.0, y + 2.2, -43.6), Basis(Vector3.FORWARD, 0.3) * Basis.from_scale(Vector3(0.06, 2.4, 0.06)))
	add("box", Color(0.85, 0.5, 0.25), Vector3(84.4, y + 3.3, -43.6), Vector3(0.9, 0.12, 0.08))
	# Brizna, el robot dormido.
	var bx := 88.0
	var bz := -29.5
	add("sph", Color(0.75, 0.78, 0.8), Vector3(bx, y + 0.6, bz), Vector3(1.0, 0.9, 1.0))
	add("sph", Color(0.82, 0.85, 0.88), Vector3(bx, y + 1.25, bz), Vector3(0.6, 0.5, 0.6))
	add("sph", Color(0.2, 0.25, 0.3), Vector3(bx - 0.12, y + 1.3, bz + 0.27), Vector3(0.1, 0.1, 0.06))
	add("sph", Color(0.2, 0.25, 0.3), Vector3(bx + 0.12, y + 1.3, bz + 0.27), Vector3(0.1, 0.1, 0.06))
	add_basis("cyl", C_WOOD, Vector3(bx + 0.6, y + 0.8, bz), Basis(Vector3.FORWARD, -0.5) * Basis.from_scale(Vector3(0.05, 1.4, 0.05)))
	station(StationObject.Kind.ROBOT, Vector3(bx, y, bz), Vector3(1.2, 1.6, 1.2), {}, true)
	terrain.add_solid_circle(Vector2(bx, bz), 0.5)
	# Escalera de salida.
	for k in 8:
		add("box", C_WOOD, Vector3(72.0, y + 0.3 + k * 0.5, -26.5), Vector3(1.0, 0.06, 0.12))
	add("box", C_WOOD_DARK, Vector3(71.5, y + 2.0, -26.5), Vector3(0.08, 4.0, 0.12))
	add("box", C_WOOD_DARK, Vector3(72.5, y + 2.0, -26.5), Vector3(0.08, 4.0, 0.12))
	station(StationObject.Kind.LADDER, Vector3(72.0, y, -27.0), Vector3(1.2, 2.5, 0.6))
	bin(90.0, -42.0, 0.0)


func _outside() -> void:
	# Carretera, casas vecinas y bosque alrededor de la finca.
	add("box", Color(0.3, 0.3, 0.32), Vector3(0, -0.02, 73), Vector3(260, 0.05, 7), 0.0, false)
	for k in 16:
		add("box", Color(0.95, 0.9, 0.7), Vector3(-120 + k * 16.0, 0.02, 73), Vector3(5.0, 0.03, 0.2), 0.0, false)
	for hx in [-45.0, -10.0, 30.0, 65.0]:
		var hcol := Color(0.85, 0.78, 0.65) if rng.randf() < 0.5 else Color(0.75, 0.6, 0.52)
		add("box", hcol, Vector3(hx, 3.0, 92), Vector3(10, 6, 8))
		add_basis("prism", Color(0.45, 0.25, 0.2), Vector3(hx, 7.5, 92), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(9, 3, 11)))
	var bounds := Rect2(-62, -64, 124, 130)
	var x := -105.0
	while x <= 105.0:
		var z := -105.0
		while z <= 70.0:
			var px := x + rng.randf_range(-3.5, 3.5)
			var pz := z + rng.randf_range(-3.5, 3.5)
			var p := Vector2(px, pz)
			var d := maxf(maxf(bounds.position.x - px, px - bounds.end.x), maxf(bounds.position.y - pz, pz - bounds.end.y))
			if d > 3.0 and d < 34.0 and not Rect2(62, -50, 36, 30).has_point(p):
				tree(px, pz, rng.randf_range(1.2, 1.9), -1, false)
			z += 8.5
		x += 8.5
	for k in 9:
		var a := k * TAU / 9.0 + 0.3
		add("blob", Color(0.4, 0.45, 0.28), Vector3(cos(a) * 190.0, -8.0, sin(a) * 190.0), Vector3(120, 40, 90), 0.0, false)


# ------------------------------------------------------------------ restauración por zona

func _zone_decor(z: Dictionary) -> void:
	var zid: String = z["id"]
	var r: Rect2 = z["rect"]
	var y_secret: bool = z.get("secret", false)
	var restore := Node3D.new()
	restore.name = "Restore_" + zid
	restore.visible = false
	root.add_child(restore)
	restore_nodes[zid] = restore
	var debris := Node3D.new()
	debris.name = "Debris_" + zid
	root.add_child(debris)
	debris_nodes[zid] = debris
	var stems := []
	var blooms := []
	var bloom_cols := []
	var tries := 0
	while blooms.size() < 70 and tries < 500:
		tries += 1
		var px := rng.randf_range(r.position.x + 0.8, r.end.x - 0.8)
		var pz := rng.randf_range(r.position.y + 0.8, r.end.y - 0.8)
		var edge := minf(minf(px - r.position.x, r.end.x - px), minf(pz - r.position.y, r.end.y - pz))
		if edge > 2.6 and rng.randf() < 0.75:
			continue
		if terrain.is_solid(px, pz):
			continue
		var py := gy(px, pz)
		for k in 3:
			var ox := px + rng.randf_range(-0.35, 0.35)
			var oz := pz + rng.randf_range(-0.35, 0.35)
			var h := rng.randf_range(0.25, 0.5)
			stems.append(Transform3D(Basis.from_scale(Vector3(0.03, h, 0.03)), Vector3(ox, py + h * 0.5, oz)))
			blooms.append(Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.14, 0.22)), Vector3(ox, py + h, oz)))
			bloom_cols.append(FLOWERS[rng.randi() % FLOWERS.size()])
	if not y_secret:
		restore.add_child(_mm_node(units["cyl6"], MeshFactory.mat(Color(0.3, 0.55, 0.22)), stems, []))
		var bm := StandardMaterial3D.new()
		bm.vertex_color_use_as_albedo = true
		bm.roughness = 0.8
		restore.add_child(_mm_node(units["blob"], bm, blooms, bloom_cols))
	# Ramas caídas y trastos: desaparecen al restaurar la zona.
	var branches := []
	for k in 9:
		var px := rng.randf_range(r.position.x + 2, r.end.x - 2)
		var pz := rng.randf_range(r.position.y + 2, r.end.y - 2)
		if terrain.is_solid(px, pz):
			continue
		var blen := rng.randf_range(1.2, 2.6)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5 + rng.randf_range(-0.1, 0.1)) * Basis.from_scale(Vector3(0.09, blen, 0.09))
		branches.append(Transform3D(b, Vector3(px, gy(px, pz) + 0.06, pz)))
	debris.add_child(_mm_node(units["trunk"], MeshFactory.mat(Color(0.33, 0.22, 0.14)), branches, []))


func _mm_node(mesh: Mesh, material: Material, xforms: Array, colors: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		if not colors.is_empty():
			mm.set_instance_color(k, colors[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _flush() -> void:
	var holder := Node3D.new()
	holder.name = "StaticProps"
	root.add_child(holder)
	for key in batches:
		var b: Dictionary = batches[key]
		var xs: Array = b["x"]
		var mi := _mm_node(units[b["shape"]], MeshFactory.mat(b["color"]), xs, [])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	batches.clear()
