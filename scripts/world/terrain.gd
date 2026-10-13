class_name Terrain
extends Node3D
## Terreno: función de altura analítica muestreada en una rejilla de 0,5 m, malla del suelo por bloques,
## colisión, máscara de obstáculos para las hojas y textura de tipos de suelo (caminos, tierra, zona).

const CHUNK := 10.0
const POOL := Rect2(31, -14, 18, 13)          # piscina vacía (x, z, ancho, fondo)
const SECRET := Rect2(68, -46, 26, 22)        # taller subterráneo
const SECRET_FLOOR := -20.0
const OUTER_Y := -1.0                         # campo exterior, por debajo de cualquier punto de la finca

var gw := 0
var gh := 0
var hw := 0
var origin := GameData.GRID_ORIGIN
var inv_cell := 1.0 / GameData.CELL
var heights := PackedFloat32Array()
var solid := PackedByteArray()
var cell_zone := PackedByteArray()
var ground_bytes := PackedByteArray()   # RGBA8: camino, tierra, grava, id de zona
var ground_tex: ImageTexture
var ao_tex: ImageTexture        # oclusión suave junto a muros, troncos y vallas (1 m por píxel)
var height_tex: ImageTexture    # alturas en media precisión (para el césped instanciado)
var noise_tex: Texture2D
var pile_tex: Texture2D
var material: ShaderMaterial
var extra_materials: Array[ShaderMaterial] = []   # otros shaders que siguen el % limpio de cada zona
var _zone_clean := PackedFloat32Array()
var _pads: Array = []          # [Rect2, altura]
var _hills: Array = []         # [Vector2 centro, radio, altura]


func setup() -> void:
	gw = int(GameData.GRID_SIZE_M.x * inv_cell)
	gh = int(GameData.GRID_SIZE_M.y * inv_cell)
	hw = gw + 1
	_hills = [
		[Vector2(0, -46), 9.5, 2.6],
		[Vector2(-41, 23), 6.0, 1.3],
		[Vector2(-9, 24), 4.0, 0.5],
		[Vector2(48, -54), 5.0, 0.8],
	]
	_pads = [
		[Rect2(-13.5, -25.5, 27, 14), 0.25],   # casa
		[Rect2(34, 15, 16, 12), 0.08],         # garaje
		[Rect2(31.5, -52.5, 17, 13), 0.1],     # invernadero
		[Rect2(-15, 47, 6, 5), 0.05],          # taller
		[Rect2(28, -17, 24, 18), 0.15],        # solarium de la piscina
		[Rect2(-4, -49, 8, 8), 2.6],           # cenador en la colina
	]
	heights.resize(hw * (gh + 1))
	for j in gh + 1:
		for i in hw:
			heights[j * hw + i] = _height_fn(origin.x + i * GameData.CELL, origin.y + j * GameData.CELL)
	solid.resize(gw * gh)
	solid.fill(0)
	cell_zone.resize(gw * gh)
	cell_zone.fill(0)
	ground_bytes.resize(gw * gh * 4)
	ground_bytes.fill(0)
	for zi in GameData.ZONES.size():
		var r: Rect2 = GameData.ZONES[zi]["rect"]
		var x0 := clampi(int(round((r.position.x - origin.x) * inv_cell)), 0, gw)
		var x1 := clampi(int(round((r.end.x - origin.x) * inv_cell)), 0, gw)
		var z0 := clampi(int(round((r.position.y - origin.y) * inv_cell)), 0, gh)
		var z1 := clampi(int(round((r.end.y - origin.y) * inv_cell)), 0, gh)
		for j in range(z0, z1):
			for i in range(x0, x1):
				cell_zone[j * gw + i] = zi + 1
				ground_bytes[(j * gw + i) * 4 + 3] = (zi + 1) * 20


