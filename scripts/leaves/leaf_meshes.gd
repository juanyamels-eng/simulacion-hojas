class_name LeafMeshes
## Geometría y textura de las hojas (originales, generadas por código).
##
## Una sola malla contiene CINCO siluetas con la misma topología; el shader elige una por instancia
## (INSTANCE_CUSTOM.w), así que un único MultiMesh por bloque dibuja todas las especies en una llamada:
##   0 · arce (palmeada, 5 lóbulos puntiagudos y dientes)   → VERTEX.xz
##   1 · roble (lóbulos redondeados y senos hondos)           → UV
##   2 · abedul/álamo (ovalada con punta)                     → UV2
##   3 · sauce (lanceolada, larga y estrecha)                 → CUSTOM0.xy
##   4 · ginkgo (abanico con escotadura central)              → CUSTOM0.zw
##
## Topología (31 vértices, 32 triángulos): contorno de 22 vértices (base, 10 por lado, punta) cosido a
## 5 vértices del nervio central (cada tramo del contorno se une a su vértice de nervio en abanico y
## los cambios de vértice de nervio caen en los senos, así los lóbulos no se solapan) + pecíolo de 4.
## Al repartir el nervio en 5 puntos el shader puede plegar la hoja por el nervio (forma de V).
## Coordenadas en "unidades de hoja" (x = ancho, y = largo hacia la punta); el shader las escala.
##
## COLOR.rgb = tinte (blanco en el limbo, pardo en el pecíolo); COLOR.a = cercanía al borde (0 nervio, 1 borde).
##
## Versiones lejanas: leaf_mesh_lod() (7 vértices, 6 triángulos, misma silueta simplificada por especie)
## y leaf_mesh_far() (4 vértices, 2 triángulos) con la misma disposición de atributos.

const SHAPES := 5
const SIDE := 10
const RIBS := 5
const VEIN_TILE := 128
const ATLAS_COLS := 3
const ATLAS_ROWS := 2

