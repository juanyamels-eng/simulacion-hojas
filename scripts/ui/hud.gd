class_name HUD
extends Control
## HUD minimalista: zona y % arriba a la izquierda, dinero arriba a la derecha,
## herramienta y bolsa abajo. Avisos, notificaciones, tutorial y radar de las últimas hojas.
## Además: guías en pantalla (contenedor, puertas), aviso de mejora disponible en el diario,
## contador "+N" al recoger, pulso de la bolsa y celebración al restaurar una zona.


## Insignia animada sobre el botón del diario cuando hay una mejora que puedes comprar.
class Badge extends Control:
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(32, 32)

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var k := 1.0 + 0.14 * maxf(sin(t * 5.0), 0.0)
		draw_circle(c + Vector2(0, 2), 13.0 * k, Color(0, 0, 0, 0.25))
		draw_circle(c, 13.0 * k, Color(0.84, 0.24, 0.17))
		draw_arc(c, 13.0 * k, 0, TAU, 24, UITheme.CREAM, 2.5, true)
		var pts := PackedVector2Array([Vector2(0, -7), Vector2(6, -0.5), Vector2(2.2, -0.5), Vector2(2.2, 6.5), Vector2(-2.2, 6.5), Vector2(-2.2, -0.5), Vector2(-6, -0.5)])
		for i in pts.size():
			pts[i] = c + pts[i] * k
		draw_colored_polygon(pts, UITheme.CREAM)


## Celebración a pantalla completa: rayos dorados tras el título y confeti de hojas.
class Celebration extends Control:
	const COLS := [Color(0.98, 0.78, 0.2), Color(0.95, 0.52, 0.14), Color(0.86, 0.28, 0.12), Color(0.6, 0.72, 0.25), Color(0.98, 0.9, 0.6)]
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var rot := PackedFloat32Array()
	var spin := PackedFloat32Array()
	var leaf_size := PackedFloat32Array()
	var col := PackedColorArray()
	var t := 0.0
	var duration := 4.6
	var focus := Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func burst(n: int, vs: Vector2) -> void:
		t = duration
		pos.resize(n)
		vel.resize(n)
		rot.resize(n)
		spin.resize(n)
		leaf_size.resize(n)
		col.resize(n)
		for i in n:
			if i % 3 == 0:
				# Cañones desde las esquinas inferiores.
				var left := i % 2 == 0
				pos[i] = Vector2(-10.0 if left else vs.x + 10.0, vs.y * randf_range(0.55, 0.8))
				vel[i] = Vector2(randf_range(380, 720) * (1.0 if left else -1.0), -randf_range(520, 860))
			else:
				pos[i] = Vector2(randf_range(0, vs.x), -randf_range(20, vs.y * 0.6))
				vel[i] = Vector2(randf_range(-60, 60), randf_range(70, 190))
			rot[i] = randf() * TAU
			spin[i] = randf_range(-6.0, 6.0)
			leaf_size[i] = randf_range(16.0, 30.0)
			col[i] = COLS[randi() % COLS.size()]
		visible = true

	func active() -> bool:
		return t > 0.0

	func _process(delta: float) -> void:
		if t <= 0.0:
			if visible:
				visible = false
			return
		t -= delta
		var drag := 1.0 - minf(delta * 1.6, 0.5)
		for i in pos.size():
			var v := vel[i]
			v.y += 620.0 * delta
			v.x *= drag
			if v.y > 210.0:
				v.y = lerpf(v.y, 210.0, minf(delta * 4.0, 1.0))
			vel[i] = v
			pos[i] = pos[i] + (v + Vector2(sin(t * 2.6 + i) * 40.0, 0.0)) * delta
			rot[i] = rot[i] + spin[i] * delta
		queue_redraw()

	func _draw() -> void:
		if t <= 0.0:
			return
		var age := duration - t
		var ray_a := clampf(age * 2.5, 0.0, 1.0) * clampf(t - 0.6, 0.0, 1.0) * 0.2
		if ray_a > 0.0:
			var base := age * 0.35
			for k in 14:
				var a0 := base + k * TAU / 14.0
				var pts := PackedVector2Array([focus, focus + Vector2.from_angle(a0 - 0.07) * 760.0, focus + Vector2.from_angle(a0 + 0.07) * 760.0])
				var cols := PackedColorArray([Color(1.0, 0.88, 0.5, ray_a), Color(1.0, 0.86, 0.45, 0.0), Color(1.0, 0.86, 0.45, 0.0)])
				draw_polygon(pts, cols)
			# Resplandor suave (círculos concéntricos de poca opacidad).
			for k in 4:
				draw_circle(focus, 60.0 + k * 34.0, Color(1.0, 0.9, 0.6, ray_a * 0.28))
		var fade := clampf(t / 0.8, 0.0, 1.0)
		for i in pos.size():
			var c := col[i]
			c.a = fade
			Icons.leaf(self, pos[i], leaf_size[i], c, rot[i])


