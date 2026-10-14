class_name LeafClusterSystem
extends RefCounted
## Montones de hojas: convierte la densidad de hojas por celda en una textura RG8.
## R = cobertura (la usan el suelo y el césped para esconder la hierba bajo las hojas),
## G = altura del montón (la usan las hojas, el jugador, Bellota y las herramientas).
##
## Los montones están hechos SOLO de hojas: el shader de las hojas reparte cada hoja por el volumen
## (altura = G · profundidad propia de la hoja) y la inclina según la superficie. Para que eso se vea
## como un montón lleno y no como hojas flotando, la altura sigue a las CAPAS de hojas que caben en
## cada celda: hasta ~1,6 capas las hojas yacen planas en el suelo (altura 0) y a partir de ahí cada
## capa añade unos centímetros, con un tope suave en PILE_MAX.
##
## Dos suavizados separables: uno ancho 5×5 (1 4 6 4 1) que da la cúpula redondeada y otro local 3×3
## (1 2 1). La altura usa el menor de los dos: las hojas sueltas junto a un montón no se levantan por
## el "halo" del suavizado ancho (no flotan) y dentro del montón manda la forma redondeada.

const PILE_MAX := 1.25
const MARGIN := 2   # radio del núcleo; las celdas del borde de la rejilla quedan a cero
const LUT_SIZE := 65536
# Modelo de capas: área media de una hoja / área de celda (0,04 m² / 0,25 m²), capas que yacen planas
# y grosor que añade cada capa más (las hojas secas y enroscadas abultan).
const LAYERS_PER_LEAF := 0.16
const FLAT_LAYERS := 1.6
const LAYER_HEIGHT := 0.13

var gw := 0
var gh := 0
var bytes := PackedByteArray()
var img: Image
var tex: ImageTexture
var _rows := PackedInt32Array()    # pasada horizontal del núcleo ancho (1 4 6 4 1)
var _rows3 := PackedInt32Array()   # pasada horizontal del núcleo local (1 2 1)
static var _lut := PackedByteArray()   # suma ponderada (×256 por hoja) → altura del montón (0-255)


## Altura (m) de un montón con una densidad media de `leaves_per_cell` hojas por celda de 0,5 m.
static func height_for_density(leaves_per_cell: float) -> float:
	var layers := leaves_per_cell * LAYERS_PER_LEAF
	var lin := maxf(layers - FLAT_LAYERS, 0.0) * LAYER_HEIGHT
	var x := lin / PILE_MAX
	# tanh: crece lineal al principio y se aplana al acercarse a PILE_MAX.
	var e := exp(-2.0 * x)
	return PILE_MAX * (1.0 - e) / (1.0 + e)


func setup(w: int, h: int) -> void:
	gw = w
	gh = h
	bytes.resize(gw * gh * 2)
	bytes.fill(0)
	_rows.resize(gw * gh)
	_rows.fill(0)
	_rows3.resize(gw * gh)
	_rows3.fill(0)
	if _lut.size() != LUT_SIZE:
		_build_lut()
	img = Image.create_from_data(gw, gh, false, Image.FORMAT_RG8, bytes)
	tex = ImageTexture.create_from_image(img)


## Tabla suma → altura: se invierte la curva una vez por cada uno de los 255 niveles (umbral de suma
## a partir del cual se alcanza) y se rellenan los tramos, en vez de evaluar exp() 65.536 veces.
static func _build_lut() -> void:
	_lut.resize(LUT_SIZE)
	var k := 0
	for g in 256:
		var lim := LUT_SIZE
		if g < 255:
			# Altura a mitad de camino entre el nivel g y el g + 1 → densidad (inversa de height_for_density).
			var hm := (float(g) + 0.5) / 255.0
			var x := 0.5 * log((1.0 + hm) / (1.0 - hm))
			var layers := x * PILE_MAX / LAYER_HEIGHT + FLAT_LAYERS
			lim = mini(int(ceil(layers / LAYERS_PER_LEAF * 256.0)), LUT_SIZE)
		while k < lim:
			_lut[k] = g
			k += 1


func flush(sim: LeafSimulationSystem, full: bool = false) -> void:
	if not sim.dirty and not full:
		return
	var x0 := MARGIN
	var x1 := gw - 1 - MARGIN
	var z0 := MARGIN
	var z1 := gh - 1 - MARGIN
	if not full:
		x0 = maxi(sim.d_x0 - MARGIN, MARGIN)
		x1 = mini(sim.d_x1 + MARGIN, gw - 1 - MARGIN)
		z0 = maxi(sim.d_z0 - MARGIN, MARGIN)
		z1 = mini(sim.d_z1 + MARGIN, gh - 1 - MARGIN)
	sim.dirty = false
	var cc := sim.cell_count
	# Pasada horizontal con ventana deslizante (incluye 2 filas extra arriba y abajo).
	for iz in range(z0 - MARGIN, z1 + MARGIN + 1):
		var c := iz * gw + x0
		var a0 := cc[c - 2]
		var a1 := cc[c - 1]
		var a2 := cc[c]
		var a3 := cc[c + 1]
		for ix in range(x0, x1 + 1):
			var a4 := cc[c + 2]
			_rows[c] = a0 + a4 + (a1 + a3) * 4 + a2 * 6
			_rows3[c] = a1 + a3 + a2 * 2
			a0 = a1
			a1 = a2
			a2 = a3
			a3 = a4
			c += 1
	# Pasada vertical, también deslizante (por columnas).
	# (alias solo de lectura: aquí no se escribe en ellos)
	var rr := _rows
	var r3 := _rows3
	var lut := _lut
	var lmax := LUT_SIZE - 1
	for ix in range(x0, x1 + 1):
		var c := z0 * gw + ix
		var b0 := rr[c - gw - gw]
		var b1 := rr[c - gw]
		var b2 := rr[c]
		var b3 := rr[c + gw]
		var q1 := r3[c - gw]
		var q2 := r3[c]
		for iz in range(z0, z1 + 1):
			var b4 := rr[c + gw + gw]
			var q3 := r3[c + gw]
			var s := b0 + b4 + (b1 + b3) * 4 + b2 * 6
			if s == 0:
				bytes[c * 2] = 0
				bytes[c * 2 + 1] = 0
			else:
				var s3 := (q1 + q3 + q2 * 2) * 16
				bytes[c * 2] = mini((s * 9 >> 3) + cc[c] * 20, 255)
				bytes[c * 2 + 1] = lut[mini(mini(s, s3), lmax)]
			b0 = b1
			b1 = b2
			b2 = b3
			b3 = b4
			q1 = q2
			q2 = q3
			c += gw
	img.set_data(gw, gh, false, Image.FORMAT_RG8, bytes)
	tex.update(img)


## Altura del montón en un punto (para hundirse al pisar y para saltos).
func height_at(sim: LeafSimulationSystem, x: float, z: float) -> float:
	var c := sim.cell_index(x, z)
	if c < 0:
		return 0.0
	return float(bytes[c * 2 + 1]) / 255.0 * PILE_MAX
