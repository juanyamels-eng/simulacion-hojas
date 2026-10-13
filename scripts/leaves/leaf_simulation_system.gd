class_name LeafSimulationSystem
extends RefCounted
## Datos y física de todas las hojas.
##
## Cada hoja es un registro ligero (arrays empaquetados). Las hojas en reposo no cuestan nada:
## solo las que toca una herramienta pasan a la lista "activa" y se simulan con física simple.
## La rejilla espacial (celdas de 0,5 m con listas enlazadas) permite consultas rápidas.
## El dibujado usa MultiMesh por bloques de 10 m: solo se actualizan las instancias que se mueven.

const S_REMOVED := 0
const S_SLEEP := 1
const S_AIR := 2
const S_SUCKED := 3

const CHUNK_CELLS := 20
const STRIDE := 4096
const GRAV := 9.8
const SUCK_POINTS := 16
const MAX_WIND := 4

# --- Datos por hoja ---
var n := 0
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var yaw := PackedFloat32Array()
var spin := PackedFloat32Array()
var state := PackedByteArray()
var zone_origin := PackedByteArray()
var cell := PackedInt32Array()
var nxt := PackedInt32Array()
var prv := PackedInt32Array()
var sleep_t := PackedFloat32Array()
var colr := PackedColorArray()
var cust := PackedColorArray()
var lchunk := PackedInt32Array()
var lslot := PackedInt32Array()
var aux := PackedInt32Array()

# --- Rejilla ---
var gw := 0
var gh := 0
var hw := 0
var ox := 0.0
var oz := 0.0
var inv_cell := 2.0
var heights := PackedFloat32Array()
var solid := PackedByteArray()
var cell_zone := PackedByteArray()
var cell_head := PackedInt32Array()
var cell_count := PackedInt32Array()
var zone_counts := PackedInt32Array()
var zone_initial := PackedInt32Array()
var zone_values := PackedFloat32Array()

# Caja de celdas modificadas (para regenerar la textura de montones).
var dirty := false
var d_x0 := 0
var d_z0 := 0
var d_x1 := 0
var d_z1 := 0

# --- Lista activa ---
var active := PackedInt32Array()
var active_idx := PackedInt32Array()
var active_n := 0
var max_active := 750

# --- Render ---
var cw := 0
var ch := 0
var chunk_rid: Array[RID] = []
var chunk_mm: Array[MultiMesh] = []
var chunk_count := PackedInt32Array()
var chunk_cap := PackedInt32Array()
var slot_leaf := PackedInt32Array()
var btab: Array[Basis] = []
var create_chunk: Callable      # (chunk_index, capacity) -> MultiMesh

# --- Viento y succión ---
var wind_n := 0
var wind_o := PackedVector3Array()
var wind_d := PackedVector3Array()
var wind_p := PackedFloat32Array()   # rango, cos(medio ángulo), potencia, turbulencia
var suck_pos := PackedVector3Array()
var suck_acc := PackedFloat32Array()
var arrived_count := PackedInt32Array()
var arrived_value := PackedFloat32Array()
var in_flight := PackedInt32Array()
var ambient_wind := Vector3.ZERO

var time := 0.0
var rake_carry := 0.0


func _init() -> void:
	for y in 32:
		var by := Basis(Vector3.UP, y * TAU / 32.0)
		btab.append(by * Basis(Vector3.RIGHT, 0.06))
		btab.append(by * Basis(Vector3.RIGHT, -0.09) * Basis(Vector3.FORWARD, 0.06))
		btab.append(by * Basis(Vector3.FORWARD, 0.11))
		btab.append(by * Basis(Vector3.RIGHT, 0.13) * Basis(Vector3.FORWARD, -0.08))
		btab.append(by * Basis(Vector3.RIGHT, 0.65))
		btab.append(by * Basis(Vector3.FORWARD, 1.15))
		btab.append(by * Basis(Vector3.RIGHT, 1.8))
		btab.append(by * Basis(Vector3.FORWARD, 2.5) * Basis(Vector3.RIGHT, 0.5))
	wind_o.resize(MAX_WIND)
	wind_d.resize(MAX_WIND)
	wind_p.resize(MAX_WIND * 4)
	suck_pos.resize(SUCK_POINTS)
	suck_acc.resize(SUCK_POINTS)
	suck_acc.fill(20.0)
	arrived_count.resize(SUCK_POINTS)
	arrived_value.resize(SUCK_POINTS)
	in_flight.resize(SUCK_POINTS)