var touch: TouchInputManager
var _zone_name: Label
var _zone_pct: Label
var _zone_bar: ProgressBar
var _zone_rem: Label
var _money: Label
var _money_shown := 0.0
var _tool_name: Label
var _tool_status: Label
var _bag_bar: ProgressBar
var _bag_label: Label
var _carry: Label
var _prompt: Label
var _hint: PanelContainer
var _hint_label: Label
var _hint_t := 0.0
var _banner: Label
var _banner_t := 0.0
var _objective: Label
var _toasts: VBoxContainer
var _fps: Label
var _top_left: PanelContainer
var _top_right: HBoxContainer
var _bottom: PanelContainer
var _popups: Array = []
var _radar: PackedVector3Array = PackedVector3Array()
var _radar_t := 0.0
var _tut_t := 0.0
var _tut_start := Vector3.INF
var _tut_yaw := 0.0
var _safe := Rect2()
var _markers: GuideMarkers
var _journal_btn: IconButton
var _badge: Badge
var _upgrade_t := 0.5
var upgrade_available := ""
var _upgrade_toast_at := -1000.0
var gain := 0
var _gain_t := 0.0
var _gain_pop := 0.0
var _bag_pulse := 0.0
var _bag_icon: IconView
var _bag_value: Label
var _fill_styles: Array[StyleBoxFlat] = []
var _celebration: Celebration
var _celeb_box: VBoxContainer
var _celeb_title: Label
var _celeb_sub: Label
var celebrations := 0
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.get_theme()
	_build()
	EventBus.money_earned.connect(_on_money_earned)
	EventBus.bag_changed.connect(_on_bag_changed)
	EventBus.tool_changed.connect(_on_tool_changed)
	EventBus.upgrade_purchased.connect(_on_upgrade)
	EventBus.hint.connect(show_hint)
	EventBus.toast.connect(add_toast)
	EventBus.zone_entered.connect(_on_zone_entered)
	EventBus.zone_progress.connect(_on_zone_progress)
	EventBus.leaves_collected.connect(_on_leaves_collected)
	EventBus.zone_completed.connect(_on_zone_completed)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _panel(radius: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.box(Color(UITheme.PAPER, 0.92), radius, UITheme.WOOD, 4, 14, true)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _build() -> void:
	_markers = GuideMarkers.new()
	add_child(_markers)
	for c in [UITheme.GREEN, Color(0.93, 0.66, 0.18), UITheme.RED]:
		_fill_styles.append(UITheme.box(c, 10, Color(0, 0, 0, 0), 0, 0))
	_top_left = _panel()
	add_child(_top_left)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_top_left.add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)
	_zone_name = UITheme.label("Entrada", 26, UITheme.INK)
	row.add_child(_zone_name)
	_zone_pct = UITheme.label("0,0 %", 26, UITheme.ACCENT_DARK)
	row.add_child(_zone_pct)
	_zone_bar = ProgressBar.new()
	_zone_bar.custom_minimum_size = Vector2(280, 14)
	_zone_bar.show_percentage = false
	v.add_child(_zone_bar)
	_zone_rem = UITheme.label("", 18, UITheme.INK_SOFT)
	v.add_child(_zone_rem)
	_objective = UITheme.label("", 17, UITheme.INK_SOFT)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD
	_objective.custom_minimum_size = Vector2(280, 0)
	v.add_child(_objective)

	_top_right = HBoxContainer.new()
	_top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_right)
	var money_panel := _panel()
	var mrow := HBoxContainer.new()
	money_panel.add_child(mrow)
	var coin := IconView.new()
	coin.icon = "coin"
	coin.color = UITheme.GOLD
	coin.custom_minimum_size = Vector2(40, 40)
	mrow.add_child(coin)
	_money = UITheme.label("0 $", 30, UITheme.INK)
	mrow.add_child(_money)
	_top_right.add_child(money_panel)
	for id in ["journal", "pause"]:
		var b := IconButton.new()
		b.icon_name = id
		b.custom_minimum_size = Vector2(76, 76)
		if id == "journal":
			b.pressed.connect(_on_journal_pressed)
			_journal_btn = b
			_badge = Badge.new()
			_badge.position = Vector2(50, -8)
			_badge.visible = false
			b.add_child(_badge)
		else:
			b.pressed.connect(func(): EventBus.open_menu.emit(id))
		_top_right.add_child(b)

	_bottom = _panel(16)
	add_child(_bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 0)
	_bottom.add_child(bv)
	var brow := HBoxContainer.new()
	bv.add_child(brow)
	_tool_name = UITheme.label("Manos", 22, UITheme.INK)
	brow.add_child(_tool_name)
	_tool_status = UITheme.label("", 17, UITheme.INK_SOFT)
	_tool_status.visible = false
	brow.add_child(_tool_status)
	_bag_icon = IconView.new()
	_bag_icon.icon = "bag"
	_bag_icon.color = Color(0.2, 0.42, 0.24)
	_bag_icon.custom_minimum_size = Vector2(30, 30)
	_bag_icon.pivot_offset = Vector2(15, 15)
	brow.add_child(_bag_icon)
	_bag_bar = ProgressBar.new()
	_bag_bar.custom_minimum_size = Vector2(200, 20)
	_bag_bar.show_percentage = false
	_bag_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(_bag_bar)
	_bag_label = UITheme.label("0 / 50", 20, UITheme.INK)
	brow.add_child(_bag_label)
	_bag_value = UITheme.label("", 17, UITheme.ACCENT_DARK)
	_bag_value.visible = false
	brow.add_child(_bag_value)
	_carry = UITheme.label("", 17, UITheme.ACCENT_DARK)
	bv.add_child(_carry)
	_bottom.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PAPER, 0.85), 14, UITheme.WOOD, 3, 10, true))

	_prompt = UITheme.outlined("", 22)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt)

	_hint = _panel()
	_hint_label = UITheme.label("", 22, UITheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint_label.custom_minimum_size = Vector2(460, 0)
	_hint.add_child(_hint_label)
	_hint.modulate.a = 0.0
	add_child(_hint)

	_banner = UITheme.outlined("", 48, UITheme.CREAM)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	add_child(_banner)

	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_toasts)

	_fps = UITheme.outlined("", 18)
	add_child(_fps)

	_celebration = Celebration.new()
	_celebration.visible = false
	add_child(_celebration)
	_celeb_box = VBoxContainer.new()
	_celeb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_celeb_box.add_theme_constant_override("separation", 0)
	_celeb_title = UITheme.outlined("", 64, UITheme.GOLD, Color(0.3, 0.14, 0.05))
	_celeb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_celeb_box.add_child(_celeb_title)
	_celeb_sub = UITheme.outlined("", 28, UITheme.CREAM)
	_celeb_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_celeb_box.add_child(_celeb_sub)
	_celeb_box.modulate.a = 0.0
	add_child(_celeb_box)