# Lado derecho, de la base a la punta (sin incluir ninguna de las dos). Índices 1…10.
const OUTLINES := [
	# 0 · arce: lóbulo basal, lóbulo lateral grande con dientes, seno hondo y lóbulo central dentado.
	[Vector2(0.12, -0.27), Vector2(0.30, -0.26), Vector2(0.25, -0.12), Vector2(0.48, -0.02), Vector2(0.53, 0.16),
		Vector2(0.36, 0.17), Vector2(0.30, 0.25), Vector2(0.14, 0.18), Vector2(0.24, 0.42), Vector2(0.10, 0.44)],
	# 1 · roble: aurícula basal y cuatro lóbulos redondeados con senos hondos.
	[Vector2(0.07, -0.33), Vector2(0.17, -0.22), Vector2(0.09, -0.12), Vector2(0.27, -0.06), Vector2(0.26, 0.06),
		Vector2(0.11, 0.10), Vector2(0.27, 0.24), Vector2(0.11, 0.30), Vector2(0.19, 0.42), Vector2(0.06, 0.48)],
	# 2 · abedul/álamo: ovalada, base algo acorazonada y punta acuminada.
	[Vector2(0.10, -0.34), Vector2(0.24, -0.30), Vector2(0.34, -0.18), Vector2(0.40, -0.04), Vector2(0.38, 0.10),
		Vector2(0.33, 0.22), Vector2(0.25, 0.33), Vector2(0.17, 0.42), Vector2(0.10, 0.50), Vector2(0.05, 0.56)],
	# 3 · sauce: lanceolada, larga y estrecha.
	[Vector2(0.04, -0.42), Vector2(0.08, -0.34), Vector2(0.11, -0.22), Vector2(0.125, -0.10), Vector2(0.13, 0.02),
		Vector2(0.125, 0.14), Vector2(0.11, 0.26), Vector2(0.09, 0.37), Vector2(0.06, 0.47), Vector2(0.03, 0.56)],
	# 4 · ginkgo: cuña en la base que se abre en abanico; la "punta" es la escotadura central.
	[Vector2(0.05, -0.28), Vector2(0.12, -0.18), Vector2(0.22, -0.06), Vector2(0.33, 0.06), Vector2(0.42, 0.16),
		Vector2(0.46, 0.26), Vector2(0.40, 0.33), Vector2(0.29, 0.37), Vector2(0.17, 0.37), Vector2(0.07, 0.34)],
]
const BASES := [Vector2(0, -0.17), Vector2(0, -0.40), Vector2(0, -0.30), Vector2(0, -0.46), Vector2(0, -0.34)]
const TIPS := [Vector2(0, 0.62), Vector2(0, 0.56), Vector2(0, 0.64), Vector2(0, 0.66), Vector2(0, 0.22)]
# Cinco vértices del nervio por forma (en el arce los tres primeros coinciden: abanico desde la palma).
const MIDRIB := [
	[Vector2(0, -0.05), Vector2(0, -0.05), Vector2(0, -0.05), Vector2(0, 0.2), Vector2(0, 0.4)],
	[Vector2(0, -0.26), Vector2(0, -0.08), Vector2(0, 0.12), Vector2(0, 0.32), Vector2(0, 0.46)],
	[Vector2(0, -0.2), Vector2(0, -0.05), Vector2(0, 0.12), Vector2(0, 0.3), Vector2(0, 0.46)],
	[Vector2(0, -0.36), Vector2(0, -0.16), Vector2(0, 0.08), Vector2(0, 0.32), Vector2(0, 0.52)],
	[Vector2(0, -0.26), Vector2(0, -0.15), Vector2(0, 0.0), Vector2(0, 0.1), Vector2(0, 0.16)],
]
# Vértice de nervio de cada punto de un lado (0 = base … SIDE + 1 = punta): el primer punto de cada
# tramo es un seno, de modo que cada abanico es "estrellado" desde su vértice de nervio.
const RIB_OF := [0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 4]
const PETIOLE_LEN := [0.2, 0.15, 0.16, 0.12, 0.2]
# Puntos del contorno (índices del lado derecho) que conserva la versión lejana y su centro.
const LOD_PICK := [[2, 5], [4, 7], [4, 7], [5, 8], [6, 8]]
const LOD_CENTER := [Vector2(0, -0.05), Vector2(0, 0.0), Vector2(0, 0.05), Vector2(0, 0.0), Vector2(0, -0.08)]
const FAR_HALF_WIDTH := [0.42, 0.25, 0.36, 0.12, 0.4]
# Semiancho de cada forma (el shader normaliza el enrollado de los bordes con él).
const WIDTH := [0.5, 0.27, 0.4, 0.13, 0.46]

static var _cache := {}


