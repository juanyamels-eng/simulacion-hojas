class_name UIManager
extends CanvasLayer
## Gestiona HUD, controles táctiles y la pila de menús (pausa, diario, tienda, ajustes, notas...).

const RECORDS := "user://records.cfg"

var hud: HUD
var touch: TouchInputManager
var main_menu: MainMenu
var loading: Control
var stack: Array[Control] = []
var world: Node


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch = TouchInputManager.new()
	touch.visible = false
	add_child(touch)
	hud = HUD.new()
	hud.touch = touch
	hud.visible = false
	add_child(hud)
	move_child(touch, -1)
	EventBus.open_menu.connect(_on_open_menu)
	EventBus.note_read.connect(show_note)


func show_loading() -> void:
	loading = ColorRect.new()
	(loading as ColorRect).color = Color(0.16, 0.1, 0.07)
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	var l := UITheme.outlined("Villa Hojarasca", 64, UITheme.GOLD)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	loading.add_child(l)
	var sub := UITheme.outlined("Barriendo el camino…", 26, UITheme.CREAM)
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.position.y -= 90
	loading.add_child(sub)
	add_child(loading)


func hide_loading() -> void:
	if loading:
		var tw := create_tween()
		tw.tween_property(loading, "modulate:a", 0.0, 0.5)
		tw.tween_callback(loading.queue_free)
		loading = null


func bind_world(w: Node) -> void:
	world = w


func show_main_menu() -> void:
	hud.visible = false
	touch.visible = false
	main_menu = MainMenu.new()
	main_menu.ui = self
	add_child(main_menu)
	if world:
		world.set_menu_mode(true)


func start_game() -> void:
	if main_menu:
		main_menu.queue_free()
		main_menu = null
	if world:
		world.set_menu_mode(false)
	GameManager.start_playing()
	hud.visible = true
	touch.visible = true
	hud.refresh_all()
	InputState.reset()
	InputState.enabled = true


func push(m: Control) -> void:
	touch.release_all()
	add_child(m)
	stack.append(m)
	if m.has_signal("closed"):
		m.closed.connect(_on_closed.bind(m))
	_update_pause()
	AudioManager.play_ui("open")


func _on_closed(m: Control) -> void:
	stack.erase(m)
	_update_pause()
	hud.refresh_all()


func close_top() -> void:
	if stack.is_empty():
		return
	var m: Control = stack.back()
	if m is Modal:
		(m as Modal).close_modal()
	else:
		stack.pop_back()
		m.queue_free()
		_update_pause()


func _update_pause() -> void:
	var menu_open := not stack.is_empty()
	get_tree().paused = menu_open and GameManager.in_game
	InputState.enabled = not menu_open and GameManager.in_game
	if menu_open:
		AudioManager.stop_all_tool_loops()


func _on_open_menu(menu: String) -> void:
	match menu:
		"pause":
			if stack.is_empty() and GameManager.in_game:
				open_pause()
		"pause_if_playing":
			if stack.is_empty() and GameManager.in_game:
				open_pause()
		"journal":
			if GameManager.in_game:
				open_journal("map")
		"shop":
			if GameManager.in_game:
				open_journal("shop", "Taller de Brizna")
		"back":
			if not stack.is_empty():
				close_top()
			elif GameManager.in_game:
				open_pause()
			else:
				confirm("¿Salir del juego?", func(): GameManager.quit_game())


func open_journal(tab: String, title: String = "") -> void:
	var j := Journal.new()
	j.tab = tab
	if title != "":
		j.set_title(title)
	push(j)


func open_pause() -> void:
	var m := Modal.new()
	m.set_title("Pausa")
	m.size_ratio = Vector2(0.46, 0.8)
	var v := m.content
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UITheme.button("CONTINUAR", func(): m.close_modal(), 30))
	v.add_child(UITheme.button("DIARIO", func(): open_journal("map"), 28))
	v.add_child(UITheme.secondary(UITheme.button("AJUSTES", func(): push(SettingsPanel.new()), 28)))
	if GameManager.is_time_attack():
		v.add_child(UITheme.secondary(UITheme.button("REINICIAR CONTRARRELOJ", _restart_time_attack, 26)))
	else:
		v.add_child(UITheme.secondary(UITheme.button("REINICIAR ZONA", _ask_reset_zone.bind(m), 26)))
	v.add_child(UITheme.secondary(UITheme.button("MENÚ PRINCIPAL", func(): return_to_menu(), 28)))
	push(m)


func _restart_time_attack() -> void:
	GameManager.launch("time_attack", true, GameManager.time_attack_zone)


func _ask_reset_zone(pause_modal: Modal) -> void:
	var z := AreaManager.current_zone
	if z == "":
		return
	var text := "¿Devolver todas las hojas de %s a su sitio? Las recompensas ya cobradas se conservan." % GameData.zone_by_id(z)["name"]
	confirm(text, _do_reset_zone.bind(pause_modal, z))


func _do_reset_zone(pause_modal: Modal, z: String) -> void:
	if is_instance_valid(pause_modal):
		pause_modal.close_modal()
	world.reset_zone(z)


