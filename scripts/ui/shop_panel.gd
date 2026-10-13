class_name ShopPanel
extends HBoxContainer
## Árbol de mejoras por categorías con tarjetas de compra.

var category := "hands"
var _cats: VBoxContainer
var _list: VBoxContainer
var _money: Label


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cats = VBoxContainer.new()
	_cats.custom_minimum_size = Vector2(250, 0)
	add_child(_cats)
	_money = UITheme.label("", 28, UITheme.ACCENT_DARK)
	_cats.add_child(_money)
	for c in GameData.CATEGORIES:
		var cid: String = c["id"]
		var b := UITheme.button(c["name"], func(): _select(cid), 20, 240)
		b.custom_minimum_size.y = 52
		b.set_meta("cat", cid)
		_cats.add_child(b)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	EventBus.money_changed.connect(_on_money)
	_select(category)


func _on_money(_m: float) -> void:
	if is_inside_tree():
		_refresh()


func _select(cid: String) -> void:
	category = cid
	_refresh()


func _refresh() -> void:
	_money.text = "∞" if GameManager.is_zen() else EconomyManager.format_money(EconomyManager.money)
	for b in _cats.get_children():
		if b is Button:
			var sel: bool = b.get_meta("cat") == category
			b.modulate = Color(1, 1, 1) if sel else Color(0.85, 0.8, 0.75)
			if sel:
				for st in ["normal", "hover", "pressed"]:
					b.remove_theme_stylebox_override(st)
			else:
				UITheme.secondary(b)
	for c in _list.get_children():
		c.queue_free()
	for id in GameData.UPGRADES:
		var def: Dictionary = GameData.UPGRADES[id]
		if def["cat"] == category:
			_list.add_child(_card(id, def))


func _card(id: String, def: Dictionary) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(UITheme.PAPER_DARK, 16, Color(UITheme.WOOD, 0.5), 2, 14))
	var h := HBoxContainer.new()
	p.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var lvl := UpgradeManager.get_level(id)
	var maxl := UpgradeManager.max_level(id)
	var title := HBoxContainer.new()
	v.add_child(title)
	title.add_child(UITheme.label(def["name"], 26, UITheme.INK))
	var pips := ""
	for k in maxl:
		pips += "●" if k < lvl else "○"
	if maxl > 1:
		title.add_child(UITheme.label(pips, 20, UITheme.ACCENT))
	var desc := UITheme.label(def["desc"], 18, UITheme.INK_SOFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(desc)
	var now := UpgradeManager.format_value(id, lvl)
	var stat_text := "Actual: " + now
	if lvl < maxl:
		stat_text += "   →   " + UpgradeManager.format_value(id, lvl + 1)
	v.add_child(UITheme.label(stat_text, 20, UITheme.WOOD_DARK))
	var reason := UpgradeManager.lock_reason(id)
	var btn: Button
	if lvl >= maxl:
		btn = UITheme.button("Máximo", func(): pass, 22, 190)
		btn.disabled = true
	elif reason != "":
		btn = UITheme.button("Bloqueado", func(): pass, 22, 190)
		btn.disabled = true
		var rl := UITheme.label(reason, 17, UITheme.RED)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.add_child(rl)
	else:
		var cost := UpgradeManager.next_cost(id)
		btn = UITheme.button("Gratis" if GameManager.is_zen() else EconomyManager.format_money(cost), func(): _buy(id), 24, 190)
		btn.disabled = not EconomyManager.can_afford(cost)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(btn)
	return p


func _buy(id: String) -> void:
	if UpgradeManager.buy(id):
		var def: Dictionary = GameData.UPGRADES[id]
		EventBus.toast.emit("Mejora comprada", "%s · %s" % [def["name"], UpgradeManager.format_value(id, UpgradeManager.get_level(id))], "reward")
	else:
		AudioManager.play_ui("error")
	_refresh()