## Posiciones de los vértices de una forma, en el orden común a todas.
static func _shape_points(s: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var o: Array = OUTLINES[s]
	pts.append(BASES[s])
	for k in SIDE:
		pts.append(o[k])
	pts.append(TIPS[s])
	for k in range(SIDE - 1, -1, -1):
		var q: Vector2 = o[k]
		pts.append(Vector2(-q.x, q.y))
	for m in RIBS:
		pts.append(MIDRIB[s][m])
	var b: Vector2 = BASES[s]
	var plen := float(PETIOLE_LEN[s])
	pts.append(b + Vector2(-0.022, 0.035))
	pts.append(b + Vector2(0.022, 0.035))
	pts.append(b + Vector2(0.014, -plen))
	pts.append(b + Vector2(-0.008, -plen))
	return pts


## Índices de triángulos de la malla cercana (comunes a todas las formas).
static func triangle_indices() -> PackedInt32Array:
	var shapes: Array[PackedVector2Array] = []
	for s in SHAPES:
		shapes.append(_shape_points(s))
	return _indices(shapes)


static func _indices(shapes: Array[PackedVector2Array]) -> PackedInt32Array:
	var outline_n := 2 * SIDE + 2
	var mid0 := outline_n
	var vcount := shapes[0].size()
	var idx := PackedInt32Array()
	var right: Array[int] = []
	for j in SIDE + 2:
		right.append(j)
	var left: Array[int] = []
	for j in SIDE + 2:
		left.append(0 if j == 0 else (outline_n - j if j <= SIDE else SIDE + 1))
	for side in [right, left]:
		for j in SIDE + 1:
			var a: int = side[j]
			var b: int = side[j + 1]
			var ma := mid0 + int(RIB_OF[j])
			var mb := mid0 + int(RIB_OF[j + 1])
			_tri(idx, shapes, ma, a, b)
			if ma != mb:
				_tri(idx, shapes, ma, b, mb)
	# Pecíolo (dos triángulos).
	_tri(idx, shapes, vcount - 4, vcount - 3, vcount - 2)
	_tri(idx, shapes, vcount - 4, vcount - 2, vcount - 1)
	return idx


## Puntos 2D de una forma (para pruebas y para otras mallas).
static func shape_points(s: int) -> PackedVector2Array:
	return _shape_points(s)


static func leaf_mesh() -> ArrayMesh:
	if _cache.has("leaf"):
		return _cache["leaf"]
	var shapes: Array[PackedVector2Array] = []
	for s in SHAPES:
		shapes.append(_shape_points(s))
	var idx := _indices(shapes)
	var vcount := shapes[0].size()
	var mid0 := 2 * SIDE + 2
	var cols := PackedColorArray()
	for v in vcount:
		if v >= vcount - 4:
			cols.append(Color(0.6, 0.45, 0.32, 0.35))
		elif v >= mid0:
			cols.append(Color(1, 1, 1, 0.0))
		else:
			cols.append(Color(1, 1, 1, 1.0))
	var mesh := _make(shapes, cols, idx)
	_cache["leaf"] = mesh
	return mesh


## Versión lejana: 7 vértices (base, 2 por lado, punta y centro) y 6 triángulos en abanico.
static func leaf_mesh_lod() -> ArrayMesh:
	if _cache.has("leaf_lod"):
		return _cache["leaf_lod"]
	var shapes: Array[PackedVector2Array] = []
	for s in SHAPES:
		var o: Array = OUTLINES[s]
		var pick: Array = LOD_PICK[s]
		var lo: Vector2 = o[int(pick[0]) - 1]
		var hi: Vector2 = o[int(pick[1]) - 1]
		shapes.append(PackedVector2Array([LOD_CENTER[s], BASES[s], lo, hi, TIPS[s], Vector2(-hi.x, hi.y), Vector2(-lo.x, lo.y)]))
	var idx := PackedInt32Array()
	for k in 6:
		_tri(idx, shapes, 0, 1 + k, 1 + (k + 1) % 6)
	var cols := PackedColorArray([Color(1, 1, 1, 0.0)])
	for k in 6:
		cols.append(Color(1, 1, 1, 0.8))
	var mesh := _make(shapes, cols, idx)
	_cache["leaf_lod"] = mesh
	return mesh


## Versión muy lejana: rombo de 4 vértices con las proporciones de cada especie.
static func leaf_mesh_far() -> ArrayMesh:
	if _cache.has("leaf_far"):
		return _cache["leaf_far"]
	var shapes: Array[PackedVector2Array] = []
	for s in SHAPES:
		var w := float(FAR_HALF_WIDTH[s])
		var b: Vector2 = BASES[s]
		var t: Vector2 = TIPS[s]
		if s == 4:
			t = Vector2(0, 0.37)
		var mid := lerpf(b.y, t.y, 0.45)
		shapes.append(PackedVector2Array([b, Vector2(w, mid), t, Vector2(-w, mid)]))
	var idx := PackedInt32Array()
	_tri(idx, shapes, 0, 1, 2)
	_tri(idx, shapes, 0, 2, 3)
	var cols := PackedColorArray([Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.6)])
	var mesh := _make(shapes, cols, idx)
	_cache["leaf_far"] = mesh
	return mesh


