class_name WorldBuilder
extends RefCounted
## Construye toda la finca de forma procedural: muros, vallas, casa, árboles, atrezo de cada zona,
## objetos interactivos y decoración que aparece al restaurar cada zona.
## La geometría estática se agrupa en MultiMesh por malla, material y región (pocas llamadas de dibujo):
## el color va por instancia y su alfa elige el patrón procedural (madera, piedra, tejas...) del
## shader de atrezo; copas, setos y arbustos usan el shader de follaje (con viento).
## Los objetos repetidos y detallados (árboles, farolas, bancos, contenedores) son prefabricados:
## una sola malla fusionada con color por vértice, instanciada muchas veces.

const K_PROP := 0
const K_FOL := 1
const K_LAMP := 2

const P_PLAIN := MeshFactory.PAT_PLAIN
const P_WOOD := MeshFactory.PAT_WOOD
const P_PLANKS_H := MeshFactory.PAT_PLANKS_H
const P_PLANKS_V := MeshFactory.PAT_PLANKS_V
const P_STONE := MeshFactory.PAT_STONE
const P_BRICK := MeshFactory.PAT_BRICK
const P_ROOF := MeshFactory.PAT_ROOF
const P_BARK := MeshFactory.PAT_BARK
const P_BIRCH := MeshFactory.PAT_BIRCH
const P_METAL := MeshFactory.PAT_METAL
const P_GLASS := MeshFactory.PAT_GLASS
const P_TILE := MeshFactory.PAT_TILE
const P_STRIPES := MeshFactory.PAT_STRIPES
const P_WATER := MeshFactory.PAT_WATER
const P_STRAW := MeshFactory.PAT_STRAW
const P_GLOW := MeshFactory.PAT_GLOW

const C_TRUNK := Color(0.42, 0.29, 0.19)
const C_BIRCH := Color(0.92, 0.9, 0.84)
const C_STONE := Color(0.74, 0.7, 0.62)
const C_STONE_DARK := Color(0.56, 0.53, 0.48)
const C_WOOD := Color(0.62, 0.42, 0.25)
const C_WOOD_DARK := Color(0.4, 0.27, 0.16)
const C_PAINT := Color(0.95, 0.92, 0.85)
const C_HEDGE := Color(0.21, 0.37, 0.18)
const C_IRON := Color(0.17, 0.17, 0.19)
const C_TERRACOTTA := Color(0.76, 0.4, 0.24)
const C_SAND := Color(0.9, 0.8, 0.58)
const C_SOIL := Color(0.32, 0.22, 0.14)
const C_LEAFPILE := Color(0.86, 0.45, 0.14)
const CANOPY := [Color(0.93, 0.5, 0.13), Color(0.95, 0.74, 0.2), Color(0.8, 0.24, 0.1), Color(0.88, 0.4, 0.12), Color(0.72, 0.45, 0.13)]
const FLOWERS := [Color(0.95, 0.45, 0.6), Color(0.62, 0.42, 0.85), Color(1.0, 0.96, 0.9), Color(1.0, 0.82, 0.25), Color(0.92, 0.25, 0.2)]
const TREE_TINTS := {
	"maple": [Color(0.95, 0.42, 0.11), Color(0.97, 0.58, 0.14), Color(0.8, 0.19, 0.08), Color(0.98, 0.7, 0.2), Color(0.9, 0.3, 0.1)],
	"oak": [Color(0.86, 0.58, 0.17), Color(0.74, 0.44, 0.14), Color(0.92, 0.7, 0.24), Color(0.72, 0.58, 0.22)],
	"birch": [Color(0.98, 0.83, 0.26), Color(0.96, 0.72, 0.2), Color(0.88, 0.84, 0.34)],
	"pine": [Color(0.17, 0.33, 0.21), Color(0.21, 0.38, 0.23), Color(0.15, 0.3, 0.2)],
}

var root: Node3D
var terrain: Terrain
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var drng := RandomNumberGenerator.new()   # decoración menuda (no altera la disposición principal)
var batches := {}
var meshes := {}
var density_points := []
var bins: Array[RecycleBin] = []
var gates: Array[GateDoor] = []
var ducts_defs := []
var stations: Array[StationObject] = []
var restore_nodes := {}     # zona -> Node3D que aparece al 100 %
var debris_nodes := {}      # zona -> Node3D que desaparece al 100 %
var batch_count := 0
var instance_count := 0
var batch_stats := {}       # malla -> número de lotes (diagnóstico)
var dense := true           # calidad baja: menos decoración menuda
var _outside_mode := false


func build(r: Node3D, t: Terrain) -> void:
	root = r
	terrain = t
	rng.seed = 20241013
	drng.seed = 777
	dense = PerformanceManager.level != PerformanceManager.LOW
	body = StaticBody3D.new()
	body.name = "StaticWorld"
	body.collision_layer = Interactable.LAYER_WORLD
	root.add_child(body)
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


# ------------------------------------------------------------------ lotes

func gy(x: float, z: float) -> float:
	return Terrain.OUTER_Y if _outside_mode else terrain.height_at(x, z)


func _ground(pos: Vector3) -> float:
	return Terrain.OUTER_Y if _outside_mode else gy(pos.x, pos.z)


func pcol(c: Color, pat: int, vertical_grain: bool = false) -> Color:
	return MeshFactory.pc(c, pat, vertical_grain)


func _shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)


func _mesh_of(id: String) -> Mesh:
	if not meshes.has(id):
		meshes[id] = MeshFactory.unit(id)
	return meshes[id]


## Añade una instancia a su lote (malla + material + región de 40 m). Para no multiplicar los lotes,
## todo el atrezo normal proyecta sombra y el detalle menudo (con distancia de dibujado) no.
func put(id: String, kind: int, xf: Transform3D, color: Color, custom: Color, shadow: bool = true, detail: bool = false) -> void:
	match id:
		"cyl8":
			id = "cyl6"
		"cone6":
			id = "cone"
		"rock2":
			id = "rock0"
		"blob1", "blob2":
			if kind == K_FOL:
				id = "blob0"
	shadow = not detail and kind != K_LAMP and not _outside_mode
	var p := xf.origin
	var cell := 80.0 if _outside_mode else 40.0
	var region := int(floor((p.x + 240.0) / cell)) * 1000 + int(floor((p.z + 240.0) / cell)) + (500000 if _outside_mode else 0)
	var key := "%s|%d|%d|%d" % [id, kind, region, int(detail)]
	if not batches.has(key):
		_mesh_of(id)
		batches[key] = {"id": id, "kind": kind, "shadow": shadow, "detail": detail, "x": [], "c": [], "d": []}
	var b: Dictionary = batches[key]
	(b["x"] as Array).append(xf)
	(b["c"] as Array).append(color)
	(b["d"] as Array).append(custom)


func add(shape: String, color: Color, pos: Vector3, size: Vector3, rot_y: float = 0.0, shadow: bool = true) -> void:
	add_basis(shape, color, pos, Basis(Vector3.UP, rot_y) * Basis.from_scale(size), shadow)


## Pieza de atrezo. ao: radio (m) de la oclusión de contacto con el suelo (-1 = según su tamaño).
func add_basis(shape: String, color: Color, pos: Vector3, basis: Basis, shadow: bool = true, ao: float = -1.0, detail: bool = false) -> void:
	if ao < 0.0:
		ao = clampf(0.35 * maxf(basis.x.length(), basis.z.length()), 0.12, 0.9)
	put(shape, K_PROP, Transform3D(basis, pos), color, Color(_ground(pos), ao, rng.randf(), 0.0), shadow, detail)


## Pieza en el marco local de un objeto (posición y giro), con tamaño en metros.
func ladd(shape: String, color: Color, frame: Transform3D, lpos: Vector3, size: Vector3, lbasis: Basis = Basis.IDENTITY, shadow: bool = true) -> void:
	add_basis(shape, color, frame * lpos, frame.basis * lbasis * Basis.from_scale(size), shadow)


## Follaje (copas, setos, arbustos): sway = vaivén por viento, ao = radio de oclusión con el suelo.
func fol(shape: String, color: Color, pos: Vector3, basis: Basis, sway: float = 0.5, ao: float = 0.0, shadow: bool = true, detail: bool = false) -> void:
	put(shape, K_FOL, Transform3D(basis, pos), color, Color(_ground(pos), sway, rng.randf(), ao), shadow, detail)


## Cristal luminoso de farola (material compartido con Atmosphere, que lo enciende al atardecer).
func glow(shape: String, pos: Vector3, basis: Basis) -> void:
	put(shape, K_LAMP, Transform3D(basis, pos), Color.WHITE, Color(0, 0, 0, 0), false)


## Instancia de un prefabricado (malla fusionada construida una vez con builder).
func prefab(id: String, kind: int, builder: Callable, xf: Transform3D, tint: Color = Color.WHITE, ao: float = 0.5, shadow: bool = true, sway: float = 0.0) -> void:
	if not meshes.has(id):
		meshes[id] = MeshFactory.prefab(id, builder)
	var g := _ground(xf.origin)
	var custom := Color(g, sway, rng.randf(), ao) if kind == K_FOL else Color(g, ao, rng.randf(), 0.0)
	put(id, kind, xf, tint, custom, shadow)


func _flush() -> void:
	var holder := Node3D.new()
	holder.name = "StaticProps"
	root.add_child(holder)
	var detail_range := float(PerformanceManager.get_param("props_distance")) * 0.42
	batch_count = 0
	instance_count = 0
	for key in batches:
		var b: Dictionary = batches[key]
		var xs: Array = b["x"]
		var mat: Material
		match int(b["kind"]):
			K_FOL: mat = MeshFactory.foliage_mat()
			K_LAMP: mat = MeshFactory.lamp_mat()
			_: mat = MeshFactory.prop_mat()
		var mi := _mm_node(meshes[b["id"]], mat, xs, b["c"], b["d"])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if b["detail"]:
			mi.visibility_range_end = detail_range
		holder.add_child(mi)
		batch_count += 1
		instance_count += xs.size()
		batch_stats[b["id"]] = int(batch_stats.get(b["id"], 0)) + 1
	batches.clear()


## Nodo MultiMesh situado en el centro de sus instancias (la distancia de dibujado se mide bien
## y las coordenadas locales son pequeñas).
func _mm_node(mesh: Mesh, material: Material, xforms: Array, colors: Array, customs: Array = []) -> MultiMeshInstance3D:
	var center := Vector3.ZERO
	for x in xforms:
		center += (x as Transform3D).origin
	if not xforms.is_empty():
		center /= xforms.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.use_custom_data = not customs.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		var xf: Transform3D = xforms[k]
		xf.origin -= center
		mm.set_instance_transform(k, xf)
		if not colors.is_empty():
			mm.set_instance_color(k, colors[k])
		if not customs.is_empty():
			mm.set_instance_custom_data(k, customs[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.position = center
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------ utilidades de juego

## Caja apoyada en el suelo (pos = centro de la base).
func block(color: Color, x: float, z: float, size: Vector3, rot_y: float = 0.0, collide: bool = true, leaf_solid: bool = true, y_off: float = 0.0) -> void:
	var y := gy(x, z) + y_off
	add("box", color, Vector3(x, y + size.y * 0.5, z), size, rot_y)
	if collide:
		collider(Vector3(x, y + size.y * 0.5, z), size, rot_y)
	if leaf_solid:
		terrain.add_solid_box(Vector2(x, z), Vector2(size.x, size.z) * 0.5, rot_y)


## Solo colisión y hueco para las hojas (sin geometría visible).
func solid(x: float, z: float, size: Vector3, rot_y: float = 0.0, leaf_solid: bool = true) -> void:
	collider(Vector3(x, gy(x, z) + size.y * 0.5, z), size, rot_y)
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


# ------------------------------------------------------------------ árboles

## Árbol de una de cuatro especies (arce, roble, abedul, pino), cada una con tres variantes
## prefabricadas: tronco con raíces y ramas (atrezo) + copa de racimos (follaje con viento).
func tree(x: float, z: float, scale: float = 1.0, kind: int = -1, collide: bool = true) -> void:
	if kind < 0:
		kind = 0 if rng.randf() < 0.65 else (1 if rng.randf() < 0.6 else 2)
	var y := gy(x, z) if collide else Terrain.OUTER_Y
	var s := scale * rng.randf_range(0.85, 1.15)
	var species := "pine"
	if kind == 0:
		species = "maple" if rng.randf() < 0.6 else "oak"
	elif kind == 1:
		species = "birch"
	var variant := rng.randi() % 2
	var lod := not collide
	if lod:
		# Bosque exterior: una variante por especie y troncos sin ramas (pocas mallas, pocos lotes).
		variant = 0
		if species == "birch":
			species = "maple"
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y, z))
	var tid := ("tl_%s" if lod else "tr_%s_%d") % ([species] if lod else [species, variant])
	var cid := ("cl_%s" if lod else "cn_%s_%d") % ([species] if lod else [species, variant])
	if not meshes.has(tid):
		meshes[tid] = MeshFactory.prefab(tid, _tree_parts.bind(species, variant, 3 if lod else 0))
	if not meshes.has(cid):
		meshes[cid] = MeshFactory.prefab(cid, _tree_parts.bind(species, variant, 2 if lod else 1))
	var pal: Array = TREE_TINTS[species]
	var tint: Color = pal[rng.randi() % pal.size()]
	tint = tint.lerp(pal[rng.randi() % pal.size()], rng.randf() * 0.5) * rng.randf_range(0.92, 1.06)
	tint.a = 1.0
	put(tid, K_PROP, xf, Color.WHITE, Color(y, 0.55 * s, rng.randf(), 0.0), true)
	put(cid, K_FOL, xf, tint, Color(y, 0.55 if species == "pine" else 1.0, rng.randf(), 0.0), true)
	if species != "pine":
		density_points.append([Vector2(x, z), 4.2 * s, 2.0])
	if collide:
		collider(Vector3(x, y + 1.5, z), Vector3(0.6, 3.0, 0.6) * s)
		terrain.add_solid_circle(Vector2(x, z), 0.28 * s)
		# Matas y setas al pie del tronco.
		if dense and species != "pine":
			for k in 3:
				var a := drng.randf() * TAU
				var d := drng.randf_range(0.45, 0.8) * s
				tuft(x + cos(a) * d, z + sin(a) * d, drng.randf_range(0.3, 0.5))
			if drng.randf() < 0.35:
				var a2 := drng.randf() * TAU
				mushrooms(x + cos(a2) * 0.7 * s, z + sin(a2) * 0.7 * s)


func _branch_part(from: Vector3, to: Vector3, rad: float, color: Color) -> Array:
	var d := to - from
	var len := d.length()
	var yax := d / len
	var ref := Vector3.FORWARD if absf(yax.z) < 0.9 else Vector3.RIGHT
	var xax := yax.cross(ref).normalized()
	var zax := xax.cross(yax)
	return [MeshFactory.unit("branch"), Transform3D(Basis(xax * rad * 2.0, yax * len, zax * rad * 2.0), from), color]


## Piezas de un árbol. part: 0 tronco y ramas, 1 copa, 2 copa lejana (menos racimos), 3 tronco lejano.
## La copa lleva colores relativos por racimo (más rojizo, más dorado); el tono otoñal lo pone la instancia.
func _tree_parts(species: String, variant: int, part: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = 1000 + variant * 7919 + species.length() * 104729
	var parts := []
	var bark := pcol(C_TRUNK, P_BARK)
	var mults := [Color(1, 1, 1), Color(1.0, 0.74, 0.66), Color(0.97, 0.97, 0.82), Color(0.9, 0.82, 0.8)]
	if species == "pine":
		var h := 2.2
		if part == 0 or part == 3:
			parts.append(MeshFactory.part("trunk", Vector3(0, h * 0.5, 0), Vector3(0.46, h, 0.46), pcol(C_TRUNK.darkened(0.15), P_BARK)))
			return parts
		var tiers := 5 if part == 1 else 3
		for k in tiers:
			var t := float(k) / (tiers - 1)
			var w := lerpf(3.5, 1.0, t) * r.randf_range(0.94, 1.06)
			var th := lerpf(1.7, 1.35, t)
			var c := Color(0.86, 0.9, 0.86).lerp(Color.WHITE, t)
			parts.append([MeshFactory.unit("pine"), Transform3D(Basis(Vector3.UP, r.randf() * TAU) * Basis.from_scale(Vector3(w, th, w)), Vector3(0, lerpf(1.75, 5.5, t), 0)), c])
		return parts
	var h := 3.0
	var trunk_d := 0.62
	var main_size := Vector3(3.3, 3.2, 3.3)
	var main_y := 1.25
	var n := 4
	var spread := Vector2(1.15, 1.55)
	var sub_size := Vector2(1.9, 2.5)
	var sub_y := Vector2(-0.15, 1.9)
	var squash := 0.95
	var bcol := bark
	if species == "oak":
		h = 2.6
		trunk_d = 0.86
		main_size = Vector3(3.9, 3.0, 3.9)
		main_y = 1.4
		n = 4
		spread = Vector2(1.7, 2.15)
		sub_size = Vector2(2.3, 2.9)
		sub_y = Vector2(0.1, 1.6)
		squash = 0.82
	elif species == "birch":
		h = 3.7
		trunk_d = 0.36
		main_size = Vector3(2.2, 2.7, 2.2)
		main_y = 1.0
		n = 3
		spread = Vector2(0.6, 0.95)
		sub_size = Vector2(1.5, 1.9)
		sub_y = Vector2(-0.8, 0.9)
		squash = 1.25
		bcol = pcol(C_BIRCH, P_BIRCH)
	if part == 2:
		n = 2
	var subs := []
	for k in n:
		var a := k * TAU / n + r.randf_range(-0.4, 0.4) + variant
		var rad := r.randf_range(spread.x, spread.y)
		var t := float(k % 2) if n > 2 else 0.5
		subs.append(Vector3(cos(a) * rad, h + lerpf(sub_y.x, sub_y.y, clampf(t * 0.7 + r.randf() * 0.3, 0.0, 1.0)), sin(a) * rad))
	if part == 0 or part == 3:
		var lean := Basis(Vector3.FORWARD, r.randf_range(-0.05, 0.05)) if species == "birch" else Basis.IDENTITY
		parts.append([MeshFactory.unit("trunk"), Transform3D(lean * Basis.from_scale(Vector3(trunk_d, h, trunk_d)), Vector3(0, h * 0.5, 0)), bcol])
		if part == 3:
			return parts
		var br := trunk_d * (0.26 if species != "birch" else 0.3)
		for c in subs:
			var cv: Vector3 = c
			var from := Vector3(0, h * r.randf_range(0.62, 0.8), 0)
			parts.append(_branch_part(from, Vector3(cv.x * 0.72, cv.y - 0.2, cv.z * 0.72), br, bcol))
		if species == "oak":
			parts.append(_branch_part(Vector3(0, h * 0.85, 0), Vector3(0.2, h + 0.9, -0.1), trunk_d * 0.3, bcol))
		return parts
	# Copa: un racimo principal y varios secundarios.
	parts.append([MeshFactory.unit("blob%d" % variant), Transform3D(Basis(Vector3.UP, r.randf() * TAU) * Basis.from_scale(main_size), Vector3(0, h + main_y, 0)), mults[0]])
	for k in subs.size():
		var cv: Vector3 = subs[k]
		var sz := r.randf_range(sub_size.x, sub_size.y)
		var bid := "blob_lo" if part == 2 else "blob%d" % ((variant + k + 1) % 3)
		parts.append([MeshFactory.unit(bid), Transform3D(Basis(Vector3.UP, r.randf() * TAU) * Basis.from_scale(Vector3(sz, sz * squash, sz)), cv), mults[1 + k % 3]])
	if part == 1 and species == "birch":
		parts.append([MeshFactory.unit("blob1"), Transform3D(Basis.from_scale(Vector3(1.3, 1.6, 1.3)), Vector3(0.2, h + 2.3, -0.1)), mults[2]])
	return parts


# ------------------------------------------------------------------ piezas de decoración

func tuft(x: float, z: float, size: float, color: Color = Color(-1, 0, 0)) -> void:
	if color.r < 0.0:
		color = Color(0.42, 0.5, 0.2).lerp(Color(0.7, 0.62, 0.3), drng.randf())
	var y := gy(x, z)
	fol("tuft", color, Vector3(x, y + size * 0.45, z), Basis(Vector3.UP, drng.randf() * TAU) * Basis.from_scale(Vector3(size, size, size)), 1.0, 0.0, false, true)


func mushrooms(x: float, z: float) -> void:
	var y := gy(x, z)
	for k in 2 + drng.randi() % 3:
		var px := x + drng.randf_range(-0.25, 0.25)
		var pz := z + drng.randf_range(-0.25, 0.25)
		var h := drng.randf_range(0.06, 0.14)
		add_basis("cyl6", Color(0.93, 0.88, 0.78), Vector3(px, y + h * 0.5, pz), Basis.from_scale(Vector3(0.035, h, 0.035)), false, 0.05, true)
		var cap := Color(0.75, 0.22, 0.12) if drng.randf() < 0.6 else Color(0.72, 0.5, 0.3)
		add_basis("sph_lo", cap, Vector3(px, y + h, pz), Basis.from_scale(Vector3(0.14, 0.07, 0.14) * drng.randf_range(0.8, 1.3)), false, 0.0, true)


func pumpkin(x: float, z: float, size: float = 0.5, y_off: float = 0.0) -> void:
	var y := gy(x, z) + y_off
	var c := Color(0.95, 0.5, 0.1).lerp(Color(0.98, 0.62, 0.15), drng.randf())
	if drng.randf() < 0.12:
		c = Color(0.93, 0.9, 0.8)
	add_basis("pumpkin", c, Vector3(x, y + size * 0.3, z), Basis(Vector3.UP, drng.randf() * TAU) * Basis.from_scale(Vector3.ONE * size), true, size * 0.6)


func rock(x: float, z: float, size: float, collide: bool = false) -> void:
	var y := gy(x, z)
	var c := C_STONE_DARK.lerp(C_STONE, drng.randf())
	add_basis("rock%d" % (drng.randi() % 3), c, Vector3(x, y + size * 0.18, z), Basis(Vector3.UP, drng.randf() * TAU) * Basis.from_scale(Vector3(size, size * drng.randf_range(0.6, 0.9), size * drng.randf_range(0.8, 1.1))), true, size * 0.5)
	if collide:
		collider(Vector3(x, y + size * 0.25, z), Vector3(size * 0.8, size * 0.5, size * 0.8))
		terrain.add_solid_circle(Vector2(x, z), size * 0.4)


## Arbusto de varios racimos. Con collide, bloquea al jugador y a las hojas en su base.
func bush(x: float, z: float, size: float, color: Color, collide: bool = true) -> void:
	var y := gy(x, z)
	var n := 2 + rng.randi() % 2
	for k in n:
		var off := Vector3.ZERO
		if k > 0:
			off = Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)) * size
		var sz := size * (1.0 if k == 0 else rng.randf_range(0.6, 0.85))
		var c := color.lerp(color.lightened(0.15), rng.randf())
		fol("blob%d" % (rng.randi() % 3), c, Vector3(x + off.x, y + sz * 0.32, z + off.z), Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sz, sz * 0.8, sz)), 0.4, size * 0.45)
	if collide:
		collider(Vector3(x, y + size * 0.4, z), Vector3(size * 0.7, size * 0.8, size * 0.7))
		terrain.add_solid_circle(Vector2(x, z), size * 0.38)


