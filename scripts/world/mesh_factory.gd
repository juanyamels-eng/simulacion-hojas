class_name MeshFactory
## Geometría procedural original: hojas, primitivas con color y piezas de atrezo.
## Los materiales se reutilizan por color para minimizar cambios de estado en la GPU.

static var _mats := {}
static var _meshes := {}


static func mat(c: Color, rough: float = 0.95, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [c.to_html(), rough, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic_specular = 0.2
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


## Bolsa de hojas: esfera achatada con nudo.
static func bag_mesh() -> ArrayMesh:
	if _meshes.has("bag"):
		return _meshes["bag"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 7
	var segs := 10
	for r in rings:
		for s in segs:
			for q in [[r, s], [r + 1, s], [r, s + 1], [r + 1, s], [r + 1, s + 1], [r, s + 1]]:
				var v: float = float(q[0]) / rings
				var u: float = float(q[1]) / segs * TAU
				var radius := sin(v * PI) * (0.36 + 0.04 * sin(u * 3.0 + v * 5.0)) * (1.0 - 0.35 * v * v)
				var y := -cos(v * PI) * 0.42 + 0.06 * v
				var p := Vector3(cos(u) * radius, y, sin(u) * radius)
				st.set_normal(p.normalized())
				st.add_vertex(p)
	# Nudo.
	var top := Vector3(0, 0.5, 0)
	for s in 6:
		var a := s * TAU / 6.0
		var b := (s + 1) * TAU / 6.0
		var p1 := Vector3(cos(a) * 0.07, 0.42, sin(a) * 0.07)
		var p2 := Vector3(cos(b) * 0.07, 0.42, sin(b) * 0.07)
		st.set_normal(Vector3.UP)
		st.add_vertex(p1)
		st.add_vertex(top + Vector3(cos(a) * 0.12, 0.08, sin(a) * 0.12))
		st.add_vertex(p2)
	st.generate_normals()
	var mesh := st.commit()
	_meshes["bag"] = mesh
	return mesh