func _layout() -> void:
	var vs := get_viewport_rect().size
	_safe = Rect2(Vector2.ZERO, vs)
	if OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var ws := Vector2(DisplayServer.window_get_size())
		if ws.x > 0 and sa.size.x > 0:
			var k := vs / ws
			_safe = Rect2(Vector2(sa.position) * k, Vector2(sa.size) * k)
	_safe = _safe.grow(-14.0)
	_top_left.position = _safe.position
	_top_right.position = Vector2(_safe.end.x - _top_right.get_combined_minimum_size().x, _safe.position.y)
	_toasts.position = Vector2(_safe.end.x - 420, _safe.position.y + 96)
	_toasts.size = Vector2(420, 400)
	_fps.position = Vector2(_safe.get_center().x - 40, _safe.position.y)


func _process(delta: float) -> void:
	_time += delta
	_update_celebration(delta)
	var p := touch._player() if touch else null
	if p == null:
		return
	# Dinero con conteo animado.
	_money_shown = lerpf(_money_shown, EconomyManager.money, minf(delta * 8.0, 1.0))
	if absf(_money_shown - EconomyManager.money) < 0.5:
		_money_shown = EconomyManager.money
	_money.text = "∞" if GameManager.is_zen() else EconomyManager.format_money(_money_shown)
	_top_right.position = Vector2(_safe.end.x - _top_right.get_combined_minimum_size().x, _safe.position.y)
	# Barra inferior centrada.
	var bsize := _bottom.get_combined_minimum_size()
	_bottom.size = bsize
	_bottom.position = Vector2(_safe.get_center().x - bsize.x * 0.5, _safe.end.y - bsize.y)
	if p.bags.is_carrying():
		var worth := "" if GameManager.is_zen() else " (≈ %s)" % EconomyManager.format_money(p.bags.held_value * EconomyManager.multiplier())
		_carry.text = "Llevas una bolsa de %d hojas%s: lánzala o llévala al contenedor" % [p.bags.held_leaves, worth]
		_carry.visible = true
	else:
		_carry.visible = false
	# Texto de interacción encima del botón.
	var ib := touch._btn("interact")
	_prompt.text = p.prompt
	_prompt.modulate = Color(1, 1, 1, 1.0 if p.prompt_available else 0.65)
	var psize := _prompt.get_combined_minimum_size()
	_prompt.size = psize
	_prompt.position = Vector2(minf(ib.center.x - psize.x * 0.5, _safe.end.x - psize.x), ib.center.y - ib.radius - psize.y - 6)
	# Aviso.
	if _hint_t > 0.0:
		_hint_t -= delta
		_hint.modulate.a = clampf(_hint_t * 2.0, 0.0, 1.0)
		var hs := _hint.get_combined_minimum_size()
		_hint.size = hs
		_hint.position = Vector2(_safe.get_center().x - hs.x * 0.5, _safe.position.y + 8)
	else:
		_hint.modulate.a = 0.0
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(minf(_banner_t, 2.6 - _banner_t) * 2.0, 0.0, 1.0)
		var bs := _banner.get_combined_minimum_size()
		_banner.size = bs
		_banner.position = Vector2(_safe.get_center().x - bs.x * 0.5, _safe.position.y + vs_h() * 0.2)
	if GameManager.is_time_attack() and p.get_parent().has_method("time_attack_seconds"):
		var secs: float = p.get_parent().time_attack_seconds()
		_banner.text = "%d:%02d" % [int(secs) / 60, int(secs) % 60]
		_banner_t = 1.3
	_fps.visible = SettingsManager.get_value("show_fps", false)
	if _fps.visible:
		_fps.text = "%d FPS · %s · %d hojas activas" % [Engine.get_frames_per_second(), PerformanceManager.preset()["name"], p.leaf_manager.sim.active_n]
	_update_popups(delta)
	_update_radar(delta, p)
	_tutorial(delta, p)
	_markers.visible = InputState.enabled
	_markers.update_markers(delta, p)
	_update_upgrade_badge(delta)
	_update_feedback(delta, p)
	queue_redraw()