## Macizo de flores pequeño (sin colisión).
func flower_patch(x: float, z: float, radius: float, count: int, palette: Array = FLOWERS, y_off: float = 0.0) -> void:
	for k in count:
		var a := drng.randf() * TAU
		var d := sqrt(drng.randf()) * radius
		var px := x + cos(a) * d
		var pz := z + sin(a) * d
		var y := gy(px, pz) + y_off
		var h := drng.randf_range(0.22, 0.42)
		add_basis("cyl6", Color(0.3, 0.52, 0.22), Vector3(px, y + h * 0.5, pz), Basis.from_scale(Vector3(0.025, h, 0.025)), false, 0.0, true)
		var c: Color = palette[drng.randi() % palette.size()]
		add_basis("flower", c, Vector3(px, y + h, pz), Basis(Vector3.UP, drng.randf() * TAU) * Basis(Vector3.RIGHT, drng.randf_range(-0.3, 0.3)) * Basis.from_scale(Vector3.ONE * drng.randf_range(0.28, 0.4)), false, 0.0, true)
	if y_off > 0.0:
		return
	for k in maxi(1, count / 3):
		tuft(x + drng.randf_range(-radius, radius) * 0.7, z + drng.randf_range(-radius, radius) * 0.7, drng.randf_range(0.25, 0.4), Color(0.3, 0.5, 0.2))


## Maceta de barro con planta (bola recortada, hierba o flores).
func pot(x: float, z: float, size: float = 0.6, plant: int = 0, y_off: float = 0.0, collide: bool = true) -> void:
	var y := gy(x, z) + y_off
	var f := Transform3D(Basis.IDENTITY, Vector3(x, y, z))
	ladd("cyl", pcol(C_TERRACOTTA, P_PLAIN), f, Vector3(0, size * 0.4, 0), Vector3(size * 0.8, size * 0.8, size * 0.8))
	ladd("cyl", pcol(C_TERRACOTTA.lightened(0.08), P_PLAIN), f, Vector3(0, size * 0.78, 0), Vector3(size * 0.9, size * 0.14, size * 0.9), Basis.IDENTITY, false)
	ladd("cyl", C_SOIL, f, Vector3(0, size * 0.8, 0), Vector3(size * 0.76, 0.02, size * 0.76), Basis.IDENTITY, false)
	match plant:
		0:
			fol("blob_lo", Color(0.24, 0.45, 0.2), Vector3(x, y + size * 1.25, z), Basis.from_scale(Vector3.ONE * size * 1.05), 0.3)
		1:
			for k in 3:
				fol("tuft", Color(0.6, 0.6, 0.32), Vector3(x + drng.randf_range(-0.1, 0.1) * size, y + size * 1.15, z + drng.randf_range(-0.1, 0.1) * size), Basis(Vector3.UP, k * 2.1) * Basis.from_scale(Vector3(size, size * 1.3, size)), 1.0, 0.0, false)
		_:
			fol("blob_lo", Color(0.28, 0.48, 0.22), Vector3(x, y + size * 0.95, z), Basis.from_scale(Vector3(size * 0.95, size * 0.6, size * 0.95)), 0.3, 0.0, false)
			for k in 5:
				var a := k * TAU / 5.0 + drng.randf()
				var c: Color = FLOWERS[drng.randi() % FLOWERS.size()]
				add_basis("flower", c, Vector3(x + cos(a) * size * 0.3, y + size * 1.15, z + sin(a) * size * 0.3), Basis.from_scale(Vector3.ONE * size * 0.45), false, 0.0)
	if collide:
		collider(Vector3(x, y + size * 0.5, z), Vector3(size * 0.75, size, size * 0.75))
		terrain.add_solid_circle(Vector2(x, z), size * 0.4)


func hay_bale(x: float, z: float, rot_y: float = 0.0) -> void:
	var y := gy(x, z)
	var f := Transform3D(Basis(Vector3.UP, rot_y), Vector3(x, y, z))
	var straw := pcol(Color(0.88, 0.74, 0.4), P_STRAW)
	ladd("cyl", straw, f, Vector3(0, 0.5, 0), Vector3(1.0, 1.3, 1.0), Basis(Vector3.FORWARD, PI * 0.5))
	for sx in [-0.35, 0.35]:
		ladd("cyl", Color(0.55, 0.35, 0.2), f, Vector3(sx, 0.5, 0), Vector3(1.02, 0.04, 1.02), Basis(Vector3.FORWARD, PI * 0.5), false)
	collider(f * Vector3(0, 0.5, 0), Vector3(1.3, 1.0, 1.0), rot_y)
	terrain.add_solid_box(Vector2(x, z), Vector2(0.65, 0.5), rot_y)


func wheelbarrow(x: float, z: float, rot_y: float, load: Color = C_LEAFPILE) -> void:
	var y := gy(x, z)
	var f := Transform3D(Basis(Vector3.UP, rot_y), Vector3(x, y, z))
	var tray := pcol(Color(0.25, 0.48, 0.42), P_METAL)
	ladd("box", tray, f, Vector3(0, 0.55, 0), Vector3(0.75, 0.32, 1.0))
	ladd("box", tray, f, Vector3(0, 0.6, 0.55), Vector3(0.7, 0.3, 0.25), Basis(Vector3.RIGHT, -0.6))
	ladd("cyl", Color(0.12, 0.12, 0.12), f, Vector3(0, 0.22, 0.78), Vector3(0.42, 0.1, 0.42), Basis(Vector3.FORWARD, PI * 0.5))
	ladd("cyl", pcol(Color(0.7, 0.7, 0.72), P_METAL), f, Vector3(0, 0.22, 0.78), Vector3(0.12, 0.12, 0.12), Basis(Vector3.FORWARD, PI * 0.5), false)
	for sx in [-0.3, 0.3]:
		ladd("box", pcol(C_WOOD, P_WOOD), f, Vector3(sx, 0.48, -0.25), Vector3(0.05, 0.05, 1.6), Basis(Vector3.RIGHT, 0.12))
		ladd("box", C_IRON, f, Vector3(sx, 0.2, -0.3), Vector3(0.04, 0.4, 0.04))
	fol("blob_lo", load, f * Vector3(0, 0.78, 0.0), f.basis * Basis.from_scale(Vector3(0.7, 0.32, 0.9)), 0.0, 0.0)
	collider(f * Vector3(0, 0.45, 0), Vector3(0.8, 0.9, 1.6), rot_y)
	terrain.add_solid_box(Vector2(x, z), Vector2(0.4, 0.75), rot_y)


func birdhouse(x: float, z: float, rot_y: float, color: Color) -> void:
	var y := gy(x, z)
	var f := Transform3D(Basis(Vector3.UP, rot_y), Vector3(x, y, z))
	ladd("box", pcol(C_WOOD_DARK, P_WOOD, true), f, Vector3(0, 0.9, 0), Vector3(0.09, 1.8, 0.09))
	ladd("box", pcol(color, P_PLANKS_V), f, Vector3(0, 1.98, 0), Vector3(0.34, 0.36, 0.3))
	ladd("prism", pcol(Color(0.55, 0.25, 0.2), P_ROOF), f, Vector3(0, 2.26, 0), Vector3(0.46, 0.22, 0.42))
	ladd("cyl8", Color(0.08, 0.06, 0.05), f, Vector3(0, 2.02, 0.152), Vector3(0.09, 0.01, 0.09), Basis(Vector3.RIGHT, PI * 0.5), false)
	ladd("cyl6", C_WOOD_DARK, f, Vector3(0, 1.92, 0.2), Vector3(0.02, 0.1, 0.02), Basis(Vector3.RIGHT, PI * 0.5), false)
	collider(Vector3(x, y + 0.9, z), Vector3(0.15, 1.8, 0.15))


func bollard(x: float, z: float) -> void:
	var y := gy(x, z)
	add("cyl8", pcol(C_IRON, P_METAL), Vector3(x, y + 0.35, z), Vector3(0.14, 0.7, 0.14))
	add("cyl8", pcol(C_IRON, P_METAL), Vector3(x, y + 0.04, z), Vector3(0.22, 0.08, 0.22))
	glow("cyl6", Vector3(x, y + 0.8, z), Basis.from_scale(Vector3(0.16, 0.2, 0.16)))
	add("cone6", pcol(C_IRON, P_METAL), Vector3(x, y + 0.97, z), Vector3(0.26, 0.14, 0.26))
	collider(Vector3(x, y + 0.5, z), Vector3(0.2, 1.0, 0.2))


func signpost(x: float, z: float, rot_y: float) -> void:
	var y := gy(x, z)
	var f := Transform3D(Basis(Vector3.UP, rot_y), Vector3(x, y, z))
	ladd("box", pcol(C_WOOD_DARK, P_WOOD, true), f, Vector3(0, 1.1, 0), Vector3(0.1, 2.2, 0.1))
	ladd("cone4", pcol(C_WOOD_DARK, P_WOOD), f, Vector3(0, 2.27, 0), Vector3(0.16, 0.14, 0.16), Basis(Vector3.UP, PI * 0.25))
	var boards := [[1.85, 0.0, Color(0.62, 0.45, 0.27)], [1.55, PI * 0.6, Color(0.55, 0.38, 0.22)], [1.25, -PI * 0.35, Color(0.66, 0.5, 0.3)]]
	for b in boards:
		var by: float = b[0]
		var ba: float = b[1]
		var bc: Color = b[2]
		var bb := Basis(Vector3.UP, ba)
		ladd("box", pcol(bc, P_WOOD), f, bb * Vector3(0.38, by, 0), Vector3(0.7, 0.18, 0.04), bb)
		ladd("prism", pcol(bc, P_WOOD), f, bb * Vector3(0.79, by, 0), Vector3(0.18, 0.12, 0.04), bb * Basis(Vector3.FORWARD, -PI * 0.5))
	collider(Vector3(x, y + 1.1, z), Vector3(0.15, 2.2, 0.15))
	terrain.add_solid_circle(Vector2(x, z), 0.1)


func crate(x: float, z: float, size: float, rot_y: float, fill: Color = Color(-1, 0, 0), y_off: float = 0.0) -> void:
	var y := gy(x, z) + y_off
	var f := Transform3D(Basis(Vector3.UP, rot_y), Vector3(x, y, z))
	ladd("box", pcol(Color(0.72, 0.55, 0.33), P_PLANKS_H), f, Vector3(0, size * 0.4, 0), Vector3(size, size * 0.8, size * 0.75))
	for sx in [-0.5, 0.5]:
		ladd("box", pcol(Color(0.6, 0.44, 0.26), P_WOOD, true), f, Vector3(sx * size, size * 0.4, 0), Vector3(0.05, size * 0.82, size * 0.77), Basis.IDENTITY, false)
	if fill.r >= 0.0:
		for k in 6:
			add_basis("sph_lo", fill.lerp(fill.lightened(0.2), drng.randf()), f * Vector3(drng.randf_range(-0.35, 0.35) * size, size * 0.8, drng.randf_range(-0.25, 0.25) * size), Basis.from_scale(Vector3.ONE * size * 0.22), false, 0.0, true)
	if y_off == 0.0:
		collider(f * Vector3(0, size * 0.4, 0), Vector3(size, size * 0.8, size * 0.75), rot_y)
		terrain.add_solid_box(Vector2(x, z), Vector2(size, size * 0.75) * 0.5, rot_y)


func barrel(x: float, z: float, color: Color, size: Vector3 = Vector3(0.7, 0.95, 0.7), lying: bool = false, rot_y: float = 0.0) -> void:
	var y := gy(x, z)
	var b := Basis(Vector3.UP, rot_y)
	var pos := Vector3(x, y + size.y * 0.5, z)
	if lying:
		b = b * Basis(Vector3.FORWARD, PI * 0.5)
		pos.y = y + size.x * 0.48
	add_basis("barrel", pcol(color, P_METAL), pos, b * Basis.from_scale(size))
	for k in 2:
		var off := b * Vector3(0, (k - 0.5) * size.y * 0.55, 0)
		add_basis("cyl", pcol(color.darkened(0.35), P_METAL), pos + off, b * Basis.from_scale(Vector3(size.x * 1.0, 0.04, size.z * 1.0)), false)


# ------------------------------------------------------------------ mobiliario prefabricado

func bench(x: float, z: float, rot_y: float) -> void:
	var y := gy(x, z)
	prefab("bench", K_PROP, _bench_parts, Transform3D(Basis(Vector3.UP, rot_y), Vector3(x, y, z)), Color.WHITE, 0.45)
	collider(Vector3(x, y + 0.45, z), Vector3(1.6, 0.9, 0.5), rot_y)


func _bench_parts() -> Array:
	var wood := pcol(Color(0.66, 0.43, 0.24), P_WOOD)
	var iron := pcol(C_IRON, P_METAL)
	var p := []
	for k in 3:
		p.append(MeshFactory.part("box", Vector3(0, 0.46, -0.13 + k * 0.13), Vector3(1.6, 0.05, 0.11), wood))
	for k in 2:
		p.append(MeshFactory.part("box", Vector3(0, 0.64 + k * 0.17, -0.26 - k * 0.025), Vector3(1.6, 0.12, 0.04), wood, Basis(Vector3.RIGHT, -0.12)))
	for sx in [-0.72, 0.72]:
		p.append(MeshFactory.part("box", Vector3(sx, 0.22, 0.14), Vector3(0.05, 0.46, 0.05), iron))
		p.append(MeshFactory.part("box", Vector3(sx, 0.45, -0.25), Vector3(0.05, 0.9, 0.05), iron, Basis(Vector3.RIGHT, -0.12)))
		p.append(MeshFactory.part("box", Vector3(sx, 0.43, -0.05), Vector3(0.05, 0.05, 0.42), iron))
		p.append(MeshFactory.part("box", Vector3(sx, 0.66, 0.0), Vector3(0.06, 0.05, 0.42), wood))
		p.append(MeshFactory.part("box", Vector3(sx, 0.55, 0.18), Vector3(0.04, 0.22, 0.04), iron))
	return p


func lamp(x: float, z: float) -> void:
	var y := gy(x, z)
	prefab("lamp", K_PROP, _lamp_parts, Transform3D(Basis.IDENTITY, Vector3(x, y, z)), Color.WHITE, 0.3)
	glow("cyl6", Vector3(x, y + 3.06, z), Basis.from_scale(Vector3(0.3, 0.36, 0.3)))
	collider(Vector3(x, y + 1.4, z), Vector3(0.2, 2.8, 0.2))
	terrain.add_solid_circle(Vector2(x, z), 0.15)


func _lamp_parts() -> Array:
	var iron := pcol(C_IRON, P_METAL)
	var p := []
	p.append(MeshFactory.part("cyl8", Vector3(0, 0.15, 0), Vector3(0.36, 0.3, 0.36), iron))
	p.append(MeshFactory.part("cyl8", Vector3(0, 0.36, 0), Vector3(0.24, 0.14, 0.24), iron))
	p.append(MeshFactory.part("cyl8", Vector3(0, 1.55, 0), Vector3(0.1, 2.5, 0.1), iron))
	p.append(MeshFactory.part("cyl8", Vector3(0, 2.0, 0), Vector3(0.15, 0.06, 0.15), iron))
	p.append(MeshFactory.part("cyl8", Vector3(0, 2.8, 0), Vector3(0.17, 0.1, 0.17), iron))
	p.append(MeshFactory.part("cyl6", Vector3(0, 2.86, 0), Vector3(0.38, 0.05, 0.38), iron))
	for k in 3:
		p.append(MeshFactory.part("box", Vector3(0, 3.06, 0), Vector3(0.025, 0.4, 0.37), iron, Basis(Vector3.UP, k * PI / 3.0 + PI / 6.0)))
	p.append(MeshFactory.part("cone6", Vector3(0, 3.36, 0), Vector3(0.5, 0.24, 0.5), iron))
	p.append(MeshFactory.part("sph", Vector3(0, 3.52, 0), Vector3(0.09, 0.09, 0.09), iron))
	# Volutas decorativas bajo el farol.
	for k in 2:
		p.append(MeshFactory.part("box", Vector3(0, 2.68, 0), Vector3(0.36, 0.035, 0.035), iron, Basis(Vector3.UP, k * PI * 0.5) * Basis(Vector3.FORWARD, 0.0)))
	return p


func bin(x: float, z: float, rot_y: float) -> void:
	var b := RecycleBin.new()
	b.position = Vector3(x, gy(x, z), z)
	b.rotation.y = rot_y
	var xf := Transform3D(Basis(Vector3.UP, rot_y), b.position)
	prefab("bin", K_PROP, _bin_parts, xf, Color.WHITE, 0.7)
	prefab("bin_leaves", K_FOL, _bin_leaf_parts, xf, Color.WHITE, 0.0, false, 0.0)
	var l := Label3D.new()
	l.text = "RECICLAJE"
	l.font_size = 40
	l.pixel_size = 0.006
	l.outline_size = 10
	l.outline_modulate = Color(0.08, 0.2, 0.1)
	l.position = Vector3(0, 0.95, 0.73)
	b.add_child(l)
	Interactable.make_shape(b, Vector3(2.6, 1.5, 1.4), Vector3(0, 0.75, 0))
	root.add_child(b)
	terrain.add_solid_box(Vector2(x, z), Vector2(1.35, 0.75), rot_y)
	bins.append(b)


