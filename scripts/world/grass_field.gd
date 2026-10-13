class_name GrassField
extends MultiMeshInstance3D
## Césped de verdad alrededor de la cámara: una rejilla de matas (MultiMesh) fija en el mundo que
## se recoloca a saltos de una celda cuando la cámara avanza, así que no "nada" ni cuesta CPU.
## Todo el trabajo por mata ocurre en la GPU (grass.gdshader): altura del terreno, ocultación bajo
## la hojarasca y en caminos/muros, color seco→verde de cada zona, flores, viento y pisadas.
## Densidad según PerformanceManager.level. Una sola llamada de dibujo, sin sombras propias.

# [matas por lado, separación en metros] para BAJO, MEDIO y ALTO.
const DENSITY := [[32, 0.36], [52, 0.3], [64, 0.28]]

var terrain: Terrain
var leaf_manager: LeafManager
var _mat: ShaderMaterial
var _spacing := 0.3
var _n := 0
var _half := 8.0
var _cell := Vector2i(1 << 30, 0)
var _flower_center := Vector3.ZERO


func setup(t: Terrain, lm: LeafManager) -> void:
	terrain = t
	leaf_manager = lm
	name = "GrassField"
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/grass.gdshader")
	t.bind_ground_params(_mat)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _tuft_mesh()
	_mat.set_shader_parameter("flower_center", _flower_center)
	_apply_quality(PerformanceManager.level)
	PerformanceManager.quality_changed.connect(_apply_quality)


func _apply_quality(level: int) -> void:
	var d: Array = DENSITY[clampi(level, 0, DENSITY.size() - 1)]
	_n = int(d[0])
	_spacing = float(d[1])
	_half = _n * _spacing * 0.5
	var count := _n * _n
	var buf := PackedFloat32Array()
	buf.resize(count * 12)
	buf.fill(0.0)
	for j in _n:
		for i in _n:
			var k := (j * _n + i) * 12
			buf[k] = 1.0
			buf[k + 3] = (i - (_n >> 1)) * _spacing
			buf[k + 5] = 1.0
			buf[k + 10] = 1.0
			buf[k + 11] = (j - (_n >> 1)) * _spacing
	multimesh.instance_count = count
	multimesh.buffer = buf
	multimesh.custom_aabb = AABB(Vector3(-_half - 1.0, -30.0, -_half - 1.0), Vector3(_half * 2.0 + 2.0, 40.0, _half * 2.0 + 2.0))
	_mat.set_shader_parameter("spacing", _spacing)
	_mat.set_shader_parameter("fade_radius", _half * 0.97)
	_cell = Vector2i(1 << 30, 0)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var ahead := Vector2(fwd.x, fwd.z)
	if ahead.length_squared() > 0.0001:
		ahead = ahead.normalized() * _half * 0.35
	var c := Vector2i(roundi((cp.x + ahead.x) / _spacing), roundi((cp.z + ahead.y) / _spacing))
	if c != _cell:
		_cell = c
		global_position = Vector3(c.x * _spacing, 0.0, c.y * _spacing)
	_mat.set_shader_parameter("cam_pos", cp)
	if leaf_manager:
		var w := leaf_manager.sim.ambient_wind
		_mat.set_shader_parameter("wind", Vector2(w.x, w.z))


## Mata de 9 hojas (un triángulo cada una) y una florecilla (2 triángulos) que el shader solo
## despliega en algunas matas del césped restaurado. UV.y = altura relativa, UV.x = 1 en la flor.
func _tuft_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var blades := 9
	for k in blades:
		var a := k * TAU / blades + rng.randf_range(-0.35, 0.35)
		var out := Vector3(cos(a), 0.0, sin(a))
		var perp := Vector3(-out.z, 0.0, out.x)
		var r0 := 0.0 if k == 0 else rng.randf_range(0.02, 0.055)
		var hgt := 0.22 if k == 0 else rng.randf_range(0.1, 0.19)
		var lean := 0.02 if k == 0 else rng.randf_range(0.04, 0.09)
		var w := rng.randf_range(0.009, 0.015)
		var b := out * r0
		var tip := b + out * lean + Vector3(0.0, hgt, 0.0)
		if k == 0:
			_flower_center = tip + Vector3(0.0, 0.006, 0.0)
		var s := verts.size()
		verts.append_array([b - perp * w, b + perp * w, tip])
		uvs.append_array([Vector2(0, 0), Vector2(0, 0), Vector2(0, 1)])
		idx.append_array([s, s + 1, s + 2])
	# Florecilla: rombo casi horizontal sobre la hoja central.
	var fc := _flower_center
	var r := 0.03
	var s0 := verts.size()
	verts.append_array([fc + Vector3(r, -0.004, 0), fc + Vector3(0, -0.004, r), fc + Vector3(-r, -0.004, 0), fc + Vector3(0, -0.004, -r)])
	uvs.append_array([Vector2(1, 1), Vector2(1, 1), Vector2(1, 1), Vector2(1, 1)])
	idx.append_array([s0, s0 + 1, s0 + 2, s0, s0 + 2, s0 + 3])
	for v in verts.size():
		norms.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