## Añade un triángulo con el orden de vértices que Godot considera cara frontal vista desde arriba.
## Se decide con la forma ovalada (2), que no tiene triángulos degenerados.
static func _tri(idx: PackedInt32Array, shapes: Array[PackedVector2Array], a: int, b: int, c: int) -> void:
	var ref := shapes[2]
	var pa := Vector3(ref[a].x, 0.0, -ref[a].y)
	var pb := Vector3(ref[b].x, 0.0, -ref[b].y)
	var pc := Vector3(ref[c].x, 0.0, -ref[c].y)
	if (pb - pa).cross(pc - pa).y > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


## Área con signo de un triángulo de una forma (positiva = misma orientación que la forma de referencia).
## Sirve a las pruebas para comprobar que ninguna silueta tiene triángulos dados la vuelta.
static func signed_area(pts: PackedVector2Array, a: int, b: int, c: int) -> float:
	return ((pts[b] - pts[a]).cross(pts[c] - pts[a])) * 0.5


static func _make(shapes: Array[PackedVector2Array], cols: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uv1 := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cust := PackedFloat32Array()
	var norms := PackedVector3Array()
	for v in shapes[0].size():
		var p0 := shapes[0][v]
		verts.append(Vector3(p0.x, 0.0, p0.y))
		uv1.append(shapes[1][v])
		uv2.append(shapes[2][v])
		var p3 := shapes[3][v]
		var p4 := shapes[4][v]
		cust.append_array([p3.x, p3.y, p4.x, p4.y])
		norms.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uv1
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_CUSTOM0] = cust
	arrays[Mesh.ARRAY_INDEX] = idx
	var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	return mesh


# ------------------------------------------------------------------ mallas para partículas

## Hoja de arce para partículas (hojas que caen, estallidos): plegada por el nervio y con los bordes
## algo levantados; colores de vértice casi blancos (el color lo pone la partícula), borde más oscuro.
## Mide como la antigua (~0,22 m de largo a escala 1).
static func particle_leaf(scale: float = 0.24) -> ArrayMesh:
	var key := "particle_%d" % int(scale * 1000.0)
	if _cache.has(key):
		return _cache[key]
	var pts := _shape_points(0)
	var shapes: Array[PackedVector2Array] = []
	for s in SHAPES:
		shapes.append(_shape_points(s))
	var idx := _indices(shapes)
	var mid0 := 2 * SIDE + 2
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for v in pts.size():
		var p := pts[v]
		var edge := v < mid0
		var hgt := 0.16 * absf(p.x) + 0.22 * p.x * p.x + 0.12 * maxf(p.y, 0.0) * maxf(p.y, 0.0)
		verts.append(Vector3(p.x, hgt, -p.y) * scale)
		norms.append(Vector3(-(0.16 * signf(p.x) + 0.44 * p.x), 1.0, 0.24 * maxf(p.y, 0.0)).normalized())
		if v >= pts.size() - 4:
			cols.append(Color(0.62, 0.48, 0.36))
		elif edge:
			cols.append(Color(0.86, 0.8, 0.76))
		else:
			cols.append(Color(1.08, 1.04, 0.92))
	var mesh := _plain(verts, norms, cols, idx)
	_cache[key] = mesh
	return mesh


