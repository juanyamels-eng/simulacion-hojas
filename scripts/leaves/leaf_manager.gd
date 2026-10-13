class_name LeafManager
extends Node3D
## Orquesta el sistema de hojas: generación determinista, bloques de render, LOD,
## distancia de dibujado, montones, recuentos por zona y guardado del estado.

const P_HAND := 0
const P_VACUUM := 1
const P_DUCT0 := 2
const P_ROBOT := 12

# Paleta general de otoño [color, peso] (la usan otros sistemas: partículas, decoración...).
const PALETTE := [
	[Color(0.96, 0.76, 0.18), 0.27],
	[Color(0.95, 0.52, 0.12), 0.3],
	[Color(0.84, 0.24, 0.1), 0.18],
	[Color(0.58, 0.35, 0.16), 0.19],
	[Color(0.5, 0.62, 0.2), 0.06],
]

# Especies de hoja: [peso, escala mínima, escala máxima, paleta [[color, peso]...]].
# La silueta (arce, roble, lanceolada, acorazonada) la dibuja LeafMeshes según la especie.
const SPECIES := [
	[0.4, 0.9, 1.3, [[Color(0.86, 0.2, 0.08), 0.28], [Color(0.94, 0.38, 0.1), 0.3], [Color(0.96, 0.58, 0.12), 0.26], [Color(0.97, 0.76, 0.2), 0.16]]],
	[0.22, 0.85, 1.2, [[Color(0.6, 0.33, 0.13), 0.34], [Color(0.75, 0.46, 0.18), 0.3], [Color(0.84, 0.38, 0.12), 0.2], [Color(0.48, 0.29, 0.13), 0.16]]],
	[0.18, 0.8, 1.15, [[Color(0.97, 0.78, 0.22), 0.4], [Color(0.94, 0.62, 0.16), 0.3], [Color(0.72, 0.7, 0.24), 0.18], [Color(0.86, 0.5, 0.14), 0.12]]],
	[0.2, 0.75, 1.1, [[Color(0.99, 0.84, 0.3), 0.38], [Color(0.95, 0.69, 0.18), 0.3], [Color(0.58, 0.64, 0.2), 0.14], [Color(0.9, 0.55, 0.16), 0.18]]],
]

var sim := LeafSimulationSystem.new()
var cluster := LeafClusterSystem.new()
var terrain: Terrain
var material: ShaderMaterial
var leaf_mesh: ArrayMesh
var leaf_mesh_lod: ArrayMesh
var chunk_nodes: Array[MultiMeshInstance3D] = []
var chunk_lod := PackedByteArray()
var zone_filter := ""
var orig_pos := PackedVector3Array()
var _count_timer := 0.0
var _pile_timer := 0.0
var _lod_timer := 0.0
var _lod_dist := 20.0
var _draw_dist := 46.0


func _ready() -> void:
	process_priority = 50


func setup(t: Terrain, density_points: Array, saved: PackedByteArray, only_zone: String = "") -> void:
	terrain = t
	zone_filter = only_zone
	sim.setup_grid(t)
	cluster.setup(sim.gw, sim.gh)
	leaf_mesh = LeafMeshes.leaf_mesh()
	leaf_mesh_lod = LeafMeshes.leaf_mesh_lod()
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/leaf.gdshader")
	material.set_shader_parameter("pile_tex", cluster.tex)
	material.set_shader_parameter("vein_tex", LeafMeshes.vein_texture())
	material.set_shader_parameter("grid_rect", Vector4(sim.ox, sim.oz, 1.0 / GameData.GRID_SIZE_M.x, 1.0 / GameData.GRID_SIZE_M.y))
	material.set_shader_parameter("pile_max", LeafClusterSystem.PILE_MAX)
	sim.create_chunk = _create_chunk_node
	chunk_nodes.resize(sim.cw * sim.ch)
	chunk_lod.resize(sim.cw * sim.ch)
	chunk_lod.fill(0)
	_generate(density_points)
	if saved.size() >= 4:
		_apply_state(saved)
	for i in sim.n:
		if sim.state[i] != LeafSimulationSystem.S_REMOVED:
			var c := sim.cell_index(sim.pos[i].x, sim.pos[i].z)
			if c < 0:
				sim.state[i] = LeafSimulationSystem.S_REMOVED
			else:
				sim.link_cell(i, c)
	sim.build_render()
	cluster.flush(sim, true)
	_apply_quality(PerformanceManager.level)
	PerformanceManager.quality_changed.connect(_apply_quality)
	SaveManager.register_leaf_provider(self)
	push_counts()


