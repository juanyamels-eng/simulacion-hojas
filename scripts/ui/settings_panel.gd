class_name SettingsPanel
extends Modal
## Ajustes: gráficos, FPS, resaltar hojas (contorno de color para verlas en cualquier suelo), cámara (sensibilidad, invertir Y, balanceo, FOV, giroscopio),
## volúmenes independientes, vibración y tamaño de controles.


func _init() -> void:
	super()
	set_title("Ajustes")


func _ready() -> void:
	super._ready()
	var v := scroll_box()
	v.add_child(_section("Gráficos"))
	v.add_child(_choice("Calidad", "graphics", [["auto", "Automático"], ["low", "Bajo"], ["medium", "Medio"], ["high", "Alto"]]))
	v.add_child(_choice("Límite de FPS", "fps", [[30, "30"], [60, "60"], [0, "Máximo"]]))
	v.add_child(_toggle("Mostrar FPS", "show_fps"))
	v.add_child(_toggle("Resaltar hojas", "highlight_leaves"))
	v.add_child(_section("Cámara y controles"))
	v.add_child(_slider("Sensibilidad horizontal", "sens_x", 0.2, 3.0, 0.05))
	v.add_child(_slider("Sensibilidad vertical", "sens_y", 0.2, 3.0, 0.05))
	v.add_child(_toggle("Invertir eje Y", "invert_y"))
	v.add_child(_toggle("Balanceo al caminar", "head_bob"))
	v.add_child(_slider("Campo de visión (FOV)", "fov", 60.0, 95.0, 1.0))
	v.add_child(_toggle("Giroscopio", "gyro"))
	v.add_child(_slider("Tamaño de los controles", "joystick_size", 0.8, 1.3, 0.05))
	v.add_child(_section("Sonido"))
	v.add_child(_slider("Música", "music", 0.0, 1.0, 0.05))
	v.add_child(_slider("Efectos", "sfx", 0.0, 1.0, 0.05))
	v.add_child(_slider("Ambiente", "ambient", 0.0, 1.0, 0.05))
	v.add_child(_toggle("Vibración", "haptics"))


func _section(t: String) -> Label:
	var l := UITheme.label(t, 28, UITheme.ACCENT_DARK)
	return l


func _row(text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UITheme.label(text, 22, UITheme.INK)
	l.custom_minimum_size = Vector2(330, 0)
	h.add_child(l)
	return h


func _slider(text: String, key: String, mn: float, mx: float, step: float) -> HBoxContainer:
	var h := _row(text)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(SettingsManager.get_value(key))
	s.custom_minimum_size = Vector2(320, 48)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := UITheme.label("", 22, UITheme.WOOD_DARK)
	val.custom_minimum_size = Vector2(80, 0)
	var fmt := func(x: float) -> String:
		return ("%d" % int(x)) if mx > 10.0 else ("%d %%" % int(round(x * 100.0)) if mx <= 1.0 else "%.2f" % x)
	val.text = fmt.call(s.value)
	s.value_changed.connect(func(x: float):
		val.text = fmt.call(x)
		SettingsManager.set_value(key, x))
	h.add_child(s)
	h.add_child(val)
	return h


func _toggle(text: String, key: String) -> HBoxContainer:
	var h := _row(text)
	var c := CheckButton.new()
	c.button_pressed = bool(SettingsManager.get_value(key))
	c.custom_minimum_size = Vector2(90, 48)
	c.toggled.connect(func(on: bool):
		AudioManager.play_ui("click")
		SettingsManager.set_value(key, on))
	h.add_child(c)
	return h


func _choice(text: String, key: String, options: Array) -> HBoxContainer:
	var h := _row(text)
	var current: Variant = SettingsManager.get_value(key)
	var buttons: Array[Button] = []
	for o in options:
		var value: Variant = o[0]
		var b := UITheme.button(o[1], func(): pass, 20, 120)
		b.custom_minimum_size.y = 52
		buttons.append(b)
		h.add_child(b)
		b.pressed.connect(func():
			SettingsManager.set_value(key, value)
			_mark(buttons, options, value))
	_mark(buttons, options, current)
	return h


func _mark(buttons: Array[Button], options: Array, value: Variant) -> void:
	for k in buttons.size():
		var b := buttons[k]
		if options[k][0] == value:
			for st in ["normal", "hover", "pressed"]:
				b.remove_theme_stylebox_override(st)
		else:
			UITheme.secondary(b)
