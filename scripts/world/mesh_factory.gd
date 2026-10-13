class_name MeshFactory
## Geometría procedural original: hojas, primitivas con color y piezas de atrezo.
## Los materiales se reutilizan por color para minimizar cambios de estado en la GPU.
## El atrezo estático usa dos materiales compartidos (prop.gdshader y foliage.gdshader) con el color
## por instancia o por vértice; el alfa del color elige el patrón procedural (ver pc()).

static var _mats := {}
static var _meshes := {}

# Patrones de prop.gdshader (alfa del color = (patrón + 16 · veta vertical) / 32).
enum { PAT_PLAIN, PAT_WOOD, PAT_PLANKS_H, PAT_PLANKS_V, PAT_STONE, PAT_BRICK, PAT_ROOF, PAT_BARK,
	PAT_BIRCH, PAT_METAL, PAT_GLASS, PAT_TILE, PAT_STRIPES, PAT_WATER, PAT_STRAW, PAT_GLOW }

const LAMP_COLOR := Color(1.0, 0.86, 0.55)
const FRONT_CW := true   # Godot: las caras frontales van en sentido horario visto desde fuera


static func mat(c: Color, rough: float = 0.95, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [c.to_html(), rough, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic_specular = 0.2
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


static func box(size: Vector3) -> BoxMesh:
	var key := "box%s" % size
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return _meshes[key]


static func cyl(top: float, bottom: float, height: float, segs: int = 10) -> CylinderMesh:
	var key := "cyl%.3f_%.3f_%.3f_%d" % [top, bottom, height, segs]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = height
		c.radial_segments = segs
		c.rings = 1
		_meshes[key] = c
	return _meshes[key]


static func sphere(radius: float, segs: int = 8, rings: int = 5) -> SphereMesh:
	var key := "sph%.3f_%d_%d" % [radius, segs, rings]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = radius
		s.height = radius * 2.0
		s.radial_segments = segs
		s.rings = rings
		_meshes[key] = s
	return _meshes[key]


## Hoja con lóbulos, nervio central plegado y puntas curvadas. Unos 22 triángulos, opaca.
static func leaf_mesh() -> ArrayMesh:
	if _meshes.has("leaf"):
		return _meshes["leaf"]
	var half := [
		Vector2(0.0, 0.56), Vector2(0.12, 0.38), Vector2(0.29, 0.40), Vector2(0.23, 0.2),
		Vector2(0.45, 0.1), Vector2(0.31, -0.05), Vector2(0.36, -0.22), Vector2(0.15, -0.19),
		Vector2(0.05, -0.33),
	]
	var outline: Array[Vector2] = []
	for p in half:
		outline.append(p)
	for k in range(half.size() - 1, 0, -1):
		outline.append(Vector2(-half[k].x, half[k].y))
	outline.append(Vector2(0.0, -0.36))
	var scale := 0.24
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3(0.0, 0.035, 0.05) * scale)
	cols.append(Color(0.78, 0.74, 0.7))
	norms.append(Vector3.UP)
	for p in outline:
		var curl := 0.06 * absf(p.y) + 0.05 * absf(p.x)
		verts.append(Vector3(p.x, curl, -p.y) * scale)
		cols.append(Color(1.05, 1.0, 0.95))
		norms.append(Vector3(p.x * 0.5, 1.0, -p.y * 0.3).normalized())
	var m := outline.size()
	for k in m:
		idx.append_array([0, 1 + k, 1 + (k + 1) % m])
	# Pecíolo.
	var s0 := verts.size()
	verts.append_array([Vector3(-0.018, 0.01, 0.34) * scale, Vector3(0.018, 0.01, 0.34) * scale, Vector3(0.0, 0.02, 0.6) * scale])
	cols.append_array([Color(0.6, 0.5, 0.4), Color(0.6, 0.5, 0.4), Color(0.55, 0.45, 0.35)])
	norms.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
	idx.append_array([s0, s0 + 1, s0 + 2])
	var mesh := _array_mesh(verts, norms, cols, idx)
	_meshes["leaf"] = mesh
	return mesh


## Versión lejana: rombo de 2 triángulos.
static func leaf_mesh_lod() -> ArrayMesh:
	if _meshes.has("leaf_lod"):
		return _meshes["leaf_lod"]
	var s := 0.24
	var verts := PackedVector3Array([Vector3(0, 0.01, -0.56) * s, Vector3(0.4, 0.0, 0.0) * s, Vector3(0, 0.01, 0.36) * s, Vector3(-0.4, 0.0, 0.0) * s])
	var norms := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var cols := PackedColorArray([Color(1, 1, 1), Color(1, 1, 1), Color(0.9, 0.9, 0.9), Color(1, 1, 1)])
	var mesh := _array_mesh(verts, norms, cols, PackedInt32Array([0, 1, 2, 0, 2, 3]))
	_meshes["leaf_lod"] = mesh
	return mesh


static func _array_mesh(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Prisma triangular (tejados). size = ancho (x), alto (y), fondo (z).
static func roof(size: Vector3) -> PrismMesh:
	var key := "roof%s" % size
	if not _meshes.has(key):
		var p := PrismMesh.new()
		p.size = size
		_meshes[key] = p
	return _meshes[key]


## Bolsa de hojas: saco abombado con arrugas, cuello fruncido y nudo con dos orejas.
static func bag_mesh() -> ArrayMesh:
	if _meshes.has("bag"):
		return _meshes["bag"]
	var rings := 10
	var segs := 14
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for r in rings + 1:
		var v := float(r) / rings
		for s in segs + 1:
			var u := float(s) / segs * TAU
			var wrinkle := 0.03 * sin(u * 3.0 + v * 5.0) + 0.018 * sin(u * 7.0 - v * 11.0)
			var radius := sin(v * PI) * (0.37 + wrinkle) * (1.0 - 0.42 * v * v)
			radius = lerpf(radius, 0.045, smoothstep(0.78, 1.0, v))
			var y := -cos(v * PI) * 0.42 + 0.05 * v
			verts.append(Vector3(cos(u) * radius, y, sin(u) * radius))
			var g := 0.8 + 0.2 * smoothstep(-0.04, 0.04, wrinkle)
			cols.append(Color(g, g, g, 1.0))
	for r in rings:
		for s in segs:
			var a := r * (segs + 1) + s
			var b := a + segs + 1
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	var body := _build(verts, idx, cols, Vector3(0, 0.0, 0))
	var mesh := merge([[body, Transform3D.IDENTITY, Color.WHITE],
		[_colored(sphere(0.5, 8, 5)), Transform3D(Basis.from_scale(Vector3(0.13, 0.1, 0.13)), Vector3(0, 0.45, 0)), Color.WHITE],
		[_colored(sphere(0.5, 6, 4)), Transform3D(Basis(Vector3.BACK, -0.6) * Basis.from_scale(Vector3(0.09, 0.17, 0.035)), Vector3(0.05, 0.53, 0)), Color.WHITE],
		[_colored(sphere(0.5, 6, 4)), Transform3D(Basis(Vector3.BACK, 0.7) * Basis.from_scale(Vector3(0.08, 0.15, 0.035)), Vector3(-0.05, 0.52, 0.01)), Color.WHITE]])
	_meshes["bag"] = mesh
	return mesh


# ------------------------------------------------------------------ materiales estilizados

static var _noise: Texture2D


## Ruido suave compartido por los shaders de atrezo y follaje (128², sin costuras, con mipmaps).
static func noise_tex() -> Texture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.seed = 4127
		n.frequency = 0.045
		n.fractal_octaves = 3
		var img := n.get_seamless_image(128, 128)
		img.convert(Image.FORMAT_L8)
		img.generate_mipmaps()
		_noise = ImageTexture.create_from_image(img)
	return _noise


## Material compartido del atrezo (color por vértice/instancia, patrón en el alfa).
## object_space: patrones en espacio de objeto, para piezas que se mueven (puertas, herramientas).
static func prop_mat(object_space: bool = false) -> ShaderMaterial:
	var key := "prop_os" if object_space else "prop"
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/prop.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("object_space", 1.0 if object_space else 0.0)
	_mats[key] = m
	return m


## Material estilizado de color y patrón fijos, para primitivas sin color por vértice.
static func solid_mat(c: Color, pattern: int = PAT_PLAIN) -> ShaderMaterial:
	var key := "solid|%s|%d" % [c.to_html(), pattern]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/prop.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("object_space", 1.0)
	m.set_shader_parameter("use_vertex_color", 0.0)
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("pattern", float(pattern))
	_mats[key] = m
	return m


## Material compartido del follaje (copas, setos, arbustos, matas).
static func foliage_mat() -> ShaderMaterial:
	if _mats.has("foliage"):
		return _mats["foliage"]
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/foliage.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex())
	_mats["foliage"] = m
	return m


## Cristal de farola: material compartido que Atmosphere hace brillar al caer la tarde.
static func lamp_mat() -> StandardMaterial3D:
	return mat(LAMP_COLOR)


## Color con el patrón procedural codificado en el alfa (ver prop.gdshader).
static func pc(c: Color, pattern: int, vertical_grain: bool = false) -> Color:
	return Color(c.r, c.g, c.b, (pattern + (16 if vertical_grain else 0) + 0.25) / 32.0)


# ------------------------------------------------------------------ mallas unitarias para lotes

## Mallas de tamaño unidad (caben en un cubo de 1 m centrado) con color por vértice.
static func unit(id: String) -> Mesh:
	var key := "u_" + id
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh
	match id:
		"box": m = _colored(box(Vector3.ONE))
		"cyl": m = _colored(cyl(0.5, 0.5, 1.0, 10))
		"cyl6": m = _colored(cyl(0.5, 0.5, 1.0, 6))
		"cyl8": m = _colored(cyl(0.5, 0.5, 1.0, 8))
		"cone": m = _colored(cyl(0.0, 0.5, 1.0, 10))
		"cone4": m = _colored(cyl(0.0, 0.5, 1.0, 4))
		"cone6": m = _colored(cyl(0.0, 0.5, 1.0, 6))
		"sph": m = _colored(sphere(0.5, 12, 7))
		"sph_lo": m = _colored(sphere(0.5, 7, 4))
		"prism": m = _colored(roof(Vector3.ONE))
		"trunk": m = trunk_mesh()
		"branch": m = branch_mesh()
		"blob0": m = blob_mesh(0)
		"blob1": m = blob_mesh(1)
		"blob2": m = blob_mesh(2)
		"blob_lo": m = blob_mesh(3, 0)
		"rock0": m = rock_mesh(0)
		"rock1": m = rock_mesh(1)
		"rock2": m = rock_mesh(2)
		"pumpkin": m = pumpkin_mesh()
		"flower": m = flower_mesh()
		"tuft": m = tuft_mesh()
		"picket": m = picket_mesh()
		"hedge": m = hedge_mesh()
		"pine": m = pine_tier_mesh()
		"ring": m = ring_mesh()
		"barrel": m = barrel_mesh()
		_:
			push_error("MeshFactory.unit: malla desconocida " + id)
			m = _colored(box(Vector3.ONE))
	_meshes[key] = m
	return m


## Copia una primitiva añadiéndole color por vértice (oscurece la base si ao_bottom > 0).
static func _colored(m: Mesh, ao_bottom: float = 0.0) -> ArrayMesh:
	var arr := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for k in verts.size():
		var s := 1.0 - ao_bottom * (1.0 - smoothstep(-0.5, 0.0, verts[k].y))
		cols[k] = Color(s, s, s, 1.0)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = arr[Mesh.ARRAY_NORMAL]
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


## Construye una malla orientando cada triángulo hacia fuera (Godot: caras frontales en sentido horario)
## y calculando normales suaves en los vértices compartidos.
## hint: dirección "hacia fuera" por vértice; si está vacía se usa (vértice - center), o el eje Y si axis_y.
static func _build(verts: PackedVector3Array, idx: PackedInt32Array, cols: PackedColorArray, center: Vector3 = Vector3.ZERO, axis_y: bool = false, hint: PackedVector3Array = PackedVector3Array(), radial: float = 0.0) -> ArrayMesh:
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	var tris := PackedInt32Array(idx)
	var use_hint := hint.size() == verts.size()
	for k in range(0, tris.size(), 3):
		var ia := tris[k]
		var ib := tris[k + 1]
		var ic := tris[k + 2]
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		var fn := (b - a).cross(c - a)
		var out: Vector3
		if use_hint:
			out = hint[ia] + hint[ib] + hint[ic]
		else:
			out = (a + b + c) / 3.0 - center
			if axis_y:
				out.y = 0.0
		var outward := fn.dot(out) > 0.0
		if outward == FRONT_CW:
			tris[k + 1] = ic
			tris[k + 2] = ib
		if not outward:
			fn = -fn
		norms[ia] += fn
		norms[ib] += fn
		norms[ic] += fn
	for k in norms.size():
		var nv := norms[k].normalized()
		if radial > 0.0:
			var rv := hint[k] if use_hint else verts[k] - center
			if axis_y and not use_hint:
				rv.y = 0.0
			nv = nv.lerp(rv.normalized(), radial).normalized()
		norms[k] = nv
	return _array_mesh(verts, norms, cols, tris)


## Igual que _build pero con sombreado plano (cada triángulo con sus propios vértices).
static func _build_flat(verts: PackedVector3Array, idx: PackedInt32Array, cols: PackedColorArray, center: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var v2 := PackedVector3Array()
	var c2 := PackedColorArray()
	var i2 := PackedInt32Array()
	for k in idx.size():
		v2.append(verts[idx[k]])
		c2.append(cols[idx[k]])
		i2.append(k)
	return _build(v2, i2, c2, center)


## Fusiona piezas [Mesh, Transform3D, Color] en una sola malla con color por vértice.
## El color de la pieza multiplica el de sus vértices y su alfa (patrón) sustituye al del vértice.
static func merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for prt in parts:
		var m: Mesh = prt[0]
		var xf: Transform3D = prt[1]
		var pcol: Color = prt[2]
		var arr := m.surface_get_arrays(0)
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var vc = arr[Mesh.ARRAY_COLOR]
		var pi = arr[Mesh.ARRAY_INDEX]
		var has_vc: bool = vc is PackedColorArray and (vc as PackedColorArray).size() == pv.size()
		var nb := xf.basis.inverse().transposed()
		var base := verts.size()
		for k in pv.size():
			verts.append(xf * pv[k])
			norms.append((nb * pn[k]).normalized())
			var c := pcol
			if has_vc:
				var v: Color = vc[k]
				c = Color(v.r * pcol.r, v.g * pcol.g, v.b * pcol.b, pcol.a)
			cols.append(c)
		if pi is PackedInt32Array and (pi as PackedInt32Array).size() > 0:
			for k in (pi as PackedInt32Array):
				idx.append(base + k)
		else:
			for k in pv.size():
				idx.append(base + k)
	return _array_mesh(verts, norms, cols, idx)


## Pieza para merge(): malla unitaria escalada, girada y colocada.
static func part(id: String, pos: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> Array:
	return [unit(id), Transform3D(basis * Basis.from_scale(size), pos), color]


## Malla fusionada en caché (prefabricado), construida una sola vez con builder.call() -> Array de piezas.
static func prefab(id: String, builder: Callable) -> ArrayMesh:
	var key := "pf_" + id
	if not _meshes.has(key):
		_meshes[key] = merge(builder.call())
	return _meshes[key]


static func has_prefab(id: String) -> bool:
	return _meshes.has("pf_" + id)


# ------------------------------------------------------------------ generadores de formas orgánicas

static func _ico(sub: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized()
	var f := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for s in sub:
		var cache := {}
		var nf := PackedInt32Array()
		for k in range(0, f.size(), 3):
			var a := f[k]
			var b := f[k + 1]
			var c := f[k + 2]
			var ab := _ico_mid(v, cache, a, b)
			var bc := _ico_mid(v, cache, b, c)
			var ca := _ico_mid(v, cache, c, a)
			nf.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		f = nf
	return [v, f]


static func _ico_mid(v: Array, cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 4096 + maxi(a, b)
	if cache.has(key):
		return cache[key]
	v.append(((v[a] as Vector3) + (v[b] as Vector3)).normalized())
	cache[key] = v.size() - 1
	return v.size() - 1


## Racimo de copa: icosfera abollada (80 triángulos), base algo aplanada, oclusión horneada abajo.
static func blob_mesh(variant: int, sub: int = 1) -> ArrayMesh:
	var ico := _ico(sub)
	var dirs: Array = ico[0]
	var faces: PackedInt32Array = ico[1]
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var ph := variant * 2.39 + 0.7
	for d in dirs:
		var dv: Vector3 = d
		var lump := 0.12 * sin(dv.x * 3.1 + ph) * sin(dv.y * 2.7 + ph * 1.7) + 0.09 * sin(dv.z * 4.3 - ph) * cos(dv.x * 3.7 + ph * 0.6) + 0.05 * sin((dv.x + dv.y - dv.z) * 7.0 + ph)
		var p := dv * 0.5 * (1.0 + lump)
		if p.y < -0.3:
			p.y = lerpf(p.y, -0.3, 0.35)
		verts.append(p)
		var s := lerpf(0.68, 1.0, smoothstep(-0.45, 0.4, dv.y))
		cols.append(Color(s, s, s, 1.0))
	return _build(verts, faces, cols, Vector3.ZERO, false, PackedVector3Array(), 0.45 if sub > 0 else 0.7)


## Roca facetada (icosaedro deformado de 20 caras con la base plana).
static func rock_mesh(variant: int) -> ArrayMesh:
	var ico := _ico(0)
	var dirs: Array = ico[0]
	var faces: PackedInt32Array = ico[1]
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for k in dirs.size():
		var dv: Vector3 = dirs[k]
		var h := fposmod(sin(k * 12.9898 + variant * 78.233) * 43758.5453, 1.0)
		var p := dv * 0.5 * (0.78 + 0.4 * h)
		p.y = maxf(p.y * 0.8, -0.22)
		verts.append(p)
		var s := 0.82 + 0.25 * h
		cols.append(Color(s, s, s, 1.0))
	return _build_flat(verts, faces, cols, Vector3(0, -0.05, 0))


## Calabaza con gajos y tallo (unos 260 triángulos).
static func pumpkin_mesh() -> ArrayMesh:
	var rings := 6
	var segs := 16
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for r in rings + 1:
		var v := float(r) / rings
		for s in segs + 1:
			var u := float(s) / segs * TAU
			var rib := 0.86 + 0.14 * sqrt(absf(cos(u * 4.0)))
			var sv := sin(v * PI)
			var p := Vector3(cos(u) * sv * 0.5 * rib, -cos(v * PI) * 0.31, sin(u) * sv * 0.5 * rib)
			p.y -= 0.07 * (1.0 - smoothstep(0.0, 0.35, sv)) * (1.0 if v > 0.5 else -0.6)
			verts.append(p)
			var g := (0.72 + 0.28 * sqrt(absf(cos(u * 4.0)))) * lerpf(0.7, 1.0, smoothstep(0.0, 0.6, v))
			cols.append(Color(g, g, g, 1.0))
	for r in rings:
		for s in segs:
			var a := r * (segs + 1) + s
			var b := a + segs + 1
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	var body := _build(verts, idx, cols, Vector3.ZERO)
	var stem := _colored(cyl(0.035, 0.055, 0.2, 5))
	return merge([[body, Transform3D.IDENTITY, Color.WHITE],
		[stem, Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(0.02, 0.3, 0)), Color(0.45, 0.5, 0.25)]])


## Flor: cinco pétalos alrededor de un botón (cabeza a y=0, mirando arriba).
static func flower_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.append(Vector3(0, 0.06, 0))
	cols.append(Color(1.0, 0.8, 0.3))
	for k in 5:
		var a := k * TAU / 5.0
		verts.append(Vector3(cos(a) * 0.16, 0.03, sin(a) * 0.16))
		cols.append(Color(1.0, 0.75, 0.25))
	for k in 5:
		idx.append_array([0, 1 + k, 1 + (k + 1) % 5])
	for k in 5:
		var a := k * TAU / 5.0 + 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var b := verts.size()
		verts.append_array([dir * 0.08 + Vector3(0, 0.02, 0), dir * 0.3 + side * 0.15 + Vector3(0, 0.06, 0),
			dir * 0.5 + Vector3(0, 0.12, 0), dir * 0.3 - side * 0.15 + Vector3(0, 0.06, 0)])
		cols.append_array([Color(0.8, 0.8, 0.8), Color.WHITE, Color.WHITE, Color.WHITE])
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	return _build(verts, idx, cols, Vector3(0, -1.0, 0))


## Mata de hierba: seis briznas finas de doble cara (12 triángulos).
static func tuft_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in 6:
		var a := k * TAU / 6.0 + 0.4 * sin(k * 2.1)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var h := 0.75 + 0.25 * absf(sin(k * 1.7))
		var base := dir * 0.08 + Vector3(0, -0.5, 0)
		var tip := dir * (0.25 + 0.15 * absf(cos(k * 1.3))) + Vector3(0, -0.5 + h, 0)
		var n := (dir * 0.5 + Vector3.UP).normalized()
		var b := verts.size()
		verts.append_array([base - side * 0.05, base + side * 0.05, tip])
		cols.append_array([Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5), Color.WHITE])
		norms.append_array([n, n, n])
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 1])
	return _array_mesh(verts, norms, cols, idx)


## Extrusión de un perfil convexo (plano XY) a lo largo de Z, de -0.5 a 0.5.
static func _extrude(profile: PackedVector2Array, smooth: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := profile.size()
	if smooth:
		for z in [-0.5, 0.5]:
			for p in profile:
				verts.append(Vector3(p.x, p.y, z))
				cols.append(Color.WHITE)
		for k in n:
			var k2 := (k + 1) % n
			idx.append_array([k, k2, n + k, k2, n + k2, n + k])
	else:
		for k in n:
			var p0 := profile[k]
			var p1 := profile[(k + 1) % n]
			var b := verts.size()
			verts.append_array([Vector3(p0.x, p0.y, -0.5), Vector3(p1.x, p1.y, -0.5), Vector3(p0.x, p0.y, 0.5), Vector3(p1.x, p1.y, 0.5)])
			cols.append_array([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var side := _build(verts, idx, cols, Vector3.ZERO, false)
	var cv := PackedVector3Array()
	var cc := PackedColorArray()
	var ci := PackedInt32Array()
	for z in [-0.5, 0.5]:
		var b := cv.size()
		for p in profile:
			cv.append(Vector3(p.x, p.y, z))
			cc.append(Color.WHITE)
		for k in range(1, n - 1):
			ci.append_array([b, b + k, b + k + 1])
	var caps := _build(cv, ci, cc, Vector3.ZERO)
	return merge([[side, Transform3D.IDENTITY, Color.WHITE], [caps, Transform3D.IDENTITY, Color.WHITE]])


## Tabla de valla con punta (perfil extruido en Z).
static func picket_mesh() -> ArrayMesh:
	return _extrude(PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.3), Vector2(0.0, 0.5), Vector2(-0.5, 0.3)]), false)


## Seto con los cantos superiores redondeados (perfil en XY, largo en Z).
static func hedge_mesh() -> ArrayMesh:
	return _extrude(PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.2), Vector2(0.44, 0.38),
		Vector2(0.26, 0.48), Vector2(0.0, 0.5), Vector2(-0.26, 0.48), Vector2(-0.44, 0.38), Vector2(-0.5, 0.2)]), true)