func _exit_tree() -> void:
	SaveManager.unregister_leaf_provider(self)


func _generate(density_points: Array) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.frequency = 0.07
	var rng := RandomNumberGenerator.new()
	var gen_pos := PackedVector3Array()
	var gen_zone := PackedByteArray()
	for zi in GameData.ZONES.size():
		var z: Dictionary = GameData.ZONES[zi]
		if zone_filter != "" and z["id"] != zone_filter:
			continue
		var r: Rect2 = z["rect"]
		var target := int(round(float(z["leaves"]) * GameManager.leaf_multiplier()))
		rng.seed = 1000 + zi * 7919 + GameManager.ngplus_level * 31
		var local_points := []
		for dp in density_points:
			if r.grow(4.0).has_point(dp[0]):
				local_points.append(dp)
		var piles := []
		for k in 3 + int(r.get_area() / 500.0):
			piles.append(Vector2(rng.randf_range(r.position.x + 3, r.end.x - 3), rng.randf_range(r.position.y + 3, r.end.y - 3)))
		var placed := 0
		var tries := 0
		while placed < target and tries < target * 60:
			tries += 1
			var x := rng.randf_range(r.position.x + 0.3, r.end.x - 0.3)
			var zz := rng.randf_range(r.position.y + 0.3, r.end.y - 0.3)
			var c := terrain.cell_of(x, zz)
			if c < 0 or terrain.solid[c] != 0:
				continue
			var d := 1.25 + maxf(noise.get_noise_2d(x, zz), 0.0) * 1.8
			var e := minf(minf(x - r.position.x, r.end.x - x), minf(zz - r.position.y, r.end.y - zz))
			if e < 2.0:
				d += 1.5 * (1.0 - e / 2.0)
			var p2 := Vector2(x, zz)
			for dp in local_points:
				var rad: float = dp[1]
				var d2 := p2.distance_squared_to(dp[0])
				if d2 < rad * rad * 4.0:
					d += float(dp[2]) * exp(-d2 / (rad * rad))
			for pp in piles:
				var d2 := p2.distance_squared_to(pp)
				if d2 < 9.0:
					d += 5.0 * exp(-d2 / 1.1)
			if terrain.ground_bytes[c * 4] > 128:
				d *= 0.55
			if rng.randf() * 7.0 > d:
				continue
			gen_pos.append(Vector3(x, terrain.height_at(x, zz) + 0.015, zz))
			gen_zone.append(zi)
			placed += 1
	sim.allocate(gen_pos.size())
	orig_pos = gen_pos
	rng.seed = 777
	var total_w := 0.0
	for sp in SPECIES:
		total_w += float(sp[0])
	for i in sim.n:
		sim.pos[i] = gen_pos[i]
		sim.zone_origin[i] = gen_zone[i]
		sim.zone_initial[gen_zone[i]] += 1
		sim.yaw[i] = rng.randf() * TAU
		var pick := rng.randf() * total_w
		var species := 0
		for k in SPECIES.size():
			pick -= float(SPECIES[k][0])
			if pick <= 0.0:
				species = k
				break
		var spec: Array = SPECIES[species]
		var pal: Array = spec[3]
		var pal_w := 0.0
		for pe in pal:
			pal_w += float(pe[1])
		var cpick := rng.randf() * pal_w
		var col: Color = pal[0][0]
		for pe in pal:
			cpick -= float(pe[1])
			if cpick <= 0.0:
				col = pe[0]
				break
		var tone := rng.randf_range(0.84, 1.08)
		col = Color(col.r * tone, col.g * tone * rng.randf_range(0.93, 1.06), col.b * tone, 1.0)
		sim.colr[i] = col
		var shape := (float(species) + rng.randf() * 0.96) / float(SPECIES.size())
		sim.cust[i] = Color(rng.randf_range(float(spec[1]), float(spec[2])), rng.randf(), rng.randf_range(0.9, 1.03), shape)


