class_name LeafMeshes
## Geometría y textura de las hojas del suelo (originales, generadas por código).
##
## Una sola malla contiene CUATRO siluetas (arce palmeado, roble lobulado, hoja lanceolada y hoja
## acorazonada) con la misma topología: VERTEX guarda la forma 0, UV la 1, UV2 la 2 y CUSTOM0.xy la 3.
## El shader elige la silueta por instancia (INSTANCE_CUSTOM.w), de modo que un único MultiMesh por
## bloque sigue dibujando todas las hojas en una llamada.
##
## Topología: contorno de 20 vértices (base, 8 por lado, punta) "cosido" a 3 vértices del nervio central.
## En el arce los 3 vértices centrales coinciden (abanico desde el pecíolo); en las demás se reparten por
## el nervio, lo que permite lóbulos laterales sin triángulos solapados. Coordenadas en "unidades de hoja"
## (x = ancho, y = largo hacia la punta); el shader las escala, curva y orienta.
##
## COLOR.rgb = tinte (blanco en el limbo, marrón en el pecíolo); COLOR.a = cercanía al borde (0 nervio, 1 borde).

const SHAPES := 4
const SIDE := 8
const VEIN_TILE := 128

# Lado derecho, de la base a la punta (sin incluir ninguna de las dos).
const OUTLINES := [
	# 0 · arce: 5 lóbulos puntiagudos, senos profundos.
	[Vector2(0.06, -0.27), Vector2(0.30, -0.24), Vector2(0.17, -0.02), Vector2(0.44, 0.22),
		Vector2(0.24, 0.20), Vector2(0.10, 0.12), Vector2(0.17, 0.34), Vector2(0.07, 0.40)],
	# 1 · roble: lóbulos redondeados a lo largo del nervio.
	[Vector2(0.07, -0.36), Vector2(0.05, -0.27), Vector2(0.20, -0.18), Vector2(0.11, -0.06),
		Vector2(0.27, 0.04), Vector2(0.12, 0.12), Vector2(0.24, 0.25), Vector2(0.10, 0.33)],
	# 2 · lanceolada (haya, sauce): óvalo alargado.
	[Vector2(0.08, -0.36), Vector2(0.14, -0.26), Vector2(0.17, -0.13), Vector2(0.18, 0.0),
		Vector2(0.17, 0.13), Vector2(0.14, 0.25), Vector2(0.10, 0.36), Vector2(0.05, 0.46)],
	# 3 · acorazonada (tilo, abedul): base con escotadura y punta acuminada.
	[Vector2(0.12, -0.34), Vector2(0.26, -0.26), Vector2(0.34, -0.10), Vector2(0.35, 0.06),
		Vector2(0.30, 0.20), Vector2(0.21, 0.31), Vector2(0.11, 0.40), Vector2(0.04, 0.48)],
]
const BASES := [Vector2(0, -0.22), Vector2(0, -0.42), Vector2(0, -0.40), Vector2(0, -0.26)]
const TIPS := [Vector2(0, 0.56), Vector2(0, 0.52), Vector2(0, 0.56), Vector2(0, 0.56)]
const MIDRIB := [
	[Vector2(0, -0.08), Vector2(0, -0.08), Vector2(0, -0.08)],
	[Vector2(0, -0.25), Vector2(0, 0.0), Vector2(0, 0.28)],
	[Vector2(0, -0.25), Vector2(0, 0.02), Vector2(0, 0.28)],
	[Vector2(0, -0.18), Vector2(0, 0.02), Vector2(0, 0.22)],
]
const PETIOLE_LEN := [0.2, 0.16, 0.14, 0.2]
const LOD_PICK := [[1, 3], [2, 4], [1, 4], [2, 4]]   # puntos del contorno que conserva la versión lejana

static var _cache := {}


## Nervio central asignado a cada punto de un lado (0 = base … SIDE + 1 = punta).
static func _rib_of(j: int) -> int:
	if j <= 3:
		return 0
	if j <= 6:
		return 1
	return 2


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
	for m in 3:
		pts.append(MIDRIB[s][m])
	var b: Vector2 = BASES[s]
	pts.append(b + Vector2(-0.018, 0.03))
	pts.append(b + Vector2(0.018, 0.03))
	pts.append(b + Vector2(0.01, -float(PETIOLE_LEN[s])))
	return pts


