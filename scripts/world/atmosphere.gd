class_name Atmosphere
extends Node3D
## Luz y aire de la finca: cielo estilizado con nubes, sol cálido contra ambiente frío, niebla con
## dispersión solar, etalonado suave, viñeta, hojas que caen dando vueltas, motas de polvo al sol,
## remolinos de hojas en las ráfagas y bandadas de pájaros. Todo barato y escalado según la calidad.

const MENU_DAY := 0.765          # luz dorada fija para el menú principal
const DUST_BASE := 36
const FALL_BASE := 70
const SWIRL_BASE := 26
const BIRDS_MAX := 7

## Colores reales de las hojas del suelo (mismos tonos y pesos que la hojarasca).
const LEAF_TONES := [
	[Color(0.96, 0.76, 0.18), 0.27],
	[Color(0.95, 0.52, 0.12), 0.3],
	[Color(0.84, 0.24, 0.1), 0.18],
	[Color(0.58, 0.35, 0.16), 0.19],
	[Color(0.5, 0.62, 0.2), 0.06],
]

## Fotogramas clave del día:
## [t, elevación°, azimut°, color sol, energía sol, cénit, horizonte, energía ambiente, opacidad sombra, nubes]
## El sol sale por la derecha de la entrada (+X), cruza por detrás de quien mira a la casa y se pone por la
## izquierda (−X): la fachada queda iluminada de lado y las sombras cruzan los caminos.
## En el crepúsculo (luz mínima y sin sombras) el sol salta al amanecer sin que se note.
const KEYS := [
	[0.0, 7.0, 108.0, Color(1.0, 0.7, 0.48), 0.85, Color(0.36, 0.52, 0.78), Color(1.0, 0.78, 0.6), 0.42, 0.7, 0.5],
	[0.1, 21.0, 88.0, Color(1.0, 0.85, 0.66), 1.1, Color(0.28, 0.52, 0.86), Color(0.98, 0.86, 0.7), 0.4, 1.0, 0.54],
	[0.33, 50.0, 28.0, Color(1.0, 0.95, 0.86), 1.25, Color(0.24, 0.49, 0.88), Color(0.84, 0.88, 0.9), 0.4, 1.0, 0.56],
	[0.62, 33.0, -28.0, Color(1.0, 0.87, 0.68), 1.2, Color(0.27, 0.49, 0.85), Color(0.96, 0.85, 0.68), 0.4, 1.0, 0.54],
	[0.8, 16.0, -55.0, Color(1.0, 0.74, 0.46), 1.18, Color(0.29, 0.45, 0.78), Color(1.0, 0.74, 0.48), 0.4, 1.0, 0.5],
	[0.9, 5.0, -70.0, Color(1.0, 0.57, 0.32), 0.95, Color(0.24, 0.35, 0.62), Color(1.0, 0.62, 0.36), 0.42, 0.85, 0.48],
	[0.95, 1.5, -76.0, Color(1.0, 0.55, 0.35), 0.45, Color(0.16, 0.22, 0.46), Color(0.95, 0.6, 0.42), 0.46, 0.3, 0.46],
	[0.97, 1.0, -78.0, Color(0.88, 0.62, 0.56), 0.3, Color(0.17, 0.24, 0.48), Color(0.82, 0.64, 0.58), 0.5, 0.0, 0.46],
	[0.97, 1.0, 112.0, Color(0.88, 0.62, 0.56), 0.3, Color(0.17, 0.24, 0.48), Color(0.82, 0.64, 0.58), 0.5, 0.0, 0.46],
	[1.0, 7.0, 108.0, Color(1.0, 0.7, 0.48), 0.85, Color(0.36, 0.52, 0.78), Color(1.0, 0.78, 0.6), 0.42, 0.7, 0.5],
]

const LEAF_FALL_SHADER := """
shader_type spatial;
// Hoja que cae: da vueltas sobre sí misma y se mece (todo en el vértice, opaca y barata).
render_mode cull_disabled, specular_disabled, diffuse_lambert_wrap;

void vertex() {
	float ph = float(INSTANCE_ID) * 2.399;
	float sp = 1.4 + fract(ph * 0.618) * 1.8;
	float t = TIME * sp + ph;
	float ax = sin(t) * 1.4;
	float az = cos(t * 0.73 + ph) * 1.1;
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(ax), sin(ax)), vec3(0.0, -sin(ax), cos(ax)));
	mat3 rz = mat3(vec3(cos(az), sin(az), 0.0), vec3(-sin(az), cos(az), 0.0), vec3(0.0, 0.0, 1.0));
	mat3 r = rz * rx;
	VERTEX = r * VERTEX + vec3(sin(t * 0.5), 0.0, cos(t * 0.43)) * 0.12;
	NORMAL = r * NORMAL;
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		c *= 0.8;
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""

const BIRD_SHADER := """
shader_type spatial;
// Silueta de pájaro: alas que baten y planean de vez en cuando.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.2, 0.15, 0.13);

