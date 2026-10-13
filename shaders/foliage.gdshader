shader_type spatial;
// Follaje estilizado: copas, setos, arbustos y matas. Opaco (sin recortes alfa).
//  - COLOR.rgb: color base (vértice × instancia); el color por vértice lleva la oclusión horneada.
//  - INSTANCE_CUSTOM: x = altura del suelo, y = cantidad de vaivén, z = semilla, w = radio de oclusión de contacto.
// Patrón de racimos de hojas en dos tonos (dos lecturas de ruido), vaivén suave por viento en el vértice
// y luz que atraviesa las hojas a contraluz.
render_mode world_vertex_coords, cull_back;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float wind = 1.0;
uniform float clump_scale = 2.4;
uniform float translucency = 0.55;
uniform vec3 bounce_color : source_color = vec3(0.95, 0.52, 0.2);

varying vec3 wp;
varying float hgt;
varying float seed;
varying float ao_h;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float ground = INSTANCE_CUSTOM.x;
	float h = max(VERTEX.y - ground, 0.0);
	float ph = TIME * 1.15 + dot(c.xz, vec2(0.21, 0.17)) + INSTANCE_CUSTOM.z * 6.283;
	float flutter = sin(TIME * 3.7 + dot(VERTEX, vec3(1.9, 2.3, 1.7)));
	vec3 sway = vec3(sin(ph), 0.0, sin(ph * 0.83 + 1.3) * 0.6) * (0.012 * h) + vec3(flutter * 0.02, flutter * 0.01, -flutter * 0.015);
	VERTEX += sway * INSTANCE_CUSTOM.y * wind;
	wp = VERTEX;
	hgt = h;
	seed = INSTANCE_CUSTOM.z;
	float r = INSTANCE_CUSTOM.w;
	ao_h = r > 0.0 ? h / r : 100.0;
}

void fragment() {
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 off = vec2(seed * 7.3, seed * 3.1);
	// Dos proyecciones (lateral y cenital) mezcladas según la normal, para dos octavas de ruido:
	// sin costuras ni estiramientos en setos y copas redondeadas.
	vec2 side_uv = vec2(wp.x + wp.z, wp.y);
	// Peso nítido: la proyección cenital solo en superficies casi horizontales (sin estiramientos).
	float t = smoothstep(0.55, 0.85, abs(nw.y));
	float s1 = clump_scale * 0.5;
	float s2 = clump_scale * 1.9;
	float n = mix(texture(noise_tex, side_uv * s1 + off).r, texture(noise_tex, wp.xz * s1 + off).r, t);
	float n2 = mix(texture(noise_tex, side_uv * s2 + off.yx).r, texture(noise_tex, wp.xz * s2 + off.yx).r, t);
	float clump = smoothstep(0.34, 0.72, n * 0.7 + n2 * 0.5 - 0.1);
	vec3 base = COLOR.rgb;
	vec3 dark = base * vec3(0.68, 0.64, 0.68);
	vec3 lit = base * 1.06 + vec3(0.03, 0.025, 0.0);
	vec3 col = mix(dark, lit, clump);
	// Puntas de hoja: motas claras finas.
	col += base * 0.12 * smoothstep(0.72, 0.82, n2);
	col *= mix(0.84, 1.05, smoothstep(-0.7, 0.8, nw.y));
	col *= mix(0.55, 1.0, smoothstep(0.0, 1.0, ao_h));
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.18;
	float down = clamp(-nw.y, 0.0, 1.0);
	EMISSION = col * bounce_color * 0.16 * down * (1.0 - smoothstep(1.5, 6.0, hgt));
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + 0.5) / 1.5, 0.0, 1.0);
	// Las hojas dejan pasar algo de luz: sombras algo más suaves (y menos dientes de sierra).
	DIFFUSE_LIGHT += LIGHT_COLOR * (ATTENUATION * 0.8 + 0.2) * w * (0.95 / PI);
	// Contraluz: la luz atraviesa las hojas.
	float through = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * max(ATTENUATION, 0.3) * through * translucency * (1.0 / PI);
}