static func leaf_mesh() -> ArrayMesh:
	if _cache.has("leaf"):
		return _cache["leaf"]
	var outline_n := 2 * SIDE + 2
	var mid0 := outline_n
	var shapes: Array[PackedVector2Array] = []
	for s in SHAPES:
		shapes.append(_shape_points(s))
	var vcount := shapes[0].size()
	var idx := PackedInt32Array()
	# Lado derecho: índices 0 (base) … SIDE + 1 (punta). Lado izquierdo: punta … base.
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
			var ma := mid0 + _rib_of(j)
			var mb := mid0 + _rib_of(j + 1)
			_tri(idx, shapes, ma, a, b)
			if ma != mb:
				_tri(idx, shapes, ma, b, mb)
	# Pecíolo.
	_tri(idx, shapes, vcount - 3, vcount - 2, vcount - 1)
	var verts := PackedVector3Array()
	var uv1 := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cust := PackedFloat32Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for v in vcount:
		var p0 := shapes[0][v]
		verts.append(Vector3(p0.x, 0.0, p0.y))
		uv1.append(shapes[1][v])
		uv2.append(shapes[2][v])
		var p3 := shapes[3][v]
		cust.append_array([p3.x, p3.y, 0.0, 0.0])
		norms.append(Vector3.UP)
		if v >= vcount - 3:
			cols.append(Color(0.62, 0.48, 0.34, 0.0))
		elif v >= mid0:
			cols.append(Color(1, 1, 1, 0.0))
		else:
			cols.append(Color(1, 1, 1, 1.0))
	var mesh := _make(verts, norms, cols, uv1, uv2, cust, idx)
	_cache["leaf"] = mesh
	return mesh


## Versión lejana: 6 vértices y 4 triángulos con la misma disposición de atributos.
static func leaf_mesh_lod() -> ArrayMesh:
	if _cache.has("leaf_lod"):
		return _cache["leaf_lod"]
	var shapes: Array[PackedVector2Array] = []
	for s in SHAPES:
		var o: Array = OUTLINES[s]
		var pick: Array = LOD_PICK[s]
		var lo: Vector2 = o[pick[0]]
		var hi: Vector2 = o[pick[1]]
		var pts := PackedVector2Array([BASES[s], lo, hi, TIPS[s], Vector2(-hi.x, hi.y), Vector2(-lo.x, lo.y)])
		shapes.append(pts)
	var idx := PackedInt32Array()
	for k in 4:
		_tri(idx, shapes, 0, k + 1, k + 2)
	var verts := PackedVector3Array()
	var uv1 := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cust := PackedFloat32Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for v in 6:
		var p0 := shapes[0][v]
		verts.append(Vector3(p0.x, 0.0, p0.y))
		uv1.append(shapes[1][v])
		uv2.append(shapes[2][v])
		cust.append_array([shapes[3][v].x, shapes[3][v].y, 0.0, 0.0])
		norms.append(Vector3.UP)
		cols.append(Color(1, 1, 1, 0.45))
	var mesh := _make(verts, norms, cols, uv1, uv2, cust, idx)
	_cache["leaf_lod"] = mesh
	return mesh


## Añade un triángulo con el orden de vértices que Godot considera cara frontal vista desde arriba.
## Se decide con la forma lanceolada (la única sin triángulos degenerados).
static func _tri(idx: PackedInt32Array, shapes: Array[PackedVector2Array], a: int, b: int, c: int) -> void:
	var ref := shapes[2]
	var pa := Vector3(ref[a].x, 0.0, -ref[a].y)
	var pb := Vector3(ref[b].x, 0.0, -ref[b].y)
	var pc := Vector3(ref[c].x, 0.0, -ref[c].y)
	if (pb - pa).cross(pc - pa).y > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


static func _make(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, uv1: PackedVector2Array,
		uv2: PackedVector2Array, cust: PackedFloat32Array, idx: PackedInt32Array) -> ArrayMesh:
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


# ------------------------------------------------------------------ textura de nervaduras