func setup_grid(terrain: Terrain) -> void:
	gw = terrain.gw
	gh = terrain.gh
	hw = terrain.hw
	ox = terrain.origin.x
	oz = terrain.origin.y
	inv_cell = terrain.inv_cell
	heights = terrain.heights
	solid = terrain.solid.duplicate()
	cell_zone = terrain.cell_zone
	cell_head.resize(gw * gh)
	cell_head.fill(-1)
	cell_count.resize(gw * gh)
	cell_count.fill(0)
	var nz := GameData.ZONES.size()
	zone_counts.resize(nz)
	zone_counts.fill(0)
	zone_initial.resize(nz)
	zone_initial.fill(0)
	zone_values.resize(nz)
	for i in nz:
		zone_values[i] = float(GameData.ZONES[i]["value"])
	cw = int(ceil(float(gw) / CHUNK_CELLS))
	ch = int(ceil(float(gh) / CHUNK_CELLS))
	chunk_rid.resize(cw * ch)
	chunk_mm.resize(cw * ch)
	chunk_count.resize(cw * ch)
	chunk_count.fill(0)
	chunk_cap.resize(cw * ch)
	chunk_cap.fill(0)
	slot_leaf.resize(cw * ch * STRIDE)


func allocate(count: int) -> void:
	n = count
	pos.resize(n)
	vel.resize(n)
	yaw.resize(n)
	spin.resize(n)
	state.resize(n)
	state.fill(S_SLEEP)
	zone_origin.resize(n)
	cell.resize(n)
	cell.fill(-1)
	nxt.resize(n)
	prv.resize(n)
	sleep_t.resize(n)
	colr.resize(n)
	cust.resize(n)
	lchunk.resize(n)
	lchunk.fill(-1)
	lslot.resize(n)
	aux.resize(n)
	active.resize(n)
	active_idx.resize(n)
	active_idx.fill(-1)


# ---------------------------------------------------------------- utilidades de rejilla

func cell_index(x: float, z: float) -> int:
	if x < ox or z < oz:
		return -1
	var ix := int((x - ox) * inv_cell)
	var iz := int((z - oz) * inv_cell)
	if ix >= gw or iz >= gh:
		return -1
	return iz * gw + ix