void vertex() {
	float ph = float(INSTANCE_ID) * 1.73;
	float w = abs(VERTEX.x);
	float flap = smoothstep(0.15, 0.55, sin(TIME * 0.55 + ph) * 0.5 + 0.5);
	VERTEX.y += (sin(TIME * 10.0 + ph * 3.1) * flap + (1.0 - flap) * 0.22) * w * 0.6;
}

void fragment() {
	ALBEDO = tint;
}
"""

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var falling: CPUParticles3D
var rain: CPUParticles3D
var dust: CPUParticles3D
var swirl: CPUParticles3D
var birds: MultiMeshInstance3D
var vignette: CanvasLayer
var leaf_material: ShaderMaterial
var dust_material: StandardMaterial3D
var bird_material: ShaderMaterial
var lamp_material: StandardMaterial3D
var level := 1
var _cloud_off := Vector2(0.37, 0.12)
var _bird_wait := 7.0
var _bird_t := 0.0
var _bird_from := Vector3.ZERO
var _bird_dir := Vector3.FORWARD
var _bird_side := Vector3.RIGHT
var _bird_speed := 10.0
var _bird_len := 240.0
var _bird_count := 5
var _swirl_pos := Vector3.ZERO
var _overcast := 0.0
var _overcast_target := 0.0


# ------------------------------------------------------------------ construcción

func build() -> void:
	name = "Atmosphere"
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("cloud_noise", _cloud_tex())
	sky_mat.set_shader_parameter("sky_energy", 1.15)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	# Ambiente desde el cielo (azulado arriba, cálido en el horizonte) con un rebote cálido del suelo.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.82
	env.ambient_light_color = Color(0.62, 0.48, 0.34)
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.84
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0042
	env.fog_sun_scatter = 0.32
	env.fog_sky_affect = 0.0
	env.fog_light_energy = 1.0
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 42.0
	sun.directional_shadow_fade_start = 0.75
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	add_child(sun)
	_build_vignette()


func _cloud_tex() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.011
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5
	var img := noise.get_seamless_image(256, 256)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_vignette() -> void:
	vignette = CanvasLayer.new()
	vignette.name = "Vignette"
	vignette.layer = 5
	var rect := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.width = 128
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.08, 1.08)
	var g := Gradient.new()
	var edge := Color(0.13, 0.06, 0.02)
	g.set_color(0, Color(edge, 0.0))
	g.set_offset(0, 0.0)
	g.set_color(1, Color(edge, 0.42))
	g.set_offset(1, 1.0)
	g.add_point(0.58, Color(edge, 0.0))
	g.add_point(0.82, Color(edge, 0.13))
	gt.gradient = g
	rect.texture = gt
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.add_child(rect)
	add_child(vignette)


func _palette_ramp() -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	var acc := 0.0
	for pe in LEAF_TONES:
		offs.append(acc)
		cols.append(pe[0])
		acc += float(pe[1])
	g.offsets = offs
	g.colors = cols
	return g


func build_particles() -> void:
	leaf_material = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = LEAF_FALL_SHADER
	leaf_material.shader = sh
	var ramp := _palette_ramp()
	# Hojas que caen alrededor de quien mira: forma real de hoja, colores reales, giran al caer.
	falling = CPUParticles3D.new()
	falling.name = "FallingLeaves"
	falling.amount = FALL_BASE
	falling.lifetime = 10.0
	falling.preprocess = 10.0
	falling.local_coords = false
	falling.mesh = MeshFactory.leaf_mesh()
	falling.material_override = leaf_material
	falling.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	falling.emission_box_extents = Vector3(16, 1.2, 16)
	falling.direction = Vector3(0.0, -1.0, 0.0)
	falling.spread = 20.0
	falling.gravity = Vector3(0.05, -0.05, 0.02)
	falling.initial_velocity_min = 0.7
	falling.initial_velocity_max = 1.1
	falling.scale_amount_min = 1.0
	falling.scale_amount_max = 1.6
	falling.color_initial_ramp = ramp
	falling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(falling)
	# Remolino de hojas que levanta cada ráfaga de viento.
	swirl = CPUParticles3D.new()
	swirl.name = "GustSwirl"
	swirl.amount = SWIRL_BASE
	swirl.one_shot = true
	swirl.emitting = false
	swirl.lifetime = 3.6
	swirl.explosiveness = 0.55
	swirl.randomness = 0.5
	swirl.local_coords = false
	swirl.mesh = MeshFactory.leaf_mesh()
	swirl.material_override = leaf_material
	swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	swirl.emission_sphere_radius = 1.3
	swirl.direction = Vector3(0, 1, 0)
	swirl.spread = 30.0
	swirl.initial_velocity_min = 2.4
	swirl.initial_velocity_max = 4.2
	swirl.gravity = Vector3(0, -1.7, 0)
	swirl.tangential_accel_min = 6.0
	swirl.tangential_accel_max = 9.0
	swirl.radial_accel_min = -2.6
	swirl.radial_accel_max = -1.2
	swirl.damping_min = 0.3
	swirl.damping_max = 0.7
	swirl.scale_amount_min = 1.1
	swirl.scale_amount_max = 1.6
	swirl.color_initial_ramp = ramp
	swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(swirl)
	# Motas de polvo y semillas flotando en la luz (diminutas, aditivas, sin niebla).
	dust_material = StandardMaterial3D.new()
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dust_material.vertex_color_use_as_albedo = true
	dust_material.disable_fog = true
	dust_material.disable_receive_shadows = true
	dust_material.albedo_texture = _dot_tex()
	dust_material.albedo_color = Color(1.0, 0.85, 0.6)
	dust = CPUParticles3D.new()
	dust.name = "DustMotes"
	dust.amount = DUST_BASE
	dust.lifetime = 7.0
	dust.preprocess = 7.0
	dust.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.045)
	dust.mesh = q
	dust.material_override = dust_material
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(5.5, 1.6, 5.5)
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 180.0
	dust.initial_velocity_min = 0.03
	dust.initial_velocity_max = 0.14
	dust.gravity = Vector3(0.03, 0.015, 0.0)
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.7, Color(1, 1, 1, 0.8))
	dust.color_ramp = fade
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)
	# Llovizna (solo tras completar la campaña).
	rain = CPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 160
	rain.lifetime = 1.0
	rain.local_coords = false
	rain.mesh = MeshFactory.box(Vector3(0.01, 0.35, 0.01))
	rain.material_override = MeshFactory.mat(Color(0.75, 0.82, 0.9), 0.2, 0.3)
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(14, 1, 14)
	rain.direction = Vector3(0, -1, 0)
	rain.spread = 3.0
	rain.gravity = Vector3(0, -20, 0)
	rain.initial_velocity_min = 8.0
	rain.initial_velocity_max = 10.0
	rain.emitting = false
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)
	_build_birds()
	# Las farolas (material compartido de sus globos) se encienden al caer la tarde.
	lamp_material = MeshFactory.mat(Color(1.0, 0.86, 0.55))
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.62, 0.26)
	lamp_material.emission_energy_multiplier = 0.25
	apply_quality(level)


func _dot_tex() -> Texture2D:
	var gt := GradientTexture2D.new()
	gt.width = 32
	gt.height = 32
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	gt.gradient = g
	return gt


func _build_birds() -> void:
	var verts := PackedVector3Array()
	# Cuerpo y cola.
	verts.append_array([Vector3(0, 0, -0.34), Vector3(0.07, 0, 0.08), Vector3(-0.07, 0, 0.08)])
	verts.append_array([Vector3(0, 0, 0.05), Vector3(0.12, 0, 0.34), Vector3(-0.12, 0, 0.34)])
	# Alas: tramo interior y punta barrida hacia atrás (simétricas).
	for sx: float in [1.0, -1.0]:
		var a := Vector3(0.05 * sx, 0, -0.13)
		var b := Vector3(0.05 * sx, 0, 0.1)
		var c := Vector3(0.42 * sx, 0.03, -0.06)
		var d := Vector3(0.42 * sx, 0.03, 0.1)
		var e := Vector3(0.78 * sx, 0.0, 0.2)
		verts.append_array([a, b, c, c, b, d, c, d, e])
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for k in verts.size():
		norms.append(Vector3.UP)
		cols.append(Color.WHITE)
		idx.append(k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	bird_material = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BIRD_SHADER
	bird_material.shader = sh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = BIRDS_MAX
	mm.visible_instance_count = BIRDS_MAX
	birds = MultiMeshInstance3D.new()
	birds.name = "Birds"
	birds.multimesh = mm
	birds.material_override = bird_material
	birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	birds.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))
	birds.visible = false
	add_child(birds)


# ------------------------------------------------------------------ calidad

func apply_quality(lv: int) -> void:
	level = lv
	var p: Dictionary = PerformanceManager.PRESETS[lv]
	var pf: float = p["particles"]
	var high := lv == PerformanceManager.HIGH
	var low := lv == PerformanceManager.LOW
	sun.shadow_enabled = p["shadows"]
	if high:
		# Dos cortes: sombras nítidas cerca y alcance largo para las copas lejanas.
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_split_1 = 0.22
		sun.directional_shadow_max_distance = 64.0
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 40.0
	get_viewport().scaling_3d_scale = float(p["scale"])
	# Etalonado suave (algo más de contraste y saturación). En Compatibility va en la misma pasada que el
	# escalado de resolución 3D de Medio/Bajo, así que es casi gratis; sin él el cielo sale lavado.
	# El resplandor (glow) se probó: funciona, pero apenas se nota con esta luz y cuesta varias pasadas.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.04
	env.glow_enabled = false
	vignette.visible = not low
	sky_mat.set_shader_parameter("cloud_alpha", 0.9)
	sky_mat.set_shader_parameter("cloud_detail", 0.0 if low else 1.0)
	if falling:
		falling.amount = maxi(int(FALL_BASE * pf), 12)
		swirl.amount = maxi(int(SWIRL_BASE * pf), 10)
		dust.amount = maxi(int(DUST_BASE * pf), 10)
		dust.visible = not low
		dust.emitting = not low
		_bird_count = 3 if low else (5 if lv == PerformanceManager.MEDIUM else BIRDS_MAX)
		birds.multimesh.visible_instance_count = _bird_count


# ------------------------------------------------------------------ ciclo de luz

func update_light(day: float) -> void:
	var ia := 0
	for k in KEYS.size() - 1:
		if day >= float(KEYS[k][0]) and day <= float(KEYS[k + 1][0]):
			ia = k
			break
	var a: Array = KEYS[ia]
	var b: Array = KEYS[ia + 1]
	var span := float(b[0]) - float(a[0])
	var t := 1.0 if span < 0.00001 else clampf((day - float(a[0])) / span, 0.0, 1.0)
	var elev := deg_to_rad(lerpf(a[1], b[1], t))
	var az := deg_to_rad(lerpf(a[2], b[2], t))
	var sun_col: Color = (a[3] as Color).lerp(b[3], t)
	var sun_e := lerpf(a[4], b[4], t)
	var zenith: Color = (a[5] as Color).lerp(b[5], t)
	var horizon: Color = (a[6] as Color).lerp(b[6], t)
	var amb := lerpf(a[7], b[7], t)
	var shadow := lerpf(a[8], b[8], t)
	var cover := lerpf(a[9], b[9], t)
	# Cielo encapotado mientras llovizna (transición de ~10 s).
	_overcast = move_toward(_overcast, _overcast_target, 0.05)
	if _overcast > 0.0:
		var oc := _overcast
		sun_e *= 1.0 - 0.55 * oc
		shadow *= 1.0 - 0.6 * oc
		cover -= 0.28 * oc
		zenith = zenith.lerp(Color(0.5, 0.55, 0.62), 0.55 * oc)
		horizon = horizon.lerp(Color(0.72, 0.72, 0.72), 0.45 * oc)
	# 0 de día, 1 con el sol bajo el horizonte: farolas, luciérnagas.
	var night := 1.0 - clampf((rad_to_deg(elev) - 2.0) / 10.0, 0.0, 1.0)
	sun.rotation = Vector3(-elev, az, 0.0)
	sun.light_color = sun_col
	sun.light_energy = sun_e
	sun.shadow_opacity = clampf(shadow, 0.0, 1.0)
	env.ambient_light_energy = amb
	env.ambient_light_color = Color(0.64, 0.5, 0.36).lerp(horizon, 0.3)
	# Niebla del color del horizonte (algo más fría y oscura) para fundir el fondo con el cielo.
	env.fog_light_color = horizon.lerp(zenith, 0.22).darkened(0.08)
	var low_sun := 1.0 - clampf(elev / deg_to_rad(40.0), 0.0, 1.0)
	env.fog_sun_scatter = 0.18 + 0.3 * low_sun
	var sm := sky_mat
	sm.set_shader_parameter("zenith_color", zenith)
	sm.set_shader_parameter("horizon_color", horizon)
	sm.set_shader_parameter("ground_color", Color(0.46, 0.47, 0.3).lerp(horizon, 0.45).darkened(0.1))
	sm.set_shader_parameter("sun_tint", sun_col)
	sm.set_shader_parameter("sun_glow", 0.7 + 0.6 * low_sun)
	sm.set_shader_parameter("horizon_glow", 0.25 + 0.45 * low_sun)
	sm.set_shader_parameter("cloud_lit", Color(1.0, 0.98, 0.95).lerp(sun_col, 0.2 + 0.5 * low_sun))
	sm.set_shader_parameter("cloud_shade", zenith.lerp(horizon, 0.55).lerp(sun_col, 0.12).darkened(0.12))
	sm.set_shader_parameter("cloud_cover", cover)
	sm.set_shader_parameter("cloud_offset", _cloud_off)
	if dust_material:
		# Motas doradas de día; al anochecer se vuelven luciérnagas.
		var glow := clampf(sun_e / 1.5, 0.0, 1.0)
		var mote := Color(sun_col.r, sun_col.g * 0.95, sun_col.b * 0.85) * (0.55 + 0.45 * glow)
		dust_material.albedo_color = mote.lerp(Color(0.8, 1.0, 0.38), night)
	if lamp_material:
		lamp_material.emission_energy_multiplier = 0.2 + 1.5 * night
	if bird_material:
		bird_material.set_shader_parameter("tint", Color(0.2, 0.15, 0.14).lerp(zenith, 0.15).darkened(0.25 * (1.0 - clampf(sun_e, 0.0, 1.0))))


## Cada fotograma: deriva de las nubes (se envía al cielo junto con la luz) y viento en las partículas.
func update_wind(wind: Vector3, dt: float) -> void:
	_cloud_off += Vector2(wind.x, wind.z) * dt * 0.00045
	_cloud_off = Vector2(fposmod(_cloud_off.x, 1.0), fposmod(_cloud_off.y, 1.0))
	if falling:
		falling.gravity = Vector3(wind.x * 0.14, -0.05, wind.z * 0.14)
		dust.gravity = Vector3(wind.x * 0.05, 0.012, wind.z * 0.05)


# ------------------------------------------------------------------ por fotograma

func follow(focus: Vector3, delta: float) -> void:
	falling.global_position = focus + Vector3(0, 8.5, 0)
	rain.global_position = focus + Vector3(0, 10, 0)
	dust.global_position = focus + Vector3(0, 1.3, 0)
	if swirl.emitting:
		swirl.global_position = _swirl_pos
	_update_birds(focus, delta)


## Llovizna: activa las gotas y encapota el cielo poco a poco.
func set_rain(on: bool) -> void:
	if rain.emitting != on:
		rain.emitting = on
	_overcast_target = 1.0 if on else 0.0


## Remolino visual de hojas en el centro de una ráfaga.
func gust(center: Vector3) -> void:
	_swirl_pos = center + Vector3(0, 0.2, 0)
	swirl.global_position = _swirl_pos
	swirl.restart()


func _update_birds(focus: Vector3, delta: float) -> void:
	if not birds.visible:
		_bird_wait -= delta
		if _bird_wait <= 0.0:
			_start_flock(focus)
		return
	_bird_t += delta
	var dist := _bird_t * _bird_speed
	if dist > _bird_len:
		birds.visible = false
		_bird_wait = randf_range(30.0, 70.0)
		return
	var mm := birds.multimesh
	var lead := _bird_from + _bird_dir * dist
	var bank := sin(_bird_t * 0.35) * 0.12
	var rot := Basis.looking_at(_bird_dir, Vector3.UP) * Basis(Vector3.FORWARD, bank)
	for i in _bird_count:
		var row := float((i + 1) >> 1)
		var sd := 1.0 if i % 2 == 1 else -1.0
		var off := -_bird_dir * row * 2.3 + _bird_side * sd * row * 2.0
		off.y = sin(_bird_t * 1.3 + i * 1.7) * 0.35 - row * 0.2
		mm.set_instance_transform(i, Transform3D(rot, lead + off))


func _start_flock(focus: Vector3) -> void:
	var ang := randf() * TAU
	_bird_dir = Vector3(cos(ang), 0.0, sin(ang))
	_bird_side = _bird_dir.cross(Vector3.UP).normalized()
	var lateral := randf_range(-22.0, 22.0)
	_bird_len = 260.0
	_bird_from = focus - _bird_dir * (_bird_len * 0.5) + _bird_side * lateral
	_bird_from.y = focus.y + randf_range(15.0, 26.0)
	_bird_speed = randf_range(9.0, 12.0)
	_bird_t = 0.0
	birds.visible = true