func _bin_parts() -> Array:
	var green := pcol(Color(0.2, 0.47, 0.27), P_PLAIN)
	var dark := pcol(Color(0.13, 0.32, 0.19), P_PLAIN)
	var p := []
	p.append(MeshFactory.part("box", Vector3(0, 0.12, 0), Vector3(2.6, 0.14, 1.4), dark))
	p.append(MeshFactory.part("box", Vector3(0, 0.84, 0.65), Vector3(2.6, 1.42, 0.1), green))
	p.append(MeshFactory.part("box", Vector3(0, 0.84, -0.65), Vector3(2.6, 1.42, 0.1), green))
	p.append(MeshFactory.part("box", Vector3(1.25, 0.84, 0), Vector3(0.1, 1.42, 1.4), green))
	p.append(MeshFactory.part("box", Vector3(-1.25, 0.84, 0), Vector3(0.1, 1.42, 1.4), green))
	# Borde superior y nervios.
	p.append(MeshFactory.part("box", Vector3(0, 1.57, 0.69), Vector3(2.72, 0.09, 0.12), dark))
	p.append(MeshFactory.part("box", Vector3(0, 1.57, -0.69), Vector3(2.72, 0.09, 0.12), dark))
	p.append(MeshFactory.part("box", Vector3(1.29, 1.57, 0), Vector3(0.12, 0.09, 1.5), dark))
	p.append(MeshFactory.part("box", Vector3(-1.29, 1.57, 0), Vector3(0.12, 0.09, 1.5), dark))
	for sx in [-1.12, -0.95, 0.95, 1.12]:
		p.append(MeshFactory.part("box", Vector3(sx, 0.84, 0.71), Vector3(0.07, 1.3, 0.04), dark))
		p.append(MeshFactory.part("box", Vector3(sx, 0.84, -0.71), Vector3(0.07, 1.3, 0.04), dark))
	# Placa del rótulo y flechas de reciclaje.
	p.append(MeshFactory.part("box", Vector3(0, 0.95, 0.705), Vector3(1.6, 0.34, 0.01), Color(0.92, 0.9, 0.82)))
	for k in 3:
		var a := k * TAU / 3.0
		p.append(MeshFactory.part("box", Vector3(cos(a) * 0.13, 0.48 + sin(a) * 0.13, 0.705), Vector3(0.16, 0.05, 0.012), Color(0.92, 0.9, 0.82), Basis(Vector3.BACK, a + PI * 0.5)))
	# Ruedas.
	for c in [Vector2(-1.05, 0.55), Vector2(1.05, 0.55), Vector2(-1.05, -0.55), Vector2(1.05, -0.55)]:
		var cv: Vector2 = c
		p.append(MeshFactory.part("cyl", Vector3(cv.x, 0.1, cv.y), Vector3(0.2, 0.08, 0.2), Color(0.1, 0.1, 0.1), Basis(Vector3.FORWARD, PI * 0.5)))
	# Tapa abierta con asa.
	var lid := Basis(Vector3.RIGHT, -1.1)
	p.append(MeshFactory.part("box", Vector3(0, 1.85, -1.1), Vector3(2.7, 0.08, 1.2), dark, lid))
	p.append(MeshFactory.part("box", Vector3(0, 1.62 + 0.42, -1.1 - 0.62), Vector3(0.6, 0.06, 0.06), Color(0.1, 0.1, 0.1), lid))
	p.append(MeshFactory.part("box", Vector3(0, 1.18, 0), Vector3(2.4, 0.1, 1.2), pcol(Color(0.55, 0.32, 0.12), P_PLAIN)))
	return p


func _bin_leaf_parts() -> Array:
	var p := []
	var cols := [Color(0.9, 0.48, 0.14), Color(0.82, 0.3, 0.1), Color(0.95, 0.68, 0.2)]
	for k in 4:
		p.append(MeshFactory.part("blob_lo", Vector3(-0.85 + k * 0.57, 1.3, 0.05 * (k % 2)), Vector3(0.85, 0.35, 1.05), cols[k % 3]))
	return p


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
						_segment(seg_type, a + dir * seg_start, a + dir * s, dir, outward)
					seg_type = typ
					seg_start = s
	_main_gate()


func _main_gate() -> void:
	# Portón principal decorativo (la carretera queda fuera).
	var stone := pcol(C_STONE_DARK, P_STONE)
	for sx in [-3.4, 3.4]:
		var y := gy(sx, 64)
		block(stone, sx, 64, Vector3(1.0, 2.8, 1.0))
		add("box", pcol(C_STONE, P_PLAIN), Vector3(sx, y + 2.88, 64), Vector3(1.2, 0.16, 1.2))
		add("box", stone, Vector3(sx, y + 0.12, 64), Vector3(1.15, 0.24, 1.15))
		# Farol sobre cada pilar.
		add("cyl8", pcol(C_IRON, P_METAL), Vector3(sx, y + 3.02, 64), Vector3(0.3, 0.12, 0.3))
		glow("cyl6", Vector3(sx, y + 3.28, 64), Basis.from_scale(Vector3(0.3, 0.38, 0.3)))
		for k in 3:
			add("box", pcol(C_IRON, P_METAL), Vector3(sx, y + 3.28, 64), Vector3(0.025, 0.42, 0.36), k * PI / 3.0 + PI / 6.0)
		add("cone6", pcol(C_IRON, P_METAL), Vector3(sx, y + 3.6, 64), Vector3(0.5, 0.26, 0.5))
	var iron := pcol(C_IRON, P_METAL)
	for k in 13:
		var x := -2.6 + k * 0.43
		var h := 2.2 + 0.25 * cos((x / 2.9) * PI * 0.5)
		add("box", iron, Vector3(x, gy(x, 64) + h * 0.5, 64), Vector3(0.05, h, 0.05))
		add("cone4", iron, Vector3(x, gy(x, 64) + h + 0.06, 64), Vector3(0.1, 0.16, 0.1), PI * 0.25)
	add("box", iron, Vector3(0, gy(0, 64) + 2.15, 64), Vector3(5.9, 0.08, 0.08))
	add("box", iron, Vector3(0, gy(0, 64) + 0.35, 64), Vector3(5.9, 0.06, 0.06))
	for k in 6:
		var x := -2.15 + k * 0.86
		add_basis("ring", pcol(C_IRON, P_METAL), Vector3(x, gy(0, 64) + 1.75, 64), Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.45, 0.3, 0.45)), false, 0.0)
	collider(Vector3(0, 1.2, 64), Vector3(6.0, 2.6, 0.4))
	terrain.add_solid_box(Vector2(0, 64), Vector2(3.0, 0.25))
	# Tablón del rótulo (por dentro tapa el texto invertido).
	add("box", pcol(Color(0.42, 0.28, 0.16), P_WOOD), Vector3(0, 3.35, 63.98), Vector3(4.6, 0.62, 0.08))
	for sx in [-2.0, 2.0]:
		add("box", iron, Vector3(sx, 2.75, 63.98), Vector3(0.04, 0.62, 0.04))
	var title_sign := label("VILLA HOJARASCA", Vector3(0, 3.35, 64.1), 96, PI)
	title_sign.modulate = Color(1.0, 0.86, 0.55)


func _segment(kind: String, a: Vector2, b: Vector2, dir: Vector2, outward: Vector2) -> void:
	var length := a.distance_to(b)
	if length < 0.3:
		return
	var rot := -atan2(dir.y, dir.x)
	var pieces := maxi(1, int(ceil(length / 4.0)))
	var inward := Vector3(-outward.x, 0, -outward.y)
	for k in pieces:
		var p0 := a + dir * (length * k / pieces)
		var p1 := a + dir * (length * (k + 1) / pieces)
		var mid := (p0 + p1) * 0.5
		var plen := p0.distance_to(p1)
		var y := minf(gy(p0.x, p0.y), gy(p1.x, p1.y))
		match kind:
			"wall":
				add("box", pcol(C_STONE, P_STONE), Vector3(mid.x, y + 0.65, mid.y), Vector3(plen + 0.05, 2.5, 0.55), rot)
				add("box", pcol(C_STONE_DARK, P_PLAIN), Vector3(mid.x, y + 1.97, mid.y), Vector3(plen + 0.1, 0.14, 0.7), rot)
				collider(Vector3(mid.x, y + 1.2, mid.y), Vector3(plen, 3.4, 0.55), rot)
				# Pilastra al inicio de cada tramo.
				add("box", pcol(C_STONE_DARK, P_STONE), Vector3(p0.x, y + 0.7, p0.y), Vector3(0.8, 2.6, 0.8), rot)
				add("box", pcol(C_STONE, P_PLAIN), Vector3(p0.x, y + 2.06, p0.y), Vector3(0.95, 0.14, 0.95), rot)
				# Hiedra otoñal y matas al pie, por el lado de la finca.
				if drng.randf() < 0.45:
					var t := drng.randf_range(0.2, 0.8)
					var ip := p0.lerp(p1, t)
					var ih := drng.randf_range(0.9, 1.8)
					var ivy_pal := [Color(0.82, 0.22, 0.1), Color(0.9, 0.42, 0.12), Color(0.36, 0.52, 0.2), Color(0.7, 0.16, 0.12)]
					var ivy: Color = ivy_pal[drng.randi() % ivy_pal.size()]
					ivy = ivy.lerp(ivy_pal[drng.randi() % ivy_pal.size()], drng.randf() * 0.5)
					fol("blob0", ivy, Vector3(ip.x, y + ih * 0.5, ip.y) + inward * 0.3, Basis(Vector3.UP, rot) * Basis.from_scale(Vector3(drng.randf_range(1.2, 2.6), ih, 0.32)), 0.2, 0.4)
				if dense:
					for q in 2:
						var tp := p0.lerp(p1, drng.randf()) + Vector2(inward.x, inward.z) * 0.42
						tuft(tp.x, tp.y, drng.randf_range(0.3, 0.55))
			"hedge":
				var hc := C_HEDGE.lerp(Color(0.3, 0.46, 0.2), drng.randf())
				fol("hedge", hc, Vector3(mid.x, y + 1.0, mid.y), Basis(Vector3.UP, rot + PI * 0.5) * Basis.from_scale(Vector3(0.95, 2.4, plen + 0.3)), 0.15, 0.6)
				collider(Vector3(mid.x, y + 1.1, mid.y), Vector3(plen, 2.2, 0.9), rot)
			"fence":
				var post := pcol(C_WOOD_DARK, P_WOOD, true)
				for f in [0.0, 1.0]:
					var pp := p0.lerp(p1, f)
					var py := gy(pp.x, pp.y)
					add("box", post, Vector3(pp.x, py + 0.6, pp.y), Vector3(0.14, 1.3, 0.14), rot)
					add("cone4", pcol(C_WOOD_DARK, P_PLAIN), Vector3(pp.x, py + 1.32, pp.y), Vector3(0.22, 0.16, 0.22), rot + PI * 0.25)
				var rail := pcol(C_WOOD, P_WOOD)
				for ry in [0.35, 0.85]:
					add("box", rail, Vector3(mid.x, y + ry, mid.y), Vector3(plen, 0.08, 0.05), rot)
				var pickets := int(plen / 0.24)
				var paint := pcol(C_PAINT, P_WOOD, true)
				for q in pickets:
					var pp := p0.lerp(p1, (q + 0.5) / pickets)
					var ph := 1.0 + 0.06 * sin(q * 1.3)
					add_basis("picket", paint, Vector3(pp.x, gy(pp.x, pp.y) + ph * 0.5 - 0.05, pp.y), Basis(Vector3.UP, rot) * Basis.from_scale(Vector3(0.09, ph, 0.03)), true, 0.2)
				collider(Vector3(mid.x, y + 0.75, mid.y), Vector3(plen, 1.6, 0.2), rot)
				if dense and drng.randf() < 0.5:
					var tp := p0.lerp(p1, drng.randf())
					var side := 0.3 if drng.randf() < 0.5 else -0.3
					tuft(tp.x + dir.y * side, tp.y - dir.x * side, drng.randf_range(0.3, 0.5))
		terrain.add_solid_box(mid, Vector2(plen * 0.5 + 0.1, 0.3 if kind == "fence" else 0.45), rot)
	if kind == "wall":
		var y2 := gy(b.x, b.y)
		add("box", pcol(C_STONE_DARK, P_STONE), Vector3(b.x, y2 + 0.7, b.y), Vector3(0.8, 2.6, 0.8), rot)
		add("box", pcol(C_STONE, P_PLAIN), Vector3(b.x, y2 + 2.06, b.y), Vector3(0.95, 0.14, 0.95), rot)


# ------------------------------------------------------------------ edificios

## Ventana con marco, parteluces, alféizar y (opcional) contraventanas y jardinera.
## c: centro del cristal en la fachada; n: normal de la fachada (horizontal).
func window(c: Vector3, w: float, h: float, n: Vector3, trim: Color, shutter: Color = Color(0, 0, 0, 0), flower_box: bool = false) -> void:
	var right := Vector3.UP.cross(n).normalized()
	var f := Transform3D(Basis(right, Vector3.UP, n), c)
	var t := pcol(trim, P_PLAIN)
	ladd("box", pcol(Color.WHITE, P_GLASS), f, Vector3(0, 0, 0.02), Vector3(w - 0.06, h - 0.06, 0.04), Basis.IDENTITY, false)
	ladd("box", t, f, Vector3(0, h * 0.5, 0.05), Vector3(w + 0.12, 0.09, 0.1), Basis.IDENTITY, false)
	ladd("box", t, f, Vector3(0, -h * 0.5, 0.05), Vector3(w + 0.12, 0.09, 0.1), Basis.IDENTITY, false)
	ladd("box", t, f, Vector3(-w * 0.5, 0, 0.05), Vector3(0.09, h, 0.1), Basis.IDENTITY, false)
	ladd("box", t, f, Vector3(w * 0.5, 0, 0.05), Vector3(0.09, h, 0.1), Basis.IDENTITY, false)
	ladd("box", t, f, Vector3(0, 0, 0.045), Vector3(0.05, h, 0.05), Basis.IDENTITY, false)
	ladd("box", t, f, Vector3(0, h * 0.12, 0.045), Vector3(w, 0.05, 0.05), Basis.IDENTITY, false)
	ladd("box", t, f, Vector3(0, -h * 0.5 - 0.06, 0.1), Vector3(w + 0.3, 0.07, 0.22))
	ladd("box", t, f, Vector3(0, h * 0.5 + 0.1, 0.07), Vector3(w + 0.32, 0.12, 0.12), Basis.IDENTITY, false)
	if shutter.a > 0.0:
		for sx in [-1.0, 1.0]:
			ladd("box", pcol(shutter, P_PLANKS_V), f, Vector3(sx * (w * 0.5 + w * 0.24 + 0.08), 0, 0.04), Vector3(w * 0.46, h * 1.02, 0.05), Basis.IDENTITY, false)
	if flower_box:
		ladd("box", pcol(Color(0.5, 0.33, 0.2), P_PLANKS_H), f, Vector3(0, -h * 0.5 - 0.24, 0.2), Vector3(w + 0.1, 0.24, 0.26))
		for k in 4:
			var lx := -w * 0.4 + k * w * 0.27
			fol("blob_lo", Color(0.26, 0.45, 0.2), f * Vector3(lx, -h * 0.5 - 0.06, 0.2), f.basis * Basis.from_scale(Vector3(0.36, 0.26, 0.26)), 0.4, 0.0, false)
			var fc: Color = FLOWERS[(k + int(absf(c.x) * 3.0)) % FLOWERS.size()]
			add_basis("flower", fc, f * Vector3(lx + 0.06, -h * 0.5 + 0.07, 0.24), Basis.from_scale(Vector3.ONE * 0.26), false, 0.0, true)


## Frontón triangular del color de la pared bajo un tejado a dos aguas (relleno de los hastiales).
func gable(color: Color, center: Vector3, basis: Basis) -> void:
	add_basis("prism", color, center, basis, false, 0.0)


func _house() -> void:
	var y := 0.25
	var wall := pcol(Color(0.93, 0.86, 0.72), P_PLANKS_H)
	var trim := Color(0.98, 0.96, 0.9)
	var tpc := pcol(trim, P_PLAIN)
	var roofc := pcol(Color(0.64, 0.28, 0.21), P_ROOF)
	var shutter := Color(0.24, 0.42, 0.33)
	var stone := pcol(C_STONE_DARK.lightened(0.05), P_STONE)
	house_box(wall, Vector3(0, y + 3.2, -18.5), Vector3(22, 6.4, 9))
	add("box", stone, Vector3(0, y + 0.35, -18.5), Vector3(22.24, 0.8, 9.24))
	add("box", tpc, Vector3(0, y + 3.25, -18.5), Vector3(22.3, 0.2, 9.3))
	add("box", tpc, Vector3(0, y + 6.45, -18.5), Vector3(22.4, 0.2, 9.4))
	for cx in [-11.0, 11.0]:
		for cz in [-14.0, -23.0]:
			add("box", tpc, Vector3(cx, y + 3.4, cz), Vector3(0.32, 6.2, 0.32))
	# Tejado de tejas, cumbrera y hastiales.
	add_basis("prism", roofc, Vector3(0, y + 8.0, -18.5), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(10.4, 3.2, 23.2)))
	gable(wall, Vector3(0, y + 7.9, -18.5), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(9.0, 2.9, 22.0)))
	add("box", pcol(Color(0.5, 0.22, 0.17), P_PLAIN), Vector3(0, y + 9.62, -18.5), Vector3(23.4, 0.16, 0.34))
	for sz in [-1.0, 1.0]:
		add_basis("box", tpc, Vector3(0, y + 6.36, -18.5 + sz * 5.15), Basis.from_scale(Vector3(23.3, 0.18, 0.12)), false)
	# Buhardillas.
	for dx in [-5.2, 5.2]:
		var dz := -15.7
		add("box", wall, Vector3(dx, y + 7.7, dz), Vector3(1.7, 1.5, 1.8))
		add_basis("prism", roofc, Vector3(dx, y + 8.75, dz + 0.1), Basis.from_scale(Vector3(2.1, 0.75, 2.1)))
		window(Vector3(dx, y + 7.75, dz + 0.9), 0.75, 0.85, Vector3(0, 0, 1), trim)
	# Chimenea de ladrillo con sombrerete y humo.
	house_box(pcol(Color(0.62, 0.36, 0.28), P_BRICK), Vector3(-6, y + 8.5, -20), Vector3(1.2, 4.0, 1.2), false)
	add("box", pcol(C_STONE_DARK, P_PLAIN), Vector3(-6, y + 10.55, -20), Vector3(1.45, 0.16, 1.45))
	for px in [-6.25, -5.75]:
		add("cyl8", pcol(C_TERRACOTTA, P_PLAIN), Vector3(px, y + 10.82, -20), Vector3(0.24, 0.4, 0.24))
	_chimney_smoke(Vector3(-6.0, y + 11.1, -20.0))
	# Torreón.
	add("cyl", wall, Vector3(11, y + 4.5, -14.5), Vector3(4.4, 9.0, 4.4))
	add("cyl", stone, Vector3(11, y + 0.4, -14.5), Vector3(4.6, 0.8, 4.6))
	add("cyl", tpc, Vector3(11, y + 3.25, -14.5), Vector3(4.6, 0.2, 4.6))
	add("cyl", tpc, Vector3(11, y + 8.95, -14.5), Vector3(4.75, 0.25, 4.75))
	add("cone", roofc, Vector3(11, y + 10.6, -14.5), Vector3(5.4, 3.2, 5.4))
	add("cyl8", pcol(C_IRON, P_METAL), Vector3(11, y + 12.45, -14.5), Vector3(0.06, 0.8, 0.06))
	add("sph", pcol(Color(0.85, 0.62, 0.3), P_METAL), Vector3(11, y + 12.3, -14.5), Vector3(0.22, 0.22, 0.22))
	for row in 2:
		for a in [-0.6, 0.35, 1.3]:
			var nv := Vector3(sin(a), 0, cos(a))
			window(Vector3(11, y + (1.7 if row == 0 else 5.6), -14.5) + nv * 2.18, 0.8, 1.3, nv, trim)
	collider(Vector3(11, y + 4.5, -14.5), Vector3(4.2, 9.0, 4.2))
	terrain.add_solid_circle(Vector2(11, -14.5), 2.25)
	terrain.add_solid_box(Vector2(0, -18.5), Vector2(11.0, 4.5))
	# Ventanas: fachada, laterales y trasera.
	for row in 2:
		var wy := y + (1.6 if row == 0 else 4.7)
		for k in 5:
			var x := -9.0 + k * 3.6
			var sh := Color(0, 0, 0, 0) if (row == 0 and absf(x) < 2.0) else shutter
			window(Vector3(x, wy, -14.0), 1.15, 1.45, Vector3(0, 0, 1), trim, sh, row == 0)
		for k in 6:
			var x := -9.0 + k * 3.6
			if row == 0 and is_equal_approx(x, -1.8):
				continue
			window(Vector3(x, wy, -23.0), 1.15, 1.45, Vector3(0, 0, -1), trim, shutter)
		for wz in [-20.5, -16.5]:
			window(Vector3(-11.0, wy, wz), 1.15, 1.45, Vector3(-1, 0, 0), trim, shutter)
		for wz in [-21.3, -18.4]:
			window(Vector3(11.0, wy, wz), 1.15, 1.45, Vector3(1, 0, 0), trim, shutter)
	# Puerta trasera con escalón.
	add("box", pcol(Color(0.3, 0.42, 0.34), P_PLANKS_V), Vector3(-1.8, y + 1.25, -23.03), Vector3(1.1, 2.3, 0.08))
	add("box", tpc, Vector3(-1.8, y + 2.47, -23.06), Vector3(1.4, 0.14, 0.12))
	add("box", pcol(C_STONE, P_PLAIN), Vector3(-1.8, y + 0.08, -23.4), Vector3(1.6, 0.16, 0.7))
	_porch(y, trim)
	label("1907", Vector3(0, y + 6.9, -13.9), 56)


