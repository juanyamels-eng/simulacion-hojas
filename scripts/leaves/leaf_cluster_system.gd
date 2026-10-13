class_name LeafClusterSystem
extends RefCounted
## Montones de hojas: convierte la densidad de hojas por celda en una textura RG8.
## R = cobertura (hojarasca sobre el césped), G = altura del montón (suavizada).
## El shader del suelo eleva el terreno con G y el de las hojas las coloca encima:
## los montones crecen en tamaño, altura y densidad sin generar mallas nuevas.

const PILE_MAX := 1.25

var gw := 0
var gh := 0
var bytes := PackedByteArray()
var img: Image
var tex: ImageTexture


func setup(w: int, h: int) -> void:
	gw = w
	gh = h
	bytes.resize(gw * gh * 2)
	bytes.fill(0)
	img = Image.create_from_data(gw, gh, false, Image.FORMAT_RG8, bytes)
	tex = ImageTexture.create_from_image(img)


func flush(sim: LeafSimulationSystem, full: bool = false) -> void:
	if not sim.dirty and not full:
		return
	var x0 := 1
	var x1 := gw - 2
	var z0 := 1
	var z1 := gh - 2
	if not full:
		x0 = maxi(sim.d_x0 - 2, 1)
		x1 = mini(sim.d_x1 + 2, gw - 2)
		z0 = maxi(sim.d_z0 - 2, 1)
		z1 = mini(sim.d_z1 + 2, gh - 2)
	sim.dirty = false
	var cc := sim.cell_count
	for iz in range(z0, z1 + 1):
		var row := iz * gw
		for ix in range(x0, x1 + 1):
			var c := row + ix
			var cnt := cc[c]
			var s := cnt * 4 + (cc[c - 1] + cc[c + 1] + cc[c - gw] + cc[c + gw]) * 2 + cc[c - gw - 1] + cc[c - gw + 1] + cc[c + gw - 1] + cc[c + gw + 1]
			if s == 0:
				bytes[c * 2] = 0
				bytes[c * 2 + 1] = 0
				continue
			bytes[c * 2] = mini(s * 18 + cnt * 20, 255)
			bytes[c * 2 + 1] = int((1.0 - exp(-float(s) / 480.0)) * 255.0)
	img.set_data(gw, gh, false, Image.FORMAT_RG8, bytes)
	tex.update(img)


## Altura del montón en un punto (para hundirse al pisar y para saltos).
func height_at(sim: LeafSimulationSystem, x: float, z: float) -> float:
	var c := sim.cell_index(x, z)
	if c < 0:
		return 0.0
	return float(bytes[c * 2 + 1]) / 255.0 * PILE_MAX
