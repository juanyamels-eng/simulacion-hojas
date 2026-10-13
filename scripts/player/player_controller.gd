class_name PlayerController
extends CharacterBody3D
## Jugador en primera persona: movimiento suave, sprint con resistencia, salto,
## interacción contextual (tocar o mantener), patadas a las hojas y saltos en montones.

const GRAVITY := 17.0
const EYE_HEIGHT := 1.6
const INTERACT_RANGE := 3.4

var leaf_manager: LeafManager
var cam: CameraController
var tools: ToolManager
var bags: BagSystem
var body_anchor: Node3D

var stamina := 4.0
var sprinting := false
var prompt := ""
var prompt_available := false
var prompt_hold := 0.0
var hold_progress := 0.0
var target: Object = null
var _hold_active := false
var _was_on_floor := true
var _fall_speed := 0.0
var _step_dist := 0.0
var _zone_timer := 0.0
var _kick_timer := 0.0
var _rustle_cool := 0.0
var _ray := PhysicsRayQueryParameters3D.new()


func setup(lm: LeafManager) -> void:
	leaf_manager = lm
	collision_layer = 16
	collision_mask = Interactable.LAYER_WORLD
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	body_anchor = Node3D.new()
	add_child(body_anchor)
	cam = CameraController.new()
	cam.position.y = EYE_HEIGHT
	add_child(cam)
	cam.setup(self)
	bags = BagSystem.new()
	add_child(bags)
	bags.setup(self)
	tools = ToolManager.new()
	add_child(tools)
	tools.setup(self)
	_ray.collision_mask = Interactable.LAYER_INTERACT | Interactable.LAYER_BAG
	_ray.collide_with_areas = false
	_ray.exclude = [get_rid()]


func teleport(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO
	cam.pitch = 0.0


func current_speed_limit() -> float:
	var s := float(UpgradeManager.get_value("move_speed")) * (1.0 + AreaManager.speed_bonus)
	if sprinting:
		s *= float(UpgradeManager.get_value("sprint"))
	if bags.is_carrying():
		s *= float(UpgradeManager.get_value("bag_carry"))
	s *= tools.speed_factor()
	return s


func _physics_process(delta: float) -> void:
	if not InputState.enabled:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	var mv := InputState.move if InputState.enabled else Vector2.ZERO
	var max_stamina := float(UpgradeManager.get_value("stamina"))
	var want_sprint := (InputState.sprint_held or mv.length() > 0.93) and mv.y > 0.3
	if want_sprint and stamina > 0.0:
		sprinting = true
		if max_stamina < 900.0:
			stamina -= delta
	else:
		sprinting = false
		stamina = minf(stamina + delta * 0.8, max_stamina)
	if max_stamina > 900.0:
		stamina = max_stamina
	var b := global_transform.basis
	var dir := (b.x * mv.x - b.z * mv.y)
	dir.y = 0.0
	var target_vel := dir * current_speed_limit()
	var accel := 14.0 if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta * maxf(current_speed_limit(), 1.0))
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta * maxf(current_speed_limit(), 1.0))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	if InputState.jump_pressed and is_on_floor() and InputState.enabled:
		InputState.jump_pressed = false
		velocity.y = float(UpgradeManager.get_value("jump"))
		_fall_speed = 0.0
		AudioManager.play_sfx("jump", Vector3.INF, -8.0)
	InputState.jump_pressed = false
	move_and_slide()
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_on_land()
	_was_on_floor = on_floor


func _process(delta: float) -> void:
	if InputState.enabled:
		cam.apply_look(delta)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var feet := global_position
	var pile_h := leaf_manager.pile_height_at(feet.x, feet.z)
	cam.update_effects(delta, hspeed, is_on_floor(), pile_h)
	_leaf_contact(delta, hspeed, pile_h)
	_update_interaction(delta)
	tools.process_tools(delta)
	_zone_timer -= delta
	if _zone_timer <= 0.0:
		_zone_timer = 0.4
		AreaManager.set_current_zone(AreaManager.zone_at(global_position))
	InputState.consume_frame()


