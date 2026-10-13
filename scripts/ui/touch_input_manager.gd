class_name TouchInputManager
extends Control
## Controles táctiles multitáctiles: joystick dinámico a la izquierda, cámara arrastrando a la derecha,
## botones grandes (usar, interactuar, saltar, herramienta) y rueda rápida de herramientas.
## También admite teclado y ratón para pruebas en escritorio.

class TouchButton:
	var id := ""
	var center := Vector2.ZERO
	var radius := 60.0
	var touch := -1
	var flash := 0.0

var buttons: Array[TouchButton] = []
var joy_touch := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var joy_radius := 90.0
var joy_home := Vector2.ZERO
var look_touch := -1
var tool_touch_t := 0.0
var wheel_open := false
var wheel_sel := ""
var wheel_center := Vector2.ZERO
var safe := Rect2()
var ui_scale := 1.0
var _mouse_look := false
var _keys := {}
var _desktop := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_desktop = not OS.has_feature("mobile")
	for id in ["action", "interact", "jump", "tool"]:
		var b := TouchButton.new()
		b.id = id
		buttons.append(b)
	get_viewport().size_changed.connect(_layout)
	EventBus.settings_changed.connect(_layout)
	_layout()


func _btn(id: String) -> TouchButton:
	for b in buttons:
		if b.id == id:
			return b
	return null


func _layout() -> void:
	var vs := get_viewport_rect().size
	safe = Rect2(Vector2.ZERO, vs)
	if OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var ws := Vector2(DisplayServer.window_get_size())
		if ws.x > 0 and sa.size.x > 0:
			var k := vs / ws
			safe = Rect2(Vector2(sa.position) * k, Vector2(sa.size) * k)
	safe = safe.grow(-16.0)
	ui_scale = clampf(vs.y / 720.0, 0.85, 1.25) * float(SettingsManager.get_value("joystick_size", 1.0))
	var s := ui_scale
	var br := safe.end
	_btn("action").center = br - Vector2(118, 118) * s
	_btn("action").radius = 80 * s
	_btn("interact").center = br - Vector2(118, 292) * s
	_btn("interact").radius = 60 * s
	_btn("jump").center = br - Vector2(282, 78) * s
	_btn("jump").radius = 54 * s
	_btn("tool").center = br - Vector2(290, 232) * s
	_btn("tool").radius = 50 * s
	joy_radius = 92 * s
	joy_home = Vector2(safe.position.x + 170 * s, safe.end.y - 160 * s)


func _player() -> PlayerController:
	if GameManager.world and is_instance_valid(GameManager.world) and GameManager.world.player:
		return GameManager.world.player
	return null


func active() -> bool:
	return visible and InputState.enabled and GameManager.in_game


func release_all() -> void:
	joy_touch = -1
	look_touch = -1
	wheel_open = false
	for b in buttons:
		b.touch = -1
	InputState.reset()


func _input(event: InputEvent) -> void:
	if not active():
		if joy_touch >= 0 or look_touch >= 0:
			release_all()
		return
	if event is InputEventScreenTouch:
		_touch(event)
	elif event is InputEventScreenDrag:
		_drag(event)
	elif _desktop and event.device != InputEvent.DEVICE_ID_EMULATION:
		_desktop_input(event)