func _create_chunk_node(c: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = leaf_mesh
	var cx := c % sim.cw
	var cz := c / sim.cw
	var x0 := sim.ox + cx * 10.0
	var z0 := sim.oz + cz * 10.0
	var ymin := -24.0 if x0 >= 60.0 else -4.0
	mm.custom_aabb = AABB(Vector3(x0 - 1.5, ymin, z0 - 1.5), Vector3(13.0, 10.0 - ymin, 13.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	chunk_nodes[c] = mi
	return mm


func _apply_quality(level: int) -> void:
	var p: Dictionary = PerformanceManager.PRESETS[level]
	sim.max_active = int(p["active_leaves"])
	_lod_dist = float(p["lod_distance"])
	_draw_dist = float(p["leaf_distance"])
	_lod_timer = 1.0


func _process(delta: float) -> void:
	sim.simulate(minf(delta, 1.0 / 30.0))
	_pile_timer += delta
	if _pile_timer >= 0.1:
		_pile_timer = 0.0
		cluster.flush(sim)
	_count_timer += delta
	if _count_timer >= 0.3:
		_count_timer = 0.0
		push_counts()
	_lod_timer += delta
	if _lod_timer >= 0.25:
		_lod_timer = 0.0
		_update_lod()


func push_counts() -> void:
	AreaManager.update_counts(sim.zone_counts, sim.zone_initial)


func _update_lod() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var lod2 := _lod_dist * _lod_dist
	var draw2 := _draw_dist * _draw_dist
	for c in chunk_nodes.size():
		var mi := chunk_nodes[c]
		if mi == null:
			continue
		var center := Vector3(sim.ox + (c % sim.cw) * 10.0 + 5.0, cp.y, sim.oz + (c / sim.cw) * 10.0 + 5.0)
		if c % sim.cw * 10.0 + sim.ox >= 60.0:
			center.y = -20.0
		var d2 := maxf(center.distance_squared_to(cp) - 50.0, 0.0)
		var vis := d2 < draw2 and sim.chunk_count[c] > 0
		if mi.visible != vis:
			mi.visible = vis
		var want := 1 if d2 > lod2 else 0
		if vis and chunk_lod[c] != want:
			chunk_lod[c] = want
			mi.multimesh.mesh = leaf_mesh_lod if want == 1 else leaf_mesh


## Devuelve las hojas de una zona a su posición original.
func reset_zone(zi: int) -> void:
	for i in sim.n:
		if sim.zone_origin[i] == zi and sim.state[i] != LeafSimulationSystem.S_SUCKED:
			sim.restore_leaf(i, orig_pos[i])
	cluster.flush(sim)
	push_counts()


func pile_height_at(x: float, z: float) -> float:
	return cluster.height_at(sim, x, z)


func refresh_solid() -> void:
	sim.solid = terrain.solid.duplicate()


# ---------------------------------------------------------------- guardado

func save_leaf_state() -> PackedByteArray:
	var arr := PackedInt32Array()
	arr.resize(sim.n + 1)
	arr[0] = sim.n
	for i in sim.n:
		var st := sim.state[i]
		if st == LeafSimulationSystem.S_REMOVED or st == LeafSimulationSystem.S_SUCKED:
			arr[i + 1] = -1
		else:
			var p := sim.pos[i]
			var xq := clampi(int((p.x - sim.ox) * 100.0), 0, 65534)
			var zq := clampi(int((p.z - sim.oz) * 100.0), 0, 65534)
			arr[i + 1] = xq | (zq << 16)
	return arr.to_byte_array()


func _apply_state(bytes: PackedByteArray) -> void:
	var arr := bytes.to_int32_array()
	if arr.size() != sim.n + 1 or arr[0] != sim.n:
		push_warning("Estado de hojas incompatible: se ignora.")
		return
	for i in sim.n:
		var v := arr[i + 1]
		if v == -1:
			sim.state[i] = LeafSimulationSystem.S_REMOVED
			continue
		var x := sim.ox + float(v & 0xFFFF) / 100.0
		var z := sim.oz + float((v >> 16) & 0xFFFF) / 100.0
		sim.pos[i] = Vector3(x, sim.height_at(x, z) + 0.015, z)