func _height_fn(x: float, z: float) -> float:
	if SECRET.has_point(Vector2(x, z)):
		return SECRET_FLOOR
	var h := 0.22 * sin(x * 0.071 + 1.3) * cos(z * 0.058) + 0.12 * sin((x + z) * 0.113)
	var p := Vector2(x, z)
	for hl in _hills:
		var d2 := p.distance_squared_to(hl[0])
		var r: float = hl[1]
		if d2 < r * r * 9.0:
			h += float(hl[2]) * exp(-d2 / (r * r * 0.5))
	for pad in _pads:
		var rect: Rect2 = pad[0]
		if not rect.grow(2.0).has_point(p):
			continue
		var inside := _rect_falloff(rect, x, z, 2.0)
		if inside > 0.0:
			h = lerpf(h, float(pad[1]), inside)
	# Piscina vacía: rampa en el lado oeste y paredes en el resto.
	if POOL.has_point(p):
		var depth := lerpf(0.0, 1.0, clampf((x - POOL.position.x) / 4.0, 0.0, 1.0))
		depth += lerpf(0.0, 1.1, clampf((x - POOL.position.x - 4.0) / (POOL.size.x - 4.0), 0.0, 1.0))
		var edge := minf(minf(z - POOL.position.y, POOL.end.y - z), POOL.end.x - x)
		h -= depth * smoothstep(0.0, 0.3, edge)
	return h


func _rect_falloff(r: Rect2, x: float, z: float, fall: float) -> float:
	var dx := maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
	var d := sqrt(dx * dx + dz * dz)
	return 1.0 - smoothstep(0.0, fall, d)


## Altura del suelo (interpolación bilineal de la rejilla).
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) * inv_cell, 0.0, gw - 0.001)
	var fz := clampf((z - origin.y) * inv_cell, 0.0, gh - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var b := iz * hw + ix
	return lerpf(lerpf(heights[b], heights[b + 1], tx), lerpf(heights[b + hw], heights[b + hw + 1], tx), tz)


func cell_of(x: float, z: float) -> int:
	var ix := int(floor((x - origin.x) * inv_cell))
	var iz := int(floor((z - origin.y) * inv_cell))
	if ix < 0 or iz < 0 or ix >= gw or iz >= gh:
		return -1
	return iz * gw + ix


func _fill_cells(r: Rect2, fn: Callable) -> void:
	var x0 := clampi(int(floor((r.position.x - origin.x) * inv_cell)), 0, gw - 1)
	var x1 := clampi(int(ceil((r.end.x - origin.x) * inv_cell)) - 1, 0, gw - 1)
	var z0 := clampi(int(floor((r.position.y - origin.y) * inv_cell)), 0, gh - 1)
	var z1 := clampi(int(ceil((r.end.y - origin.y) * inv_cell)) - 1, 0, gh - 1)
	for j in range(z0, z1 + 1):
		for i in range(x0, x1 + 1):
			fn.call(j * gw + i)


## Marca como sólido (para las hojas) un rectángulo orientado.
func add_solid_box(center: Vector2, half: Vector2, angle: float = 0.0, value: int = 1) -> void:
	var ext := half.length() if angle != 0.0 else maxf(half.x, half.y)
	var r := Rect2(center - Vector2(ext, ext), Vector2(ext, ext) * 2.0)
	if angle == 0.0:
		r = Rect2(center - half, half * 2.0)
	var ca := cos(angle)
	var sa := sin(angle)
	var x0 := clampi(int(floor((r.position.x - origin.x) * inv_cell)), 0, gw - 1)
	var x1 := clampi(int(ceil((r.end.x - origin.x) * inv_cell)), 0, gw - 1)
	var z0 := clampi(int(floor((r.position.y - origin.y) * inv_cell)), 0, gh - 1)
	var z1 := clampi(int(ceil((r.end.y - origin.y) * inv_cell)), 0, gh - 1)
	for j in range(z0, z1 + 1):
		for i in range(x0, x1 + 1):
			var p := Vector2(origin.x + (i + 0.5) * GameData.CELL, origin.y + (j + 0.5) * GameData.CELL) - center
			var lx := p.x * ca - p.y * sa
			var lz := p.x * sa + p.y * ca
			if absf(lx) <= half.x and absf(lz) <= half.y:
				solid[j * gw + i] = value


func add_solid_circle(center: Vector2, radius: float, value: int = 1) -> void:
	var r2 := radius * radius
	_fill_cells(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), func(c):
		var p := Vector2(origin.x + (c % gw + 0.5) * GameData.CELL, origin.y + (c / gw + 0.5) * GameData.CELL)
		if p.distance_squared_to(center) <= r2:
			solid[c] = value)


func is_solid(x: float, z: float) -> bool:
	var c := cell_of(x, z)
	return c < 0 or solid[c] != 0


## Pinta la textura de suelo. channel: 0 camino, 1 tierra/huerto, 2 arena/grava.
func paint_rect(r: Rect2, channel: int, value: float = 1.0) -> void:
	_fill_cells(r, func(c): _paint(c, channel, value))