func _touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		for b in buttons:
			if b.touch < 0 and e.position.distance_to(b.center) <= b.radius * 1.15:
				b.touch = e.index
				b.flash = 1.0
				match b.id:
					"action":
						InputState.action_held = true
						InputState.action_pressed = true
					"interact":
						InputState.interact_held = true
						InputState.interact_pressed = true
					"jump":
						InputState.jump_pressed = true
					"tool":
						tool_touch_t = 0.0
				get_viewport().set_input_as_handled()
				return
		if e.position.x < safe.position.x + safe.size.x * 0.45 and e.position.y > safe.position.y + safe.size.y * 0.22 and joy_touch < 0:
			joy_touch = e.index
			joy_origin = e.position
			joy_pos = e.position
			InputState.move = Vector2.ZERO
		elif look_touch < 0 and e.position.x >= safe.position.x + safe.size.x * 0.4:
			look_touch = e.index
		get_viewport().set_input_as_handled()
	else:
		for b in buttons:
			if b.touch == e.index:
				b.touch = -1
				match b.id:
					"action":
						InputState.action_held = false
					"interact":
						InputState.interact_held = false
						InputState.interact_released = true
					"tool":
						if wheel_open:
							wheel_open = false
							if wheel_sel != "":
								InputState.tool_select = wheel_sel
						else:
							InputState.tool_next = true
				return
		if e.index == joy_touch:
			joy_touch = -1
			InputState.move = Vector2.ZERO
			InputState.sprint_held = false
		elif e.index == look_touch:
			look_touch = -1


func _drag(e: InputEventScreenDrag) -> void:
	if e.index == joy_touch:
		joy_pos = e.position
		var d := joy_pos - joy_origin
		if d.length() > joy_radius * 1.6:
			# El joystick sigue al dedo si se aleja mucho.
			joy_origin = joy_pos - d.normalized() * joy_radius * 1.6
			d = joy_pos - joy_origin
		var v := d / joy_radius
		if v.length() > 1.0:
			v = v.normalized()
		var dz := 0.12
		var m := v.length()
		v = Vector2.ZERO if m < dz else v.normalized() * ((m - dz) / (1.0 - dz))
		InputState.move = Vector2(v.x, -v.y)
		InputState.sprint_held = (d.length() / joy_radius) > 1.25 and -v.y > 0.6
	elif e.index == look_touch:
		InputState.look_delta += e.relative
	else:
		var tb := _btn("tool")
		if e.index == tb.touch and wheel_open:
			_update_wheel(e.position)


func _update_wheel(p: Vector2) -> void:
	var owned := UpgradeManager.owned_tools()
	var d := p - wheel_center
	wheel_sel = ""
	if d.length() < 40.0 * ui_scale:
		return
	var best := 999.0
	for k in owned.size():
		var a := _wheel_angle(k, owned.size())
		var diff := absf(wrapf(d.angle() - a, -PI, PI))
		if diff < best:
			best = diff
			wheel_sel = owned[k]


func _wheel_angle(k: int, n: int) -> float:
	return -PI * 0.5 + (k - (n - 1) * 0.5) * 0.72 - PI * 0.35


func _process(delta: float) -> void:
	for b in buttons:
		b.flash = maxf(b.flash - delta * 4.0, 0.0)
	var tb := _btn("tool")
	if tb.touch >= 0 and not wheel_open:
		tool_touch_t += delta
		if tool_touch_t > 0.28 and UpgradeManager.owned_tools().size() > 1:
			wheel_open = true
			wheel_center = tb.center
			wheel_sel = ""
			HapticManager.pulse(15, 0.3)
	if _desktop and active():
		_desktop_poll()
	queue_redraw()


# ------------------------------------------------------------------ escritorio

func _desktop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_look = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			InputState.action_held = mb.pressed
			if mb.pressed:
				InputState.action_pressed = true
	elif event is InputEventMouseMotion and _mouse_look:
		InputState.look_delta += (event as InputEventMouseMotion).relative
	elif event is InputEventKey and not event.is_echo():
		var k := event as InputEventKey
		_keys[k.physical_keycode] = k.pressed
		if k.pressed:
			match k.physical_keycode:
				KEY_SPACE: InputState.jump_pressed = true
				KEY_E:
					InputState.interact_pressed = true
				KEY_Q, KEY_TAB: InputState.tool_next = true
				KEY_1: InputState.tool_select = "hand"
				KEY_2: InputState.tool_select = "rake"
				KEY_3: InputState.tool_select = "blower"
				KEY_4: InputState.tool_select = "vacuum"
				KEY_5: InputState.tool_select = "industrial"
		if k.physical_keycode == KEY_E:
			InputState.interact_held = k.pressed