## Atlas 2×2 (una casilla por silueta). R = nervaduras, G = moteado suave. Con mipmaps: a distancia
## los nervios se funden en vez de parpadear.
static func vein_texture() -> Texture2D:
	if _cache.has("veins"):
		return _cache["veins"]
	var size := VEIN_TILE * 2
	var veins := PackedFloat32Array()
	veins.resize(size * size)
	veins.fill(0.0)
	for s in SHAPES:
		var ox := (s % 2) * VEIN_TILE
		var oy := (s / 2) * VEIN_TILE
		for seg in _vein_segments(s):
			_stamp_segment(veins, size, ox, oy, seg[0], seg[1], float(seg[2]), float(seg[3]))
	var noise := FastNoiseLite.new()
	noise.seed = 913
	noise.frequency = 0.045
	noise.fractal_octaves = 2
	var nimg := noise.get_seamless_image(size, size)
	nimg.convert(Image.FORMAT_L8)
	var nb := nimg.get_data()
	var bytes := PackedByteArray()
	bytes.resize(size * size * 2)
	for i in size * size:
		bytes[i * 2] = int(clampf(veins[i], 0.0, 1.0) * 255.0)
		bytes[i * 2 + 1] = nb[i]
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RG8, bytes)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["veins"] = tex
	return tex


## Segmentos de nervio: [desde, hasta, grosor en px, intensidad] en unidades de hoja.
static func _vein_segments(s: int) -> Array:
	var segs := []
	var b: Vector2 = BASES[s]
	var t: Vector2 = TIPS[s]
	match s:
		0:
			var c := Vector2(0, -0.08)
			segs.append([b, c, 2.6, 1.0])
			segs.append([c, t * 0.93, 2.4, 1.0])
			for side in [1.0, -1.0]:
				var lobe := Vector2(0.44 * side, 0.22)
				var low := Vector2(0.30 * side, -0.24)
				segs.append([c, lobe * 0.94, 2.2, 0.95])
				segs.append([c, low * 0.92, 1.8, 0.85])
				segs.append([c.lerp(lobe, 0.45), Vector2(0.24 * side, 0.2) * 0.95, 1.2, 0.55])
				segs.append([c.lerp(lobe, 0.4), Vector2(0.17 * side, -0.02), 1.1, 0.45])
				segs.append([c.lerp(t, 0.45), Vector2(0.17 * side, 0.34) * 0.95, 1.2, 0.55])
				segs.append([c.lerp(t, 0.7), Vector2(0.07 * side, 0.4), 1.0, 0.45])
				segs.append([c.lerp(low, 0.5), Vector2(0.06 * side, -0.26), 1.0, 0.4])
		1:
			segs.append([b, t * 0.95, 2.6, 1.0])
			for side in [1.0, -1.0]:
				for lv in [[-0.3, Vector2(0.07, -0.35)], [-0.24, Vector2(0.19, -0.18)], [-0.07, Vector2(0.26, 0.04)], [0.13, Vector2(0.23, 0.25)], [0.3, Vector2(0.08, 0.42)]]:
					var tip: Vector2 = lv[1]
					segs.append([Vector2(0, float(lv[0])), Vector2(tip.x * side, tip.y) * 0.95, 1.5, 0.75])
		2:
			segs.append([b, t * 0.96, 2.4, 1.0])
			for side in [1.0, -1.0]:
				for k in 7:
					var y0 := -0.3 + k * 0.105
					segs.append([Vector2(0, y0), Vector2(0.15 * side * (1.0 - absf(y0) * 0.9), y0 + 0.12), 1.2, 0.6])
		3:
			segs.append([b, t * 0.95, 2.5, 1.0])
			for side in [1.0, -1.0]:
				segs.append([Vector2(0, -0.22), Vector2(0.27 * side, -0.2), 1.7, 0.8])
				segs.append([Vector2(0, -0.2), Vector2(0.3 * side, -0.02), 1.6, 0.8])
				for k in 4:
					var y0 := -0.08 + k * 0.12
					segs.append([Vector2(0, y0), Vector2((0.28 - k * 0.05) * side, y0 + 0.15), 1.2, 0.55])
	return segs


static func _stamp_segment(buf: PackedFloat32Array, size: int, ox: int, oy: int, a: Vector2, b: Vector2, thick: float, inten: float) -> void:
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
		var row := y * size
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
