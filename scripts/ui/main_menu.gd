class_name MainMenu
extends Control
## Menú principal sobre la finca real (cámara cinemática y hojas cayendo de fondo).

var ui: UIManager
var _logo: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.05, 0.02, 0.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.12, 0.06, 0.02, 0.75))
	g.set_color(1, Color(0.12, 0.06, 0.02, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.anchor_right = 0.6
	grad.offset_right = 0.0
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grad)
	var col := VBoxContainer.new()
	col.anchor_left = 0.05
	col.anchor_top = 0.06
	col.anchor_bottom = 0.96
	col.anchor_right = 0.42
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	_logo = Logo.new()
	_logo.custom_minimum_size = Vector2(440, 190)
	col.add_child(_logo)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	col.add_child(spacer)
	var has_save := SaveManager.has_save("campaign") and not GameManager.requested_new
	if has_save:
		col.add_child(UITheme.button("CONTINUAR", func(): ui.start_game(), 30, 380))
	col.add_child(UITheme.button("NUEVA PARTIDA", _new_game, 28, 380))
	col.add_child(UITheme.secondary(UITheme.button("MODOS", func(): ui.open_modes(), 26, 380)))
	col.add_child(UITheme.secondary(UITheme.button("AJUSTES", func(): ui.push(SettingsPanel.new()), 26, 380)))
	var row := HBoxContainer.new()
	col.add_child(row)
	row.add_child(UITheme.secondary(UITheme.button("CRÉDITOS", func(): ui.open_credits(), 22, 184)))
	row.add_child(UITheme.secondary(UITheme.button("SALIR", func(): GameManager.quit_game(), 22, 184)))
	var ver := UITheme.outlined("v" + str(ProjectSettings.get_setting("application/config/version")), 16)
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.position = Vector2(-90, -36)
	add_child(ver)


func _new_game() -> void:
	var exists := SaveManager.has_save("campaign") and not GameManager.requested_new
	if exists:
		ui.confirm("Se borrará la partida actual de la campaña. ¿Empezar de nuevo?", func(): GameManager.launch("campaign", true))
	elif GameManager.mode == "campaign":
		ui.start_game()
	else:
		GameManager.launch("campaign", true)
