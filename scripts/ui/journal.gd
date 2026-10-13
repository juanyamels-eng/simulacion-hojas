class_name Journal
extends Modal
## Diario: MAPA, OBJETIVOS, MEJORAS, COLECCIÓN, ESTADÍSTICAS y LOGROS.

const TABS := [["map", "MAPA"], ["objectives", "OBJETIVOS"], ["shop", "MEJORAS"], ["collection", "COLECCIÓN"], ["stats", "ESTADÍSTICAS"], ["achievements", "LOGROS"]]

var tab := "map"
var shop_category := ""
var _tabs: HBoxContainer
var _body: Control


func _init() -> void:
	super()
	set_title("Diario de la finca")
	size_ratio = Vector2(0.92, 0.92)


func _ready() -> void:
	super._ready()
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	content.add_child(_tabs)
	for t in TABS:
		var id: String = t[0]
		var b := UITheme.button(t[1], func(): _show(id), 19)
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("tab", id)
		_tabs.add_child(b)
	_show(tab)


func _show(id: String) -> void:
	tab = id
	for b in _tabs.get_children():
		if b.get_meta("tab") == id:
			for st in ["normal", "hover", "pressed"]:
				b.remove_theme_stylebox_override(st)
		else:
			UITheme.secondary(b)
	if _body:
		_body.queue_free()
	match id:
		"map": _body = _map()
		"objectives": _body = _objectives()
		"shop":
			var sp := ShopPanel.new()
			if shop_category != "":
				sp.category = shop_category
			_body = sp
		"collection": _body = _collection()
		"stats": _body = _stats()
		"achievements": _body = _achievements()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_body)


func _scroll() -> Array:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return [sc, v]


func _map() -> Control:
	var m := MapView.new()
	return m


func _objectives() -> Control:
	var s := _scroll()
	var v: VBoxContainer = s[1]
	for o in GameData.OBJECTIVES:
		var done: bool = ObjectiveManager.done.get(o["id"], false)
		var row := HBoxContainer.new()
		v.add_child(row)
		var l := UITheme.label(("✔ " if done else "") + String(o["name"]), 22, UITheme.GREEN.darkened(0.3) if done else UITheme.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(220, 20)
		bar.show_percentage = false
		bar.value = 100.0 if done else ObjectiveManager.progress(o) * 100.0
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		row.add_child(UITheme.label(EconomyManager.format_money(o["reward"]), 20, UITheme.ACCENT_DARK))
	return s[0]


func _collection() -> Control:
	var s := _scroll()
	var v: VBoxContainer = s[1]
	v.add_child(UITheme.label("Postales encontradas: %d / %d" % [CollectibleManager.found.size(), GameData.POSTCARDS.size()], 24, UITheme.WOOD_DARK))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for p in GameData.POSTCARDS:
		var found := CollectibleManager.is_found(p["id"])
		var card: Dictionary = p
		var b := UITheme.button(String(p["title"]) if found else "? ? ?", func(): EventBus.note_read.emit(card["title"], card["text"]), 18, 200)
		b.custom_minimum_size = Vector2(200, 90)
		b.disabled = not found
		var zone := GameData.zone_by_id(p["zone"])
		b.tooltip_text = zone.get("name", "")
		grid.add_child(b)
	if ProgressManager.has_flag("copper_rake"):
		v.add_child(UITheme.label("Recompensa: Rastrillo de cobre (aspecto) desbloqueado.", 22, UITheme.ACCENT_DARK))
	else:
		v.add_child(UITheme.label("Encuentra las 12 postales para desbloquear un aspecto especial.", 20, UITheme.INK_SOFT))
	v.add_child(UITheme.label("Notas leídas: %d" % (CollectibleManager.notes_read.size()), 20, UITheme.INK_SOFT))
	return s[0]


func _stats() -> Control:
	var s := _scroll()
	var v: VBoxContainer = s[1]
	for key in ProgressManager.STAT_NAMES:
		var row := HBoxContainer.new()
		v.add_child(row)
		var l := UITheme.label(ProgressManager.STAT_NAMES[key], 22, UITheme.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var val := ProgressManager.get_stat(key)
		var txt := str(int(val))
		if key == "money_earned":
			txt = EconomyManager.format_money(val)
		elif key == "play_time":
			txt = ProgressManager.format_time(val)
		elif key == "zones_completed":
			txt = "%d / 10" % int(val)
		row.add_child(UITheme.label(txt, 22, UITheme.WOOD_DARK))
	return s[0]


func _achievements() -> Control:
	var s := _scroll()
	var v: VBoxContainer = s[1]
	v.add_child(UITheme.label("Logros: %d / %d" % [AchievementManager.unlocked.size(), GameData.ACHIEVEMENTS.size()], 24, UITheme.WOOD_DARK))
	for a in GameData.ACHIEVEMENTS:
		var got := AchievementManager.is_unlocked(a["id"])
		var row := HBoxContainer.new()
		v.add_child(row)
		var ic := IconView.new()
		ic.icon = "leaf"
		ic.color = UITheme.GOLD if got else Color(0.6, 0.55, 0.5)
		ic.custom_minimum_size = Vector2(34, 34)
		row.add_child(ic)
		var l := UITheme.label("%s — %s" % [a["name"], a["desc"]], 21, UITheme.INK if got else UITheme.INK_SOFT)
		l.modulate.a = 1.0 if got else 0.6
		row.add_child(l)
	return s[0]