## Tronco con raíces en la base y algo de conicidad (8 lados).
static func trunk_mesh() -> ArrayMesh:
	var rings := [[-0.5, 0.82], [-0.4, 0.58], [-0.2, 0.48], [0.5, 0.34]]
	var segs := 8
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for r in rings.size():
		var y: float = rings[r][0]
		var rad: float = rings[r][1]
		for s in segs + 1:
			var u := float(s) / segs * TAU
			var rr := rad
			if r == 0:
				rr *= 1.0 + 0.32 * maxf(cos(u * 3.0 + 0.4), 0.0)
			elif r == 1:
				rr *= 1.0 + 0.12 * maxf(cos(u * 3.0 + 0.4), 0.0)
			verts.append(Vector3(cos(u) * rr, y, sin(u) * rr))
			var g := 0.72 if r == 0 else 1.0
			cols.append(Color(g, g, g, 1.0))
	for r in rings.size() - 1:
		for s in segs:
			var a := r * (segs + 1) + s
			var b := a + segs + 1
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	return _build(verts, idx, cols, Vector3.ZERO, true)


## Rama: cilindro cónico de 5 lados de y=0 a y=1 (para orientarla con una base).
static func branch_mesh() -> ArrayMesh:
	var segs := 5
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for r in 2:
		for s in segs + 1:
			var u := float(s) / segs * TAU
			var rad := 0.5 if r == 0 else 0.26
			verts.append(Vector3(cos(u) * rad, float(r), sin(u) * rad))
			cols.append(Color.WHITE)
	for s in segs:
		idx.append_array([s, s + segs + 1, s + 1, s + segs + 1, s + segs + 2, s + 1])
	return _build(verts, idx, cols, Vector3.ZERO, true)


