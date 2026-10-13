class_name Modal
extends Control
## Ventana modal con fondo oscurecido y panel de papel. Base de todos los menús.

signal closed

var panel: PanelContainer
var content: VBoxContainer
var title_label: Label
var header: HBoxContainer
var size_ratio := Vector2(0.86, 0.88)
var closable := true


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.02, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	header = HBoxContainer.new()
	outer.add_child(header)
	title_label = UITheme.label("", 36, UITheme.WOOD_DARK)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(content)


func set_title(t: String) -> Modal:
	title_label.text = t
	return self


func _ready() -> void:
	if closable:
		var close := UITheme.secondary(UITheme.button("✕", close_modal, 28, 72))
		close.text = "X"
		header.add_child(close)
	get_viewport().size_changed.connect(_fit)
	_fit()
	modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _fit() -> void:
	var vs := get_viewport_rect().size
	var sz := vs * size_ratio
	panel.custom_minimum_size = sz
	panel.size = sz
	panel.position = (vs - sz) * 0.5
	panel.pivot_offset = sz * 0.5


func close_modal() -> void:
	closed.emit()
	queue_free()


func scroll_box() -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v