func _porch(y: float, trim: Color) -> void:
	var tpc := pcol(trim, P_PLAIN)
	var floor_c := pcol(Color(0.6, 0.45, 0.32), P_PLANKS_V)
	add("box", pcol(C_STONE, P_STONE), Vector3(0, y + 0.13, -12.8), Vector3(16, 0.26, 2.6))
	add("box", floor_c, Vector3(0, y + 0.28, -12.8), Vector3(16.1, 0.04, 2.65))
	collider(Vector3(0, y + 0.15, -12.8), Vector3(16, 0.3, 2.6))
	# Escalones de la entrada.
	add("box", pcol(C_STONE, P_STONE), Vector3(0, y + 0.075, -11.25), Vector3(3.0, 0.15, 0.5))
	collider(Vector3(0, y + 0.075, -11.25), Vector3(3.0, 0.15, 0.5))
	# Columnas (enmarcan la puerta).
	var cols := [-7.6, -4.8, -1.6, 1.6, 4.8, 7.6]
	for cx in cols:
		var x: float = cx
		add("cyl", tpc, Vector3(x, y + 1.7, -11.8), Vector3(0.3, 2.8, 0.3))
		add("box", tpc, Vector3(x, y + 0.42, -11.8), Vector3(0.42, 0.26, 0.42))
		add("box", tpc, Vector3(x, y + 3.05, -11.8), Vector3(0.44, 0.14, 0.44))
		collider(Vector3(x, y + 1.6, -11.8), Vector3(0.3, 2.9, 0.3))
		terrain.add_solid_circle(Vector2(x, -11.8), 0.18)
	# Barandillas entre columnas (sin colisión: solo decorativas).
	for seg in [[-7.6, -4.8], [-4.8, -1.6], [1.6, 4.8], [4.8, 7.6]]:
		var x0: float = seg[0]
		var x1: float = seg[1]
		var cx := (x0 + x1) * 0.5
		var len := x1 - x0 - 0.3
		add("box", tpc, Vector3(cx, y + 1.18, -11.8), Vector3(len, 0.08, 0.12))
		add("box", tpc, Vector3(cx, y + 0.42, -11.8), Vector3(len, 0.06, 0.08), 0.0, false)
		var n := int(len / 0.2)
		for k in n:
			add_basis("box", tpc, Vector3(x0 + 0.15 + (k + 0.5) * len / n, y + 0.8, -11.8), Basis.from_scale(Vector3(0.05, 0.72, 0.05)), false, 0.0, true)
	# Tejadillo del porche.
	add("box", tpc, Vector3(0, y + 3.15, -11.75), Vector3(16.4, 0.22, 0.24))
	add_basis("box", pcol(Color(0.64, 0.28, 0.21), P_ROOF), Vector3(0, y + 3.42, -12.75), Basis(Vector3.RIGHT, 0.2) * Basis.from_scale(Vector3(16.8, 0.12, 3.1)))
	# Puerta principal con montante, cuarterones y pomo.
	var door := Color(0.22, 0.38, 0.3)
	add("box", pcol(door, P_PLAIN), Vector3(0, y + 1.3, -13.98), Vector3(1.4, 2.4, 0.1))
	for k in 4:
		var px := -0.32 + (k % 2) * 0.64
		var py := y + 0.78 + (k / 2) * 1.0
		add("box", pcol(door.lightened(0.1), P_PLAIN), Vector3(px, py, -13.92), Vector3(0.48, 0.8, 0.04), 0.0, false)
	add("box", tpc, Vector3(0, y + 2.62, -13.95), Vector3(1.75, 0.14, 0.14))
	add("box", tpc, Vector3(-0.78, y + 1.3, -13.95), Vector3(0.14, 2.6, 0.14))
	add("box", tpc, Vector3(0.78, y + 1.3, -13.95), Vector3(0.14, 2.6, 0.14))
	add("box", pcol(Color.WHITE, P_GLASS), Vector3(0, y + 2.95, -13.98), Vector3(1.4, 0.45, 0.06), 0.0, false)
	add("box", tpc, Vector3(0, y + 3.2, -13.95), Vector3(1.75, 0.1, 0.12), 0.0, false)
	add("sph", pcol(Color(0.85, 0.66, 0.3), P_METAL), Vector3(0.5, y + 1.3, -13.88), Vector3(0.1, 0.1, 0.1), 0.0, false)
	add("box", pcol(Color(0.55, 0.32, 0.2), P_STRAW), Vector3(0, y + 0.31, -13.45), Vector3(1.2, 0.02, 0.6), 0.0, false)
	# Faroles colgantes.
	for lx in [-3.2, 3.2]:
		add("cyl6", C_IRON, Vector3(lx, y + 3.1, -12.6), Vector3(0.02, 0.6, 0.02), 0.0, false)
		add("cone6", pcol(C_IRON, P_METAL), Vector3(lx, y + 2.78, -12.6), Vector3(0.3, 0.14, 0.3), 0.0, false)
		glow("cyl6", Vector3(lx, y + 2.6, -12.6), Basis.from_scale(Vector3(0.22, 0.26, 0.22)))
	# Macetas y calabazas en la entrada.
	for sx in [-1.0, 1.0]:
		pot(sx * 1.15, -13.55, 0.5, 0, 0.3, false)
		pot(sx * 2.25, -10.75, 0.62, 0)
	pumpkin(-2.1, -12.1, 0.55, 0.3)
	pumpkin(2.3, -12.25, 0.45, 0.3)
	pumpkin(-1.25, -11.15, 0.32, 0.15)
	pumpkin(2.6, -12.7, 0.3, 0.3)
	# Macizo elevado junto a la fachada (lado oeste del porche).
	block(pcol(C_STONE, P_STONE), -9.6, -13.45, Vector3(2.2, 0.42, 0.9))
	add("box", C_SOIL, Vector3(-9.6, y + 0.42, -13.45), Vector3(2.0, 0.04, 0.75), 0.0, false)
	flower_patch(-9.6, -13.45, 0.75, 7, FLOWERS, 0.42)


func _chimney_smoke(pos: Vector3) -> void:
	var pfac := float(PerformanceManager.get_param("particles"))
	if pfac < 0.5:
		return
	var p := CPUParticles3D.new()
	p.amount = 9
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.local_coords = false
	p.mesh = MeshFactory.sphere(0.5, 8, 5)
	p.material_override = MeshFactory.mat(Color(0.86, 0.84, 0.8), 1.0)
	p.direction = Vector3(0.15, 1, 0.05)
	p.spread = 12.0
	p.gravity = Vector3(0.18, 0.12, 0.05)
	p.initial_velocity_min = 0.35
	p.initial_velocity_max = 0.55
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	root.add_child(p)


# ------------------------------------------------------------------ zonas

func _zone_entrada() -> void:
	_workshop()
	bin(9.0, 50.0, PI * 0.5)
	# Buzón con aviso del cartero.
	block(pcol(C_WOOD_DARK, P_WOOD, true), 4.0, 61.0, Vector3(0.12, 1.0, 0.12))
	var my := gy(4, 61)
	add("box", pcol(Color(0.75, 0.2, 0.15), P_METAL), Vector3(4.0, my + 1.12, 61.0), Vector3(0.35, 0.24, 0.55))
	add_basis("cyl", pcol(Color(0.75, 0.2, 0.15), P_METAL), Vector3(4.0, my + 1.24, 61.0), Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.35, 0.55, 0.24)))
	add("box", pcol(Color(0.95, 0.8, 0.2), P_METAL), Vector3(4.2, my + 1.38, 61.1), Vector3(0.03, 0.22, 0.08), 0.0, false)
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
	# Decoración de otoño junto al portón.
	hay_bale(-6.0, 62.6)
	pumpkin(-6.0, 62.6, 0.55, 1.0)
	pumpkin(-5.0, 61.8, 0.6)
	pumpkin(-7.1, 61.9, 0.45)
	pumpkin(-4.6, 62.6, 0.35)
	wheelbarrow(7.6, 62.4, 0.35, Color(0.93, 0.52, 0.13))
	pumpkin(8.6, 61.5, 0.4)
	pot(-4.7, 63.2, 0.7, 2)
	pot(4.75, 63.2, 0.7, 2)
	bush(-16.5, 62.6, 1.3, Color(0.62, 0.2, 0.12))
	bush(-11.8, 62.9, 1.0, Color(0.3, 0.46, 0.2))
	bush(12.0, 62.9, 1.1, Color(0.7, 0.32, 0.12))
	signpost(3.5, 41.6, 0.4)
	birdhouse(-17.6, 50.5, PI * 0.5, Color(0.55, 0.72, 0.8))
	rock(17.6, 52.3, 0.9, true)
	rock(17.9, 53.4, 0.5)
	rock(16.9, 51.6, 0.4)
	flower_patch(-17.5, 46.5, 1.0, 8)
	flower_patch(17.0, 41.8, 0.9, 7)


func _workshop() -> void:
	# Taller de Brizna (tienda de mejoras).
	var sx := -12.0
	var sz := 50.0
	var y := gy(sx, sz)
	var planks := pcol(Color(0.6, 0.4, 0.24), P_PLANKS_V)
	house_box(planks, Vector3(sx - 2.0, y + 1.3, sz), Vector3(0.2, 2.6, 4.4))
	house_box(planks, Vector3(sx, y + 1.3, sz - 2.1), Vector3(4.2, 2.6, 0.2))
	house_box(planks, Vector3(sx, y + 1.3, sz + 2.1), Vector3(4.2, 2.6, 0.2))
	for c in [Vector2(-2.0, -2.1), Vector2(-2.0, 2.1), Vector2(2.0, -2.1), Vector2(2.0, 2.1)]:
		var cv: Vector2 = c
		add("box", pcol(C_WOOD_DARK, P_WOOD, true), Vector3(sx + cv.x, y + 1.3, sz + cv.y), Vector3(0.24, 2.6, 0.24))
	add("box", pcol(C_WOOD_DARK, P_WOOD), Vector3(sx + 2.0, y + 2.55, sz), Vector3(0.22, 0.2, 4.4))
	add_basis("prism", pcol(Color(0.66, 0.29, 0.21), P_ROOF), Vector3(sx, y + 3.15, sz), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(5.0, 1.1, 5.0)))
	gable(planks, Vector3(sx, y + 3.08, sz), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(4.3, 0.95, 4.2)))
	# Mostrador con encimera.
	house_box(pcol(C_WOOD_DARK, P_PLANKS_V), Vector3(sx + 1.7, y + 0.5, sz), Vector3(0.6, 1.0, 3.6))
	add("box", pcol(Color(0.9, 0.6, 0.2), P_WOOD), Vector3(sx + 1.72, y + 1.02, sz), Vector3(0.66, 0.06, 3.7))
	# Toldo a rayas, rótulo y farol.
	add_basis("box", pcol(Color(0.78, 0.25, 0.18), P_STRIPES), Vector3(sx + 2.75, y + 2.42, sz), Basis(Vector3.BACK, -0.32) * Basis.from_scale(Vector3(1.3, 0.05, 4.5)))
	for k in 9:
		add_basis("cone4", pcol(Color(0.78, 0.25, 0.18), P_PLAIN), Vector3(sx + 3.36, y + 2.12, sz - 2.0 + k * 0.5), Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(0.36, 0.16, 0.36)), false, 0.0)
	add("box", pcol(Color(0.42, 0.27, 0.15), P_WOOD), Vector3(sx + 2.15, y + 2.9, sz), Vector3(0.06, 0.55, 2.3))
	add("cyl6", C_IRON, Vector3(sx + 0.8, y + 2.35, sz), Vector3(0.02, 0.4, 0.02), 0.0, false)
	glow("cyl6", Vector3(sx + 0.8, y + 2.0, sz), Basis.from_scale(Vector3(0.24, 0.3, 0.24)))
	add("cone6", pcol(C_IRON, P_METAL), Vector3(sx + 0.8, y + 2.2, sz), Vector3(0.34, 0.14, 0.34), 0.0, false)
	# Estantes con botes, cajas y herramientas colgadas.
	for k in 2:
		add("box", pcol(C_WOOD, P_WOOD), Vector3(sx - 1.65, y + 1.0 + k * 0.6, sz), Vector3(0.45, 0.05, 3.6), 0.0, false)
	for k in 10:
		var cz := sz - 1.6 + k * 0.36
		var tall := 0.16 + 0.12 * fposmod(k * 0.37, 1.0)
		var cc: Color = [Color(0.3, 0.42, 0.55), Color(0.75, 0.3, 0.2), Color(0.85, 0.7, 0.3), Color(0.35, 0.55, 0.35)][k % 4]
		add("cyl8", pcol(cc, P_METAL), Vector3(sx - 1.62, y + 1.03 + (k % 2) * 0.6 + tall * 0.5, cz), Vector3(0.18, tall, 0.18), 0.0, false)
	for k in 3:
		var tz := sz + 1.95
		var tx := sx - 1.2 + k * 0.8
		add("cyl6", pcol(C_WOOD, P_WOOD, true), Vector3(tx, y + 1.35, tz), Vector3(0.04, 1.6, 0.04), 0.0, false)
		add("box", pcol(Color(0.5, 0.52, 0.55), P_METAL), Vector3(tx, y + 0.5, tz), Vector3(0.36, 0.05, 0.05), 0.0, false)
	terrain.add_solid_box(Vector2(sx, sz), Vector2(2.2, 2.2))
	label("TALLER", Vector3(sx + 2.2, y + 2.9, sz), 72, PI * 0.5)
	station(StationObject.Kind.SHOP, Vector3(sx + 1.7, y, sz), Vector3(0.9, 1.4, 3.6))
	var nt: Dictionary = GameData.NOTES[0]
	station(StationObject.Kind.NOTE, nt["pos"] - Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 0.3), nt)
	add("box", pcol(Color(0.55, 0.38, 0.22), P_WOOD), nt["pos"] + Vector3(0, 0, -0.02), Vector3(1.05, 0.75, 0.04))
	add("box", pcol(C_PAINT, P_PLAIN), nt["pos"], Vector3(0.9, 0.6, 0.04))
	# Leña apilada contra la pared norte, por fuera.
	var wz := sz - 2.75
	for row in 3:
		for k in 8 - row:
			var lx := sx - 1.5 + k * 0.4 + row * 0.2
			add_basis("cyl8", pcol(C_TRUNK.lightened(0.1), P_BARK), Vector3(lx, y + 0.13 + row * 0.24, wz), Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.24, 0.9, 0.24)), true, 0.3)
			add_basis("cyl8", Color(0.82, 0.68, 0.48), Vector3(lx, y + 0.13 + row * 0.24, wz - 0.452), Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.2, 0.01, 0.2)), false, 0.0)
	solid(sx, wz, Vector3(3.4, 0.8, 0.9))


func _zone_delantero() -> void:
	# Pedestal con esfera armilar de cobre.
	var stone := pcol(C_STONE, P_STONE)
	block(stone, 0, 25, Vector3(0.9, 0.5, 0.9))
	var py := gy(0, 25)
	add("cyl8", pcol(C_STONE, P_PLAIN), Vector3(0, py + 1.0, 25), Vector3(0.35, 1.0, 0.35))
	add("cyl8", pcol(C_STONE_DARK, P_PLAIN), Vector3(0, py + 1.55, 25), Vector3(1.0, 0.12, 1.0))
	var copper := pcol(Color(0.78, 0.5, 0.28), P_METAL)
	add_basis("ring", copper, Vector3(0, py + 2.05, 25), Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3.ONE * 0.9), true, 0.0)
	add_basis("ring", copper, Vector3(0, py + 2.05, 25), Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3.ONE * 0.9), true, 0.0)
	add_basis("ring", copper, Vector3(0, py + 2.05, 25), Basis(Vector3.FORWARD, 0.4) * Basis.from_scale(Vector3(0.95, 0.6, 0.95)), true, 0.0)
	add("sph", pcol(Color(0.85, 0.6, 0.3), P_METAL), Vector3(0, py + 2.05, 25), Vector3(0.16, 0.16, 0.16))
	for side in [-1.0, 1.0]:
		for seg in [[12.0, 21.0], [29.0, 38.0]]:
			var zc: float = (seg[0] + seg[1]) * 0.5
			var x: float = side * 2.7
			fol("hedge", C_HEDGE.lerp(Color(0.3, 0.46, 0.22), 0.3), Vector3(x, gy(x, zc) + 0.42, zc), Basis.from_scale(Vector3(0.75, 0.9, seg[1] - seg[0])), 0.12, 0.5)
			collider(Vector3(x, gy(x, zc) + 0.4, zc), Vector3(0.7, 0.8, seg[1] - seg[0]))
			terrain.add_solid_box(Vector2(x, zc), Vector2(0.35, (seg[1] - seg[0]) * 0.5))
	tree(-12, 27, 1.6, 0)
	for p in [Vector2(12, 33), Vector2(14, 15), Vector2(-14, 14), Vector2(-7, 36)]:
		tree(p.x, p.y, 1.0, 0)
	tree(8, 18, 1.0, 1)
	tree(-17, 20, 1.0, 2)
	# Pila para pájaros.
	block(stone, 10, 22, Vector3(0.5, 0.9, 0.5))
	add("cyl", pcol(C_STONE, P_PLAIN), Vector3(10, gy(10, 22) + 1.0, 22), Vector3(1.2, 0.15, 1.2))
	add("cyl", pcol(Color(0.55, 0.7, 0.75), P_WATER), Vector3(10, gy(10, 22) + 1.08, 22), Vector3(1.0, 0.02, 1.0), 0.0, false)
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
		_gnome(g.x, g.y, k)
		station(StationObject.Kind.NOTE, Vector3(g.x, gy(g.x, g.y), g.y), Vector3(0.4, 0.8, 0.4), {"id": "gnome_%d" % k, "title": "Gnomo %d de 3" % (k + 1), "text": gnome_texts[k]})
	# Farolillos bajos alrededor del círculo y rosales.
	for c in [Vector2(-3.96, 21.04), Vector2(3.96, 21.04), Vector2(-3.96, 28.96), Vector2(3.96, 28.96)]:
		bollard(c.x, c.y)
	for c in [Vector2(-3.7, 13.0), Vector2(3.7, 37.0), Vector2(-3.7, 37.0), Vector2(3.7, 13.0)]:
		bush(c.x, c.y, 0.8, Color(0.28, 0.45, 0.2), false)
		flower_patch(c.x, c.y, 0.5, 5, [Color(0.85, 0.15, 0.2), Color(0.95, 0.45, 0.55)])
	# Columpio de tablón en el gran arce.
	var swx := -10.3
	var swz := 27.6
	var sy := gy(swx, swz)
	for sxo in [-0.35, 0.35]:
		add("cyl6", Color(0.75, 0.62, 0.42), Vector3(swx + sxo, sy + 2.95, swz), Vector3(0.025, 4.3, 0.025), 0.0, false)
	add("box", pcol(C_WOOD, P_WOOD), Vector3(swx, sy + 0.8, swz), Vector3(0.85, 0.05, 0.3))
	add_basis("cyl8", pcol(C_TRUNK, P_BARK), Vector3(swx + 0.4, sy + 5.05, swz), Basis(Vector3.FORWARD, PI * 0.5 - 0.15) * Basis.from_scale(Vector3(0.22, 2.6, 0.22)))
	wheelbarrow(-9.5, 15.5, 0.8)
	rock(16.5, 37.2, 0.8, true)
	rock(17.4, 36.4, 0.45)
	bush(-18.3, 33.5, 1.2, Color(0.66, 0.22, 0.12))
	bush(18.3, 20.8, 1.1, Color(0.32, 0.47, 0.2))
	# Manta de picnic con cesta bajo el arce.
	add("box", pcol(Color(0.75, 0.22, 0.2), P_STRIPES), Vector3(10.2, gy(10.2, 31.0) + 0.02, 31.0), Vector3(1.9, 0.02, 1.5), 0.4, false)
	var bx := 10.6
	var bz := 31.2
	add("box", pcol(Color(0.72, 0.55, 0.3), P_STRAW), Vector3(bx, gy(bx, bz) + 0.17, bz), Vector3(0.5, 0.3, 0.35), 0.4)
	add_basis("ring", pcol(Color(0.6, 0.45, 0.25), P_PLAIN), Vector3(bx, gy(bx, bz) + 0.36, bz), Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.55, 0.55, 0.3)), false, 0.0)