## Piso de pino: cono con borde dentado y caído, y fondo cerrado.
static func pine_tier_mesh() -> ArrayMesh:
	var segs := 12
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.append(Vector3(0, 0.5, 0))
	cols.append(Color.WHITE)
	for s in segs:
		var u := float(s) / segs * TAU
		var r := 0.5 if s % 2 == 0 else 0.4
		verts.append(Vector3(cos(u) * r, -0.45 if s % 2 == 0 else -0.36, sin(u) * r))
		cols.append(Color(0.82, 0.82, 0.82))
	for s in segs:
		idx.append_array([0, 1 + s, 1 + (s + 1) % segs])
	var top := _build(verts, idx, cols, Vector3(0, -0.2, 0), false, PackedVector3Array(), 0.35)
	var uv := PackedVector3Array()
	var uc := PackedColorArray()
	var ui := PackedInt32Array()
	uv.append(Vector3(0, -0.28, 0))
	uc.append(Color(0.45, 0.45, 0.45))
	for s in segs:
		var u := float(s) / segs * TAU
		var r := 0.5 if s % 2 == 0 else 0.4
		uv.append(Vector3(cos(u) * r, -0.45 if s % 2 == 0 else -0.36, sin(u) * r))
		uc.append(Color(0.6, 0.6, 0.6))
	for s in segs:
		ui.append_array([0, 1 + s, 1 + (s + 1) % segs])
	var under := _build(uv, ui, uc, Vector3(0, 0.3, 0))
	return merge([[top, Transform3D.IDENTITY, Color.WHITE], [under, Transform3D.IDENTITY, Color.WHITE]])


