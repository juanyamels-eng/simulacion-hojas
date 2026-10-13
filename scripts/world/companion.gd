class_name Companion
extends Interactable
## Bellota, la perrita de la casa de al lado (diseño original, hecha con primitivas).
## Te sigue a una distancia cómoda sin estorbar (no bloquea al jugador ni las bolsas),
## se sienta y mueve la cola cuando paras, de vez en cuando corre a lanzarse a un montón
## de hojas grande, olfatea postales escondidas cerca y se deja acariciar con INTERACTUAR.
## Todo el modelo son 7 mallas con un único material de color por vértice.

enum { IDLE, FOLLOW, TO_PILE, LEAP, PLAY, TO_SNIFF, SNIFF, PETTED }

const COAT := Color(0.8, 0.52, 0.27)
const COAT_DARK := Color(0.52, 0.31, 0.16)
const CREAM := Color(0.98, 0.89, 0.74)
const DARK := Color(0.1, 0.07, 0.05)
const SCARF := Color(0.86, 0.36, 0.22)
const TAG := Color(0.98, 0.8, 0.32)
const HIP_Y := 0.33

var lm: LeafManager
var player: PlayerController
var world: World
var cfg: Dictionary = GameData.COMPANION
var state := IDLE
var pets := 0
var pile_jumps := 0
var leaves_scattered := 0
var sniffs := 0
var hint_id := ""
var target_pile := Vector3.INF

var _vel := Vector3.ZERO
var _yaw := 0.0
var _phase := 0.0
var _sit := 0.0
var _wag := 0.4
var _happy := 0.0
var _state_t := 0.0
var _idle_t := 0.0
var _behind_t := 0.0
var _pile_cd := 0.0
var _sniff_cd := 0.0
var _think := 1.0
var _side := 1.0
var _slot_view := false
var _goal := Vector3.ZERO
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
var _stuck := 0.0
var _kick_t := 0.0
var _pet_cd := 0.0
var _bark_cd := 0.0
var _quirk_t := 6.0
var _quirk := 0
var _quirk_left := 0.0
var _look_yaw := 0.0
var _hop := 0.0
var _hop_v := 0.0
var _met_t := 0.0
var _hint_until := 0.0
var _sniff_target: Node3D
var _postcards: Array = []   # sin tipo: las postales recogidas se liberan (queue_free)

var _root: Node3D
var _body: Node3D
var _head: Node3D
var _tail: Node3D
var _legs: Array[Node3D] = []
var _hearts: CPUParticles3D


func setup(w: World, leaf_manager: LeafManager, p: PlayerController) -> void:
	world = w
	lm = leaf_manager
	player = p
	collision_layer = LAYER_INTERACT
	collision_mask = 0
	make_shape(self, Vector3(0.5, 0.65, 0.95), Vector3(0, 0.38, -0.05))
	_build_model()
	var pc := cfg["pile_cooldown"] as Array
	_pile_cd = randf_range(float(pc[0]) * 0.4, float(pc[0]) * 0.7)
	_sniff_cd = 20.0
	for c in w.get_children():
		if c is StationObject:
			var so := c as StationObject
			if so.kind == StationObject.Kind.POSTCARD:
				_postcards.append(so)
	if w.builder:
		for s in w.builder.stations:
			if s.kind == StationObject.Kind.HATCH:
				_postcards.append(s)
	EventBus.collectible_found.connect(_on_collectible)
	EventBus.zone_completed.connect(_on_celebrate)
	EventBus.gate_opened.connect(_on_gate)
	place_near_player(true)


# ------------------------------------------------------------------ modelo

static var _vc_mat: StandardMaterial3D


## Material único con color por vértice (compartido por Bellota y el guante).
static func vertex_color_material() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.vertex_color_is_srgb = true
		_vc_mat.roughness = 0.88
		_vc_mat.metallic_specular = 0.25
	return _vc_mat