func vs_h() -> float:
	return get_viewport_rect().size.y


func _on_bag_changed(_c: int, _cap: int) -> void:
	_refresh_bag()


func _on_tool_changed(_t: String) -> void:
	_refresh_tool()


func _on_upgrade(_id: String, _lvl: int) -> void:
	_refresh_tool()
	_refresh_bag()


func _on_zone_progress(z: String, _p: float) -> void:
	if z == AreaManager.current_zone:
		_refresh_zone()


func _refresh_zone() -> void:
	var z := AreaManager.current_zone
	if z == "":
		return
	var def := GameData.zone_by_id(z)
	_zone_name.text = def["name"]
	var pct := AreaManager.pct(z)
	_zone_pct.text = ("%.1f %%" % pct).replace(".", ",")
	_zone_bar.value = pct
	var rem := int(AreaManager.remaining.get(z, 0))
	_zone_rem.text = "Zona restaurada" if rem <= 0 else "Quedan %d hojas" % rem
	var obj := ObjectiveManager.pending(1)
	if obj.is_empty() or GameManager.is_zen():
		_objective.text = ""
	else:
		var o: Dictionary = obj[0]
		_objective.text = "Objetivo: %s (%d/%d)" % [o["name"], int(minf(ProgressManager.get_stat(o["stat"]), o["target"])), int(o["target"])]


