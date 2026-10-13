class_name UITheme
## Tema visual: otoño, madera, papel y tonos cálidos. Todo construido en código.

const PAPER := Color(0.97, 0.91, 0.8)
const PAPER_DARK := Color(0.9, 0.82, 0.68)
const INK := Color(0.24, 0.15, 0.09)
const INK_SOFT := Color(0.42, 0.3, 0.2)
const WOOD := Color(0.55, 0.33, 0.18)
const WOOD_DARK := Color(0.36, 0.21, 0.11)
const ACCENT := Color(0.89, 0.47, 0.16)
const ACCENT_DARK := Color(0.72, 0.33, 0.1)
const GREEN := Color(0.36, 0.58, 0.28)
const RED := Color(0.78, 0.27, 0.2)
const GOLD := Color(0.98, 0.78, 0.3)
const CREAM := Color(1.0, 0.97, 0.9)

static var _theme: Theme


static func box(bg: Color, radius: int = 18, border: Color = Color(0, 0, 0, 0), border_w: int = 0, pad: int = 14, shadow: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	s.anti_aliasing = true
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.25)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 3)
	return s


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 24
	var normal := box(ACCENT, 16, ACCENT_DARK, 3, 16)
	normal.border_width_bottom = 6
	var hover := box(ACCENT.lightened(0.08), 16, ACCENT_DARK, 3, 16)
	hover.border_width_bottom = 6
	var pressed := box(ACCENT_DARK, 16, ACCENT_DARK.darkened(0.2), 3, 16)
	pressed.border_width_top = 5
	pressed.border_width_bottom = 2
	var disabled := box(Color(0.7, 0.62, 0.52), 16, Color(0.55, 0.48, 0.4), 3, 16)
	disabled.border_width_bottom = 6
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", CREAM)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", Color(0.95, 0.9, 0.82))
	t.set_color("font_outline_color", "Button", ACCENT_DARK.darkened(0.3))
	t.set_constant("outline_size", "Button", 4)
	t.set_font_size("font_size", "Button", 26)
	t.set_stylebox("panel", "PanelContainer", box(PAPER, 22, WOOD, 5, 22, true))
	t.set_stylebox("panel", "Panel", box(PAPER, 22, WOOD, 5, 22, true))
	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", 24)
	var bar_bg := box(Color(0.3, 0.2, 0.12, 0.85), 10, Color(0, 0, 0, 0), 0, 0)
	var bar_fill := box(ACCENT, 10, Color(0, 0, 0, 0), 0, 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", CREAM)
	var slider := box(Color(0.5, 0.38, 0.27), 8, Color(0, 0, 0, 0), 0, 0)
	slider.content_margin_top = 6
	slider.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", slider)
	var grab_area := box(ACCENT, 8, Color(0, 0, 0, 0), 0, 0)
	t.set_stylebox("grabber_area", "HSlider", grab_area)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab_area)
	t.set_icon("grabber", "HSlider", _circle_tex(34, CREAM, ACCENT_DARK))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(34, Color.WHITE, ACCENT_DARK))
	var scroll := box(Color(0.5, 0.38, 0.27, 0.5), 8, Color(0, 0, 0, 0), 0, 0)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", box(WOOD, 8, Color(0, 0, 0, 0), 0, 6))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(WOOD_DARK, 8, Color(0, 0, 0, 0), 0, 6))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(WOOD_DARK, 8, Color(0, 0, 0, 0), 0, 6))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_color("font_color", "CheckButton", INK)
	t.set_font_size("font_size", "CheckButton", 24)
	_theme = t
	return t


static func _circle_tex(size: int, fill: Color, border: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var r := size * 0.5 - 1.0
			if d <= r - 3.0:
				img.set_pixel(x, y, fill)
			elif d <= r:
				img.set_pixel(x, y, border)
			elif d <= r + 1.0:
				img.set_pixel(x, y, Color(border, r + 1.0 - d))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 24, color: Color = INK, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func outlined(text: String, size: int, color: Color = CREAM, outline: Color = Color(0.2, 0.12, 0.06)) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	return l


static func button(text: String, cb: Callable, size: int = 26, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, 64)
	b.pressed.connect(func():
		AudioManager.play_ui("click")
		HapticManager.pulse(10, 0.2)
		cb.call())
	return b


static func secondary(b: Button) -> Button:
	var n := box(WOOD, 16, WOOD_DARK, 3, 16)
	n.border_width_bottom = 6
	var p := box(WOOD_DARK, 16, WOOD_DARK.darkened(0.2), 3, 16)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", p)
	return b
