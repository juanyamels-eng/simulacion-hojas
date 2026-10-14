class_name LeafManager
extends Node3D
## Orquesta el sistema de hojas: generación determinista, bloques de render con 3 niveles de detalle,
## distancia de dibujado, montones, recuentos por zona, ayudas visuales y guardado del estado.
##
## API para otros sistemas (herramientas, habilidades de zona, ajustes):
##   set_highlight(center, radius) / clear_highlight()   círculo de "lo que vas a coger": las hojas de
##        dentro se levantan unos cm y brillan (solo uniformes del shader: llamar cada fotograma es gratis).
##   highlight_grab(center, radius, max_n) -> float       igual, pero ajusta el radio a las max_n hojas más
##        cercanas (las que cogería sim.capture_nearest) y devuelve el radio usado (0 si no hay hojas).
##   set_reveal(on)                                       filtro «Resaltar hojas» (lo gobierna el ajuste
##        "highlight_leaves"; las habilidades pueden forzarlo con force_reveal).
##   set_zone_glow(zone_idx, amount)                      brillo manual de las hojas de una zona (0-1).
##        Además, cada zona con >= ZONE_GLOW_PCT % limpio hace brillar sola sus últimas hojas
##        (auto_zone_glow = false lo desactiva).
##   pile_height_at(x, z)                                  altura del montón (m) en un punto.
##   draw_distance()                                       distancia a la que dejan de dibujarse las hojas.

const P_HAND := 0
const P_VACUUM := 1
const P_DUCT0 := 2
const P_ROBOT := 12

const ZONE_GLOW_PCT := 95.0
const LEAF_SIZE := 0.32          # largo aproximado (m) de una hoja de escala 1 (uniforme leaf_size del shader)
const MAX_GLOW_ZONES := 24

# Paleta general de otoño [color, peso] (para partículas, decoración...).
const PALETTE := [
	[Color(0.97, 0.76, 0.18), 0.26],
	[Color(0.95, 0.5, 0.1), 0.3],
	[Color(0.86, 0.22, 0.08), 0.2],
	[Color(0.6, 0.33, 0.13), 0.17],
	[Color(0.62, 0.66, 0.2), 0.07],
]

# Especies: [peso, escala mínima, escala máxima, paleta [[color, peso]...]]. Orden = silueta de LeafMeshes:
# 0 arce, 1 roble, 2 abedul/álamo, 3 sauce, 4 ginkgo. Colores muy variados y saturados: destacan
# sobre el césped verde y sobre la piedra gris.
const SPECIES := [
	[0.34, 0.9, 1.25, [[Color(0.78, 0.1, 0.07), 0.18], [Color(0.9, 0.22, 0.07), 0.2], [Color(0.95, 0.4, 0.08), 0.22],
		[Color(0.97, 0.58, 0.1), 0.2], [Color(0.98, 0.76, 0.18), 0.12], [Color(0.62, 0.08, 0.1), 0.08]]],
	[0.22, 0.85, 1.2, [[Color(0.6, 0.26, 0.09), 0.24], [Color(0.74, 0.4, 0.14), 0.24], [Color(0.68, 0.18, 0.08), 0.2],
		[Color(0.5, 0.3, 0.13), 0.16], [Color(0.84, 0.54, 0.18), 0.16]]],
	[0.18, 0.78, 1.08, [[Color(0.98, 0.83, 0.2), 0.36], [Color(0.96, 0.68, 0.12), 0.3], [Color(0.84, 0.84, 0.28), 0.16],
		[Color(0.99, 0.9, 0.42), 0.18]]],
	[0.12, 0.85, 1.15, [[Color(0.72, 0.75, 0.22), 0.3], [Color(0.92, 0.8, 0.32), 0.3], [Color(0.55, 0.62, 0.18), 0.2],
		[Color(0.9, 0.6, 0.16), 0.2]]],
	[0.14, 0.75, 1.0, [[Color(1.0, 0.8, 0.1), 0.45], [Color(0.99, 0.88, 0.24), 0.35], [Color(0.96, 0.6, 0.08), 0.2]]],
]

# Distancias por calidad (m): detalle completo, versión simplificada, rombo lejano y fin del dibujado.
const QUALITY := {
	0: {"lod": 12.0, "far": 24.0, "draw": 46.0},
	1: {"lod": 18.0, "far": 34.0, "draw": 66.0},
	2: {"lod": 26.0, "far": 48.0, "draw": 95.0},
}

