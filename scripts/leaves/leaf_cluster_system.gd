class_name LeafClusterSystem
extends RefCounted
## Montones de hojas: convierte la densidad de hojas por celda en una textura RG8.
## R = cobertura (hojarasca sobre el césped), G = altura del montón.
## Se suaviza con un núcleo binomial 5×5 separable (dos pasadas): los montones salen como cúpulas
## redondeadas en vez de mesetas. El shader del suelo eleva el terreno con G y el de las hojas las
## coloca encima: los montones crecen en tamaño, altura y densidad sin generar mallas nuevas.

const PILE_MAX := 1.25
const MARGIN := 2   # radio del núcleo; las celdas del borde de la rejilla quedan a cero
const LUT_SIZE := 32768

var gw := 0
var gh := 0
var bytes := PackedByteArray()
var img: Image
var tex: ImageTexture
var _rows := PackedInt32Array()   # pasada horizontal del núcleo (1 4 6 4 1)
static var _lut := PackedByteArray()   # suma ponderada → altura del montón (0-255), sin exp() por celda


func setup(w: int, h: int) -> void:
	gw = w
	gh = h
	bytes.resize(gw * gh * 2)
	bytes.fill(0)
	_rows.resize(gw * gh)
	_rows.fill(0)
	if _lut.size() != LUT_SIZE:
		_lut.resize(LUT_SIZE)
		for k in LUT_SIZE:
			_lut[k] = int((1.0 - exp(-float(k) / 7000.0)) * 255.0)
	img = Image.create_from_data(gw, gh, false, Image.FORMAT_RG8, bytes)
	tex = ImageTexture.create_from_image(img)


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
			a0 = a1
			a1 = a2
			a2 = a3
			a3 = a4
			c += 1
	# Pasada vertical, también deslizante (por columnas).
	var rr := _rows
	var lut := _lut
	for ix in range(x0, x1 + 1):
		var c := z0 * gw + ix
		var b0 := rr[c - gw - gw]
		var b1 := rr[c - gw]
		var b2 := rr[c]
		var b3 := rr[c + gw]
		for iz in range(z0, z1 + 1):
			var b4 := rr[c + gw + gw]
			var s := b0 + b4 + (b1 + b3) * 4 + b2 * 6
			if s == 0:
				bytes[c * 2] = 0
				bytes[c * 2 + 1] = 0
			else:
				bytes[c * 2] = mini((s * 9 >> 3) + cc[c] * 20, 255)
				bytes[c * 2 + 1] = lut[mini(s, LUT_SIZE - 1)]
			b0 = b1
			b1 = b2
			b2 = b3
			b3 = b4
			c += gw
	img.set_data(gw, gh, false, Image.FORMAT_RG8, bytes)
	tex.update(img)


## Altura del montón en un punto (para hundirse al pisar y para saltos).
func height_at(sim: LeafSimulationSystem, x: float, z: float) -> float:
	var c := sim.cell_index(x, z)
	if c < 0:
		return 0.0
	return float(bytes[c * 2 + 1]) / 255.0 * PILE_MAX