func _gnome(x: float, z: float, k: int) -> void:
	var y := gy(x, z)
	var hat: Color = [Color(0.82, 0.15, 0.12), Color(0.2, 0.45, 0.25), Color(0.85, 0.55, 0.15)][k]
	add("cyl8", Color(0.25, 0.4, 0.7), Vector3(x, y + 0.2, z), Vector3(0.24, 0.4, 0.24))
	add("cyl8", Color(0.35, 0.22, 0.15), Vector3(x, y + 0.03, z), Vector3(0.28, 0.06, 0.28))
	add("sph", Color(0.96, 0.8, 0.66), Vector3(x, y + 0.47, z), Vector3(0.19, 0.18, 0.19))
	add("cone", hat, Vector3(x, y + 0.67, z), Vector3(0.24, 0.34, 0.24))
	add("sph", Color(0.97, 0.96, 0.92), Vector3(x, y + 0.38, z + 0.06), Vector3(0.17, 0.16, 0.12))
	add("sph", Color(0.92, 0.55, 0.5), Vector3(x, y + 0.46, z + 0.1), Vector3(0.05, 0.05, 0.05), 0.0, false)


func _zone_patio() -> void:
	# Fuente de dos pilas con agua.
	var y := gy(0, -3)
	var stone := pcol(C_STONE, P_STONE)
	add("cyl", stone, Vector3(0, y + 0.3, -3), Vector3(4.8, 0.6, 4.8))
	add("cyl", pcol(C_STONE_DARK.lightened(0.1), P_STONE), Vector3(0, y + 0.08, -3), Vector3(5.05, 0.16, 5.05))
	add("cyl", pcol(Color(0.36, 0.52, 0.5), P_WATER), Vector3(0, y + 0.61, -3), Vector3(4.3, 0.02, 4.3), 0.0, false)
	add("cyl8", stone, Vector3(0, y + 1.1, -3), Vector3(0.5, 1.6, 0.5))
	add("cyl", pcol(C_STONE, P_PLAIN), Vector3(0, y + 1.9, -3), Vector3(1.6, 0.25, 1.6))
	add("cyl", pcol(Color(0.4, 0.56, 0.55), P_WATER), Vector3(0, y + 2.03, -3), Vector3(1.4, 0.02, 1.4), 0.0, false)
	add("cyl8", pcol(C_STONE, P_PLAIN), Vector3(0, y + 2.25, -3), Vector3(0.22, 0.45, 0.22))
	add("sph", pcol(C_STONE_DARK, P_PLAIN), Vector3(0, y + 2.55, -3), Vector3(0.4, 0.3, 0.4))
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
		block(pcol(C_TERRACOTTA, P_BRICK), sx, -10.6, Vector3(0.9, 0.7, 0.9))
		add("box", pcol(C_STONE, P_PLAIN), Vector3(sx, gy(sx, -10.6) + 0.72, -10.6), Vector3(1.0, 0.06, 1.0))
		fol("blob1", Color(0.26, 0.47, 0.2), Vector3(sx, gy(sx, -10.6) + 1.15, -10.6), Basis.from_scale(Vector3(1.0, 0.9, 1.0)), 0.3)
		fol("blob2", Color(0.28, 0.5, 0.22), Vector3(sx, gy(sx, -10.6) + 1.75, -10.6), Basis.from_scale(Vector3(0.65, 0.6, 0.65)), 0.3)
	bin(5.0, 7.0, 0.0)
	# Mesa de jardín con sillas.
	var tx := -12.5
	var tz := 0.0
	var ty := gy(tx, tz)
	add("cyl", pcol(Color(0.92, 0.92, 0.88), P_METAL), Vector3(tx, ty + 0.74, tz), Vector3(1.2, 0.05, 1.2))
	add("cyl8", pcol(C_IRON, P_METAL), Vector3(tx, ty + 0.37, tz), Vector3(0.08, 0.74, 0.08))
	add("cyl8", pcol(C_IRON, P_METAL), Vector3(tx, ty + 0.03, tz), Vector3(0.6, 0.06, 0.6))
	for k in 3:
		var a := k * TAU / 3.0 + 0.4
		var cf := Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(tx + cos(a) * 1.0, ty, tz + sin(a) * 1.0))
		ladd("box", pcol(Color(0.92, 0.92, 0.88), P_METAL), cf, Vector3(0, 0.45, 0), Vector3(0.45, 0.04, 0.45))
		ladd("box", pcol(Color(0.92, 0.92, 0.88), P_METAL), cf, Vector3(0, 0.7, 0.22), Vector3(0.45, 0.5, 0.04))
		for c in [Vector2(-0.19, -0.19), Vector2(0.19, -0.19), Vector2(-0.19, 0.19), Vector2(0.19, 0.19)]:
			var cv: Vector2 = c
			ladd("box", pcol(C_IRON, P_METAL), cf, Vector3(cv.x, 0.22, cv.y), Vector3(0.03, 0.45, 0.03), Basis.IDENTITY, false)
	add("cyl8", Color(0.95, 0.95, 0.92), Vector3(tx + 0.2, ty + 0.8, tz + 0.1), Vector3(0.1, 0.08, 0.1), 0.0, false)
	add("cyl8", pcol(Color(0.85, 0.5, 0.3), P_METAL), Vector3(tx - 0.25, ty + 0.84, tz - 0.1), Vector3(0.18, 0.16, 0.18), 0.0, false)
	collider(Vector3(tx, ty + 0.4, tz), Vector3(1.2, 0.8, 1.2))
	terrain.add_solid_circle(Vector2(tx, tz), 0.6)
	# Arbustos junto a la fachada oeste.
	bush(-12.3, -16.0, 1.1, Color(0.3, 0.46, 0.2))
	bush(-12.4, -20.6, 1.2, Color(0.64, 0.24, 0.12))
	flower_patch(-12.4, -18.3, 0.8, 6)


func _zone_garaje() -> void:
	var y := gy(42, 22)
	var wall := pcol(Color(0.84, 0.76, 0.63), P_PLANKS_H)
	var trim := Color(0.96, 0.94, 0.88)
	var tpc := pcol(trim, P_PLAIN)
	house_box(wall, Vector3(42, y + 2.0, 22), Vector3(12, 4.0, 10))
	add("box", pcol(C_STONE_DARK, P_STONE), Vector3(42, y + 0.3, 22), Vector3(12.2, 0.6, 10.2))
	for cx in [36.0, 48.0]:
		for cz in [17.0, 27.0]:
			add("box", tpc, Vector3(cx, y + 2.0, cz), Vector3(0.28, 4.0, 0.28))
	add("box", tpc, Vector3(42, y + 4.02, 22), Vector3(12.3, 0.16, 10.3))
	add_basis("prism", pcol(Color(0.47, 0.3, 0.24), P_ROOF), Vector3(42, y + 5.0, 22), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(11, 2.0, 13)))
	gable(wall, Vector3(42, y + 4.95, 22), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(9.9, 1.85, 12.0)))
	add("box", pcol(Color(0.36, 0.22, 0.17), P_PLAIN), Vector3(42, y + 6.02, 22), Vector3(13.2, 0.14, 0.3))
	# Puerta seccional, marco, tirador y farol.
	add("box", pcol(Color(0.55, 0.62, 0.66), P_PLANKS_H), Vector3(42, y + 1.6, 27.04), Vector3(6.0, 3.2, 0.1))
	add("box", tpc, Vector3(42, y + 3.3, 27.08), Vector3(6.5, 0.2, 0.14))
	add("box", tpc, Vector3(38.9, y + 1.6, 27.08), Vector3(0.2, 3.3, 0.14))
	add("box", tpc, Vector3(45.1, y + 1.6, 27.08), Vector3(0.2, 3.3, 0.14))
	add("box", pcol(C_IRON, P_METAL), Vector3(42, y + 0.6, 27.12), Vector3(0.6, 0.06, 0.05), 0.0, false)
	for k in 4:
		add("box", pcol(Color.WHITE, P_GLASS), Vector3(40.0 + k * 1.33, y + 2.65, 27.1), Vector3(0.9, 0.35, 0.03), 0.0, false)
	add("box", pcol(C_IRON, P_METAL), Vector3(42, y + 3.7, 27.15), Vector3(0.22, 0.3, 0.12), 0.0, false)
	glow("cyl6", Vector3(42, y + 3.48, 27.32), Basis.from_scale(Vector3(0.2, 0.26, 0.2)))
	add("cone6", pcol(C_IRON, P_METAL), Vector3(42, y + 3.65, 27.32), Vector3(0.3, 0.12, 0.3), 0.0, false)
	window(Vector3(36.0, y + 2.0, 19.5), 1.1, 1.0, Vector3(-1, 0, 0), trim, Color(0.3, 0.42, 0.5))
	window(Vector3(36.0, y + 2.0, 24.5), 1.1, 1.0, Vector3(-1, 0, 0), trim, Color(0.3, 0.42, 0.5))
	window(Vector3(48.0, y + 2.0, 22.0), 1.1, 1.0, Vector3(1, 0, 0), trim, Color(0.3, 0.42, 0.5))
	terrain.add_solid_box(Vector2(42, 22), Vector2(6, 5))
	_car(30.0, 33.0, 0.3)
	# Bidón azul del Tónico Otoñal y barriles.
	barrel(34.0, 30.0, Color(0.2, 0.4, 0.85))
	solid(34.0, 30.0, Vector3(0.7, 0.95, 0.7))
	barrel(33.0, 29.2, Color(0.55, 0.32, 0.18))
	solid(33.0, 29.2, Vector3(0.7, 0.95, 0.7))
	# Neumáticos sobre un palé.
	block(pcol(C_WOOD, P_PLANKS_V), 52.0, 14.0, Vector3(0.9, 0.16, 0.9))
	for k in 3:
		add_basis("ring", Color(0.13, 0.13, 0.14), Vector3(52.0, gy(52, 14) + 0.3 + k * 0.25, 14.0), Basis(Vector3.UP, k * 0.7) * Basis.from_scale(Vector3(1.05, 1.0, 1.05)))
	solid(52.0, 14.0, Vector3(0.85, 0.9, 0.85))
	# Banco de trabajo con herramientas.
	_workbench(55.0, 21.0)
	for p in [Vector2(24, 37), Vector2(57, 37), Vector2(24, 13)]:
		tree(p.x, p.y, 1.0, 0)
	tree(57, 12, 1.1, 2)
	bin(55.0, 31.0, -PI * 0.5)
	# Canasta de baloncesto junto a la explanada.
	var hx := 47.6
	var hz := 38.6
	var hy := gy(hx, hz)
	add("cyl8", pcol(Color(0.3, 0.32, 0.35), P_METAL), Vector3(hx, hy + 1.6, hz), Vector3(0.12, 3.2, 0.12))
	add("box", pcol(Color(0.95, 0.95, 0.92), P_PLAIN), Vector3(hx - 0.55, hy + 3.2, hz), Vector3(0.05, 0.8, 1.1))
	add("box", Color(0.85, 0.3, 0.15), Vector3(hx - 0.58, hy + 3.1, hz), Vector3(0.02, 0.3, 0.4), 0.0, false)
	add_basis("ring", pcol(Color(0.9, 0.4, 0.12), P_METAL), Vector3(hx - 0.85, hy + 2.95, hz), Basis.from_scale(Vector3(0.55, 0.15, 0.55)), false, 0.0)
	collider(Vector3(hx, hy + 1.6, hz), Vector3(0.2, 3.2, 0.2))
	terrain.add_solid_circle(Vector2(hx, hz), 0.12)
	add("sph", Color(0.88, 0.45, 0.15), Vector3(44.0, gy(44, 38) + 0.13, 38.0), Vector3(0.26, 0.26, 0.26))
	# Escalera apoyada en la pared y bicicleta vieja.
	var lb := Basis(Vector3.BACK, -0.25)
	var lc := Vector3(35.57, y + 1.5, 21.0)
	for lz in [-0.25, 0.25]:
		add_basis("box", pcol(C_WOOD, P_WOOD, true), lc + Vector3(0, 0, lz), lb * Basis.from_scale(Vector3(0.06, 3.1, 0.06)))
	for k in 9:
		var t := (k + 0.5) / 9.0 * 3.0 - 1.5
		add_basis("box", pcol(C_WOOD, P_WOOD), lc + lb.y * t, Basis.from_scale(Vector3(0.04, 0.04, 0.5)), false, 0.0)
	var bkf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(48.45, y, 24.0))
	for wx in [-0.55, 0.55]:
		ladd("ring", Color(0.12, 0.12, 0.12), bkf, Vector3(wx, 0.38, 0), Vector3(0.75, 0.25, 0.75), Basis(Vector3.RIGHT, PI * 0.5), false)
	var frame := pcol(Color(0.7, 0.15, 0.15), P_METAL)
	ladd("box", frame, bkf, Vector3(0, 0.58, 0), Vector3(0.8, 0.04, 0.04), Basis(Vector3.BACK, -0.25), false)
	ladd("box", frame, bkf, Vector3(-0.25, 0.48, 0), Vector3(0.04, 0.45, 0.04), Basis(Vector3.BACK, 0.35), false)
	ladd("box", frame, bkf, Vector3(0.48, 0.55, 0), Vector3(0.04, 0.4, 0.04), Basis(Vector3.BACK, -0.3), false)
	ladd("box", Color(0.15, 0.12, 0.1), bkf, Vector3(-0.32, 0.74, 0), Vector3(0.22, 0.05, 0.1), Basis.IDENTITY, false)
	ladd("box", C_IRON, bkf, Vector3(0.55, 0.8, 0), Vector3(0.04, 0.04, 0.5), Basis.IDENTITY, false)
	# Tablones apilados.
	for k in 4:
		add("box", pcol(Color(0.7, 0.52, 0.32), P_WOOD), Vector3(51.0, gy(51, 38.6) + 0.08 + k * 0.12, 38.6), Vector3(3.0, 0.1, 0.25 + 0.05 * (k % 2)), 0.05 * k)
	solid(51.0, 38.6, Vector3(3.0, 0.5, 0.5))
	bush(21.6, 38.5, 1.1, Color(0.6, 0.22, 0.1))
	bush(58.6, 25.0, 1.2, Color(0.3, 0.46, 0.2))
	flower_patch(36.6, 28.3, 0.7, 6)


func _car(cx: float, cz: float, rot: float) -> void:
	var cy := gy(cx, cz)
	var f := Transform3D(Basis(Vector3.UP, rot), Vector3(cx, cy, cz))
	var paint := pcol(Color(0.25, 0.55, 0.55), P_METAL)
	var dark := pcol(Color(0.2, 0.45, 0.45), P_METAL)
	var chrome := pcol(Color(0.85, 0.86, 0.88), P_METAL)
	var glass := pcol(Color.WHITE, P_GLASS)
	ladd("box", paint, f, Vector3(0, 0.66, 0), Vector3(3.9, 0.55, 1.7))
	ladd("box", paint, f, Vector3(1.25, 0.9, 0), Vector3(1.3, 0.22, 1.55))
	ladd("box", paint, f, Vector3(-1.45, 0.9, 0), Vector3(0.9, 0.2, 1.55))
	for w in [Vector2(-1.3, -0.82), Vector2(1.3, -0.82), Vector2(-1.3, 0.82), Vector2(1.3, 0.82)]:
		var wv: Vector2 = w
		ladd("sph", dark, f, Vector3(wv.x, 0.78, wv.y * 0.98), Vector3(1.05, 0.62, 0.42))
		ladd("cyl", Color(0.1, 0.1, 0.1), f, Vector3(wv.x, 0.38, wv.y * 1.12), Vector3(0.75, 0.24, 0.75), Basis(Vector3.RIGHT, PI * 0.5))
		ladd("cyl", chrome, f, Vector3(wv.x, 0.38, wv.y * 1.12 + signf(wv.y) * 0.1), Vector3(0.36, 0.06, 0.36), Basis(Vector3.RIGHT, PI * 0.5), false)
	ladd("box", paint, f, Vector3(-0.2, 1.3, 0), Vector3(2.0, 0.62, 1.5))
	ladd("box", paint, f, Vector3(-0.2, 1.64, 0), Vector3(2.1, 0.08, 1.58))
	for sz in [-1.0, 1.0]:
		ladd("box", glass, f, Vector3(-0.2, 1.33, sz * 0.76), Vector3(1.75, 0.42, 0.02), Basis.IDENTITY, false)
	ladd("box", glass, f, Vector3(0.82, 1.33, 0), Vector3(0.02, 0.42, 1.36), Basis(Vector3.BACK, -0.2), false)
	ladd("box", glass, f, Vector3(-1.22, 1.33, 0), Vector3(0.02, 0.42, 1.36), Basis(Vector3.BACK, 0.15), false)
	for bx in [-2.0, 2.0]:
		ladd("box", chrome, f, Vector3(bx, 0.48, 0), Vector3(0.12, 0.14, 1.8))
	for sz in [-0.55, 0.55]:
		ladd("sph", Color(1.0, 0.95, 0.8), f, Vector3(1.92, 0.82, sz), Vector3(0.2, 0.2, 0.2), Basis.IDENTITY, false)
		ladd("sph", Color(0.75, 0.12, 0.1), f, Vector3(-1.94, 0.8, sz), Vector3(0.12, 0.12, 0.12), Basis.IDENTITY, false)
	ladd("box", chrome, f, Vector3(1.96, 0.7, 0), Vector3(0.05, 0.25, 0.7), Basis.IDENTITY, false)
	for sz in [-0.88, 0.88]:
		ladd("box", Color(0.15, 0.15, 0.15), f, Vector3(0, 0.42, sz), Vector3(1.4, 0.05, 0.22), Basis.IDENTITY, false)
	# Hojas acumuladas sobre el techo y el capó.
	fol("blob_lo", C_LEAFPILE, f * Vector3(-0.2, 1.7, 0.1), f.basis * Basis.from_scale(Vector3(1.4, 0.12, 1.0)), 0.0, 0.0, false)
	fol("blob_lo", Color(0.8, 0.3, 0.1), f * Vector3(1.3, 1.02, -0.2), f.basis * Basis.from_scale(Vector3(0.7, 0.08, 0.6)), 0.0, 0.0, false)
	collider(Vector3(cx, cy + 0.9, cz), Vector3(4.0, 1.8, 1.9), rot)
	terrain.add_solid_box(Vector2(cx, cz), Vector2(2.0, 0.95), rot)


func _workbench(x: float, z: float) -> void:
	var y := gy(x, z)
	var f := Transform3D(Basis.IDENTITY, Vector3(x, y, z))
	ladd("box", pcol(Color(0.7, 0.5, 0.3), P_WOOD), f, Vector3(0, 0.86, 0), Vector3(1.0, 0.08, 2.2))
	ladd("box", pcol(Color(0.6, 0.42, 0.25), P_PLANKS_V), f, Vector3(0, 0.3, 0), Vector3(0.9, 0.05, 2.0))
	for c in [Vector2(-0.42, -1.0), Vector2(0.42, -1.0), Vector2(-0.42, 1.0), Vector2(0.42, 1.0)]:
		var cv: Vector2 = c
		ladd("box", pcol(C_WOOD_DARK, P_WOOD, true), f, Vector3(cv.x, 0.42, cv.y), Vector3(0.08, 0.84, 0.08))
	ladd("box", pcol(Color(0.8, 0.18, 0.15), P_METAL), f, Vector3(0.1, 1.02, 0.6), Vector3(0.35, 0.22, 0.55))
	ladd("box", pcol(Color(0.4, 0.42, 0.45), P_METAL), f, Vector3(0.0, 0.98, -0.7), Vector3(0.25, 0.16, 0.2))
	ladd("box", pcol(Color(0.75, 0.15, 0.12), P_METAL), f, Vector3(0.2, 0.36 + 0.2, -0.6), Vector3(0.25, 0.35, 0.2), Basis.IDENTITY, false)
	ladd("cyl6", pcol(C_WOOD, P_WOOD), f, Vector3(-0.2, 0.92, 0.0), Vector3(0.04, 0.6, 0.04), Basis(Vector3.RIGHT, PI * 0.5), false)
	ladd("box", pcol(Color(0.55, 0.56, 0.6), P_METAL), f, Vector3(-0.2, 0.92, -0.33), Vector3(0.1, 0.06, 0.12), Basis.IDENTITY, false)
	solid(x, z, Vector3(1.0, 0.9, 2.2))