func _refresh_bag() -> void:
	var p := touch._player() if touch else null
	if p == null:
		return
	var cap := p.bags.capacity()
	_bag_bar.max_value = cap
	_bag_bar.value = p.bags.count
	_bag_label.text = "%d / %d" % [p.bags.count, cap]
	var full := p.bags.count >= cap
	var level := 2 if full else (1 if p.bags.count >= cap * 0.8 else 0)
	_bag_bar.add_theme_stylebox_override("fill", _fill_styles[level])
	# Valor estimado de lo que llevas en la bolsa abierta (ayuda a entender la economía).
	_bag_value.visible = p.bags.count > 0 and not GameManager.is_zen()
	if _bag_value.visible:
		_bag_value.text = "≈ " + EconomyManager.format_money(p.bags.value * EconomyManager.multiplier())


func _refresh_tool() -> void:
	var p := touch._player() if touch else null
	if p == null or p.tools.current == null:
		return
	for t in GameData.TOOLS:
		if t["id"] == p.tools.current.tool_id:
			_tool_name.text = t["name"]
	_tool_status.text = p.tools.current.status_text()


func refresh_all() -> void:
	_refresh_zone()
	_refresh_bag()
	_refresh_tool()
	_money_shown = EconomyManager.money


func _on_zone_entered(z: String) -> void:
	_refresh_zone()
	if z == "" or _celebration.active():
		return
	_banner.text = GameData.zone_by_id(z)["name"]
	_banner_t = 2.6


func show_hint(text: String, seconds: float = 4.0) -> void:
	if _hint_label.text == text and _hint_t > 0.5:
		_hint_t = maxf(_hint_t, seconds * 0.5)
		return
	_hint_label.text = text
	_hint_t = seconds


func add_toast(title: String, body: String, kind: String) -> void:
	var p := _panel(14)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var col := UITheme.ACCENT_DARK
	if kind == "achievement":
		col = Color(0.55, 0.35, 0.7)
	elif kind == "objective":
		col = UITheme.GREEN.darkened(0.2)
	elif kind == "upgrade":
		col = Color(0.78, 0.26, 0.18)
	v.add_child(UITheme.label(title, 20, col))
	var b := UITheme.label(body, 18, UITheme.INK)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD
	b.custom_minimum_size = Vector2(380, 0)
	v.add_child(b)
	p.modulate.a = 0.0
	_toasts.add_child(p)
	while _toasts.get_child_count() > 4:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _on_money_earned(amount: float, world_pos: Vector3) -> void:
	var l := UITheme.outlined("+" + EconomyManager.format_money(amount), 34, UITheme.GOLD)
	add_child(l)
	var vs := get_viewport_rect().size
	var start := Vector2(vs.x * 0.5, vs.y * 0.42)
	var cam := get_viewport().get_camera_3d()
	if world_pos != Vector3.INF and cam and not cam.is_position_behind(world_pos):
		start = cam.unproject_position(world_pos)
	l.position = start - l.get_combined_minimum_size() * 0.5
	_popups.append({"l": l, "t": 1.6})


func _update_popups(delta: float) -> void:
	for i in range(_popups.size() - 1, -1, -1):
		var pp: Dictionary = _popups[i]
		pp["t"] = float(pp["t"]) - delta
		var l: Label = pp["l"]
		l.position.y -= delta * 60.0
		l.modulate.a = clampf(float(pp["t"]), 0.0, 1.0)
		if float(pp["t"]) <= 0.0:
			l.queue_free()
			_popups.remove_at(i)


func _update_radar(delta: float, p: PlayerController) -> void:
	_radar_t -= delta
	if _radar_t > 0.0:
		return
	_radar_t = 1.0
	_radar = PackedVector3Array()
	var z := AreaManager.current_zone
	if z == "":
		return
	var rem := int(AreaManager.remaining.get(z, 0))
	if rem > 0 and rem <= 15:
		_radar = p.leaf_manager.sim.remaining_in_zone(GameData.zone_index(z), 15)