func height_at(x: float, z: float) -> float:
	var fx := clampf((x - ox) * inv_cell, 0.0, gw - 0.001)
	var fz := clampf((z - oz) * inv_cell, 0.0, gh - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var b := iz * hw + ix
	return (heights[b] * (1.0 - tx) + heights[b + 1] * tx) * (1.0 - tz) + (heights[b + hw] * (1.0 - tx) + heights[b + hw + 1] * tx) * tz


func chunk_of_cell(c: int) -> int:
	return (c / gw / CHUNK_CELLS) * cw + (c % gw) / CHUNK_CELLS


func _mark_dirty(c: int) -> void:
	var ix := c % gw
	var iz := c / gw
	if not dirty:
		dirty = true
		d_x0 = ix
		d_x1 = ix
		d_z0 = iz
		d_z1 = iz
		return
	if ix < d_x0: d_x0 = ix
	if ix > d_x1: d_x1 = ix
	if iz < d_z0: d_z0 = iz
	if iz > d_z1: d_z1 = iz


func link_cell(i: int, c: int) -> void:
	var h := cell_head[c]
	nxt[i] = h
	prv[i] = -1
	if h >= 0:
		prv[h] = i
	cell_head[c] = i
	cell_count[c] += 1
	var z := cell_zone[c]
	if z > 0:
		zone_counts[z - 1] += 1
	cell[i] = c
	_mark_dirty(c)


func unlink_cell(i: int) -> void:
	var c := cell[i]
	if c < 0:
		return
	var p := prv[i]
	var nx := nxt[i]
	if p >= 0:
		nxt[p] = nx
	else:
		cell_head[c] = nx
	if nx >= 0:
		prv[nx] = p
	cell_count[c] -= 1
	var z := cell_zone[c]
	if z > 0:
		zone_counts[z - 1] -= 1
	cell[i] = -1
	_mark_dirty(c)


func _set_cell(i: int, c: int) -> void:
	unlink_cell(i)
	link_cell(i, c)
	var nc := chunk_of_cell(c)
	if nc != lchunk[i]:
		_move_chunk(i, nc)


# ---------------------------------------------------------------- render

func leaf_xform(i: int) -> Transform3D:
	var yi := int(yaw[i] * 5.0929582) & 31
	var t := i & 3
	if state[i] != S_SLEEP:
		t = 4 + ((int(time * 7.0) + i) & 3)
	return Transform3D(btab[yi * 8 + t], pos[i])


## Construye los buffers iniciales de todos los bloques (tras generar o cargar).
func build_render() -> void:
	chunk_count.fill(0)
	for i in n:
		if state[i] == S_REMOVED or cell[i] < 0:
			continue
		var c := chunk_of_cell(cell[i])
		var s := chunk_count[c]
		if s >= STRIDE:
			continue
		slot_leaf[c * STRIDE + s] = i
		lchunk[i] = c
		lslot[i] = s
		chunk_count[c] = s + 1
	for c in cw * ch:
		if chunk_count[c] > 0:
			_rebuild_chunk(c, maxi(64, nearest_po2(chunk_count[c] + chunk_count[c] / 2 + 8)))


func _rebuild_chunk(c: int, cap: int) -> void:
	cap = mini(cap, STRIDE)
	var mm: MultiMesh = chunk_mm[c]
	if mm == null:
		mm = create_chunk.call(c)
		chunk_mm[c] = mm
		chunk_rid[c] = mm.get_rid()
	var cnt := chunk_count[c]
	var buf := PackedFloat32Array()
	buf.resize(cap * 20)
	var base := c * STRIDE
	for s in cnt:
		var i := slot_leaf[base + s]
		var t := leaf_xform(i)
		var b := t.basis
		var o := t.origin
		var cl := colr[i]
		var cu := cust[i]
		var k := s * 20
		buf[k] = b.x.x
		buf[k + 1] = b.y.x
		buf[k + 2] = b.z.x
		buf[k + 3] = o.x
		buf[k + 4] = b.x.y
		buf[k + 5] = b.y.y
		buf[k + 6] = b.z.y
		buf[k + 7] = o.y
		buf[k + 8] = b.x.z
		buf[k + 9] = b.y.z
		buf[k + 10] = b.z.z
		buf[k + 11] = o.z
		buf[k + 12] = cl.r
		buf[k + 13] = cl.g
		buf[k + 14] = cl.b
		buf[k + 15] = cl.a
		buf[k + 16] = cu.r
		buf[k + 17] = cu.g
		buf[k + 18] = cu.b
		buf[k + 19] = cu.a
	mm.instance_count = cap
	mm.buffer = buf
	mm.visible_instance_count = cnt
	chunk_cap[c] = cap


func _move_chunk(i: int, nc: int) -> void:
	if chunk_count[nc] >= STRIDE:
		return
	if lchunk[i] >= 0:
		_remove_from_chunk(i)
	if chunk_count[nc] >= chunk_cap[nc]:
		chunk_count[nc] += 1
		slot_leaf[nc * STRIDE + chunk_count[nc] - 1] = i
		lchunk[i] = nc
		lslot[i] = chunk_count[nc] - 1
		_rebuild_chunk(nc, maxi(64, chunk_cap[nc] * 2))
		return
	var s := chunk_count[nc]
	slot_leaf[nc * STRIDE + s] = i
	lchunk[i] = nc
	lslot[i] = s
	chunk_count[nc] = s + 1
	var rid := chunk_rid[nc]
	RenderingServer.multimesh_instance_set_transform(rid, s, leaf_xform(i))
	RenderingServer.multimesh_instance_set_color(rid, s, colr[i])
	RenderingServer.multimesh_instance_set_custom_data(rid, s, cust[i])
	RenderingServer.multimesh_set_visible_instances(rid, s + 1)


func _remove_from_chunk(i: int) -> void:
	var c := lchunk[i]
	if c < 0:
		return
	var s := lslot[i]
	var last := chunk_count[c] - 1
	var rid := chunk_rid[c]
	if s != last:
		var j := slot_leaf[c * STRIDE + last]
		slot_leaf[c * STRIDE + s] = j
		lslot[j] = s
		RenderingServer.multimesh_instance_set_transform(rid, s, leaf_xform(j))
		RenderingServer.multimesh_instance_set_color(rid, s, colr[j])
		RenderingServer.multimesh_instance_set_custom_data(rid, s, cust[j])
	chunk_count[c] = last
	RenderingServer.multimesh_set_visible_instances(rid, last)
	lchunk[i] = -1


func set_leaf_color(i: int, c: Color) -> void:
	colr[i] = c
	if lchunk[i] >= 0:
		RenderingServer.multimesh_instance_set_color(chunk_rid[lchunk[i]], lslot[i], c)


# ---------------------------------------------------------------- estados

func _activate(i: int) -> bool:
	if active_idx[i] >= 0:
		return true
	if active_n >= max_active:
		return false
	active[active_n] = i
	active_idx[i] = active_n
	active_n += 1
	sleep_t[i] = 0.0
	return true


func _deactivate(i: int) -> void:
	var k := active_idx[i]
	if k < 0:
		return
	var last := active[active_n - 1]
	active[k] = last
	active_idx[last] = k
	active_idx[i] = -1
	active_n -= 1


func wake(i: int, v: Vector3) -> bool:
	if state[i] != S_SLEEP:
		if state[i] == S_AIR:
			vel[i] += v * 0.5
		return state[i] == S_AIR
	if not _activate(i):
		return false
	state[i] = S_AIR
	vel[i] = v
	spin[i] = randf_range(-9.0, 9.0)
	return true


func _sleep(i: int) -> void:
	_deactivate(i)
	state[i] = S_SLEEP
	vel[i] = Vector3.ZERO
	var p := pos[i]
	p.y = height_at(p.x, p.z) + 0.015
	pos[i] = p
	if lchunk[i] >= 0:
		RenderingServer.multimesh_instance_set_transform(chunk_rid[lchunk[i]], lslot[i], leaf_xform(i))


## Captura una hoja hacia un punto de succión (mano, aspiradora, conducto...).
func capture(i: int, point: int, start_speed: float) -> void:
	var st := state[i]
	if st == S_REMOVED or st == S_SUCKED:
		return
	unlink_cell(i)
	in_flight[point] += 1
	if not _activate(i):
		_arrive(i, point)
		return
	state[i] = S_SUCKED
	aux[i] = point
	vel[i] = Vector3(start_speed, 0.0, 0.0)


func _arrive(i: int, point: int) -> void:
	arrived_count[point] += 1
	arrived_value[point] += zone_values[zone_origin[i]]
	in_flight[point] -= 1
	remove_leaf(i)


func remove_leaf(i: int) -> void:
	if state[i] == S_REMOVED:
		return
	_deactivate(i)
	unlink_cell(i)
	_remove_from_chunk(i)
	state[i] = S_REMOVED


func restore_leaf(i: int, p: Vector3) -> void:
	var was_removed := state[i] == S_REMOVED
	_deactivate(i)
	state[i] = S_SLEEP
	vel[i] = Vector3.ZERO
	pos[i] = p
	var c := cell_index(p.x, p.z)
	if c < 0:
		return
	if was_removed:
		link_cell(i, c)
		_move_chunk(i, chunk_of_cell(c))
	else:
		if c != cell[i]:
			_set_cell(i, c)
		if lchunk[i] >= 0:
			RenderingServer.multimesh_instance_set_transform(chunk_rid[lchunk[i]], lslot[i], leaf_xform(i))


## Mueve una hoja en reposo sin despertarla (rastrillo, empujes masivos).
func move_sleeping(i: int, p: Vector3) -> void:
	pos[i] = p
	var c := cell_index(p.x, p.z)
	if c >= 0 and c != cell[i]:
		_set_cell(i, c)
	if lchunk[i] >= 0:
		RenderingServer.multimesh_instance_set_transform(chunk_rid[lchunk[i]], lslot[i], leaf_xform(i))


# ---------------------------------------------------------------- simulación

func add_wind(origin: Vector3, dir: Vector3, rng: float, cos_half: float, power: float, turb: float) -> void:
	if wind_n >= MAX_WIND:
		return
	wind_o[wind_n] = origin
	wind_d[wind_n] = dir
	var k := wind_n * 4
	wind_p[k] = rng
	wind_p[k + 1] = cos_half
	wind_p[k + 2] = power
	wind_p[k + 3] = turb
	wind_n += 1


func simulate(dt: float) -> void:
	time += dt
	var air_drag := exp(-1.4 * dt)
	var ground_fric := exp(-6.5 * dt)
	var gdt := GRAV * dt
	var k := 0
	while k < active_n:
		var i := active[k]
		var st := state[i]
		if st == S_SUCKED:
			var pt := aux[i]
			var sp := pos[i]
			var sd := suck_pos[pt] - sp
			var dist := sd.length()
			var spd := vel[i].x + suck_acc[pt] * dt
			if dist < 0.3 or spd * dt >= dist:
				_arrive(i, pt)
				continue
			var dn := sd / dist
			# Pequeño remolino alrededor del eje de succión.
			var swirl := Vector3(-dn.z, 0.0, dn.x) * sin(time * 9.0 + i) * minf(dist, 1.5) * 0.9
			sp += (dn * spd + swirl) * dt
			vel[i] = Vector3(spd, 0.0, 0.0)
			pos[i] = sp
			yaw[i] += 14.0 * dt
			if lchunk[i] >= 0:
				RenderingServer.multimesh_instance_set_transform(chunk_rid[lchunk[i]], lslot[i], Transform3D(btab[(int(yaw[i] * 5.0929582) & 31) * 8 + 4 + ((int(time * 9.0) + i) & 3)], sp))
			k += 1
			continue
		var p := pos[i]
		var v := vel[i]
		for w in wind_n:
			var rel := p - wind_o[w]
			var wd := wind_d[w]
			var along := rel.dot(wd)
			var wr := wind_p[w * 4]
			if along > 0.0 and along < wr:
				var dl := rel.length()
				if dl > 0.01 and along / dl > wind_p[w * 4 + 1]:
					var f := wind_p[w * 4 + 2] * (1.0 - along / wr * 0.7)
					var tb := wind_p[w * 4 + 3]
					v += (wd * f + Vector3(sin(i * 1.7 + time * 8.0) * tb, f * 0.28 + absf(sin(i * 3.1 + time * 5.0)) * tb, cos(i * 2.3 + time * 7.0) * tb)) * dt
		v.y -= gdt
		v *= air_drag
		if v.y < -2.2:
			v.y = lerpf(v.y, -2.2, 0.25)
		# Aleteo al caer: las hojas planean en vez de caer como piedras.
		if v.y < 0.0:
			v.x += sin(time * 4.3 + i) * 1.6 * dt + ambient_wind.x * dt
			v.z += cos(time * 3.7 + i * 0.7) * 1.6 * dt + ambient_wind.z * dt
		var np := p + v * dt
		var c := cell_index(np.x, np.z)
		if c < 0 or solid[c] != 0:
			np.x = p.x
			np.z = p.z
			v.x *= -0.3
			v.z *= -0.3
			c = cell[i]
			if c < 0:
				c = cell_index(np.x, np.z)
		var fx := (np.x - ox) * inv_cell
		var fz := (np.z - oz) * inv_cell
		var ix := int(fx)
		var iz := int(fz)
		var tx := fx - ix
		var tz := fz - iz
		var b := iz * hw + ix
		var h00 := heights[b]
		var h10 := heights[b + 1]
		var h01 := heights[b + hw]
		var h11 := heights[b + hw + 1]
		var gy := (h00 * (1.0 - tx) + h10 * tx) * (1.0 - tz) + (h01 * (1.0 - tx) + h11 * tx) * tz + 0.015
		var grounded := false
		if np.y <= gy:
			np.y = gy
			if v.y < -1.5:
				v.y = -v.y * 0.12
			else:
				v.y = 0.0
			v.x *= ground_fric
			v.z *= ground_fric
			# Pendientes: las hojas sueltas ruedan cuesta abajo.
			v.x -= (h10 - h00) * inv_cell * 2.2 * dt
			v.z -= (h01 - h00) * inv_cell * 2.2 * dt
			grounded = true
		pos[i] = np
		vel[i] = v
		if c >= 0 and c != cell[i]:
			_set_cell(i, c)
		spin[i] *= 0.985
		yaw[i] += spin[i] * dt
		if grounded and v.x * v.x + v.z * v.z < 0.05:
			sleep_t[i] += dt
			if sleep_t[i] > 0.3:
				_sleep(i)
				continue
		else:
			sleep_t[i] = 0.0
		if lchunk[i] >= 0:
			var t := (i & 3) if grounded else 4 + ((int(time * 7.0) + i) & 3)
			RenderingServer.multimesh_instance_set_transform(chunk_rid[lchunk[i]], lslot[i], Transform3D(btab[(int(yaw[i] * 5.0929582) & 31) * 8 + t], np))
		k += 1
	wind_n = 0


# ---------------------------------------------------------------- consultas para herramientas

func _cell_range(center: Vector3, radius: float) -> Rect2i:
	var x0 := clampi(int((center.x - radius - ox) * inv_cell), 0, gw - 1)
	var x1 := clampi(int((center.x + radius - ox) * inv_cell), 0, gw - 1)
	var z0 := clampi(int((center.z - radius - oz) * inv_cell), 0, gh - 1)
	var z1 := clampi(int((center.z + radius - oz) * inv_cell), 0, gh - 1)
	return Rect2i(x0, z0, x1 - x0, z1 - z0)


## Captura las hojas más cercanas a un punto (recogida con la mano). Devuelve cuántas.
func capture_nearest(center: Vector3, radius: float, max_n: int, point: int, speed: float) -> int:
	var r := _cell_range(center, radius)
	var r2 := radius * radius
	var best_i := PackedInt32Array()
	var best_d := PackedFloat32Array()
	for iz in range(r.position.y, r.end.y + 1):
		for ix in range(r.position.x, r.end.x + 1):
			var c := iz * gw + ix
			if cell_count[c] == 0:
				continue
			var li := cell_head[c]
			while li >= 0:
				var st := state[li]
				if st == S_SLEEP or st == S_AIR:
					var d := pos[li] - center
					d.y *= 0.5
					var d2 := d.length_squared()
					if d2 <= r2:
						if best_i.size() < max_n:
							best_i.append(li)
							best_d.append(d2)
						else:
							var worst := 0
							for q in range(1, best_d.size()):
								if best_d[q] > best_d[worst]:
									worst = q
							if d2 < best_d[worst]:
								best_i[worst] = li
								best_d[worst] = d2
				li = nxt[li]
	for li in best_i:
		capture(li, point, speed)
	return best_i.size()


## Captura hojas dentro de un radio (aspiradora, conductos, robot), hasta max_n.
func capture_radius(center: Vector3, radius: float, max_n: int, point: int, speed: float, min_y: float = -999.0) -> int:
	if max_n <= 0:
		return 0
	var r := _cell_range(center, radius)
	var r2 := radius * radius
	var got := 0
	for iz in range(r.position.y, r.end.y + 1):
		for ix in range(r.position.x, r.end.x + 1):
			var c := iz * gw + ix
			if cell_count[c] == 0:
				continue
			var li := cell_head[c]
			while li >= 0:
				var nx := nxt[li]
				var st := state[li]
				if (st == S_SLEEP or st == S_AIR) and pos[li].y >= min_y:
					var d := pos[li] - center
					d.y = 0.0
					if d.length_squared() <= r2:
						capture(li, point, speed)
						got += 1
						if got >= max_n:
							return got
				li = nx
	return got


## Despierta hojas en reposo dentro de un cono de aire (soplador). Recorre de cerca a lejos.
func blow_wake(origin: Vector3, dir: Vector3, rng: float, half_angle: float, power: float, max_new: int) -> int:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return 0
	flat = flat.normalized()
	var side := Vector3(-flat.z, 0.0, flat.x)
	var cos_half := cos(half_angle)
	var tan_half := tan(half_angle)
	var woke := 0
	var along := 0.25
	while along < rng and woke < max_new:
		var half_w := along * tan_half + 0.3
		var lat := -half_w
		while lat <= half_w:
			var q := origin + flat * along + side * lat
			var c := cell_index(q.x, q.z)
			lat += 0.5
			if c < 0 or cell_count[c] == 0:
				continue
			var li := cell_head[c]
			while li >= 0:
				var nx := nxt[li]
				if state[li] == S_SLEEP:
					var rel := pos[li] - origin
					rel.y = 0.0
					var dl := rel.length()
					if dl > 0.01 and rel.dot(flat) / dl > cos_half * 0.92:
						var f := power * (1.0 - along / rng * 0.6)
						var v := flat * f * randf_range(0.35, 0.7) + Vector3(randf_range(-0.6, 0.6), f * randf_range(0.15, 0.4) + 0.8, randf_range(-0.6, 0.6))
						if wake(li, v):
							woke += 1
							if woke >= max_new:
								return woke
						else:
							return woke
				li = nx
		along += 0.5
	return woke


## Empuje masivo sin física (soplador industrial): desplaza hojas en reposo dentro del cono.
func shove_cone(origin: Vector3, dir: Vector3, rng: float, half_angle: float, amount: float, max_n: int) -> int:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var side := Vector3(-flat.z, 0.0, flat.x)
	var tan_half := tan(half_angle)
	var moved := 0
	var along := rng
	# De lejos a cerca, para no empujar dos veces la misma hoja.
	while along > 0.5 and moved < max_n:
		var half_w := along * tan_half + 0.3
		var lat := -half_w
		while lat <= half_w:
			var q := origin + flat * along + side * lat
			var c := cell_index(q.x, q.z)
			lat += 0.5
			if c < 0 or cell_count[c] == 0:
				continue
			var li := cell_head[c]
			while li >= 0:
				var nx := nxt[li]
				if state[li] == S_SLEEP:
					var step := amount * (1.0 - along / rng * 0.5) * (0.6 + 0.4 * fposmod(li * 0.618, 1.0))
					var p := pos[li] + flat * step + side * sin(li + time * 3.0) * step * 0.3
					var c2 := cell_index(p.x, p.z)
					if c2 >= 0 and solid[c2] == 0:
						p.y = height_at(p.x, p.z) + 0.015
						move_sleeping(li, p)
						moved += 1
						if moved >= max_n:
							return moved
				li = nx
		along -= 0.5
	return moved


## Rastrillo: barre las hojas que atraviesa el cabezal y las acumula delante de él.
func rake_sweep(prev_c: Vector3, cur_c: Vector3, right: Vector3, width: float, capacity: int, grip: float, seed: int) -> int:
	var m := cur_c - prev_c
	m.y = 0.0
	var ml := m.length()
	if ml < 0.002:
		return 0
	var nd := m / ml
	var half := width * 0.5
	var bb := Rect2(Vector2(prev_c.x, prev_c.z), Vector2.ZERO)
	for corner in [prev_c + right * half, prev_c - right * half, cur_c + right * half, cur_c - right * half]:
		bb = bb.expand(Vector2(corner.x, corner.z))
	bb = bb.grow(0.4)
	var x0 := clampi(int((bb.position.x - ox) * inv_cell), 0, gw - 1)
	var x1 := clampi(int((bb.end.x - ox) * inv_cell), 0, gw - 1)
	var z0 := clampi(int((bb.position.y - oz) * inv_cell), 0, gh - 1)
	var z1 := clampi(int((bb.end.y - oz) * inv_cell), 0, gh - 1)
	var depth := 0.06 + rake_carry / (width * 260.0)
	var moved := 0
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var c := iz * gw + ix
			if cell_count[c] == 0:
				continue
			var li := cell_head[c]
			while li >= 0:
				var nx := nxt[li]
				if state[li] == S_SLEEP:
					var rel := pos[li] - cur_c
					var lat := rel.dot(right)
					var fwd := rel.x * nd.x + rel.z * nd.z
					if absf(lat) <= half and fwd <= 0.03 and fwd >= -(ml + 0.2):
						var hsh := fposmod(sin(float(li * 13 + seed) * 12.9898) * 43758.5453, 1.0)
						if moved < capacity and hsh < grip:
							var spill := 0.0
							if absf(lat) > half * 0.82:
								spill = signf(lat) * 0.05
							var np := cur_c + right * (lat + spill) + nd * (0.04 + fposmod(hsh * 7.31, 1.0) * depth)
							var c2 := cell_index(np.x, np.z)
							if c2 >= 0 and solid[c2] == 0:
								np.y = height_at(np.x, np.z) + 0.015
								move_sleeping(li, np)
								moved += 1
								# Algunas hojas saltan un poco: da vida al barrido.
								if hsh < 0.025:
									wake(li, nd * 1.2 + Vector3(0, 1.4, 0))
				li = nx
	rake_carry = lerpf(rake_carry, float(moved) * 6.0, 0.15)
	return moved


## Patada/explosión: despierta hojas cercanas con un impulso (caminar, saltar en un montón).
func kick(center: Vector3, radius: float, push: Vector3, up: float, max_n: int, radial: float = 0.0) -> int:
	var r := _cell_range(center, radius)
	var r2 := radius * radius
	var got := 0
	for iz in range(r.position.y, r.end.y + 1):
		for ix in range(r.position.x, r.end.x + 1):
			var c := iz * gw + ix
			if cell_count[c] == 0:
				continue
			var li := cell_head[c]
			while li >= 0:
				var nx := nxt[li]
				if state[li] == S_SLEEP:
					var d := pos[li] - center
					d.y = 0.0
					var d2 := d.length_squared()
					if d2 <= r2:
						var fall := 1.0 - sqrt(d2) / radius
						var v := push * fall + Vector3(0.0, up * (0.5 + fall) * randf_range(0.6, 1.2), 0.0)
						if radial != 0.0 and d2 > 0.0001:
							v += d.normalized() * radial * fall
						v += Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
						if not wake(li, v):
							return got
						got += 1
						if got >= max_n:
							return got
				li = nx
	return got


func count_in_radius(center: Vector3, radius: float) -> int:
	var r := _cell_range(center, radius)
	var total := 0
	for iz in range(r.position.y, r.end.y + 1):
		for ix in range(r.position.x, r.end.x + 1):
			total += cell_count[iz * gw + ix]
	return total


## Posiciones de hojas restantes en una zona (para el "radar" de las últimas hojas).
func remaining_in_zone(zone_idx: int, max_n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var rect: Rect2 = GameData.ZONES[zone_idx]["rect"]
	var x0 := clampi(int((rect.position.x - ox) * inv_cell), 0, gw - 1)
	var x1 := clampi(int((rect.end.x - ox) * inv_cell), 0, gw - 1)
	var z0 := clampi(int((rect.position.y - oz) * inv_cell), 0, gh - 1)
	var z1 := clampi(int((rect.end.y - oz) * inv_cell), 0, gh - 1)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var c := iz * gw + ix
			if cell_count[c] == 0 or cell_zone[c] != zone_idx + 1:
				continue
			var li := cell_head[c]
			while li >= 0:
				out.append(pos[li])
				if out.size() >= max_n:
					return out
				li = nxt[li]
	return out


func take_arrived(point: int) -> Vector2:
	var r := Vector2(arrived_count[point], arrived_value[point])
	arrived_count[point] = 0
	arrived_value[point] = 0.0
	return r