func _zone_infantil() -> void:
	# Columpios.
	var sx := -47.0
	var sz := 32.0
	var y := gy(sx, sz)
	var red := pcol(Color(0.8, 0.25, 0.2), P_METAL)
	for ex in [-2.0, 2.0]:
		for lean in [-0.28, 0.28]:
			add_basis("cyl8", red, Vector3(sx + ex, y + 1.25, sz + lean * 1.25), Basis(Vector3.RIGHT, lean) * Basis.from_scale(Vector3(0.12, 2.6, 0.12)))
		add("box", red, Vector3(sx + ex, y + 0.9, sz), Vector3(0.06, 0.06, 0.62), 0.0, false)
	add_basis("cyl8", red, Vector3(sx, y + 2.5, sz), Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.12, 4.3, 0.12)))
	for k in [-0.9, 0.9]:
		add("box", Color(0.15, 0.15, 0.17), Vector3(sx + k, y + 0.55, sz), Vector3(0.55, 0.05, 0.26))
		add("cyl6", pcol(C_IRON, P_METAL), Vector3(sx + k - 0.25, y + 1.5, sz), Vector3(0.025, 1.9, 0.025), 0.0, false)
		add("cyl6", pcol(C_IRON, P_METAL), Vector3(sx + k + 0.25, y + 1.5, sz), Vector3(0.025, 1.9, 0.025), 0.0, false)
	collider(Vector3(sx, y + 1.3, sz), Vector3(4.4, 2.6, 0.6))
	for ex in [-2.0, 2.0]:
		terrain.add_solid_circle(Vector2(sx + ex, sz - 0.35), 0.15)
		terrain.add_solid_circle(Vector2(sx + ex, sz + 0.35), 0.15)
	# Tobogán con escalera, barandillas y tejadillo.
	var tx := -31.0
	var tz := 19.0
	var ty := gy(tx, tz)
	var yellow := pcol(Color(0.95, 0.75, 0.2), P_PLAIN)
	for c in [Vector2(-0.45, -1.95), Vector2(0.45, -1.95), Vector2(-0.45, -1.25), Vector2(0.45, -1.25)]:
		var cv: Vector2 = c
		add("box", pcol(C_WOOD, P_WOOD, true), Vector3(tx + cv.x, ty + 1.4, tz + cv.y), Vector3(0.1, 2.8, 0.1))
	add("box", pcol(C_WOOD, P_PLANKS_V), Vector3(tx, ty + 1.95, tz - 1.6), Vector3(1.0, 0.08, 0.8))
	add("box", yellow, Vector3(tx, ty + 1.0, tz - 1.6), Vector3(1.0, 2.0, 0.8))
	add_basis("prism", pcol(Color(0.2, 0.5, 0.75), P_PLAIN), Vector3(tx, ty + 3.0, tz - 1.6), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(1.0, 0.5, 1.2)))
	for k in 6:
		add("box", pcol(C_WOOD, P_WOOD), Vector3(tx, ty + 0.3 + k * 0.3, tz - 2.15), Vector3(0.9, 0.05, 0.12), 0.0, false)
	var chute := Basis(Vector3.RIGHT, 0.62)
	add_basis("box", pcol(Color(0.3, 0.6, 0.85), P_METAL), Vector3(tx, ty + 1.0, tz + 0.3), chute * Basis.from_scale(Vector3(0.8, 0.08, 3.6)))
	for sxo in [-0.42, 0.42]:
		add_basis("box", pcol(Color(0.3, 0.6, 0.85), P_METAL), Vector3(tx + sxo, ty + 1.12, tz + 0.3), chute * Basis.from_scale(Vector3(0.06, 0.22, 3.6)))
	collider(Vector3(tx, ty + 1.0, tz - 1.6), Vector3(1.0, 2.0, 0.8))
	terrain.add_solid_box(Vector2(tx, tz - 1.6), Vector2(0.5, 0.4))
	# Arenero con arena, cubo y castillo.
	for e in [[Vector2(-48, 14), Vector3(4.2, 0.3, 0.2)], [Vector2(-48, 18), Vector3(4.2, 0.3, 0.2)], [Vector2(-50, 16), Vector3(0.2, 0.3, 4.2)], [Vector2(-46, 16), Vector3(0.2, 0.3, 4.2)]]:
		block(pcol(C_WOOD, P_WOOD), e[0].x, e[0].y, e[1], 0.0, true, false)
	add("box", pcol(C_SAND, P_PLAIN), Vector3(-48, gy(-48, 16) + 0.05, 16), Vector3(3.8, 0.1, 3.8), 0.0, false)
	add("cyl8", pcol(Color(0.85, 0.2, 0.2), P_PLAIN), Vector3(-49.2, gy(-49.2, 15.2) + 0.2, 15.2), Vector3(0.24, 0.22, 0.24))
	add_basis("box", pcol(Color(0.2, 0.45, 0.85), P_PLAIN), Vector3(-49.0, gy(-49, 15.5) + 0.13, 15.6), Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, 0.3) * Basis.from_scale(Vector3(0.06, 0.04, 0.4)), false)
	add("cyl8", pcol(C_SAND.darkened(0.05), P_PLAIN), Vector3(-46.8, gy(-46.8, 16.9) + 0.18, 16.9), Vector3(0.36, 0.2, 0.36))
	add("cone6", pcol(C_SAND.darkened(0.05), P_PLAIN), Vector3(-46.8, gy(-46.8, 16.9) + 0.37, 16.9), Vector3(0.28, 0.2, 0.28))
	# Balancín.
	add("box", pcol(Color(0.3, 0.55, 0.3), P_METAL), Vector3(-53, gy(-53, 24) + 0.5, 24), Vector3(0.3, 0.5, 0.4))
	add_basis("box", pcol(Color(0.95, 0.55, 0.2), P_PLAIN), Vector3(-53, gy(-53, 24) + 0.65, 24), Basis(Vector3.FORWARD, 0.18) * Basis.from_scale(Vector3(3.6, 0.1, 0.35)))
	for ex in [-1.5, 1.5]:
		add_basis("box", pcol(C_IRON, P_METAL), Vector3(-53 + ex * cos(0.18), gy(-53, 24) + 0.65 + 0.25 + ex * 0.18, 24), Basis.from_scale(Vector3(0.04, 0.3, 0.3)), false)
	collider(Vector3(-53, gy(-53, 24) + 0.5, 24), Vector3(3.6, 1.0, 0.4))
	# Casita de juegos.
	var hx := -25.0
	var hz := 21.0
	var hy := gy(hx, hz)
	house_box(pcol(Color(0.95, 0.72, 0.72), P_PLANKS_H), Vector3(hx, hy + 1.1, hz), Vector3(2.6, 2.2, 2.6))
	add_basis("prism", pcol(Color(0.55, 0.3, 0.55), P_ROOF), Vector3(hx, hy + 2.7, hz), Basis.from_scale(Vector3(3.0, 1.0, 3.0)))
	gable(pcol(Color(0.95, 0.72, 0.72), P_PLANKS_H), Vector3(hx, hy + 2.67, hz), Basis.from_scale(Vector3(2.6, 0.9, 2.6)))
	add("box", pcol(Color(0.35, 0.25, 0.2), P_PLANKS_V), Vector3(hx + 1.31, hy + 0.8, hz), Vector3(0.05, 1.4, 0.8))
	add("box", pcol(Color(0.98, 0.95, 0.9), P_PLAIN), Vector3(hx + 1.33, hy + 1.55, hz), Vector3(0.06, 0.1, 0.95), 0.0, false)
	add("sph", pcol(Color(0.9, 0.75, 0.3), P_METAL), Vector3(hx + 1.36, hy + 0.8, hz + 0.25), Vector3(0.07, 0.07, 0.07), 0.0, false)
	window(Vector3(hx, hy + 1.25, hz + 1.3), 0.7, 0.6, Vector3(0, 0, 1), Color(0.98, 0.95, 0.9), Color(0.4, 0.6, 0.75), true)
	add("box", pcol(Color(0.62, 0.36, 0.28), P_BRICK), Vector3(hx - 0.7, hy + 3.0, hz - 0.5), Vector3(0.35, 0.8, 0.35))
	terrain.add_solid_box(Vector2(hx, hz), Vector2(1.3, 1.3))
	# Carrito rojo junto a la casita.
	var wf := Transform3D(Basis(Vector3.UP, 0.5), Vector3(-27.9, gy(-27.9, 23.3), 23.3))
	ladd("box", pcol(Color(0.82, 0.18, 0.15), P_METAL), wf, Vector3(0, 0.32, 0), Vector3(0.9, 0.25, 0.55))
	for c in [Vector2(-0.32, -0.3), Vector2(0.32, -0.3), Vector2(-0.32, 0.3), Vector2(0.32, 0.3)]:
		var cv: Vector2 = c
		ladd("cyl", Color(0.12, 0.12, 0.12), wf, Vector3(cv.x, 0.11, cv.y), Vector3(0.22, 0.05, 0.22), Basis(Vector3.RIGHT, PI * 0.5), false)
	ladd("box", C_IRON, wf, Vector3(0.75, 0.35, 0), Vector3(0.6, 0.03, 0.03), Basis(Vector3.BACK, 0.4), false)
	fol("blob_lo", C_LEAFPILE, wf * Vector3(0, 0.48, 0), wf.basis * Basis.from_scale(Vector3(0.75, 0.22, 0.45)), 0.0, 0.0, false)
	# Caballito de muelle y pelota.
	var rx := -38.0
	var rz := 30.0
	var ry := gy(rx, rz)
	add("cyl8", pcol(C_IRON, P_METAL), Vector3(rx, ry + 0.03, rz), Vector3(0.5, 0.06, 0.5))
	add("cyl8", pcol(Color(0.6, 0.62, 0.65), P_METAL), Vector3(rx, ry + 0.3, rz), Vector3(0.14, 0.5, 0.14))
	add("box", pcol(Color(0.95, 0.85, 0.3), P_PLAIN), Vector3(rx, ry + 0.68, rz), Vector3(0.7, 0.32, 0.26))
	add("box", pcol(Color(0.95, 0.85, 0.3), P_PLAIN), Vector3(rx + 0.36, ry + 0.95, rz), Vector3(0.22, 0.42, 0.22), -0.2)
	add("sph", Color(0.12, 0.1, 0.1), Vector3(rx + 0.42, ry + 1.05, rz + 0.11), Vector3(0.05, 0.05, 0.05), 0.0, false)
	add("box", pcol(Color(0.85, 0.3, 0.2), P_PLAIN), Vector3(rx + 0.25, ry + 1.0, rz), Vector3(0.08, 0.3, 0.28), 0.0, false)
	add("box", Color(0.2, 0.2, 0.22), Vector3(rx + 0.2, ry + 0.95, rz), Vector3(0.04, 0.04, 0.5), 0.0, false)
	collider(Vector3(rx, ry + 0.5, rz), Vector3(0.8, 1.0, 0.4))
	terrain.add_solid_circle(Vector2(rx, rz), 0.3)
	add("sph", pcol(Color(0.95, 0.3, 0.3), P_STRIPES), Vector3(-42.0, gy(-42, 35) + 0.18, 35.0), Vector3(0.36, 0.36, 0.36))
	for p in [Vector2(-35, 38), Vector2(-24, 14), Vector2(-57, 12), Vector2(-58, 27)]:
		tree(p.x, p.y, 1.0, 0)
	tree(-36, 12, 1.0, 1)
	bin(-55.0, 37.0, 0.0)
	bush(-58.5, 38.4, 1.2, Color(0.66, 0.24, 0.12))
	bush(-21.6, 12.4, 1.0, Color(0.3, 0.46, 0.2))
	flower_patch(-22.0, 30.0, 0.9, 8)
	flower_patch(-58.0, 20.0, 0.8, 6)


func _zone_huerto() -> void:
	var crop := 0
	for bx in [-52.0, -44.0, -36.0]:
		for bz in [-14.0, -4.0]:
			terrain.paint_rect(Rect2(bx - 2.5, bz - 3.5, 5, 7), 1)
			for e in [[Vector2(0, -3.5), Vector3(5.2, 0.35, 0.2)], [Vector2(0, 3.5), Vector3(5.2, 0.35, 0.2)], [Vector2(-2.5, 0), Vector3(0.2, 0.35, 7.2)], [Vector2(2.5, 0), Vector3(0.2, 0.35, 7.2)]]:
				block(pcol(C_WOOD, P_PLANKS_H), bx + e[0].x, bz + e[0].y, e[1], 0.0, true, false)
			_crops(bx, bz, crop)
			crop += 1
	# Espantapájaros.
	var y := gy(-30, -8)
	add("cyl6", pcol(C_WOOD_DARK, P_WOOD, true), Vector3(-30, y + 1.1, -8), Vector3(0.12, 2.2, 0.12))
	add_basis("cyl6", pcol(C_WOOD_DARK, P_WOOD), Vector3(-30, y + 1.6, -8), Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.1, 1.8, 0.1)))
	add("box", pcol(Color(0.55, 0.3, 0.45), P_PLANKS_V), Vector3(-30, y + 1.35, -8), Vector3(0.6, 0.7, 0.3))
	add("box", pcol(Color(0.35, 0.4, 0.6), P_PLAIN), Vector3(-30, y + 0.85, -8), Vector3(0.5, 0.35, 0.28))
	add("sph", pcol(Color(0.85, 0.75, 0.5), P_STRAW), Vector3(-30, y + 2.0, -8), Vector3(0.4, 0.42, 0.4))
	add("cyl", pcol(Color(0.42, 0.32, 0.17), P_STRAW), Vector3(-30, y + 2.18, -8), Vector3(0.8, 0.04, 0.8))
	add("cone", pcol(Color(0.42, 0.32, 0.17), P_STRAW), Vector3(-30, y + 2.36, -8), Vector3(0.42, 0.36, 0.42))
	for sxo in [-0.9, 0.9]:
		fol("tuft", Color(0.85, 0.72, 0.4), Vector3(-30 + sxo, y + 1.55, -8), Basis(Vector3.FORWARD, -signf(sxo) * 1.3) * Basis.from_scale(Vector3(0.25, 0.3, 0.25)), 0.6, 0.0, false)
	add("sph", Color(0.08, 0.06, 0.05), Vector3(-30.08, y + 2.04, -7.81), Vector3(0.05, 0.05, 0.03), 0.0, false)
	add("sph", Color(0.08, 0.06, 0.05), Vector3(-29.92, y + 2.04, -7.81), Vector3(0.05, 0.05, 0.03), 0.0, false)
	collider(Vector3(-30, y + 1.1, -8), Vector3(0.3, 2.2, 0.3))
	terrain.add_solid_circle(Vector2(-30, -8), 0.15)
	# Buzón calabaza.
	block(pcol(C_WOOD_DARK, P_WOOD, true), -25.0, 5.0, Vector3(0.12, 0.9, 0.12))
	add("pumpkin", Color(0.97, 0.52, 0.12), Vector3(-25, gy(-25, 5) + 1.1, 5), Vector3(0.75, 0.75, 0.75))
	add("box", Color(0.15, 0.1, 0.06), Vector3(-25, gy(-25, 5) + 1.08, 5.35), Vector3(0.3, 0.06, 0.03), 0.0, false)
	# Cobertizo de tablas con puerta y ventana.
	var shx := -55.0
	var shz := -20.0
	var shy := gy(shx, shz)
	var shw := pcol(Color(0.52, 0.43, 0.32), P_PLANKS_V)
	house_box(shw, Vector3(shx, shy + 1.4, shz), Vector3(4.0, 2.8, 3.0))
	add_basis("prism", pcol(Color(0.36, 0.32, 0.3), P_ROOF), Vector3(shx, shy + 3.3, shz), Basis.from_scale(Vector3(4.6, 1.0, 3.6)))
	gable(shw, Vector3(shx, shy + 3.25, shz), Basis.from_scale(Vector3(4.0, 0.9, 3.0)))
	var door := pcol(Color(0.4, 0.33, 0.25), P_PLANKS_V)
	add("box", door, Vector3(shx + 2.02, shy + 1.05, shz), Vector3(0.06, 2.0, 1.1))
	for dy in [0.4, 1.7]:
		add("box", pcol(Color(0.34, 0.27, 0.2), P_WOOD), Vector3(shx + 2.06, shy + dy, shz), Vector3(0.04, 0.12, 1.1), 0.0, false)
	add_basis("box", pcol(Color(0.34, 0.27, 0.2), P_WOOD), Vector3(shx + 2.06, shy + 1.05, shz), Basis(Vector3.RIGHT, 0.95) * Basis.from_scale(Vector3(0.04, 1.4, 0.1)), false)
	add("sph", pcol(C_IRON, P_METAL), Vector3(shx + 2.09, shy + 1.05, shz - 0.4), Vector3(0.07, 0.07, 0.07), 0.0, false)
	window(Vector3(shx, shy + 1.6, shz + 1.5), 0.8, 0.7, Vector3(0, 0, 1), Color(0.85, 0.82, 0.75))
	terrain.add_solid_box(Vector2(shx, shz), Vector2(2.0, 1.5))
	barrel(-52.6, -18.0, Color(0.35, 0.42, 0.38), Vector3(0.75, 0.9, 0.75))
	add("cyl", pcol(Color(0.3, 0.45, 0.48), P_WATER), Vector3(-52.6, gy(-52.6, -18) + 0.9, -18.0), Vector3(0.66, 0.02, 0.66), 0.0, false)
	solid(-52.6, -18.0, Vector3(0.7, 0.9, 0.7))
	# Compostadores de tablas llenos de hojas.
	for k in 3:
		var cxp := -44.0 + k * 1.8
		var cy := gy(cxp, -21.5)
		var slat := pcol(Color(0.56, 0.42, 0.28), P_PLANKS_H)
		add("box", slat, Vector3(cxp, cy + 0.5, -22.2), Vector3(1.5, 1.0, 0.08))
		add("box", slat, Vector3(cxp - 0.71, cy + 0.5, -21.5), Vector3(0.08, 1.0, 1.5))
		add("box", slat, Vector3(cxp + 0.71, cy + 0.5, -21.5), Vector3(0.08, 1.0, 1.5))
		add("box", slat, Vector3(cxp, cy + 0.3, -20.8), Vector3(1.5, 0.6, 0.08))
		add("box", Color(0.3, 0.2, 0.12), Vector3(cxp, cy + 0.45, -21.5), Vector3(1.36, 0.9, 1.36), 0.0, false)
		fol("blob_lo", [C_LEAFPILE, Color(0.62, 0.3, 0.12), Color(0.45, 0.28, 0.15)][k], Vector3(cxp, cy + 0.95, -21.5), Basis.from_scale(Vector3(1.35, 0.45, 1.35)), 0.0, 0.0)
		solid(cxp, -21.5, Vector3(1.5, 1.0, 1.5))
	for p in [Vector2(-57, 7), Vector2(-23, -22), Vector2(-58, -5)]:
		tree(p.x, p.y, 0.95, 0)
	bin(-56.0, -10.0, PI * 0.5)
	# Pacas, carretilla, regadera, girasoles y cajón de manzanas.
	hay_bale(-24.5, -12.0, 0.3)
	hay_bale(-31.5, 3.2, 1.3)
	pumpkin(-30.6, 2.3, 0.5)
	pumpkin(-24.0, -10.9, 0.45)
	wheelbarrow(-46.8, -23.2, 1.9)
	var wx := -48.0
	var wz := -9.0
	var wy := gy(wx, wz)
	var can := pcol(Color(0.3, 0.55, 0.42), P_METAL)
	add("cyl", can, Vector3(wx, wy + 0.17, wz), Vector3(0.3, 0.32, 0.3))
	add_basis("cyl8", can, Vector3(wx + 0.25, wy + 0.25, wz), Basis(Vector3.FORWARD, -0.9) * Basis.from_scale(Vector3(0.05, 0.4, 0.05)), false)
	add_basis("ring", can, Vector3(wx - 0.05, wy + 0.36, wz), Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(0.3, 0.3, 0.2)), false)
	for k in 4:
		var fz := -1.0 + k * 1.2
		var fy := gy(-59.2, fz)
		add("cyl6", Color(0.35, 0.5, 0.2), Vector3(-59.2, fy + 0.9, fz), Vector3(0.05, 1.8, 0.05), 0.0, false)
		add_basis("cyl", pcol(Color(0.98, 0.78, 0.15), P_PLAIN), Vector3(-58.95, fy + 1.78, fz), Basis(Vector3.FORWARD, 1.0) * Basis.from_scale(Vector3(0.5, 0.06, 0.5)), false, 0.0)
		add_basis("cyl", Color(0.35, 0.22, 0.1), Vector3(-58.91, fy + 1.79, fz), Basis(Vector3.FORWARD, 1.0) * Basis.from_scale(Vector3(0.26, 0.08, 0.26)), false, 0.0)
		fol("tuft", Color(0.3, 0.5, 0.2), Vector3(-59.2, fy + 0.7, fz), Basis.from_scale(Vector3(0.6, 0.5, 0.6)), 0.6, 0.0, false)
	crate(-33.0, -21.0, 0.7, 0.3, Color(0.8, 0.15, 0.1))
	crate(-32.2, -21.6, 0.7, -0.2)
	crate(-32.6, -21.3, 0.7, 0.1, Color(0.9, 0.7, 0.2), 0.56)
	bush(-58.6, -24.0, 1.2, Color(0.32, 0.47, 0.2))
	flower_patch(-21.8, 8.2, 0.9, 7)