var sim := LeafSimulationSystem.new()
var cluster := LeafClusterSystem.new()
var terrain: Terrain
var material: ShaderMaterial
var leaf_mesh: ArrayMesh
var leaf_mesh_lod: ArrayMesh
var leaf_mesh_far: ArrayMesh
var site_tex: ImageTexture
var chunk_nodes: Array[MultiMeshInstance3D] = []
var chunk_lod := PackedByteArray()
var chunk_y := PackedFloat32Array()   # altura media del terreno de cada bloque
var zone_filter := ""
var orig_pos := PackedVector3Array()
var auto_zone_glow := true
var force_reveal := false
var _count_timer := 0.0
var _pile_timer := 0.0
var _lod_timer := 0.0
var _lod_dist := 18.0
var _far_dist := 34.0
var _draw_dist := 66.0
var _zone_glow := PackedFloat32Array()
var _zone_glow_manual := PackedFloat32Array()
var _glow_ids := Vector4.ZERO
var _glow_amt := Vector4.ZERO
var _highlight_on := false
var _reveal := false
var _grab_key := Vector4.INF
var _grab_r := 0.0
var _grab_t := 0


func _ready() -> void:
	process_priority = 50


func setup(t: Terrain, density_points: Array, saved: PackedByteArray, only_zone: String = "") -> void:
	terrain = t
	zone_filter = only_zone
	sim.setup_grid(t)
	cluster.setup(sim.gw, sim.gh)
	sim.cluster = cluster
	leaf_mesh = LeafMeshes.leaf_mesh()
	leaf_mesh_lod = LeafMeshes.leaf_mesh_lod()
	leaf_mesh_far = LeafMeshes.leaf_mesh_far()
	site_tex = _build_site_tex()
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/leaf.gdshader")
	material.set_shader_parameter("pile_tex", cluster.tex)
	material.set_shader_parameter("site_tex", site_tex)
	material.set_shader_parameter("vein_tex", LeafMeshes.vein_texture())
	material.set_shader_parameter("grid_rect", Vector4(sim.ox, sim.oz, 1.0 / (sim.gw / sim.inv_cell), 1.0 / (sim.gh / sim.inv_cell)))
	material.set_shader_parameter("grid_cells", Vector2(sim.gw, sim.gh))
	material.set_shader_parameter("cell_size", 1.0 / sim.inv_cell)
	material.set_shader_parameter("pile_max", LeafClusterSystem.PILE_MAX)
	material.set_shader_parameter("leaf_size", LEAF_SIZE)
	_zone_glow.resize(MAX_GLOW_ZONES)
	_zone_glow.fill(0.0)
	_zone_glow_manual.resize(MAX_GLOW_ZONES)
	_zone_glow_manual.fill(0.0)
	material.set_shader_parameter("glow_zones", Vector4.ZERO)
	material.set_shader_parameter("glow_amount", Vector4.ZERO)
	material.set_shader_parameter("highlight", Vector4(0.0, -1000.0, 0.0, 0.0))
	sim.create_chunk = _create_chunk_node
	chunk_nodes.resize(sim.cw * sim.ch)
	chunk_lod.resize(sim.cw * sim.ch)
	chunk_lod.fill(0)
	_chunk_heights()
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
	EventBus.settings_changed.connect(_on_settings_changed)
	_on_settings_changed()
	SaveManager.register_leaf_provider(self)
	refresh_allowed_zones()
	EventBus.zone_unlocked.connect(_on_zone_unlocked)
	push_counts()


func _exit_tree() -> void:
	SaveManager.unregister_leaf_provider(self)


## Textura estática por celda: RG = pendiente del terreno (0,5 = llano; ±2 en todo el rango) para que
## las hojas se apoyen inclinadas en las cuestas, B = zona + 1 (para el brillo de las últimas hojas).
func _build_site_tex() -> ImageTexture:
	var bytes := PackedByteArray()
	bytes.resize(sim.gw * sim.gh * 4)
	var hw := sim.hw
	var k := 0.5 * sim.inv_cell
	for iz in sim.gh:
		for ix in sim.gw:
			var b := iz * hw + ix
			var h00 := sim.heights[b]
			var h10 := sim.heights[b + 1]
			var h01 := sim.heights[b + hw]
			var h11 := sim.heights[b + hw + 1]
			var gx := ((h10 + h11) - (h00 + h01)) * k
			var gz := ((h01 + h11) - (h00 + h10)) * k
			var o := (iz * sim.gw + ix) * 4
			bytes[o] = clampi(int(round(127.5 + gx * 63.75)), 0, 255)
			bytes[o + 1] = clampi(int(round(127.5 + gz * 63.75)), 0, 255)
			bytes[o + 2] = sim.cell_zone[iz * sim.gw + ix]
			bytes[o + 3] = 255
	return ImageTexture.create_from_image(Image.create_from_data(sim.gw, sim.gh, false, Image.FORMAT_RGBA8, bytes))


## Altura mínima/máxima del terreno de cada bloque (cajas de recorte ajustadas y LOD en 3D).
var _chunk_hmin := PackedFloat32Array()
var _chunk_hmax := PackedFloat32Array()


