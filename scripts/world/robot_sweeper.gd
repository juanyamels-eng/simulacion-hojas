class_name RobotSweeper
extends Node3D
## Brizna, el robot barrehojas: tras repararlo trabaja despacio en la zona donde estés,
## buscando los grupos de hojas más densos. Ayuda, pero no sustituye al jugador.

var lm: LeafManager
var player: PlayerController
var target := Vector3.INF
var _retarget := 0.0
var _budget := 0.0
var _brush: Node3D
var _bob := 0.0


func setup(leaf_manager: LeafManager, p: PlayerController) -> void:
	lm = leaf_manager
	player = p
	var body := MeshInstance3D.new()
	body.mesh = MeshFactory.sphere(0.45, 12, 8)
	body.material_override = MeshFactory.mat(Color(0.75, 0.78, 0.8), 0.4)
	body.position.y = 0.5
	body.scale = Vector3(1, 0.85, 1)
	add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = MeshFactory.sphere(0.27, 10, 6)
	head.material_override = MeshFactory.mat(Color(0.85, 0.88, 0.9), 0.4)
	head.position.y = 1.0
	add_child(head)
	for sx in [-0.1, 0.1]:
		var eye := MeshInstance3D.new()
		eye.mesh = MeshFactory.sphere(0.05, 6, 4)
		eye.material_override = MeshFactory.mat(Color(0.3, 0.8, 1.0), 0.3, 2.0)
		eye.position = Vector3(sx, 1.03, -0.24)
		add_child(eye)
	_brush = Node3D.new()
	_brush.position = Vector3(0, 0.08, -0.35)
	add_child(_brush)
	for k in 6:
		var bristle := MeshInstance3D.new()
		bristle.mesh = MeshFactory.box(Vector3(0.5, 0.05, 0.06))
		bristle.material_override = MeshFactory.mat(Color(0.85, 0.6, 0.25))
		bristle.rotation.y = k * PI / 6.0
		_brush.add_child(bristle)
	visible = false


func _process(delta: float) -> void:
	if UpgradeManager.get_level("robot") <= 0 or not GameManager.in_game:
		visible = false
		return
	var zid := AreaManager.current_zone
	if zid == "" or GameData.zone_by_id(zid).get("secret", false):
		return
	var rect: Rect2 = GameData.zone_by_id(zid)["rect"]
	if not visible or not rect.has_point(Vector2(global_position.x, global_position.z)):
		# Se teletransporta junto al jugador cuando cambias de zona.
		var p := player.global_position + player.global_transform.basis.x * 1.5
		global_position = Vector3(p.x, lm.sim.height_at(p.x, p.z), p.z)
		visible = true
		target = Vector3.INF
	_retarget -= delta
	if target == Vector3.INF or _retarget <= 0.0 or global_position.distance_to(target) < 0.4:
		_retarget = 4.0
		target = _pick_target(rect)
	var speed := 1.1 * float(UpgradeManager.get_value("robot_speed"))
	var to := target - global_position
	to.y = 0.0
	if to.length() > 0.05:
		var step := to.normalized() * minf(speed * delta, to.length())
		var np := global_position + step
		if lm.terrain.is_solid(np.x, np.z):
			target = Vector3.INF
		else:
			global_position = Vector3(np.x, lm.sim.height_at(np.x, np.z), np.z)
			look_at(global_position - step.normalized(), Vector3.UP)
	_brush.rotation.y += delta * 12.0
	_bob += delta
	var sim := lm.sim
	var mouth := global_position + Vector3(0, 0.2, 0)
	sim.suck_pos[LeafManager.P_ROBOT] = mouth
	sim.suck_acc[LeafManager.P_ROBOT] = 10.0
	_budget += 6.0 * float(UpgradeManager.get_value("robot_speed")) * delta
	var n := int(_budget)
	if n > 0:
		_budget -= n
		sim.capture_radius(mouth, 1.1, n, LeafManager.P_ROBOT, 1.0)
	var got := sim.take_arrived(LeafManager.P_ROBOT)
	if got.x > 0:
		EconomyManager.deposit_leaves(got.y)
		ProgressManager.add_stat("leaves_collected", got.x)


func _pick_target(rect: Rect2) -> Vector3:
	var sim := lm.sim
	var best := Vector3.INF
	var best_n := 0
	for k in 40:
		var x := randf_range(rect.position.x + 1.0, rect.end.x - 1.0)
		var z := randf_range(rect.position.y + 1.0, rect.end.y - 1.0)
		var c := sim.cell_index(x, z)
		if c < 0 or sim.solid[c] != 0:
			continue
		var cnt := sim.count_in_radius(Vector3(x, 0, z), 1.0)
		if cnt > best_n:
			best_n = cnt
			best = Vector3(x, sim.height_at(x, z), z)
	if best == Vector3.INF:
		return global_position
	return best