func _crops(bx: float, bz: float, kind: int) -> void:
	var y := gy(bx, bz)
	match kind % 4:
		0:
			# Coles en filas.
			for row in 3:
				for k in 5:
					var px := bx - 1.6 + row * 1.6 + drng.randf_range(-0.1, 0.1)
					var pz := bz - 2.6 + k * 1.3
					fol("blob_lo", Color(0.36, 0.55, 0.3), Vector3(px, y + 0.18, pz), Basis.from_scale(Vector3(0.6, 0.42, 0.6)), 0.1, 0.25)
					fol("blob_lo", Color(0.55, 0.7, 0.45), Vector3(px, y + 0.24, pz), Basis.from_scale(Vector3(0.32, 0.28, 0.32)), 0.1, 0.0, false)
		1:
			# Calabazas entre hojas.
			for k in 6:
				var px := bx + drng.randf_range(-1.7, 1.7)
				var pz := bz + drng.randf_range(-2.7, 2.7)
				pumpkin(px, pz, drng.randf_range(0.4, 0.7))
				fol("blob_lo", Color(0.32, 0.48, 0.2), Vector3(px + 0.4, y + 0.12, pz + 0.2), Basis.from_scale(Vector3(0.7, 0.25, 0.6)), 0.2, 0.0, false)
		2:
			# Tomateras con tutores.
			for row in 2:
				for k in 4:
					var px := bx - 0.9 + row * 1.8
					var pz := bz - 2.4 + k * 1.6
					add("cyl6", pcol(C_WOOD, P_WOOD, true), Vector3(px, y + 0.7, pz), Vector3(0.04, 1.4, 0.04), 0.0, false)
					fol("blob_lo", Color(0.3, 0.48, 0.22), Vector3(px, y + 0.7, pz), Basis.from_scale(Vector3(0.6, 1.0, 0.6)), 0.4, 0.3)
					for q in 3:
						add_basis("sph_lo", Color(0.88, 0.18, 0.1), Vector3(px + drng.randf_range(-0.25, 0.25), y + drng.randf_range(0.4, 1.0), pz + drng.randf_range(-0.25, 0.25)), Basis.from_scale(Vector3.ONE * 0.12), false, 0.0, true)
		_:
			# Lechugas y zanahorias.
			for row in 4:
				for k in 6:
					var px := bx - 1.8 + row * 1.2
					var pz := bz - 2.8 + k * 1.1
					if row % 2 == 0:
						fol("blob_lo", Color(0.5, 0.72, 0.35), Vector3(px, y + 0.1, pz), Basis.from_scale(Vector3(0.38, 0.24, 0.38)), 0.1, 0.0, false)
					else:
						fol("tuft", Color(0.35, 0.6, 0.25), Vector3(px, y + 0.18, pz), Basis.from_scale(Vector3(0.35, 0.4, 0.35)), 0.8, 0.0, false, true)


func _zone_trasero() -> void:
	# Cenador en lo alto de la colina.
	var y := gy(0, -45)
	var paint := pcol(C_PAINT, P_PLAIN)
	add("cyl6", pcol(C_STONE, P_STONE), Vector3(0, y + 0.15, -45), Vector3(6.0, 0.3, 6.0))
	add("cyl6", pcol(Color(0.62, 0.46, 0.32), P_PLANKS_V), Vector3(0, y + 0.31, -45), Vector3(5.7, 0.03, 5.7))
	for k in 6:
		var a := k * TAU / 6.0
		var px := cos(a) * 2.7
		var pz := -45.0 + sin(a) * 2.7
		add("cyl8", paint, Vector3(px, y + 1.5, pz), Vector3(0.18, 2.7, 0.18))
		add("box", paint, Vector3(px, y + 0.42, pz), Vector3(0.26, 0.22, 0.26), a)
		collider(Vector3(px, y + 1.5, pz), Vector3(0.2, 2.7, 0.2))
		terrain.add_solid_circle(Vector2(px, pz), 0.12)
		# Barandilla entre columnas, salvo la entrada al norte.
		var a2 := (k + 1) * TAU / 6.0
		var mid := Vector2((cos(a) + cos(a2)) * 1.35, -45.0 + (sin(a) + sin(a2)) * 1.35)
		var rot := -atan2(sin(a2) - sin(a), cos(a2) - cos(a))
		if k != 1:
			add("box", paint, Vector3(mid.x, y + 1.15, mid.y), Vector3(2.5, 0.07, 0.1), rot)
			for q in 9:
				var t := (q + 0.5) / 9.0
				var bp := Vector2(cos(a), sin(a)).lerp(Vector2(cos(a2), sin(a2)), t) * 2.7
				add_basis("box", paint, Vector3(bp.x, y + 0.75, -45.0 + bp.y), Basis(Vector3.UP, rot) * Basis.from_scale(Vector3(0.05, 0.75, 0.05)), false, 0.0, true)
		# Arco calado bajo el alero.
		add_basis("box", paint, Vector3(mid.x, y + 2.75, mid.y), Basis(Vector3.UP, rot) * Basis.from_scale(Vector3(2.6, 0.14, 0.12)), false)
	var groof := pcol(Color(0.35, 0.46, 0.42), P_ROOF)
	add("cone6", groof, Vector3(0, y + 3.6, -45), Vector3(7.0, 1.8, 7.0))
	add("cyl6", paint, Vector3(0, y + 2.75, -45), Vector3(6.4, 0.1, 6.4))
	add("cyl8", pcol(C_IRON, P_METAL), Vector3(0, y + 4.75, -45), Vector3(0.05, 0.6, 0.05))
	add("sph", pcol(Color(0.85, 0.62, 0.3), P_METAL), Vector3(0, y + 4.6, -45), Vector3(0.18, 0.18, 0.18))
	glow("cyl6", Vector3(0, y + 2.35, -45), Basis.from_scale(Vector3(0.3, 0.36, 0.3)))
	add("cone6", pcol(C_IRON, P_METAL), Vector3(0, y + 2.6, -45), Vector3(0.42, 0.18, 0.42), 0.0, false)
	add("cyl6", C_IRON, Vector3(0, y + 2.68, -45), Vector3(0.02, 0.15, 0.02), 0.0, false)
	bench(0, -46.8, 0.0)
	# Mesa de picnic.
	var tx := 12.0
	var tz := -35.0
	var tgy := gy(tx, tz)
	var wood := pcol(Color(0.62, 0.45, 0.28), P_WOOD)
	add("box", wood, Vector3(tx, tgy + 0.75, tz), Vector3(2.2, 0.08, 0.9))
	add("box", wood, Vector3(tx, tgy + 0.45, tz - 0.75), Vector3(2.2, 0.06, 0.3))
	add("box", wood, Vector3(tx, tgy + 0.45, tz + 0.75), Vector3(2.2, 0.06, 0.3))
	for sx in [-0.85, 0.85]:
		add_basis("box", pcol(C_WOOD_DARK, P_WOOD, true), Vector3(tx + sx, tgy + 0.37, tz), Basis(Vector3.RIGHT, 0.0) * Basis.from_scale(Vector3(0.1, 0.75, 1.8)))
	add("box", pcol(Color(0.9, 0.3, 0.25), P_STRIPES), Vector3(tx, tgy + 0.8, tz), Vector3(1.0, 0.01, 0.7), 0.0, false)
	add("cyl8", pcol(Color(0.8, 0.82, 0.85), P_METAL), Vector3(tx + 0.3, tgy + 0.88, tz + 0.1), Vector3(0.12, 0.16, 0.12), 0.0, false)
	collider(Vector3(tx, tgy + 0.4, tz), Vector3(2.2, 0.8, 1.8))
	for p in [Vector2(-14, -30), Vector2(14, -58), Vector2(-15, -54), Vector2(13, -31), Vector2(-6, -60), Vector2(-12, -42), Vector2(12, -46)]:
		tree(p.x, p.y, 1.25, 0)
	tree(6, -60, 1.0, 1)
	# Trampilla secreta bajo un montón natural de hojas.
	add("box", pcol(C_WOOD_DARK, P_PLANKS_V), Vector3(8, gy(8, -56) + 0.03, -56), Vector3(1.3, 0.06, 1.3), 0.0, false)
	add("box", pcol(C_IRON, P_METAL), Vector3(8.4, gy(8, -56) + 0.08, -56), Vector3(0.1, 0.05, 0.4), 0.0, false)
	add_basis("ring", pcol(C_IRON, P_METAL), Vector3(7.75, gy(8, -56) + 0.08, -56), Basis.from_scale(Vector3(0.3, 0.25, 0.3)), false, 0.0)
	density_points.append([Vector2(8, -56), 1.4, 14.0])
	station(StationObject.Kind.HATCH, Vector3(8, gy(8, -56), -56), Vector3(1.3, 0.4, 1.3))
	bin(-17.0, -37.0, PI * 0.5)
	# Estanque con rocas, juncos y nenúfares.
	var px0 := -8.5
	var pz0 := -52.0
	var py0 := gy(px0, pz0)
	add("cyl", pcol(Color(0.25, 0.4, 0.4), P_WATER), Vector3(px0, py0 + 0.04, pz0), Vector3(4.2, 0.04, 3.6), 0.3, false)
	for k in 11:
		var a := k * TAU / 11.0 + drng.randf_range(-0.12, 0.12)
		var rx := px0 + cos(a) * 2.1 * cos(0.3) - sin(a) * 1.8 * sin(0.3)
		var rz := pz0 + cos(a) * 2.1 * sin(0.3) + sin(a) * 1.8 * cos(0.3)
		rock(rx, rz, drng.randf_range(0.45, 0.8))
	for k in 5:
		var a := 2.2 + k * 0.25
		fol("tuft", Color(0.4, 0.5, 0.22), Vector3(px0 + cos(a) * 1.7, py0 + 0.45, pz0 + sin(a) * 1.4), Basis(Vector3.UP, k) * Basis.from_scale(Vector3(0.5, 1.1, 0.5)), 1.0, 0.0, false)
	for k in 4:
		add_basis("cyl8", Color(0.32, 0.5, 0.25), Vector3(px0 + drng.randf_range(-1.2, 1.2), py0 + 0.07, pz0 + drng.randf_range(-0.9, 0.9)), Basis.from_scale(Vector3(0.45, 0.01, 0.45)), false, 0.0, true)
	add("flower", Color(0.98, 0.85, 0.9), Vector3(px0 + 0.4, py0 + 0.09, pz0 - 0.3), Vector3(0.35, 0.35, 0.35), 0.0, false)
	bench(-8.5, -48.8, PI)
	# Tronco caído con setas.
	add_basis("cyl8", pcol(C_TRUNK, P_BARK), Vector3(-3.0, gy(-3, -33) + 0.3, -33.0), Basis(Vector3.UP, 0.5) * Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.6, 3.2, 0.6)))
	add_basis("cyl8", Color(0.8, 0.66, 0.45), Vector3(-3.0 + cos(0.5) * 1.61, gy(-3, -33) + 0.3, -33.0 - sin(0.5) * 1.61), Basis(Vector3.UP, 0.5) * Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.52, 0.02, 0.52)), false, 0.0)
	mushrooms(-2.6, -32.6)
	mushrooms(-3.6, -33.5)
	solid(-3.0, -33.0, Vector3(3.2, 0.6, 0.6), 0.5)
	# Comedero de pájaros y farolillos del sendero.
	birdhouse(14.6, -33.2, -0.6, Color(0.9, 0.85, 0.7))
	for c in [Vector2(7.1, -40.9), Vector2(-7.1, -40.9), Vector2(9.5, -30.9), Vector2(-9.5, -30.9)]:
		bollard(c.x, c.y)
	bush(-18.6, -60.5, 1.3, Color(0.6, 0.22, 0.1))
	bush(18.5, -60.8, 1.1, Color(0.3, 0.46, 0.2))
	flower_patch(4.5, -50.0, 1.0, 8)


func _zone_piscina() -> void:
	var r := Terrain.POOL
	var deck := 0.15
	var coping := pcol(Color(0.88, 0.86, 0.82), P_TILE)
	add("box", coping, Vector3(r.get_center().x, deck + 0.05, r.position.y - 0.25), Vector3(r.size.x + 1.0, 0.1, 0.5))
	add("box", coping, Vector3(r.get_center().x, deck + 0.05, r.end.y + 0.25), Vector3(r.size.x + 1.0, 0.1, 0.5))
	add("box", coping, Vector3(r.end.x + 0.25, deck + 0.05, r.get_center().y), Vector3(0.5, 0.1, r.size.y))
	# Paredes de azulejo (visuales) siguiendo la forma del vaso.
	var tile := pcol(Color(0.45, 0.7, 0.78), P_TILE)
	for side in [r.position.y + 0.05, r.end.y - 0.05]:
		for k in 9:
			var x := r.position.x + 1.0 + k * 2.0
			var depth := deck - gy(x, r.get_center().y)
			if depth > 0.2:
				add("box", tile, Vector3(x, deck - depth * 0.5, side), Vector3(2.0, depth, 0.06), 0.0, false)
	add("box", tile, Vector3(r.end.x - 0.05, deck - 1.05, r.get_center().y), Vector3(0.06, 2.1, r.size.y), 0.0, false)
	# Charco de agua sucia en el fondo.
	add("cyl", pcol(Color(0.3, 0.42, 0.36), P_WATER), Vector3(47.8, gy(47.8, -4.0) + 0.03, -4.0), Vector3(1.8, 0.02, 2.6), 0.0, false)
	# Escalerilla.
	var chrome := pcol(Color(0.85, 0.87, 0.9), P_METAL)
	for lx in [43.6, 44.4]:
		add("cyl8", chrome, Vector3(lx, deck - 0.6, r.end.y - 0.12), Vector3(0.05, 1.7, 0.05), 0.0, false)
		add_basis("cyl8", chrome, Vector3(lx, deck + 0.42, r.end.y + 0.1), Basis(Vector3.RIGHT, -0.9) * Basis.from_scale(Vector3(0.05, 0.62, 0.05)), false, 0.0)
		add("cyl8", chrome, Vector3(lx, deck + 0.2, r.end.y + 0.4), Vector3(0.05, 0.5, 0.05), 0.0, false)
	for k in 3:
		add("box", chrome, Vector3(44.0, deck - 0.3 - k * 0.35, r.end.y - 0.15), Vector3(0.8, 0.04, 0.12), 0.0, false)
	# Trampolín.
	add("box", pcol(Color(0.3, 0.55, 0.75), P_PLAIN), Vector3(r.end.x - 0.6, deck + 0.55, r.get_center().y), Vector3(2.4, 0.08, 0.6))
	block(pcol(C_STONE_DARK, P_STONE), r.end.x + 0.9, r.get_center().y, Vector3(0.7, 0.6, 0.7))
	# Tumbonas con cojines, mesita y sombrilla.
	for k in 3:
		var x := 36.0 + k * 3.2
		var lf := Transform3D(Basis.IDENTITY, Vector3(x, deck, 4.0))
		ladd("box", pcol(Color(0.95, 0.95, 0.92), P_METAL), lf, Vector3(0, 0.3, 0.25), Vector3(0.72, 0.06, 1.4))
		ladd("box", pcol(Color(0.95, 0.95, 0.92), P_METAL), lf, Vector3(0, 0.55, -0.62), Vector3(0.72, 0.06, 0.75), Basis(Vector3.RIGHT, 0.75))
		ladd("box", pcol([Color(0.2, 0.5, 0.7), Color(0.85, 0.35, 0.3), Color(0.95, 0.75, 0.25)][k], P_STRIPES), lf, Vector3(0, 0.36, 0.25), Vector3(0.66, 0.08, 1.35))
		for c in [Vector2(-0.3, -0.7), Vector2(0.3, -0.7), Vector2(-0.3, 0.85), Vector2(0.3, 0.85)]:
			var cv: Vector2 = c
			ladd("box", pcol(C_WOOD, P_WOOD, true), lf, Vector3(cv.x, 0.13, cv.y), Vector3(0.05, 0.28, 0.05), Basis.IDENTITY, false)
		collider(Vector3(x, deck + 0.3, 4.0), Vector3(0.75, 0.6, 1.9))
	add("cyl8", pcol(Color(0.92, 0.92, 0.9), P_METAL), Vector3(37.6, deck + 0.42, 4.6), Vector3(0.5, 0.04, 0.5))
	add("cyl8", pcol(C_IRON, P_METAL), Vector3(37.6, deck + 0.2, 4.6), Vector3(0.05, 0.42, 0.05), 0.0, false)
	add("cyl8", Color(0.95, 0.6, 0.2), Vector3(37.5, deck + 0.5, 4.55), Vector3(0.08, 0.12, 0.08), 0.0, false)
	add("cyl8", pcol(C_IRON, P_METAL), Vector3(46.0, deck + 1.2, 4.5), Vector3(0.07, 2.4, 0.07))
	add("cone", pcol(Color(0.92, 0.42, 0.35), P_STRIPES), Vector3(46.0, deck + 2.45, 4.5), Vector3(3.2, 0.6, 3.2))
	add("cyl8", pcol(C_IRON, P_METAL), Vector3(46.0, deck + 0.05, 4.5), Vector3(0.5, 0.1, 0.5))
	add("sph", pcol(Color(0.95, 0.85, 0.3), P_STRIPES), Vector3(36.5, gy(36.5, -7) + 0.2, -7.0), Vector3(0.4, 0.4, 0.4))
	# Caseta de la piscina.
	var hx := 54.0
	var hz := -20.0
	var hy := gy(hx, hz)
	var hw := pcol(Color(0.9, 0.92, 0.95), P_PLANKS_H)
	house_box(hw, Vector3(hx, hy + 1.5, hz), Vector3(6.0, 3.0, 5.0))
	add_basis("prism", pcol(Color(0.3, 0.5, 0.65), P_ROOF), Vector3(hx, hy + 3.5, hz), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(5.6, 1.0, 6.6)))
	gable(hw, Vector3(hx, hy + 3.45, hz), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(5.0, 0.9, 6.0)))
	add("box", pcol(Color(0.98, 0.98, 0.96), P_PLAIN), Vector3(hx, hy + 3.02, hz), Vector3(6.2, 0.12, 5.2))
	add("box", pcol(Color(0.3, 0.5, 0.65), P_PLANKS_V), Vector3(hx - 3.03, hy + 1.1, hz + 0.8), Vector3(0.08, 2.1, 1.0))
	add("box", pcol(Color(0.98, 0.98, 0.96), P_PLAIN), Vector3(hx - 3.06, hy + 2.2, hz + 0.8), Vector3(0.1, 0.12, 1.25))
	window(Vector3(hx - 3.0, hy + 1.7, hz - 1.2), 1.2, 0.9, Vector3(-1, 0, 0), Color(0.98, 0.98, 0.96), Color(0.3, 0.5, 0.65))
	window(Vector3(hx, hy + 1.7, hz + 2.5), 1.2, 0.9, Vector3(0, 0, 1), Color(0.98, 0.98, 0.96), Color(0.3, 0.5, 0.65))
	add_basis("ring", pcol(Color(0.9, 0.25, 0.2), P_PLAIN), Vector3(hx - 3.1, hy + 1.6, hz + 2.0), Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.75, 0.75, 0.75)), false)
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		add("box", Color(0.97, 0.97, 0.95), Vector3(hx - 3.16, hy + 1.6 + sin(a) * 0.29, hz + 2.0 + cos(a) * 0.29), Vector3(0.04, 0.11, 0.11), 0.0, false)
	terrain.add_solid_box(Vector2(hx, hz), Vector2(3.0, 2.5))
	for p in [Vector2(23, 7), Vector2(57, 7), Vector2(23, -22)]:
		tree(p.x, p.y, 1.05, 0)
	bin(56.0, -6.0, -PI * 0.5)
	for c in [Vector2(30.2, 0.3), Vector2(50.6, 0.4), Vector2(50.6, -15.3), Vector2(30.2, -15.3)]:
		pot(c.x, c.y, 0.75, 1)
	bush(58.6, -24.0, 1.2, Color(0.64, 0.22, 0.1))
	flower_patch(22.0, -3.0, 0.8, 6)


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
	var stone := pcol(C_STONE, P_STONE)
	add("box", pcol(C_STONE_DARK, P_STONE), Vector3(sx, y + 0.4, sz), Vector3(1.4, 0.8, 1.4))
	add("box", pcol(C_STONE, P_PLAIN), Vector3(sx, y + 0.84, sz), Vector3(1.55, 0.1, 1.55))
	add("cyl8", pcol(C_STONE, P_PLAIN), Vector3(sx, y + 2.2, sz), Vector3(0.18, 2.8, 0.18))
	add("box", stone, Vector3(sx, y + 3.6, sz), Vector3(1.6, 0.2, 0.25))
	for k in 7:
		add("box", pcol(C_STONE, P_PLAIN), Vector3(sx - 0.72 + k * 0.24, y + 3.8, sz), Vector3(0.07, 0.4, 0.07))
	fol("blob_lo", Color(0.3, 0.45, 0.2), Vector3(sx + 0.55, y + 1.0, sz + 0.6), Basis.from_scale(Vector3(0.6, 0.35, 0.3)), 0.2, 0.0, false)
	collider(Vector3(sx, y + 1.5, sz), Vector3(1.4, 3.0, 1.4))
	terrain.add_solid_box(Vector2(sx, sz), Vector2(0.7, 0.7))
	bin(-36.0, -44.5, 0.0)
	for c in [Vector2(-42.9, -37.9), Vector2(-37.1, -37.9), Vector2(-42.9, -44.1)]:
		pot(c.x, c.y, 0.75, 0)


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
	var c := C_HEDGE if rng.randf() < 0.5 else Color(0.24, 0.4, 0.19)
	var b := Basis(Vector3.UP, PI * 0.5 if along_x else 0.0) * Basis.from_scale(Vector3(0.92, 2.4, length))
	fol("hedge", c, Vector3(x, y + 1.0, z), b, 0.12, 0.6)
	collider(Vector3(x, y + 1.1, z), size)
	terrain.add_solid_box(Vector2(x, z), Vector2(size.x, size.z) * 0.5)