func paint_circle(center: Vector2, radius: float, channel: int, value: float = 1.0) -> void:
	_fill_cells(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), func(c):
		var p := Vector2(origin.x + (c % gw + 0.5) * GameData.CELL, origin.y + (c / gw + 0.5) * GameData.CELL)
		if p.distance_to(center) <= radius:
			_paint(c, channel, value))


func paint_line(a: Vector2, b: Vector2, width: float, channel: int, value: float = 1.0) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b).grow(width)
	var hw2 := width * 0.5
	_fill_cells(r, func(c):
		var p := Vector2(origin.x + (c % gw + 0.5) * GameData.CELL, origin.y + (c / gw + 0.5) * GameData.CELL)
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= hw2:
			_paint(c, channel, value))


func _paint(c: int, channel: int, value: float) -> void:
	var k := c * 4 + channel
	ground_bytes[k] = maxi(ground_bytes[k], int(clampf(value, 0.0, 1.0) * 255.0))


## Construye las mallas del suelo y su colisión (después de pintar).
func build(pile_texture: Texture2D, noise_texture: Texture2D) -> void:
	pile_tex = pile_texture
	noise_tex = noise_texture
	ground_tex = ImageTexture.create_from_image(Image.create_from_data(gw, gh, false, Image.FORMAT_RGBA8, ground_bytes))
	ao_tex = _build_ao_tex()
	height_tex = _build_height_tex()
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/ground.gdshader")
	material.set_shader_parameter("pile_tex", pile_tex)
	material.set_shader_parameter("ground_tex", ground_tex)
	material.set_shader_parameter("noise_tex", noise_tex)
	material.set_shader_parameter("ao_tex", ao_tex)
	material.set_shader_parameter("grid_rect", Vector4(origin.x, origin.y, 1.0 / GameData.GRID_SIZE_M.x, 1.0 / GameData.GRID_SIZE_M.y))
	material.set_shader_parameter("grid_size", Vector2(gw, gh))
	var playable: Array[Rect2] = []
	for z in GameData.ZONES:
		playable.append((z["rect"] as Rect2).grow(2.5))
	var ccx := int(GameData.GRID_SIZE_M.x / CHUNK)
	var ccz := int(GameData.GRID_SIZE_M.y / CHUNK)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	add_child(body)
	for cz in ccz:
		for cx in ccx:
			var r := Rect2(origin.x + cx * CHUNK, origin.y + cz * CHUNK, CHUNK, CHUNK)
			var used := false
			for pr in playable:
				if pr.intersects(r):
					used = true
					break
			if used:
				_build_chunk(cx, cz, body)
	# Campo exterior: plano grande y barato, con manchas de pradera para que no se vea liso.
	var outer := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(520, 520)
	outer.mesh = pm
	outer.position = Vector3(0, OUTER_Y, 0)
	var sh := Shader.new()
	sh.code = OUTER_SHADER
	var om := ShaderMaterial.new()
	om.shader = sh
	om.set_shader_parameter("noise_tex", noise_tex)
	outer.material_override = om
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outer)
	PerformanceManager.quality_changed.connect(_apply_quality)
	_apply_quality(PerformanceManager.level)


const OUTER_SHADER := """
shader_type spatial;
render_mode specular_disabled, diffuse_lambert_wrap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
varying vec2 wxz;
void vertex() {
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
	float n1 = texture(noise_tex, wxz * 0.011).r;
	float n2 = texture(noise_tex, wxz * 0.06).r;
	vec3 c = mix(vec3(0.3, 0.42, 0.16), vec3(0.47, 0.5, 0.22), smoothstep(0.3, 0.75, n1));
	c *= 0.86 + 0.28 * n2;
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
"""


## Detalle procedural del suelo (losas, hojarasca dibujada, flores) según la calidad gráfica.
func _apply_quality(level: int) -> void:
	if material == null:
		return
	var dist := 26.0
	if level == PerformanceManager.LOW:
		dist = 0.0
	elif level == PerformanceManager.MEDIUM:
		dist = 20.0
	material.set_shader_parameter("detail_dist", dist)