## Hoja pequeña y sencilla (7 vértices, ovalada y plegada) para estallidos y remolinos baratos.
static func particle_leaf_small(scale: float = 0.24) -> ArrayMesh:
	var key := "particle_small_%d" % int(scale * 1000.0)
	if _cache.has(key):
		return _cache[key]
	var pts := PackedVector2Array([Vector2(0, -0.02), Vector2(0, -0.36), Vector2(0.24, -0.16), Vector2(0.22, 0.18),
		Vector2(0, 0.56), Vector2(-0.22, 0.18), Vector2(-0.24, -0.16)])
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for v in pts.size():
		var p := pts[v]
		verts.append(Vector3(p.x, 0.25 * absf(p.x) + 0.06 * absf(p.y), -p.y) * scale)
		norms.append(Vector3(-0.25 * signf(p.x), 1.0, 0.06 * signf(p.y)).normalized())
		cols.append(Color(1.05, 1.0, 0.92) if v == 0 else Color(0.88, 0.84, 0.8))
	var idx := PackedInt32Array()
	for k in 6:
		idx.append_array([0, 1 + k, 1 + (k + 1) % 6])
	var mesh := _plain(verts, norms, cols, idx)
	_cache[key] = mesh
	return mesh


static func _plain(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ------------------------------------------------------------------ textura de nervaduras

## Atlas 3×2 (una casilla por silueta; la sexta queda libre). R = nervaduras, G = moteado suave.
## Con mipmaps: a distancia los nervios se funden en vez de parpadear.
static func vein_texture() -> Texture2D:
	if _cache.has("veins"):
		return _cache["veins"]
	var w := VEIN_TILE * ATLAS_COLS
	var h := VEIN_TILE * ATLAS_ROWS
	var veins := PackedFloat32Array()
	veins.resize(w * h)
	veins.fill(0.0)
	for s in SHAPES:
		var ox := (s % ATLAS_COLS) * VEIN_TILE
		var oy := (s / ATLAS_COLS) * VEIN_TILE
		for seg in _vein_segments(s):
			_stamp_segment(veins, w, ox, oy, seg[0], seg[1], float(seg[2]), float(seg[3]))
	var noise := FastNoiseLite.new()
	noise.seed = 913
	noise.frequency = 0.045
	noise.fractal_octaves = 2
	var nimg := noise.get_seamless_image(w, h)
	nimg.convert(Image.FORMAT_L8)
	var nb := nimg.get_data()
	var bytes := PackedByteArray()
	bytes.resize(w * h * 2)
	for i in w * h:
		bytes[i * 2] = int(clampf(veins[i], 0.0, 1.0) * 255.0)
		bytes[i * 2 + 1] = nb[i]
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RG8, bytes)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["veins"] = tex
	return tex