func _desktop_poll() -> void:
	if joy_touch >= 0:
		return
	var v := Vector2(float(_keys.get(KEY_D, false)) - float(_keys.get(KEY_A, false)), float(_keys.get(KEY_W, false)) - float(_keys.get(KEY_S, false)))
	if v != Vector2.ZERO or not _keys.is_empty():
		InputState.move = v.normalized() if v.length() > 1.0 else v
		InputState.sprint_held = _keys.get(KEY_SHIFT, false)


# ------------------------------------------------------------------ dibujo

func _draw() -> void:
	if not active():
		return
	var s := ui_scale
	var p := _player()
	# Joystick.
	var base := joy_origin if joy_touch >= 0 else joy_home
	var knob := joy_pos if joy_touch >= 0 else joy_home
	if joy_touch >= 0:
		var d := knob - base
		if d.length() > joy_radius:
			knob = base + d.normalized() * joy_radius
	var a := 0.55 if joy_touch >= 0 else 0.28
	draw_circle(base, joy_radius, Color(0.12, 0.07, 0.03, a * 0.6))
	draw_arc(base, joy_radius, 0, TAU, 48, Color(1, 0.95, 0.85, a), 3.0 * s, true)
	draw_circle(knob, joy_radius * 0.42, Color(1.0, 0.93, 0.8, a + 0.2))
	# Botones.
	var carrying := p != null and p.bags.is_carrying()
	for b in buttons:
		var pressed := b.touch >= 0
		var col := UITheme.ACCENT if b.id == "action" else UITheme.WOOD
		var alpha := 0.82 if pressed else 0.62
		var icon := ""
		match b.id:
			"action":
				icon = "throw" if carrying else GameManager.current_tool
			"interact":
				icon = "interact"
				if p and p.prompt == "":
					alpha = 0.32
				elif p and not p.prompt_available:
					alpha = 0.45
			"jump":
				icon = "jump"
			"tool":
				icon = "swap"
				if UpgradeManager.owned_tools().size() <= 1:
					alpha = 0.28
		var r := b.radius * (0.94 if pressed else 1.0)
		draw_circle(b.center + Vector2(0, 4 * s), r, Color(0, 0, 0, 0.18))
		draw_circle(b.center, r, Color(col, alpha))
		draw_arc(b.center, r, 0, TAU, 48, Color(1, 0.94, 0.8, minf(alpha + 0.15, 1.0)), 3.5 * s, true)
		if b.flash > 0.0:
			draw_arc(b.center, r + 8 * s * (1.0 - b.flash), 0, TAU, 48, Color(1, 0.9, 0.6, b.flash * 0.7), 4.0 * s, true)
		Icons.draw(self, icon, b.center, r * 0.95, Color(1, 0.97, 0.9, minf(alpha + 0.3, 1.0)))
		if b.id == "interact" and p and p.hold_progress > 0.0:
			draw_arc(b.center, r + 9 * s, -PI * 0.5, -PI * 0.5 + TAU * p.hold_progress, 40, UITheme.GOLD, 7 * s, true)
	if wheel_open:
		_draw_wheel()


func _draw_wheel() -> void:
	var owned := UpgradeManager.owned_tools()
	var s := ui_scale
	draw_circle(wheel_center, 230 * s, Color(0.1, 0.06, 0.03, 0.35))
	for k in owned.size():
		var ang := _wheel_angle(k, owned.size())
		var c := wheel_center + Vector2(cos(ang), sin(ang)) * 165 * s
		var sel: bool = owned[k] == wheel_sel
		var cur: bool = owned[k] == GameManager.current_tool
		draw_circle(c, 52 * s, Color(UITheme.ACCENT if sel else UITheme.WOOD, 0.92))
		draw_arc(c, 52 * s, 0, TAU, 40, UITheme.GOLD if cur else Color(1, 0.94, 0.8), 4 * s, true)
		Icons.draw(self, owned[k], c, 58 * s, UITheme.CREAM)