func _chunk_heights() -> void:
	var n := sim.cw * sim.ch
	_chunk_hmin.resize(n)
	_chunk_hmax.resize(n)
	chunk_y.resize(n)
	_chunk_hmin.fill(1e9)
	_chunk_hmax.fill(-1e9)
	for iz in sim.gh + 1:
		var cz := mini(iz / LeafSimulationSystem.CHUNK_CELLS, sim.ch - 1)
		for ix in sim.hw:
			var cx := mini(ix / LeafSimulationSystem.CHUNK_CELLS, sim.cw - 1)
			var c := cz * sim.cw + cx
			var h := sim.heights[iz * sim.hw + ix]
			if h < _chunk_hmin[c]:
				_chunk_hmin[c] = h
			if h > _chunk_hmax[c]:
				_chunk_hmax[c] = h
	for c in n:
		chunk_y[c] = (_chunk_hmin[c] + _chunk_hmax[c]) * 0.5


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
	# Aspecto (no se guarda: puede cambiar sin romper partidas). Las posiciones de arriba sí son fijas.
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
		var tone := rng.randf_range(0.86, 1.06)
		col = Color(col.r * tone, col.g * tone * rng.randf_range(0.94, 1.06), col.b * tone * rng.randf_range(0.85, 1.1), 1.0)
		sim.colr[i] = col
		var code := (float(species) + rng.randf() * 0.96) / float(LeafMeshes.SHAPES)
		# Profundidad en un montón: más hojas cerca de la superficie (sqrt) para que se vea lleno.
		var depth := 0.05 + 0.95 * sqrt(rng.randf())
		sim.cust[i] = Color(rng.randf_range(float(spec[1]), float(spec[2])), rng.randf(), depth, code)