func _build_model() -> void:
	var m := vertex_color_material()
	_root = Node3D.new()
	add_child(_root)
	_body = Node3D.new()
	_body.position = Vector3(0, HIP_Y, 0.2)
	_root.add_child(_body)
	var body_parts := [
		[MeshFactory.sphere(0.17, 14, 9), part_xf(Vector3(0, 0.03, -0.22), Vector3(1.0, 0.92, 2.05)), COAT],
		[MeshFactory.sphere(0.14, 10, 7), part_xf(Vector3(0, -0.04, -0.24), Vector3(0.92, 0.72, 1.7)), CREAM],
		[MeshFactory.sphere(0.12, 10, 7), part_xf(Vector3(0, 0.0, -0.42), Vector3(1.0, 1.15, 0.9)), CREAM],
		[MeshFactory.sphere(0.075, 8, 5), part_xf(Vector3(0, 0.1, -0.05), Vector3(1.6, 0.6, 1.3)), COAT_DARK],
		[MeshFactory.cyl(0.115, 0.13, 0.07, 12), part_xf(Vector3(0, 0.12, -0.47), Vector3.ONE, Vector3(0.9, 0, 0)), SCARF],
		[MeshFactory.roof(Vector3(0.19, 0.13, 0.03)), part_xf(Vector3(0, 0.035, -0.548), Vector3.ONE, Vector3(0.38, 0, PI)), SCARF],
		[MeshFactory.cyl(0.024, 0.024, 0.012, 8), part_xf(Vector3(0, -0.035, -0.574), Vector3.ONE, Vector3(PI * 0.5 + 0.38, 0, 0)), TAG],
	]
	_add_mesh(_body, merge_parts(body_parts), m)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.17, -0.5)
	_body.add_child(_head)
	var head_parts := [
		[MeshFactory.sphere(0.135, 14, 9), part_xf(Vector3(0, 0.07, -0.02), Vector3(1.05, 0.95, 1.0)), COAT],
		[MeshFactory.sphere(0.075, 10, 7), part_xf(Vector3(0, 0.02, -0.14), Vector3(1.0, 0.82, 1.35)), CREAM],
		[MeshFactory.sphere(0.032, 8, 5), part_xf(Vector3(0, 0.055, -0.235), Vector3(1.2, 0.9, 1.0)), DARK],
		[MeshFactory.sphere(0.024, 8, 5), part_xf(Vector3(-0.062, 0.11, -0.112), Vector3.ONE), DARK],
		[MeshFactory.sphere(0.024, 8, 5), part_xf(Vector3(0.062, 0.11, -0.112), Vector3.ONE), DARK],
		[MeshFactory.sphere(0.008, 4, 3), part_xf(Vector3(-0.068, 0.122, -0.132), Vector3.ONE), Color(1, 1, 1)],
		[MeshFactory.sphere(0.008, 4, 3), part_xf(Vector3(0.056, 0.122, -0.132), Vector3.ONE), Color(1, 1, 1)],
		[MeshFactory.sphere(0.07, 10, 7), part_xf(Vector3(-0.122, 0.035, 0.005), Vector3(0.42, 1.15, 0.78), Vector3(0.1, 0.1, -0.32)), COAT_DARK],
		[MeshFactory.sphere(0.07, 10, 7), part_xf(Vector3(0.122, 0.035, 0.005), Vector3(0.42, 1.15, 0.78), Vector3(0.1, -0.1, 0.32)), COAT_DARK],
		[MeshFactory.sphere(0.03, 6, 4), part_xf(Vector3(0, -0.035, -0.17), Vector3(1.3, 0.5, 1.0)), Color(0.85, 0.42, 0.42)],
	]
	_add_mesh(_head, merge_parts(head_parts), m)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.1, 0.13)
	_body.add_child(_tail)
	var tail_parts := [
		[MeshFactory.cyl(0.022, 0.036, 0.26, 8), part_xf(Vector3(0, 0.13, 0), Vector3.ONE), COAT],
		[MeshFactory.sphere(0.03, 8, 5), part_xf(Vector3(0, 0.26, 0), Vector3.ONE), CREAM],
	]
	_add_mesh(_tail, merge_parts(tail_parts), m)
	# Patas: delanteras con "calcetines" crema. Cuelgan del cuerpo y se compensan al sentarse.
	var leg_front := merge_parts([
		[MeshFactory.cyl(0.042, 0.038, 0.3, 8), part_xf(Vector3(0, -0.15, 0), Vector3.ONE), COAT],
		[MeshFactory.sphere(0.048, 8, 5), part_xf(Vector3(0, -0.3, -0.018), Vector3(1.0, 0.7, 1.3)), CREAM],
	])
	var leg_back := merge_parts([
		[MeshFactory.sphere(0.07, 8, 5), part_xf(Vector3(0, -0.03, 0), Vector3(0.8, 1.1, 1.1)), COAT],
		[MeshFactory.cyl(0.04, 0.036, 0.3, 8), part_xf(Vector3(0, -0.15, 0), Vector3.ONE), COAT],
		[MeshFactory.sphere(0.046, 8, 5), part_xf(Vector3(0, -0.3, -0.018), Vector3(1.0, 0.7, 1.3)), COAT_DARK],
	])
	for k in 4:
		var leg := Node3D.new()
		var front := k < 2
		var sx := -0.1 if k % 2 == 0 else 0.1
		leg.position = Vector3(sx, -0.01, -0.42 if front else 0.0)
		_body.add_child(leg)
		_add_mesh(leg, leg_front if front else leg_back, m)
		_legs.append(leg)
	# Corazones al acariciarla.
	_hearts = CPUParticles3D.new()
	_hearts.emitting = false
	_hearts.one_shot = true
	_hearts.amount = 6
	_hearts.lifetime = 1.3
	_hearts.explosiveness = 0.55
	_hearts.local_coords = false
	_hearts.mesh = _heart_mesh()
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(1.0, 0.24, 0.38)
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hearts.material_override = hm
	_hearts.direction = Vector3.UP
	_hearts.spread = 38.0
	_hearts.gravity = Vector3(0, 0.5, 0)
	_hearts.initial_velocity_min = 0.6
	_hearts.initial_velocity_max = 1.3
	_hearts.scale_amount_min = 0.55
	_hearts.scale_amount_max = 0.95
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(0.75, 0.9))
	curve.add_point(Vector2(1.0, 0.0))
	_hearts.scale_amount_curve = curve
	_hearts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hearts.position = Vector3(0, 0.85, -0.3)
	add_child(_hearts)


