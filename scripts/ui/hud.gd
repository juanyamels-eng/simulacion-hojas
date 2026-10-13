class_name HUD
extends Control
## HUD minimalista: zona y % arriba a la izquierda, dinero arriba a la derecha,
## herramienta y bolsa abajo. Avisos, notificaciones, tutorial y radar de las últimas hojas.

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
	get_viewport().size_changed.connect(_layout)
	_layout()


func _panel(radius: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.box(Color(UITheme.PAPER, 0.92), radius, UITheme.WOOD, 4, 14, true)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _build() -> void:
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
	var bag_icon := IconView.new()
	bag_icon.icon = "bag"
	bag_icon.color = Color(0.2, 0.42, 0.24)
	bag_icon.custom_minimum_size = Vector2(30, 30)
	brow.add_child(bag_icon)
	_bag_bar = ProgressBar.new()
	_bag_bar.custom_minimum_size = Vector2(200, 20)
	_bag_bar.show_percentage = false
	_bag_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(_bag_bar)
	_bag_label = UITheme.label("0 / 50", 20, UITheme.INK)
	brow.add_child(_bag_label)
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
		_carry.text = "Llevas una bolsa de %d hojas: lánzala o llévala al contenedor" % p.bags.held_leaves
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
	var fill := UITheme.box(UITheme.RED if full else UITheme.GREEN, 10, Color(0, 0, 0, 0), 0, 0)
	_bag_bar.add_theme_stylebox_override("fill", fill)


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
	if z == "":
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
	# Punto de mira discreto.
	draw_circle(vs * 0.5, 3.0, Color(1, 1, 1, 0.75))
	draw_arc(vs * 0.5, 4.0, 0, TAU, 16, Color(0, 0, 0, 0.35), 1.0, true)
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