## Segmentos de nervio: [desde, hasta, grosor en px, intensidad] en unidades de hoja.
static func _vein_segments(s: int) -> Array:
	var segs := []
	var b: Vector2 = BASES[s]
	var t: Vector2 = TIPS[s]
	var o: Array = OUTLINES[s]
	match s:
		0:
			# Arce: cinco nervios principales que salen de la palma y secundarios hacia cada diente.
			var c: Vector2 = MIDRIB[0][0]
			segs.append([b, c, 2.6, 1.0])
			segs.append([c, t * 0.94, 2.4, 1.0])
			for side in [1.0, -1.0]:
				var basal := Vector2(0.30 * side, -0.26)
				var lateral := Vector2(0.53 * side, 0.16)
				segs.append([c, lateral * 0.95, 2.2, 0.95])
				segs.append([c, basal * 0.93, 1.8, 0.85])
				segs.append([c.lerp(lateral, 0.5), Vector2(0.48 * side, -0.02) * 0.94, 1.2, 0.55])
				segs.append([c.lerp(lateral, 0.55), Vector2(0.36 * side, 0.17) * 0.94, 1.1, 0.5])
				segs.append([c.lerp(lateral, 0.35), Vector2(0.30 * side, 0.25) * 0.92, 1.0, 0.45])
				segs.append([c.lerp(t, 0.5), Vector2(0.24 * side, 0.42) * 0.94, 1.2, 0.55])
				segs.append([c.lerp(t, 0.72), Vector2(0.10 * side, 0.44), 1.0, 0.4])
				segs.append([c.lerp(basal, 0.5), Vector2(0.12 * side, -0.26), 1.0, 0.4])
		1:
			# Roble: nervio central y uno secundario hacia cada lóbulo.
			segs.append([b, t * 0.95, 2.6, 1.0])
			for side in [1.0, -1.0]:
				for lv in [[-0.32, 1], [-0.24, 2], [-0.05, 4], [0.12, 7], [0.3, 9]]:
					var tip: Vector2 = o[int(lv[1]) - 1]
					segs.append([Vector2(0, float(lv[0])), Vector2(tip.x * side, tip.y) * 0.93, 1.5, 0.75])
		2:
			# Abedul: nervios secundarios rectos y paralelos que llegan al borde.
			segs.append([b, t * 0.96, 2.4, 1.0])
			for side in [1.0, -1.0]:
				for k in 7:
					var y0 := -0.24 + k * 0.1
					var reach := 0.36 * (1.0 - absf(y0 - 0.0) * 0.9)
					segs.append([Vector2(0, y0), Vector2(reach * side, y0 + 0.14), 1.3, 0.62])
		3:
			# Sauce: nervio central marcado y secundarios finos y tendidos.
			segs.append([b, t * 0.96, 2.4, 1.0])
			for side in [1.0, -1.0]:
				for k in 8:
					var y0 := -0.36 + k * 0.11
					segs.append([Vector2(0, y0), Vector2(0.11 * side * (1.0 - absf(y0) * 0.7), y0 + 0.13), 1.0, 0.5])
		4:
			# Ginkgo: nervios en abanico desde la base, sin nervio central.
			var root := Vector2(0, -0.3)
			segs.append([b, root, 2.2, 0.9])
			for k in 13:
				var a := lerpf(-1.18, 1.18, float(k) / 12.0)
				var dir := Vector2(sin(a), cos(a))
				var lenf := 0.62 if absf(a) > 0.12 else 0.5
				segs.append([root + dir * 0.04, root + dir * lenf, 1.0, 0.5])
	return segs


static func _stamp_segment(buf: PackedFloat32Array, width: int, ox: int, oy: int, a: Vector2, b: Vector2, thick: float, inten: float) -> void:
	# Unidades de hoja [-0.6, 0.6] → píxeles de la casilla (y hacia abajo en la imagen = punta arriba).
	var k := VEIN_TILE / 1.2
	var pa := Vector2(ox + (a.x + 0.6) * k, oy + (0.6 - a.y) * k)
	var pb := Vector2(ox + (b.x + 0.6) * k, oy + (0.6 - b.y) * k)
	var r := thick + 1.0
	var x0 := clampi(int(floorf(minf(pa.x, pb.x) - r)), ox, ox + VEIN_TILE - 1)
	var x1 := clampi(int(ceilf(maxf(pa.x, pb.x) + r)), ox, ox + VEIN_TILE - 1)
	var y0 := clampi(int(floorf(minf(pa.y, pb.y) - r)), oy, oy + VEIN_TILE - 1)
	var y1 := clampi(int(ceilf(maxf(pa.y, pb.y) + r)), oy, oy + VEIN_TILE - 1)
	var ab := pb - pa
	var len2 := maxf(ab.length_squared(), 0.0001)
	for y in range(y0, y1 + 1):
		var row := y * width
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var tt := clampf((p - pa).dot(ab) / len2, 0.0, 1.0)
			# Los nervios se afinan hacia el extremo.
			var w := thick * (1.0 - 0.55 * tt)
			var d := p.distance_to(pa + ab * tt)
			if d < w + 1.0:
				var v := inten * clampf(w + 0.5 - d, 0.0, 1.0)
				if v > buf[row + x]:
					buf[row + x] = v