static func part_xf(pos: Vector3, scl: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos)


## Une primitivas (malla, transformación, color) en una sola malla con color por vértice.
## Un solo material y una sola llamada de dibujo por pieza animada (también lo usa el guante).
static func merge_parts(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var pm: PrimitiveMesh = part[0]
		var xf: Transform3D = part[1]
		var col: Color = part[2]
		var arr := pm.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		for i in idx:
			st.set_color(col)
			st.set_normal((nb * norms[i]).normalized())
			st.add_vertex(xf * verts[i])
	return st.commit()


static func _heart_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.append(Vector3(0, -0.01, 0))
	norms.append(Vector3.BACK)
	cols.append(Color.WHITE)
	var segs := 20
	for k in segs:
		var a := k * TAU / segs
		var x := 16.0 * pow(sin(a), 3)
		var y := 13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a)
		verts.append(Vector3(x, y, 0) * 0.0055)
		norms.append(Vector3.BACK)
		cols.append(Color.WHITE)
	for k in segs:
		idx.append_array([0, 1 + k, 1 + (k + 1) % segs])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_mesh(parent: Node3D, mesh: Mesh, m: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.visibility_range_end = 70.0
	parent.add_child(mi)


# ------------------------------------------------------------------ interacción

func get_prompt(_player: Node) -> String:
	return "Acariciar a %s" % cfg["name"]


func interact(_player: Node) -> void:
	pet()


func pet() -> void:
	_happy = 2.2
	_hearts.restart()
	_hop_v = 2.4
	AudioManager.play_sfx("dog_happy", global_position + Vector3(0, 0.6, 0), -3.0, 0.08)
	HapticManager.pulse(28, 0.3)
	if _pet_cd <= 0.0:
		_pet_cd = float(cfg["pet_cooldown"])
		pets += 1
		ProgressManager.add_stat("dog_pets", 1)
	_set_state(PETTED)


func _on_collectible(id: String) -> void:
	if id == hint_id and Time.get_ticks_msec() / 1000.0 < _hint_until:
		AchievementManager.unlock("dog_find")
		_bark(0.0)
		_happy = 2.0
	if id == hint_id:
		hint_id = ""


func _on_celebrate(_z: String) -> void:
	if player and global_position.distance_to(player.global_position) < 30.0:
		_happy = 3.0
		_hop_v = 3.0
		_bark(0.15)


func _on_gate(_g: String) -> void:
	if player and global_position.distance_to(player.global_position) < 20.0:
		_happy = 1.5
		_bark(0.4)


func _bark(delay: float) -> void:
	if _bark_cd > 0.0:
		return
	_bark_cd = 1.2
	if delay <= 0.0:
		AudioManager.play_sfx("dog_bark", global_position + Vector3(0, 0.6, 0), -5.0, 0.1, 2)
	else:
		get_tree().create_timer(delay).timeout.connect(_bark_now)


func _bark_now() -> void:
	if is_inside_tree():
		AudioManager.play_sfx("dog_bark", global_position + Vector3(0, 0.6, 0), -5.0, 0.1, 2)


# ------------------------------------------------------------------ comportamiento

func _set_state(s: int) -> void:
	state = s
	_state_t = 0.0
	_stuck = 0.0
	if s == IDLE:
		_idle_t = 0.0


func _process(delta: float) -> void:
	if player == null:
		return
	_pet_cd = maxf(_pet_cd - delta, 0.0)
	_bark_cd = maxf(_bark_cd - delta, 0.0)
	_happy = maxf(_happy - delta, 0.0)
	_state_t += delta
	# No roba la interacción: con una bolsa en la mano (el rayo llega al contenedor), con la bolsa
	# llena (lo importante es cerrarla) o mientras mantienes INTERACTUAR para otra cosa.
	var busy := player.bags.is_carrying() or player.bags.is_full() or (InputState.interact_held and player.target != self)
	var want_layer := 0 if busy else LAYER_INTERACT
	if collision_layer != want_layer:
		collision_layer = want_layer
	var pp := player.global_position
	var to_p := Vector3(pp.x - global_position.x, 0.0, pp.z - global_position.z)
	var dist := to_p.length()
	var playing := GameManager.in_game and InputState.enabled
	if playing:
		_brain(delta, pp, dist)
	var speed := _move(delta, playing)
	_animate(delta, speed, to_p)


func _brain(delta: float, pp: Vector3, dist: float) -> void:
	if dist > float(cfg["teleport_dist"]) or absf(pp.y - global_position.y) > 3.0:
		place_near_player(false)
		return
	_first_meeting(delta)
	_pile_cd -= delta
	_sniff_cd -= delta
	var pfwd := _player_fwd()
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 1.0
	match state:
		IDLE:
			_idle_t += delta
			var rel := global_position - pp
			rel.y = 0.0
			var ahead := rel.normalized().dot(pfwd) if rel.length() > 0.01 else 0.0
			var resting := not moving and not InputState.action_held
			_behind_t = _behind_t + delta if ahead < -0.3 and resting else 0.0
			if dist > float(cfg["start_follow"]) or dist < 0.9:
				_start_follow(false)
			elif InputState.action_held and dist < 3.4 and ahead > 0.85:
				# Está justo delante mientras trabajas: se aparta.
				_start_follow(false)
			elif _behind_t > 6.0:
				# Lleva un rato detrás: viene a sentarse donde la veas, sin estorbar.
				_behind_t = 0.0
				_start_follow(true)
			else:
				_think_about_fun(delta, pp)
		FOLLOW:
			_goal = _slot(pp, pfwd, _slot_view)
			if _flat_dist(_goal) < 0.45 or (not _slot_view and dist < float(cfg["follow_dist"]) and not moving):
				_set_state(IDLE)
			elif not moving:
				_think_about_fun(delta, pp)
		TO_PILE:
			_goal = target_pile
			if _flat_dist(target_pile) < 1.7:
				_leap_from = global_position
				_leap_to = target_pile
				_set_state(LEAP)
				AudioManager.play_sfx("jump", global_position, -10.0, 0.15)
			elif _state_t > 7.0:
				_start_follow(false)
		LEAP:
			if _state_t >= 0.55:
				_land_in_pile()
		PLAY:
			_kick_t -= delta
			if _kick_t <= 0.0:
				_kick_t = 0.28
				leaves_scattered += lm.sim.kick(global_position, 0.7, Vector3.ZERO, 1.3, 6, 1.2)
			if _state_t > 1.7:
				_start_follow(false)
		TO_SNIFF:
			if not is_instance_valid(_sniff_target):
				_start_follow(false)
			else:
				var sp := _sniff_target.global_position
				_goal = sp + (global_position - sp).normalized() * 0.45
				if _flat_dist(_goal) < 0.35:
					_set_state(SNIFF)
					AudioManager.play_sfx("dog_sniff", global_position, -6.0, 0.1)
				elif _state_t > 9.0:
					_start_follow(false)
		SNIFF:
			_kick_t -= delta
			if _kick_t <= 0.0 and is_instance_valid(_sniff_target):
				_kick_t = 0.45
				var c := _sniff_target.global_position
				leaves_scattered += lm.sim.kick(c, 0.75, Vector3.ZERO, 1.1, 10, 1.8)
			if _state_t > 2.8:
				_bark(0.0)
				_set_state(IDLE)
				_idle_t = 1.5
		PETTED:
			if _state_t > 1.3:
				_set_state(IDLE)
				_idle_t = 1.5


func _start_follow(view: bool) -> void:
	var pp := player.global_position
	var pfwd := _player_fwd()
	# Elige el lado más cercano para no cruzarse por delante del jugador.
	var right := Vector3(-pfwd.z, 0.0, pfwd.x)
	_side = 1.0 if (global_position - pp).dot(right) >= 0.0 else -1.0
	_slot_view = view
	_goal = _slot(pp, pfwd, view)
	_set_state(FOLLOW)


## Punto de reposo: detrás y a un lado (siguiendo) o delante a un lado (para que la veas sin estorbar).
func _slot(pp: Vector3, pfwd: Vector3, view: bool) -> Vector3:
	var right := Vector3(-pfwd.z, 0.0, pfwd.x)
	for k in 2:
		var side := _side if k == 0 else -_side
		var p := pp + pfwd * 1.9 + right * side * 2.0 if view else pp - pfwd * 1.7 + right * side * 1.25
		if not lm.terrain.is_solid(p.x, p.z):
			if k == 1:
				_side = side
			return p
	return pp - pfwd * 1.4


func _think_about_fun(delta: float, pp: Vector3) -> void:
	_think -= delta
	if _think > 0.0 or GameManager.is_time_attack():
		return
	_think = 1.5
	if _sniff_cd <= 0.0:
		var card := _find_hidden_card(pp)
		if card:
			_sniff_target = card
			_sniff_cd = float(cfg["sniff_cooldown"])
			sniffs += 1
			if card is StationObject and (card as StationObject).kind == StationObject.Kind.POSTCARD:
				hint_id = String((card as StationObject).data.get("id", ""))
				_hint_until = Time.get_ticks_msec() / 1000.0 + 150.0
			_bark(0.0)
			_set_state(TO_SNIFF)
			return
		_sniff_cd = 6.0
	if _pile_cd <= 0.0:
		var pile := find_pile(pp)
		if pile != Vector3.INF:
			target_pile = pile
			var pc := cfg["pile_cooldown"] as Array
			_pile_cd = randf_range(float(pc[0]), float(pc[1]))
			_set_state(TO_PILE)
		else:
			_pile_cd = 6.0


## Busca el montón de hojas más alto cerca del jugador (pero no a sus pies).
func find_pile(pp: Vector3) -> Vector3:
	var r := float(cfg["pile_search"])
	var min_h := float(cfg["pile_min_height"])
	var best := Vector3.INF
	var best_h := min_h
	# Muestreo cada 1,25 m: los montones que superan la altura mínima son más anchos que eso.
	var step := 1.25
	var steps := int(r / step)
	for iz in range(-steps, steps + 1):
		for ix in range(-steps, steps + 1):
			var x := pp.x + ix * step
			var z := pp.z + iz * step
			var h := lm.pile_height_at(x, z)
			if h <= best_h:
				continue
			var d2 := float(ix * ix + iz * iz) * step * step
			if d2 > r * r or d2 < 6.25 or lm.terrain.is_solid(x, z):
				continue
			best_h = h
			best = Vector3(x, lm.sim.height_at(x, z), z)
	return best


func _find_hidden_card(pp: Vector3) -> Node3D:
	var r := float(cfg["sniff_radius"])
	var best: Node3D = null
	var best_d := r
	for i in range(_postcards.size() - 1, -1, -1):
		var o: Variant = _postcards[i]
		if not is_instance_valid(o) or not (o as Node).is_inside_tree() or (o as Node).is_queued_for_deletion():
			_postcards.remove_at(i)
			continue
		var so := o as StationObject
		var s: Node3D = so
		if so.kind == StationObject.Kind.HATCH and ProgressManager.has_flag("secret_found"):
			continue
		if so.is_available(player):
			continue   # ya está a la vista
		var d := Vector2(s.global_position.x - pp.x, s.global_position.z - pp.z).length()
		if d < best_d and absf(s.global_position.y - pp.y) < 3.0:
			best_d = d
			best = s
	return best


func _land_in_pile() -> void:
	var h := lm.pile_height_at(_leap_to.x, _leap_to.z)
	var amount := 70 if PerformanceManager.level != PerformanceManager.LOW else 40
	var n := lm.sim.kick(_leap_to, 1.0 + h, Vector3.ZERO, 2.2 + h * 2.0, amount, 1.6)
	leaves_scattered += n
	pile_jumps += 1
	AudioManager.play_sfx("pile_jump", _leap_to, -5.0, 0.1)
	_bark(0.25)
	_happy = 2.5
	_kick_t = 0.3
	_set_state(PLAY)
	if n > 10 and _on_screen():
		AchievementManager.unlock("dog_pile")


func _on_screen() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(global_position):
		return false
	if global_position.distance_to(cam.global_position) > 22.0:
		return false
	var sp := cam.unproject_position(global_position + Vector3(0, 0.4, 0))
	return get_viewport().get_visible_rect().has_point(sp)


func _first_meeting(delta: float) -> void:
	if ProgressManager.has_flag("met_bellota"):
		return
	_met_t += delta
	var ready_for_it := GameManager.mode != "campaign" or ProgressManager.tutorial_step >= 2
	if _met_t > 10.0 and ready_for_it:
		ProgressManager.set_flag("met_bellota")
		EventBus.toast.emit("¡Hola, %s!" % cfg["name"], "La perrita de al lado ha saltado la valla para ayudarte… a su manera. Acaríciala con INTERACTUAR.", "reward")
		_bark(0.0)


## Coloca a Bellota junto al jugador, detrás de él (fuera de cámara) en un sitio libre.
func place_near_player(initial: bool) -> void:
	var pp := player.global_position
	var pfwd := _player_fwd()
	var right := Vector3(-pfwd.z, 0.0, pfwd.x)
	# Al empezar, sentada delante a la izquierda (se la ve sin tapar los botones de la derecha);
	# al reaparecer, detrás (fuera de cámara).
	var base := pp - right * 1.3 + pfwd * 2.2 if initial else pp - pfwd * 3.0
	var spot := base
	var found := false
	for r in range(0, 12):
		for k in 8:
			var p := base + Vector3(r * 0.5, 0, 0).rotated(Vector3.UP, k * TAU / 8.0)
			if not lm.terrain.is_solid(p.x, p.z) and absf(lm.sim.height_at(p.x, p.z) - pp.y) < 2.5:
				spot = p
				found = true
				break
		if found:
			break
	global_position = Vector3(spot.x, lm.sim.height_at(spot.x, spot.z), spot.z)
	_vel = Vector3.ZERO
	var d := pp - global_position
	_yaw = atan2(-d.x, -d.z)
	rotation.y = _yaw
	_set_state(IDLE)
	_sit = 1.0 if initial else 0.0


func _player_fwd() -> Vector3:
	var f := -player.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


# ------------------------------------------------------------------ movimiento

func _move(delta: float, playing: bool) -> float:
	var want := Vector3.ZERO
	if playing and (state == FOLLOW or state == TO_PILE or state == TO_SNIFF):
		var to := _goal - global_position
		to.y = 0.0
		var d := to.length()
		if d > 0.05:
			var spd := float(cfg["walk_speed"])
			if state == TO_PILE or state == TO_SNIFF:
				spd = float(cfg["run_speed"]) * 0.85
			else:
				var pd := _flat_dist(player.global_position)
				spd = clampf((pd - 1.5) * 1.5, float(cfg["walk_speed"]), float(cfg["run_speed"]))
				spd = maxf(spd, Vector2(player.velocity.x, player.velocity.z).length() * 1.05)
			spd = minf(spd, d * 3.0 + 0.6)
			want = _steer(to / d) * spd
	_vel = _vel.move_toward(want, delta * 16.0)
	var pos := global_position
	if state == LEAP:
		var u := clampf(_state_t / 0.55, 0.0, 1.0)
		var flat := _leap_from.lerp(_leap_to, u)
		var ground := lm.sim.height_at(flat.x, flat.z)
		pos = Vector3(flat.x, ground + sin(u * PI) * 0.95, flat.z)
		var dir := _leap_to - _leap_from
		if dir.length() > 0.01:
			_yaw = lerp_angle(_yaw, atan2(-dir.x, -dir.z), minf(delta * 12.0, 1.0))
		global_position = pos
		rotation.y = _yaw
		return 6.0
	var step := _vel * delta
	var speed := _vel.length()
	if speed > 0.01:
		var np := pos + step
		if lm.terrain.is_solid(np.x, np.z):
			_vel = Vector3.ZERO
			_stuck += delta
		else:
			pos = np
			if speed < 0.25 * float(cfg["walk_speed"]) and state != IDLE:
				_stuck += delta
			else:
				_stuck = maxf(_stuck - delta, 0.0)
		_yaw = lerp_angle(_yaw, atan2(-_vel.x, -_vel.z), minf(delta * 9.0, 1.0))
	elif state == IDLE or state == PETTED or state == SNIFF:
		var face := player.global_position - pos
		if state == SNIFF and is_instance_valid(_sniff_target):
			face = _sniff_target.global_position - pos
		if Vector2(face.x, face.z).length() > 0.3 and (_sit > 0.5 or state != IDLE):
			_yaw = lerp_angle(_yaw, atan2(-face.x, -face.z), minf(delta * 3.0, 1.0))
	if _stuck > 1.6:
		_stuck = 0.0
		if state == FOLLOW and not _on_screen():
			place_near_player(false)
		else:
			_side = -_side
			_start_follow(false)
	# Hundida un poco en los montones, con saltitos de alegría.
	_hop_v -= 12.0 * delta
	_hop = maxf(_hop + _hop_v * delta, 0.0)
	if _hop <= 0.0:
		_hop_v = 0.0
	var ground_y := lm.sim.height_at(pos.x, pos.z) + lm.pile_height_at(pos.x, pos.z) * 0.45
	pos.y = lerpf(pos.y, ground_y, minf(delta * 14.0, 1.0)) if absf(pos.y - ground_y) < 1.0 else ground_y
	global_position = Vector3(pos.x, pos.y, pos.z)
	_root.position.y = _hop
	rotation.y = _yaw
	# Al correr entre las hojas, aparta algunas con las patas.
	_kick_t -= delta
	if speed > 3.0 and _kick_t <= 0.0 and state != PLAY and state != SNIFF:
		_kick_t = 0.12
		lm.sim.kick(pos + _vel.normalized() * 0.25, 0.35, _vel * 0.3, 0.6, 2)
	return speed


## Rodea obstáculos probando direcciones cada vez más abiertas.
func _steer(dir: Vector3) -> Vector3:
	var pos := global_position
	for a in [0.0, 0.45, -0.45, 0.9, -0.9, 1.4, -1.4, 2.0, -2.0]:
		var d := dir.rotated(Vector3.UP, a * _side)
		var probe := pos + d * 0.55
		if not lm.terrain.is_solid(probe.x, probe.z):
			return d
	return Vector3.ZERO


# ------------------------------------------------------------------ animación procedural

func _animate(delta: float, speed: float, to_p: Vector3) -> void:
	var sitting := state == IDLE and _idle_t > 1.1 and speed < 0.2
	_sit = move_toward(_sit, 1.0 if sitting else 0.0, delta * (2.5 if sitting else 6.0))
	var t := Time.get_ticks_msec() / 1000.0
	# Patas: trote en diagonal; la amplitud crece con la velocidad.
	var amp := clampf(speed / 3.2, 0.0, 1.0)
	_phase += delta * (4.0 + speed * 2.3)
	var swing := sin(_phase) * (0.35 + 0.35 * amp) * amp
	var dig := 0.0
	if state == SNIFF:
		dig = sin(t * 22.0) * 0.6
	var pitch := 0.58 * ease(_sit, -1.6)
	var leap_u := clampf(_state_t / 0.55, 0.0, 1.0) if state == LEAP else -1.0
	if leap_u >= 0.0:
		pitch = lerpf(0.35, -0.3, leap_u)
		swing = 0.0
	_body.rotation.x = pitch
	_body.position.y = HIP_Y - 0.13 * _sit + absf(sin(_phase)) * 0.035 * amp
	for k in 4:
		var leg := _legs[k]
		var front := k < 2
		var s := swing if (k == 0 or k == 3) else -swing
		if leap_u >= 0.0:
			s = (-0.9 if front else 0.9) * sin(leap_u * PI)
		if front:
			leg.rotation.x = -pitch + s + (dig if k == 0 else -dig) * 0.8
			leg.scale = Vector3(1, 1.0 + 0.42 * _sit, 1)
		else:
			leg.rotation.x = -pitch + s + 1.25 * _sit
			leg.scale = Vector3(1, 1.0 - 0.15 * _sit, 1)
	# Cola: más rápida y amplia cuanto más contenta está.
	var joy := clampf(_happy, 0.0, 1.0)
	var wag_speed := 9.0 + 10.0 * joy + 4.0 * amp
	var wag_amp := 0.35 + 0.45 * joy - 0.15 * _sit
	if state == SNIFF or state == TO_PILE or state == PLAY:
		wag_amp = 0.7
		wag_speed = 16.0
	_tail.rotation = Vector3(0.75 + 0.35 * joy - 0.4 * _sit, sin(t * wag_speed) * wag_amp, 0.0)
	# Cabeza: mira al jugador, ladea la cabeza a veces, olfatea el suelo.
	_quirk_t -= delta
	if _quirk_left > 0.0:
		_quirk_left -= delta
	elif _quirk_t <= 0.0 and state == IDLE:
		_quirk_t = randf_range(4.0, 9.0)
		_quirk = randi_range(0, 2)
		_quirk_left = randf_range(1.0, 1.8)
		_look_yaw = randf_range(-0.8, 0.8)
	var head_yaw := 0.0
	var head_pitch := -pitch * 0.85
	var head_roll := 0.0
	if state == IDLE or state == PETTED:
		var local := global_transform.basis.inverse() * Vector3(to_p.x, 0.0, to_p.z)
		head_yaw = clampf(atan2(-local.x, -local.z), -0.9, 0.9)
		head_pitch += 0.15
		if _quirk_left > 0.0:
			match _quirk:
				0: head_roll = 0.38
				1: head_yaw = _look_yaw
				2: head_pitch -= 0.45 + sin(t * 14.0) * 0.08
	elif state == SNIFF:
		head_pitch -= 0.75 + sin(t * 16.0) * 0.1
	elif state == PLAY:
		head_roll = sin(t * 9.0) * 0.3
	if state == PETTED:
		head_roll = sin(t * 6.0) * 0.25
		head_pitch += 0.25
	var k := minf(delta * 8.0, 1.0)
	_head.rotation = Vector3(lerpf(_head.rotation.x, head_pitch, k), lerp_angle(_head.rotation.y, head_yaw, k), lerpf(_head.rotation.z, head_roll, k))
	# Revolcón en el montón.
	var roll := sin(t * 10.0) * 0.28 if state == PLAY else 0.0
	_root.rotation.z = lerpf(_root.rotation.z, roll, k)