func return_to_menu() -> void:
	SaveManager.save_game()
	GameManager.in_game = false
	GameManager.skip_menu = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func show_note(title: String, text: String) -> void:
	var m := Modal.new()
	m.set_title(title)
	m.size_ratio = Vector2(0.6, 0.62)
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", UITheme.box(Color(1.0, 0.97, 0.88), 8, Color(0.75, 0.6, 0.4), 2, 26))
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var l := UITheme.label(text, 26, UITheme.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	paper.add_child(l)
	m.content.add_child(paper)
	m.content.add_child(UITheme.button("Cerrar", func(): m.close_modal(), 26))
	push(m)


func confirm(text: String, on_yes: Callable) -> void:
	var m := Modal.new()
	m.set_title("¿Seguro?")
	m.size_ratio = Vector2(0.5, 0.45)
	var l := UITheme.label(text, 24, UITheme.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.content.add_child(l)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UITheme.secondary(UITheme.button("No", func(): m.close_modal(), 26, 160)))
	h.add_child(UITheme.button("Sí", _confirm_yes.bind(m, on_yes), 26, 160))
	m.content.add_child(h)
	push(m)


func _confirm_yes(m: Modal, on_yes: Callable) -> void:
	m.close_modal()
	on_yes.call()


func open_modes() -> void:
	var m := Modal.new()
	m.set_title("Modos de juego")
	m.size_ratio = Vector2(0.7, 0.86)
	var v := m.scroll_box()
	_mode_row(v, "Campaña", "Restaura la finca: el modo principal.", _mode_campaign.bind(m))
	_mode_row(v, "Zen", "Todas las herramientas, dinero ilimitado, sin objetivos. Solo limpiar.", _mode_zen)
	var ng_ok := AchievementManager.is_unlocked("zones_10")
	var ng_desc := "Conserva tus mejoras, más hojas y recompensas multiplicadas." if ng_ok else "Se desbloquea al restaurar toda la finca."
	_mode_row(v, "Nueva partida +", ng_desc, _mode_ngplus, not ng_ok)
	v.add_child(UITheme.label("Contrarreloj", 30, UITheme.ACCENT_DARK))
	var cfg := ConfigFile.new()
	cfg.load(RECORDS)
	for zid in ["entrada", "jardin_delantero", "garaje", "zona_infantil"]:
		var z := GameData.zone_by_id(zid)
		var best: float = cfg.get_value("time_attack", zid, 0.0)
		var rec := "Récord: %s" % _fmt_time(best) if best > 0.0 else "Sin récord"
		_mode_row(v, z["name"], "Limpia la zona al 100 % lo antes posible. " + rec, GameManager.launch.bind("time_attack", true, zid))
	push(m)


func _mode_campaign(m: Modal) -> void:
	m.close_modal()
	_continue_or_new()


func _mode_zen() -> void:
	GameManager.launch("zen", not SaveManager.has_save("zen"))


func _mode_ngplus() -> void:
	confirm("Empezar Nueva partida+ (se reinicia la campaña conservando las mejoras).", _launch_ngplus)


func _launch_ngplus() -> void:
	GameManager.launch("ngplus", true)


func _mode_row(v: VBoxContainer, title: String, desc: String, cb: Callable, disabled: bool = false) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(UITheme.PAPER_DARK, 16, Color(UITheme.WOOD, 0.5), 2, 14))
	var h := HBoxContainer.new()
	p.add_child(h)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(UITheme.label(title, 26, UITheme.INK))
	var d := UITheme.label(desc, 18, UITheme.INK_SOFT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	tv.add_child(d)
	h.add_child(tv)
	var b := UITheme.button("Jugar", cb, 24, 150)
	b.disabled = disabled
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	v.add_child(p)


func _continue_or_new() -> void:
	if GameManager.mode == "campaign" and SaveManager.slot == "campaign":
		start_game()
	else:
		GameManager.launch("campaign", false)


static func _fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func open_credits() -> void:
	var m := Modal.new()
	m.set_title("Créditos")
	m.size_ratio = Vector2(0.6, 0.75)
	var l := UITheme.label("VILLA HOJARASCA\n\nUn juego original de limpieza de hojas.\n\nDiseño, programación, modelos 3D procedurales, sonido y música sintetizados por código: equipo de Villa Hojarasca.\n\nMotor: Godot Engine 4.5 (licencia MIT).\n\nNo se ha utilizado ningún recurso de otros juegos.\n\nGracias por jugar. Solo una hoja más…", 22, UITheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.content.add_child(l)
	push(m)


func time_attack_finished(zone_id: String, seconds: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(RECORDS)
	var best: float = cfg.get_value("time_attack", zone_id, 0.0)
	var record := best <= 0.0 or seconds < best
	if record:
		cfg.set_value("time_attack", zone_id, seconds)
		cfg.save(RECORDS)
	var m := Modal.new()
	m.set_title("¡Zona limpia!")
	m.size_ratio = Vector2(0.5, 0.55)
	m.closable = false
	var txt := "Tiempo: %s" % _fmt_time(seconds)
	txt += "\n¡Nuevo récord!" if record else "\nRécord: %s" % _fmt_time(best)
	var l := UITheme.label(txt, 34, UITheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.content.add_child(l)
	m.content.add_child(UITheme.button("Otra vez", func(): GameManager.launch("time_attack", true, zone_id), 26))
	m.content.add_child(UITheme.secondary(UITheme.button("Menú principal", func(): return_to_menu(), 26)))
	push(m)
	AudioManager.play_ui("achievement")