func _leaf_contact(delta: float, hspeed: float, pile_h: float) -> void:
	_rustle_cool = maxf(_rustle_cool - delta, 0.0)
	if is_on_floor():
		_step_dist += hspeed * delta
		if _step_dist > (1.9 if not sprinting else 2.3):
			_step_dist = 0.0
			var cover := leaf_manager.sim.count_in_radius(global_position, 0.5)
			if cover > 0 or pile_h > 0.05:
				AudioManager.play_sfx("step_leaves", Vector3.INF, -9.0 + minf(pile_h * 8.0, 5.0), 0.12, 4)
			else:
				AudioManager.play_sfx("step_grass", Vector3.INF, -14.0, 0.12, 3)
	# Al caminar se apartan las hojas de los pies; dentro de un montón, mucho más.
	_kick_timer -= delta
	if hspeed > 1.2 and _kick_timer <= 0.0:
		_kick_timer = 0.05
		var fwd := Vector3(velocity.x, 0.0, velocity.z) / hspeed
		var amount := 3 if pile_h < 0.15 else 10
		var got := leaf_manager.sim.kick(global_position + fwd * 0.35, 0.5 + pile_h * 0.6, fwd * hspeed * 0.45, 0.7 + pile_h * 2.0, amount)
		if got > 4 and _rustle_cool <= 0.0:
			_rustle_cool = 0.35
			AudioManager.play_sfx("rustle", Vector3.INF, -6.0, 0.15, 3)


func _on_land() -> void:
	var pile_h := leaf_manager.pile_height_at(global_position.x, global_position.z)
	if pile_h > 0.3 and _fall_speed > 3.0:
		var n := leaf_manager.sim.kick(global_position, 1.3 + pile_h, Vector3.ZERO, 3.0 + pile_h * 3.0, 120, 2.5)
		AudioManager.play_sfx("pile_jump", Vector3.INF, 0.0, 0.08)
		HapticManager.pulse(70, 0.8)
		cam.add_shake(0.6)
		if pile_h > 0.55 and n > 20:
			AchievementManager.unlock("pile_jump")
	elif _fall_speed > 6.0:
		AudioManager.play_sfx("step_grass", Vector3.INF, -6.0, 0.1, 3)
	_fall_speed = 0.0


func _update_interaction(delta: float) -> void:
	target = null
	prompt = ""
	prompt_available = false
	prompt_hold = 0.0
	var origin := cam.camera.global_position
	var fwd := -cam.camera.global_transform.basis.z
	_ray.from = origin
	_ray.to = origin + fwd * INTERACT_RANGE
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		if col is LeafBag:
			if not bags.is_carrying():
				target = col
				prompt = (col as LeafBag).get_prompt(self)
				prompt_available = true
		elif col is Interactable:
			var it := col as Interactable
			var txt := it.get_prompt(self)
			if txt != "":
				target = it
				prompt = txt
				prompt_available = it.is_available(self)
				prompt_hold = it.hold_time(self)
				# Un objeto que aún no se puede usar (postal tapada, puerta sin requisito...) no debe
				# impedir cerrar la bolsa cuando se mira al suelo o a un objeto de la finca.
				if not prompt_available and bags.count > 0 and not bags.is_carrying() and (it is StationObject or cam.pitch < -0.35):
					target = null
					prompt = ""
	if target == null:
		if bags.is_carrying():
			prompt = "Soltar bolsa"
			prompt_available = true
		elif bags.count > 0:
			prompt = "Cerrar bolsa (%d)" % bags.count
			prompt_available = true
			prompt_hold = float(UpgradeManager.get_value("bag_close")) / float(UpgradeManager.get_value("interact_speed"))
	if not InputState.enabled:
		_hold_active = false
		hold_progress = 0.0
		return
	if InputState.interact_pressed:
		_hold_active = true
		hold_progress = 0.0
		if prompt_hold <= 0.0:
			_hold_active = false
			_do_interact()
	if _hold_active:
		if not InputState.interact_held or not prompt_available:
			_hold_active = false
			hold_progress = 0.0
		else:
			hold_progress += delta / maxf(prompt_hold, 0.01)
			if hold_progress >= 1.0:
				_hold_active = false
				hold_progress = 0.0
				_do_interact()


func _do_interact() -> void:
	if not prompt_available:
		if prompt != "":
			AudioManager.play_ui("error")
		return
	if target is LeafBag:
		bags.pick_up(target)
	elif target is Interactable:
		(target as Interactable).interact(self)
	elif bags.is_carrying():
		bags.drop_bag()
	elif bags.count > 0:
		bags.close_bag()


func get_state() -> Dictionary:
	var p := global_position
	return {"x": p.x, "y": p.y, "z": p.z, "yaw": rotation.y, "pitch": cam.pitch}


func apply_state(d: Dictionary) -> void:
	if d.is_empty():
		return
	teleport(Vector3(float(d.get("x", 0)), float(d.get("y", 1)) + 0.1, float(d.get("z", 0))), float(d.get("yaw", 0)))
	cam.pitch = float(d.get("pitch", 0.0))