## Toroide (salvavidas, neumáticos). Radio mayor 0.38, menor 0.12, en el plano XZ.
static func ring_mesh() -> ArrayMesh:
	var segs := 14
	var sides := 6
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var hint := PackedVector3Array()
	var idx := PackedInt32Array()
	for s in segs + 1:
		var u := float(s) / segs * TAU
		var c := Vector3(cos(u), 0, sin(u)) * 0.38
		for t in sides + 1:
			var w := float(t) / sides * TAU
			var nv := Vector3(cos(u) * cos(w), sin(w), sin(u) * cos(w))
			verts.append(c + nv * 0.12)
			hint.append(nv)
			cols.append(Color.WHITE)
	for s in segs:
		for t in sides:
			var a := s * (sides + 1) + t
			var b := a + sides + 1
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	return _build(verts, idx, cols, Vector3.ZERO, false, hint, 1.0)


## Barril abombado con tapas (12 lados).
static func barrel_mesh() -> ArrayMesh:
	var rings := [[-0.5, 0.42], [-0.25, 0.48], [0.0, 0.5], [0.25, 0.48], [0.5, 0.42]]
	var segs := 12
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for r in rings.size():
		for s in segs + 1:
			var u := float(s) / segs * TAU
			var rad: float = rings[r][1]
			verts.append(Vector3(cos(u) * rad, float(rings[r][0]), sin(u) * rad))
			cols.append(Color.WHITE)
	for r in rings.size() - 1:
		for s in segs:
			var a := r * (segs + 1) + s
			var b := a + segs + 1
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	var body := _build(verts, idx, cols, Vector3.ZERO, true)
	var cap := _colored(cyl(0.42, 0.42, 1.0, 12))
	return merge([[body, Transform3D.IDENTITY, Color.WHITE],
		[cap, Transform3D(Basis.from_scale(Vector3(0.98, 0.01, 0.98)), Vector3(0, 0.495, 0)), Color(0.85, 0.85, 0.85)]])