func _draw() -> void:
	if not GameManager.in_game:
		return
	var vs := get_viewport_rect().size
	# Punto de mira discreto; se convierte en un aro dorado al apuntar a algo con lo que interactuar.
	var p := touch._player() if touch else null
	if p and p.target != null and p.prompt != "":
		var ring := Color(UITheme.GOLD, 0.95 if p.prompt_available else 0.5)
		draw_arc(vs * 0.5, 11.0, 0, TAU, 28, Color(0, 0, 0, 0.35), 4.5, true)
		draw_arc(vs * 0.5, 11.0, 0, TAU, 28, ring, 2.5, true)
		draw_circle(vs * 0.5, 2.5, ring)
	else:
		draw_circle(vs * 0.5, 3.0, Color(1, 1, 1, 0.75))
		draw_arc(vs * 0.5, 4.0, 0, TAU, 16, Color(0, 0, 0, 0.35), 1.0, true)
	_draw_gain(vs)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	for wp in _radar:
		var pos := wp + Vector3(0, 0.6, 0)
		var sp: Vector2
		if cam.is_position_behind(pos):
			continue
		sp = cam.unproject_position(pos)
		sp.x = clampf(sp.x, 30, vs.x - 30)
		sp.y = clampf(sp.y, 30, vs.y - 30)
		var bounce := sin(t * 4.0) * 4.0
		Icons.leaf(self, sp + Vector2(0, bounce), 26.0, Color(1.0, 0.75, 0.2, 0.9), 0.4)
		draw_arc(sp + Vector2(0, bounce), 17.0, 0, TAU, 20, Color(1, 1, 1, 0.8), 2.0, true)


# ------------------------------------------------------------------ mejoras disponibles

func _update_upgrade_badge(delta: float) -> void:
	_upgrade_t -= delta
	if _upgrade_t > 0.0:
		return
	_upgrade_t = 1.0
	check_upgrades()


## Busca la mejora más barata que se puede comprar ahora; enciende la insignia y avisa una vez.
func check_upgrades() -> void:
	var best := ""
	if not GameManager.is_zen() and not GameManager.is_time_attack():
		var best_cost := INF
		for id in GameData.UPGRADES:
			if UpgradeManager.can_buy(id):
				var c := float(UpgradeManager.next_cost(id))
				if c < best_cost:
					best_cost = c
					best = id
	if best != "" and upgrade_available == "":
		var now := Time.get_ticks_msec() / 1000.0
		var in_tutorial := GameManager.mode == "campaign" and ProgressManager.tutorial_step < 7
		if not in_tutorial and now - _upgrade_toast_at >= float(GameData.GUIDES["upgrade_toast_cooldown"]):
			_upgrade_toast_at = now
			var def: Dictionary = GameData.UPGRADES[best]
			add_toast("Mejora disponible", "%s · %s. Toca el diario para comprarla." % [def["name"], EconomyManager.format_money(UpgradeManager.next_cost(best))], "upgrade")
			AudioManager.play_ui("notify", -4.0)
	upgrade_available = best
	_badge.visible = best != ""


func _on_journal_pressed() -> void:
	var ui := get_parent() as UIManager
	if upgrade_available != "" and ui and GameManager.in_game:
		ui.open_journal("shop")
	else:
		EventBus.open_menu.emit("journal")


# ------------------------------------------------------------------ recoger: "+N" y pulso de la bolsa

func _on_leaves_collected(count: int, source: String) -> void:
	if source != "hand" and source != "vacuum":
		return
	if _gain_t < 0.35:
		gain = 0
	gain += count
	_gain_t = 1.15
	_gain_pop = 1.0
	_bag_pulse = 1.0


func _update_feedback(delta: float, p: PlayerController) -> void:
	_gain_t = maxf(_gain_t - delta, 0.0)
	_gain_pop = maxf(_gain_pop - delta * 5.0, 0.0)
	_bag_pulse = maxf(_bag_pulse - delta * 3.0, 0.0)
	var pulse := _bag_pulse
	if p.bags.is_full():
		pulse = maxf(pulse, 0.35 + 0.35 * sin(_time * 7.0))
	_bag_icon.scale = Vector2.ONE * (1.0 + 0.3 * _bag_pulse)
	_bag_bar.modulate = Color(1, 1, 1).lerp(Color(1.4, 1.3, 1.05), pulse)


func _draw_gain(vs: Vector2) -> void:
	if _gain_t <= 0.0 or gain <= 0:
		return
	var font := get_theme_default_font()
	var a := clampf(_gain_t / 0.35, 0.0, 1.0)
	var rise := (0.35 - minf(_gain_t, 0.35)) * 90.0
	var fs := int(30.0 * (1.0 + 0.35 * _gain_pop))
	var txt := "+%d" % gain
	var at := vs * 0.5 + Vector2(40, -36 - rise)
	Icons.leaf(self, at + Vector2(-16, -fs * 0.35), 24.0, Color(0.98, 0.72, 0.2, a), -0.5)
	draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0.25, 0.12, 0.04, 0.9 * a))
	draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.92, 0.6, a))