func _zone_invernadero() -> void:
	var r := Rect2(33, -51, 14, 10)
	var y := gy(40, -46)
	var brick := pcol(Color(0.66, 0.38, 0.28), P_BRICK)
	var frame := pcol(Color(0.95, 0.95, 0.92), P_METAL)
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
		add("box", brick, Vector3(c.x, y + 0.3, c.z), Vector3(s.x + 0.1, 0.6, s.z + 0.1))
		add("box", pcol(C_STONE, P_PLAIN), Vector3(c.x, y + 0.63, c.z), Vector3(s.x + 0.2, 0.06, s.z + 0.2))
		for hy in [1.8, 3.0]:
			add("box", frame, Vector3(c.x, y + hy, c.z), Vector3(maxf(s.x, 0.2), 0.07, maxf(s.z, 0.2)), 0.0, false)
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
	for k in 6:
		var z := r.position.y + k * 2.0
		for xx in [r.position.x, r.end.x]:
			add("box", frame, Vector3(xx, y + 1.8, z), Vector3(0.18, 3.6, 0.1), 0.0, false)
	for side in [-1.0, 1.0]:
		var roof := MeshInstance3D.new()
		roof.mesh = MeshFactory.box(Vector3(r.size.x, 0.05, 5.9))
		roof.material_override = glass_mat
		roof.position = Vector3(r.get_center().x, y + 4.4, r.get_center().y + side * 2.5)
		roof.rotation.x = side * 0.55
		roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(roof)
		for k in 8:
			var x := r.position.x + k * 2.0
			add_basis("box", frame, Vector3(x, y + 4.42, r.get_center().y + side * 2.5), Basis(Vector3.RIGHT, side * 0.55) * Basis.from_scale(Vector3(0.08, 0.1, 5.9)), false, 0.0)
	add("box", frame, Vector3(r.get_center().x, y + 5.85, r.get_center().y), Vector3(r.size.x, 0.15, 0.2))
	# Mesas de cultivo con macetas.
	for zz in [-49.5, -42.5]:
		var tz: float = zz
		add("box", pcol(C_WOOD, P_PLANKS_V), Vector3(40.0, y + 0.76, tz), Vector3(10.0, 0.08, 1.0))
		for k in 6:
			add("box", pcol(C_WOOD_DARK, P_WOOD, true), Vector3(35.4 + k * 1.84, y + 0.36, tz), Vector3(0.08, 0.72, 0.9), 0.0, false)
		add("box", pcol(C_WOOD, P_PLANKS_V), Vector3(40.0, y + 0.25, tz), Vector3(9.8, 0.05, 0.85), 0.0, false)
		solid(40.0, tz, Vector3(10.0, 0.8, 1.0))
		for k in 6:
			var px := 36.0 + k * 1.6
			pot(px, tz, 0.42, 2 if k % 2 == 0 else 0, 0.8, false)
	# Macizo central con el retoño del Arce de Cobre.
	block(brick, 40.0, -46.0, Vector3(1.4, 0.9, 1.4))
	add("box", C_SOIL, Vector3(40.0, y + 0.92, -46.0), Vector3(1.25, 0.04, 1.25), 0.0, false)
	add("cyl6", pcol(C_TRUNK, P_BARK), Vector3(40.0, y + 1.4, -46.0), Vector3(0.08, 1.0, 0.08))
	for k in 3:
		var a := k * TAU / 3.0
		fol("blob_lo", Color(0.85, 0.45, 0.2), Vector3(40.0 + cos(a) * 0.22, y + 1.9 + k * 0.08, -46.0 + sin(a) * 0.22), Basis.from_scale(Vector3(0.55, 0.45, 0.55)), 0.6, 0.0, false)
	for k in 3:
		var hx := 36.5 + k * 3.5
		add("cyl6", Color(0.55, 0.45, 0.32), Vector3(hx, y + 4.5, -46.0), Vector3(0.02, 1.6, 0.02), 0.0, false)
		add("cyl", pcol(Color(0.5, 0.36, 0.22), P_STRAW), Vector3(hx, y + 3.65, -46.0), Vector3(0.5, 0.22, 0.5), 0.0, false)
		fol("blob_lo", Color(0.3, 0.5, 0.25), Vector3(hx, y + 3.62, -46.0), Basis.from_scale(Vector3(0.65, 0.5, 0.65)), 0.4, 0.0, false)
	# Tónico derramado: bidón volcado y charco.
	block(pcol(Color(0.2, 0.4, 0.85), P_METAL), 26.0, -35.0, Vector3(0.7, 0.9, 0.7), 0.4)
	add("cyl", pcol(Color(0.35, 0.55, 1.0), P_WATER), Vector3(27.0, gy(27, -35) + 0.02, -34.6), Vector3(2.2, 0.02, 1.6), 0.0, false)
	for p in [Vector2(24, -58), Vector2(57, -58), Vector2(57, -39), Vector2(24, -47)]:
		tree(p.x, p.y, 1.1, 0)
	bin(30.0, -30.0, 0.0)
	# Colmenas y macetas apiladas junto a la entrada.
	for hx in [55.4, 57.8]:
		var hzz := -55.4
		var hy := gy(hx, hzz)
		add("box", pcol(C_WOOD_DARK, P_WOOD), Vector3(hx, hy + 0.2, hzz), Vector3(0.6, 0.4, 0.6))
		for k in 3:
			add("box", pcol(Color(0.96, 0.94, 0.86) if k != 1 else Color(0.95, 0.85, 0.5), P_PLANKS_H), Vector3(hx, hy + 0.55 + k * 0.3, hzz), Vector3(0.55, 0.28, 0.55))
		add("box", pcol(Color(0.8, 0.8, 0.78), P_METAL), Vector3(hx, hy + 1.35, hzz), Vector3(0.66, 0.08, 0.66))
		add("box", Color(0.1, 0.08, 0.06), Vector3(hx, hy + 0.45, hzz + 0.28), Vector3(0.3, 0.03, 0.02), 0.0, false)
		solid(hx, hzz, Vector3(0.6, 1.4, 0.6))
	for k in 3:
		add("cyl", pcol(C_TERRACOTTA, P_PLAIN), Vector3(37.4, gy(37.4, -52.3) + 0.12 + k * 0.17, -52.3), Vector3(0.4 - k * 0.04, 0.24, 0.4 - k * 0.04))
	pot(38.2, -52.6, 0.5, 2)
	crate(44.0, -52.7, 0.7, 0.2, Color(0.95, 0.55, 0.15))
	bush(21.5, -60.6, 1.2, Color(0.62, 0.2, 0.1))
	flower_patch(30.5, -27.5, 0.9, 7)


func _zone_secret() -> void:
	var r: Rect2 = GameData.zone_by_id("taller_secreto")["rect"]
	var y := Terrain.SECRET_FLOOR
	var wallc := pcol(Color(0.55, 0.45, 0.38), P_BRICK)
	house_box(wallc, Vector3(r.get_center().x, y + 2.0, r.position.y - 0.3), Vector3(r.size.x + 1.2, 4.4, 0.6))
	house_box(wallc, Vector3(r.get_center().x, y + 2.0, r.end.y + 0.3), Vector3(r.size.x + 1.2, 4.4, 0.6))
	house_box(wallc, Vector3(r.position.x - 0.3, y + 2.0, r.get_center().y), Vector3(0.6, 4.4, r.size.y))
	house_box(wallc, Vector3(r.end.x + 0.3, y + 2.0, r.get_center().y), Vector3(0.6, 4.4, r.size.y))
	house_box(pcol(Color(0.35, 0.3, 0.27), P_PLANKS_V), Vector3(r.get_center().x, y + 4.3, r.get_center().y), Vector3(r.size.x + 1.2, 0.4, r.size.y + 1.2))
	for k in 5:
		add("box", pcol(C_WOOD_DARK, P_WOOD), Vector3(r.position.x + 2.0 + k * 4.5, y + 3.95, r.get_center().y), Vector3(0.3, 0.3, r.size.y))
	for p in [Vector3(76, y + 3.4, -36), Vector3(86, y + 3.4, -32)]:
		var l := OmniLight3D.new()
		l.position = p
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 2.2
		l.omni_range = 14.0
		root.add_child(l)
		add("sph", pcol(Color(1.0, 0.85, 0.55), P_GLOW), p + Vector3(0, 0.3, 0), Vector3(0.4, 0.4, 0.4), 0.0, false)
		add("cone", pcol(Color(0.25, 0.4, 0.3), P_METAL), p + Vector3(0, 0.5, 0), Vector3(0.8, 0.3, 0.8), 0.0, false)
	block(pcol(C_WOOD, P_PLANKS_V), 80.0, -43.0, Vector3(5.0, 1.0, 1.2))
	block(pcol(C_WOOD, P_PLANKS_V), 91.0, -35.0, Vector3(1.2, 1.0, 5.0))
	for k in 5:
		add("box", pcol(Color(0.6, 0.45, 0.3).lerp(Color(0.3, 0.45, 0.6), k * 0.2), P_PLANKS_H), Vector3(78.0 + k * 0.8, y + 1.2, -43.0), Vector3(0.5, 0.4, 0.5))
	# Estantería con frascos y un plano en la pared.
	for k in 3:
		add("box", pcol(C_WOOD, P_WOOD), Vector3(91.6, y + 1.6 + k * 0.6, -35.0), Vector3(0.4, 0.05, 4.6), 0.0, false)
		for q in 7:
			var jc: Color = [Color(0.45, 0.65, 0.5), Color(0.8, 0.55, 0.25), Color(0.5, 0.55, 0.8)][(q + k) % 3]
			add("cyl8", pcol(jc, P_GLASS), Vector3(91.6, y + 1.75 + k * 0.6, -37.0 + q * 0.65), Vector3(0.18, 0.24, 0.18), 0.0, false)
	add("box", pcol(Color(0.2, 0.35, 0.6), P_TILE), Vector3(80.0, y + 2.4, -43.9), Vector3(2.6, 1.6, 0.04), 0.0, false)
	# Rastrillo de cobre colgado.
	add_basis("cyl8", pcol(Color(0.85, 0.5, 0.25), P_METAL), Vector3(84.0, y + 2.2, -43.6), Basis(Vector3.FORWARD, 0.3) * Basis.from_scale(Vector3(0.06, 2.4, 0.06)))
	add("box", pcol(Color(0.85, 0.5, 0.25), P_METAL), Vector3(84.4, y + 3.3, -43.6), Vector3(0.9, 0.12, 0.08))
	for k in 7:
		add("box", pcol(Color(0.85, 0.5, 0.25), P_METAL), Vector3(84.04 + k * 0.12, y + 3.2, -43.6), Vector3(0.025, 0.2, 0.025), 0.0, false)
	# Brizna, el robot dormido.
	var bx := 88.0
	var bz := -29.5
	add("sph", pcol(Color(0.75, 0.78, 0.8), P_METAL), Vector3(bx, y + 0.6, bz), Vector3(1.0, 0.9, 1.0))
	add("sph", pcol(Color(0.82, 0.85, 0.88), P_METAL), Vector3(bx, y + 1.25, bz), Vector3(0.6, 0.5, 0.6))
	add("sph", Color(0.2, 0.25, 0.3), Vector3(bx - 0.12, y + 1.3, bz + 0.27), Vector3(0.1, 0.1, 0.06))
	add("sph", Color(0.2, 0.25, 0.3), Vector3(bx + 0.12, y + 1.3, bz + 0.27), Vector3(0.1, 0.1, 0.06))
	add_basis("cyl", C_WOOD, Vector3(bx + 0.6, y + 0.8, bz), Basis(Vector3.FORWARD, -0.5) * Basis.from_scale(Vector3(0.05, 1.4, 0.05)))
	station(StationObject.Kind.ROBOT, Vector3(bx, y, bz), Vector3(1.2, 1.6, 1.2), {}, true)
	terrain.add_solid_circle(Vector2(bx, bz), 0.5)
	# Escalera de salida.
	for k in 8:
		add("box", pcol(C_WOOD, P_WOOD), Vector3(72.0, y + 0.3 + k * 0.5, -26.5), Vector3(1.0, 0.06, 0.12))
	add("box", pcol(C_WOOD_DARK, P_WOOD, true), Vector3(71.5, y + 2.0, -26.5), Vector3(0.08, 4.0, 0.12))
	add("box", pcol(C_WOOD_DARK, P_WOOD, true), Vector3(72.5, y + 2.0, -26.5), Vector3(0.08, 4.0, 0.12))
	station(StationObject.Kind.LADDER, Vector3(72.0, y, -27.0), Vector3(1.2, 2.5, 0.6))
	bin(90.0, -42.0, 0.0)
	crate(74.0, -42.5, 0.8, 0.2)
	crate(75.0, -42.8, 0.8, -0.3, Color(0.85, 0.55, 0.2))


func _outside() -> void:
	# Carretera, casas vecinas y bosque alrededor de la finca.
	_outside_mode = true
	var oy := Terrain.OUTER_Y
	add("box", pcol(Color(0.32, 0.32, 0.34), P_PLAIN), Vector3(0, oy + 0.02, 73), Vector3(260, 0.05, 7), 0.0, false)
	for side in [-1.0, 1.0]:
		add("box", pcol(Color(0.62, 0.6, 0.56), P_PLAIN), Vector3(0, oy + 0.06, 73 + side * 3.8), Vector3(260, 0.12, 0.6), 0.0, false)
	for k in 16:
		add("box", Color(0.95, 0.9, 0.7), Vector3(-120 + k * 16.0, oy + 0.05, 73), Vector3(5.0, 0.03, 0.2), 0.0, false)
	for hx in [-45.0, -10.0, 30.0, 65.0]:
		var warm := rng.randf() < 0.5
		var hcol := pcol(Color(0.88, 0.8, 0.66) if warm else Color(0.78, 0.62, 0.54), P_PLANKS_H)
		var roof := pcol(Color(0.48, 0.26, 0.2) if warm else Color(0.32, 0.36, 0.42), P_ROOF)
		add("box", hcol, Vector3(hx, oy + 3.0, 92), Vector3(10, 6, 8))
		add_basis("prism", roof, Vector3(hx, oy + 7.5, 92), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(9, 3, 11)))
		gable(hcol, Vector3(hx, oy + 7.45, 92), Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(8, 2.8, 10)))
		add("box", pcol(Color(0.6, 0.35, 0.28), P_BRICK), Vector3(hx + 2.5, oy + 8.5, 93), Vector3(0.9, 3.0, 0.9))
		add("box", pcol(Color(0.35, 0.25, 0.2), P_PLANKS_V), Vector3(hx, oy + 1.1, 87.97), Vector3(1.1, 2.2, 0.08))
		for wx in [-3.2, 3.2]:
			for wy in [1.6, 4.4]:
				window(Vector3(hx + wx, oy + wy, 88.0), 1.1, 1.2, Vector3(0, 0, -1), Color(0.96, 0.94, 0.9), Color(0.3, 0.42, 0.35) if warm else Color(0.5, 0.3, 0.25))
		bush(hx - 5.6, 87.0, 1.4, Color(0.3, 0.45, 0.2), false)
	for sx in [-7.0, 7.0]:
		prefab("lamp", K_PROP, _lamp_parts, Transform3D(Basis.IDENTITY, Vector3(sx, oy, 69.2)), Color.WHITE, 0.3)
		glow("cyl6", Vector3(sx, oy + 3.06, 69.2), Basis.from_scale(Vector3(0.3, 0.36, 0.3)))
	var bounds := Rect2(-62, -64, 124, 130)
	var low := PerformanceManager.level == PerformanceManager.LOW
	var x := -105.0
	while x <= 105.0:
		var z := -105.0
		while z <= 70.0:
			var px := x + rng.randf_range(-3.5, 3.5)
			var pz := z + rng.randf_range(-3.5, 3.5)
			var p := Vector2(px, pz)
			var d := maxf(maxf(bounds.position.x - px, px - bounds.end.x), maxf(bounds.position.y - pz, pz - bounds.end.y))
			var keep := rng.randf() < 0.75 or not low
			if d > 3.0 and d < 34.0 and not Rect2(62, -50, 36, 30).has_point(p) and keep:
				tree(px, pz, rng.randf_range(1.2, 1.9), -1, false)
				if d < 12.0 and dense and rng.randf() < 0.35:
					bush(px + rng.randf_range(-2.5, 2.5), pz + rng.randf_range(-2.5, 2.5), rng.randf_range(1.2, 2.0), Color(0.6, 0.25, 0.1).lerp(Color(0.32, 0.45, 0.2), rng.randf()), false)
			z += 8.5
		x += 8.5
	for k in 9:
		var a := k * TAU / 9.0 + 0.3
		var hc := Color(0.62, 0.42, 0.2).lerp(Color(0.45, 0.48, 0.26), rng.randf())
		fol("blob%d" % (k % 3), hc, Vector3(cos(a) * 190.0, -8.0, sin(a) * 190.0), Basis.from_scale(Vector3(120, 40, 90)), 0.0, 0.0, false)
	_outside_mode = false


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
	var stem_c := []
	var blooms := []
	var bloom_cols := []
	var customs := []
	var stem_d := []
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
			stems.append(Transform3D(Basis.from_scale(Vector3(0.025, h, 0.025)), Vector3(ox, py + h * 0.5, oz)))
			stem_c.append(Color(0.3, 0.55, 0.22))
			stem_d.append(Color(py, 0.0, 0.0, 0.0))
			blooms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25)) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.36, 0.52)), Vector3(ox, py + h, oz)))
			bloom_cols.append(FLOWERS[rng.randi() % FLOWERS.size()])
			customs.append(Color(py, 0.0, rng.randf(), 0.0))
	if not y_secret:
		restore.add_child(_mm_node(MeshFactory.unit("cyl6"), MeshFactory.prop_mat(), stems, stem_c, stem_d))
		restore.add_child(_mm_node(MeshFactory.unit("flower"), MeshFactory.prop_mat(), blooms, bloom_cols, customs))
	# Ramas caídas y trastos: desaparecen al restaurar la zona.
	var branches := []
	var bcols := []
	var bcus := []
	for k in 9:
		var px := rng.randf_range(r.position.x + 2, r.end.x - 2)
		var pz := rng.randf_range(r.position.y + 2, r.end.y - 2)
		if terrain.is_solid(px, pz):
			continue
		var blen := rng.randf_range(1.2, 2.6)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5 + rng.randf_range(-0.1, 0.1)) * Basis.from_scale(Vector3(blen, blen, blen))
		branches.append(Transform3D(b, Vector3(px, gy(px, pz) + 0.06, pz)))
		bcols.append(Color(1, 1, 1))
		bcus.append(Color(gy(px, pz), 0.3, rng.randf(), 0.0))
	debris.add_child(_mm_node(MeshFactory.prefab("twig", _twig_parts), MeshFactory.prop_mat(), branches, bcols, bcus))


## Rama caída con dos horquillas (longitud 1, a lo largo de Y).
func _twig_parts() -> Array:
	var c := pcol(Color(0.36, 0.24, 0.15), P_BARK)
	var p := []
	p.append(_branch_part(Vector3(0, -0.5, 0), Vector3(0, 0.5, 0), 0.04, c))
	p.append(_branch_part(Vector3(0, -0.1, 0), Vector3(0.22, 0.25, 0.04), 0.025, c))
	p.append(_branch_part(Vector3(0, 0.2, 0), Vector3(-0.18, 0.48, -0.03), 0.02, c))
	p.append(_branch_part(Vector3(0.22, 0.25, 0.04), Vector3(0.3, 0.42, 0.0), 0.014, c))
	return p