## Oclusión ambiental barata: máscara de celdas sólidas (sin las puertas, que se abren) suavizada.
func _build_ao_tex() -> ImageTexture:
	var n := gw * gh
	var mask := PackedByteArray()
	mask.resize(n)
	mask.fill(0)
	for c in n:
		if solid[c] != 0:
			mask[c] = 255
	for g in GameData.GATES:
		var gp: Vector2 = g["pos"]
		var half := Vector2(2.0, 0.6) if g["axis"] == "x" else Vector2(0.6, 2.0)
		var x0 := clampi(int(floor((gp.x - half.x - origin.x) * inv_cell)), 0, gw - 1)
		var x1 := clampi(int(ceil((gp.x + half.x - origin.x) * inv_cell)), 0, gw - 1)
		var z0 := clampi(int(floor((gp.y - half.y - origin.y) * inv_cell)), 0, gh - 1)
		var z1 := clampi(int(ceil((gp.y + half.y - origin.y) * inv_cell)), 0, gh - 1)
		for j in range(z0, z1 + 1):
			for i in range(x0, x1 + 1):
				mask[j * gw + i] = 0
	var img := Image.create_from_data(gw, gh, false, Image.FORMAT_L8, mask)
	img.shrink_x2()
	var wide := img.duplicate() as Image
	wide.shrink_x2()
	wide.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_BILINEAR)
	var a := img.get_data()
	var b := wide.get_data()
	for i in a.size():
		a[i] = mini(int(a[i] * 1.15 + b[i] * 0.7), 255)
	return ImageTexture.create_from_image(Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_L8, a))


## Alturas del terreno como textura de media precisión (filtrable en GLES3).
func _build_height_tex() -> ImageTexture:
	var img := Image.create_from_data(hw, gh + 1, false, Image.FORMAT_RF, heights.to_byte_array())
	img.convert(Image.FORMAT_RH)
	return ImageTexture.create_from_image(img)


## Parámetros comunes para otros shaders que se apoyan en el suelo (césped).
func bind_ground_params(m: ShaderMaterial) -> void:
	m.set_shader_parameter("pile_tex", pile_tex)
	m.set_shader_parameter("ground_tex", ground_tex)
	m.set_shader_parameter("noise_tex", noise_tex)
	m.set_shader_parameter("ao_tex", ao_tex)
	m.set_shader_parameter("height_tex", height_tex)
	m.set_shader_parameter("grid_rect", Vector4(origin.x, origin.y, 1.0 / GameData.GRID_SIZE_M.x, 1.0 / GameData.GRID_SIZE_M.y))
	m.set_shader_parameter("grid_size", Vector2(gw, gh))
	m.set_shader_parameter("height_map", Vector4(origin.x, origin.y, inv_cell, 0.0))
	m.set_shader_parameter("height_size", Vector2(hw, gh + 1))
	if not extra_materials.has(m):
		extra_materials.append(m)
	if _zone_clean.size() > 0:
		m.set_shader_parameter("zone_clean", _zone_clean)


func _build_chunk(cx: int, cz: int, body: StaticBody3D) -> void:
	var steps := int(CHUNK * inv_cell)
	var i0 := cx * steps
	var j0 := cz * steps
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	var n := steps + 1
	verts.resize(n * n)
	normals.resize(n * n)
	for j in n:
		for i in n:
			var gi := mini(i0 + i, gw)
			var gj := mini(j0 + j, gh)
			var x := origin.x + gi * GameData.CELL
			var z := origin.y + gj * GameData.CELL
			var hc := heights[gj * hw + gi]
			var hl := heights[gj * hw + maxi(gi - 1, 0)]
			var hr := heights[gj * hw + mini(gi + 1, gw)]
			var hd := heights[maxi(gj - 1, 0) * hw + gi]
			var hu := heights[mini(gj + 1, gh) * hw + gi]
			verts[j * n + i] = Vector3(x, hc, z)
			normals[j * n + i] = Vector3(hl - hr, 2.0 * GameData.CELL, hd - hu).normalized()
	for j in steps:
		for i in steps:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
			faces.append_array([verts[a], verts[b], verts[c], verts[b], verts[d], verts[c]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Margen de AABB para el desplazamiento de los montones en el shader.
	mesh.custom_aabb = AABB(Vector3(origin.x + cx * CHUNK, -25, origin.y + cz * CHUNK), Vector3(CHUNK, 32, CHUNK))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


func set_zone_clean(values: PackedFloat32Array) -> void:
	_zone_clean = values
	if material:
		material.set_shader_parameter("zone_clean", values)
	for m in extra_materials:
		m.set_shader_parameter("zone_clean", values)