func _create_chunk_node(c: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = leaf_mesh
	var cx := c % sim.cw
	var cz := c / sim.cw
	var size := LeafSimulationSystem.CHUNK_CELLS / sim.inv_cell
	var x0 := sim.ox + cx * size
	var z0 := sim.oz + cz * size
	var y0 := _chunk_hmin[c] - 0.5
	var y1 := _chunk_hmax[c] + 5.0
	mm.custom_aabb = AABB(Vector3(x0 - 1.5, y0, z0 - 1.5), Vector3(size + 3.0, y1 - y0, size + 3.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	chunk_nodes[c] = mi
	chunk_lod[c] = 0
	return mm


func _apply_quality(level: int) -> void:
	var p: Dictionary = PerformanceManager.PRESETS[level]
	sim.max_active = int(p["active_leaves"])
	var q: Dictionary = QUALITY.get(level, QUALITY[1])
	_lod_dist = float(q["lod"])
	_far_dist = float(q["far"])
	_draw_dist = float(q["draw"])
	if material:
		material.set_shader_parameter("far_boost", Vector2(_lod_dist * 1.2, _draw_dist))
	_lod_timer = 1.0


func draw_distance() -> float:
	return _draw_dist


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		sim.focus = cam.global_position
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
		var w := sim.ambient_wind
		material.set_shader_parameter("wind", Vector2(w.x, w.z))


func push_counts() -> void:
	AreaManager.update_counts(sim.zone_counts, sim.zone_initial)
	_update_zone_glow()


func _update_lod() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var lod2 := _lod_dist * _lod_dist
	var far2 := _far_dist * _far_dist
	var draw2 := _draw_dist * _draw_dist
	var size := LeafSimulationSystem.CHUNK_CELLS / sim.inv_cell
	for c in chunk_nodes.size():
		var mi := chunk_nodes[c]
		if mi == null:
			continue
		var center := Vector3(sim.ox + (c % sim.cw + 0.5) * size, chunk_y[c], sim.oz + (c / sim.cw + 0.5) * size)
		var d2 := maxf(center.distance_squared_to(cp) - size * size * 0.5, 0.0)
		var vis := d2 < draw2 and sim.chunk_count[c] > 0
		if mi.visible != vis:
			mi.visible = vis
		var want := 0
		if d2 > far2:
			want = 2
		elif d2 > lod2:
			want = 1
		if vis and chunk_lod[c] != want:
			chunk_lod[c] = want
			mi.multimesh.mesh = leaf_mesh if want == 0 else (leaf_mesh_lod if want == 1 else leaf_mesh_far)


## Devuelve las hojas de una zona a su posición original.
func reset_zone(zi: int) -> void:
	for i in sim.n:
		if sim.zone_origin[i] == zi and sim.state[i] != LeafSimulationSystem.S_SUCKED:
			sim.restore_leaf(i, orig_pos[i])
	cluster.flush(sim)
	push_counts()


func _on_zone_unlocked(_zid: String) -> void:
	refresh_allowed_zones()


## Solo las zonas desbloqueadas permiten capturar hojas (no se recoge por encima de una valla cerrada).
func refresh_allowed_zones() -> void:
	for i in GameData.ZONES.size():
		sim.zone_allowed[i] = 1 if AreaManager.is_unlocked(GameData.ZONES[i]["id"]) else 0


func pile_height_at(x: float, z: float) -> float:
	return cluster.height_at(sim, x, z)


func refresh_solid() -> void:
	sim.solid = terrain.solid.duplicate()


# ---------------------------------------------------------------- ayudas visuales

## Resalta las hojas dentro de un círculo (se levantan unos cm y brillan). Solo uniformes del shader.
func set_highlight(center: Vector3, radius: float) -> void:
	if material == null:
		return
	material.set_shader_parameter("highlight", Vector4(center.x, center.y, center.z, maxf(radius, 0.0)))
	_highlight_on = radius > 0.0


func clear_highlight() -> void:
	if material == null or not _highlight_on:
		return
	material.set_shader_parameter("highlight", Vector4(0.0, -1000.0, 0.0, 0.0))
	_highlight_on = false


## Resalta justo las hojas que cogería sim.capture_nearest(center, radius, max_n): el radio se ajusta a
## las max_n más cercanas (se recalcula como mucho 10 veces por segundo o si el punto se mueve).
## Devuelve el radio usado (0 = no hay hojas que coger: no se resalta nada).
func highlight_grab(center: Vector3, radius: float, max_n: int) -> float:
	var key := Vector4(center.x, center.y, center.z, radius * 1000.0 + max_n)
	var now := Time.get_ticks_msec()
	if _grab_key == Vector4.INF or key.w != _grab_key.w or Vector3(key.x, key.y, key.z).distance_squared_to(Vector3(_grab_key.x, _grab_key.y, _grab_key.z)) > 0.0009 or now - _grab_t > 100:
		_grab_key = key
		_grab_t = now
		_grab_r = sim.nearest_radius(center, radius, max_n)
	if _grab_r <= 0.0:
		clear_highlight()
		return 0.0
	# Un poco de margen: la hoja n-ésima queda dentro del círculo.
	set_highlight(center, _grab_r * 1.08 + 0.03)
	return _grab_r


## Filtro «Resaltar hojas»: tinte saturado y contorno luminoso.
func set_reveal(on: bool) -> void:
	_reveal = on
	if material:
		material.set_shader_parameter("reveal", 1.0 if (on or force_reveal) else 0.0)


func _on_settings_changed() -> void:
	set_reveal(bool(SettingsManager.get_value("highlight_leaves", false)))


## Brillo manual de las hojas de una zona (0 = apagado, 1 = máximo). Se suma al automático.
func set_zone_glow(zone_idx: int, amount: float) -> void:
	if zone_idx < 0 or zone_idx >= MAX_GLOW_ZONES:
		return
	_zone_glow_manual[zone_idx] = clampf(amount, 0.0, 1.0)
	_update_zone_glow()


## Cada zona con >= ZONE_GLOW_PCT % limpio (y alguna hoja aún) hace brillar sus últimas hojas.
## El shader admite 4 zonas brillando a la vez: primero la zona donde está el jugador.
func _update_zone_glow() -> void:
	if material == null or _zone_glow.size() != MAX_GLOW_ZONES:
		return
	for i in mini(GameData.ZONES.size(), MAX_GLOW_ZONES):
		var target := _zone_glow_manual[i]
		if auto_zone_glow and i < sim.zone_initial.size():
			var init := sim.zone_initial[i]
			var left := sim.zone_counts[i]
			if init > 0 and left > 0 and (1.0 - float(left) / float(init)) * 100.0 >= ZONE_GLOW_PCT:
				target = maxf(target, 1.0)
		_zone_glow[i] = target
	var ids := Vector4.ZERO
	var amt := Vector4.ZERO
	var slot := 0
	var cur := GameData.zone_index(AreaManager.current_zone) if AreaManager.current_zone != "" else -1
	if cur >= 0 and cur < MAX_GLOW_ZONES and _zone_glow[cur] > 0.0:
		ids[0] = float(cur + 1)
		amt[0] = _zone_glow[cur]
		slot = 1
	for i in mini(GameData.ZONES.size(), MAX_GLOW_ZONES):
		if slot >= 4:
			break
		if i == cur or _zone_glow[i] <= 0.0:
			continue
		ids[slot] = float(i + 1)
		amt[slot] = _zone_glow[i]
		slot += 1
	if ids != _glow_ids or amt != _glow_amt:
		_glow_ids = ids
		_glow_amt = amt
		material.set_shader_parameter("glow_zones", ids)
		material.set_shader_parameter("glow_amount", amt)


func zone_glow(zone_idx: int) -> float:
	if zone_idx < 0 or zone_idx >= _zone_glow.size():
		return 0.0
	return _zone_glow[zone_idx]


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