# ------------------------------------------------------------------ zona restaurada: celebración

func _on_zone_completed(zid: String) -> void:
	if not GameManager.in_game:
		return
	var z := GameData.zone_by_id(zid)
	if z.is_empty():
		return
	var title := "¡Zona restaurada!"
	var sub := "%s vuelve a lucir como antes" % z["name"]
	if z.get("secret", false):
		title = "¡Taller restaurado!"
		sub = "Clementina estaría orgullosa"
	elif AreaManager.completed_main_count() >= 10:
		title = "¡Villa Hojarasca restaurada!"
		sub = "Has devuelto la vida a toda la finca. ¡Gracias!"
	celebrate(title, sub)


func celebrate(title: String, sub: String) -> void:
	celebrations += 1
	_celeb_title.text = title
	_celeb_sub.text = sub
	var vs := get_viewport_rect().size
	var amount := int(80 * float(PerformanceManager.preset()["particles"]))
	_celebration.burst(maxi(amount, 24), vs)
	_banner_t = 0.0
	_banner.modulate.a = 0.0
	_celeb_box.scale = Vector2.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(_celeb_box, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play_ui("fanfare", -2.0)
	HapticManager.pulse(160, 0.9)
	var p := touch._player() if touch else null
	if p:
		p.cam.add_shake(0.3)


func is_celebrating() -> bool:
	return _celebration.active()


func _update_celebration(_delta: float) -> void:
	if not _celebration.active():
		if _celeb_box.modulate.a > 0.0:
			_celeb_box.modulate.a = 0.0
		return
	var t := _celebration.t
	var age := _celebration.duration - t
	_celeb_box.modulate.a = clampf(minf(age * 4.0, (t - 0.3) * 1.5), 0.0, 1.0)
	var bs := _celeb_box.get_combined_minimum_size()
	_celeb_box.size = bs
	_celeb_box.pivot_offset = bs * 0.5
	var center := Vector2(_safe.get_center().x, _safe.position.y + vs_h() * 0.3)
	_celeb_box.position = center - bs * 0.5
	_celebration.focus = center


# ------------------------------------------------------------------ tutorial contextual

func _tutorial(delta: float, p: PlayerController) -> void:
	if GameManager.mode != "campaign" or ProgressManager.tutorial_step >= 7:
		return
	_tut_t -= delta
	if _tut_t > 0.0:
		return
	_tut_t = 0.5
	var step := ProgressManager.tutorial_step
	if _tut_start == Vector3.INF:
		_tut_start = p.global_position
		_tut_yaw = p.rotation.y
	var advance := false
	match step:
		0:
			show_hint("Mueve el joystick de la izquierda para caminar.", 1.0)
			advance = p.global_position.distance_to(_tut_start) > 3.0
		1:
			show_hint("Arrastra el dedo por la derecha de la pantalla para mirar.", 1.0)
			advance = absf(wrapf(p.rotation.y - _tut_yaw, -PI, PI)) > 0.9
		2:
			show_hint("Apunta a las hojas y pulsa el botón grande para recogerlas.", 1.0)
			advance = ProgressManager.get_stat("leaves_collected") >= 10
		3:
			show_hint("Sigue recogiendo hasta llenar la bolsa (%d/%d)." % [p.bags.count, p.bags.capacity()], 1.0)
			advance = p.bags.is_full() or p.bags.is_carrying() or ProgressManager.get_stat("bags_used") > 0
		4:
			show_hint("Mantén pulsado INTERACTUAR (botón de arriba) para cerrar la bolsa.", 1.0)
			advance = p.bags.is_carrying() or ProgressManager.get_stat("bags_used") > 0
		5:
			show_hint("Lleva la bolsa al contenedor verde de RECICLAJE (o lánzala dentro con el botón grande).", 1.0)
			advance = ProgressManager.get_stat("bags_delivered") >= 1
		6:
			show_hint("¡Dinero! Ve al TALLER o abre el diario para comprar tu primera mejora.", 1.0)
			advance = ProgressManager.get_stat("upgrades_bought") >= 1
	if advance:
		ProgressManager.tutorial_step = step + 1
		_tut_start = p.global_position
		_tut_yaw = p.rotation.y
		if ProgressManager.tutorial_step >= 7:
			show_hint("¡Perfecto! Limpia la entrada para abrir el jardín. Tu objetivo: restaurar toda la finca.", 6.0)
