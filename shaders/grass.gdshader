shader_type spatial;
// Matas de césped alrededor de la cámara (GrassField). Cada instancia es un punto de una rejilla
// fija en el mundo: aquí se le da un desplazamiento aleatorio estable, la altura del terreno,
// el color seco→verde de su zona, viento, se aparta al pasar y DESAPARECE bajo la hojarasca,
// en caminos/tierra/grava y dentro de muros: limpiar hojas destapa el césped.
render_mode cull_disabled, specular_disabled, diffuse_lambert_wrap, world_vertex_coords;

uniform sampler2D pile_tex : filter_linear, repeat_disable;
uniform sampler2D ground_tex : filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_tex : filter_linear, repeat_disable;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec4 grid_rect;
uniform vec2 grid_size;
uniform vec4 height_map;      // origen x, origen z, 1 / celda
uniform vec2 height_size;
uniform float zone_clean[12];
uniform float spacing = 0.3;
uniform float fade_radius = 9.0;
uniform vec3 cam_pos;
uniform vec2 wind = vec2(0.6, 0.2);
uniform vec3 flower_center = vec3(0.0, 0.22, 0.0);

varying vec3 gcol;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - base;
	vec2 cell = floor(base.xz / spacing + 0.5);
	vec2 h = hash22(cell);
	vec2 h2 = hash22(cell + 31.0);
	vec2 xz = (cell + (h - 0.5) * 0.9) * spacing;
	vec2 uv = (xz - grid_rect.xy) * grid_rect.zw;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec4 pile = textureLod(pile_tex, uv, 0.0);
	float cover = clamp(pile.r * 1.4 + pile.g * 2.0, 0.0, 1.0);
	vec4 g = texelFetch(ground_tex, ivec2(clamp(uv, 0.0, 0.9999) * grid_size), 0);
	float bare = max(max(g.r, g.g), g.b);
	float ao = textureLod(ao_tex, uv, 0.0).r;
	float d = distance(xz, cam_pos.xz);
	float vis = inside * (1.0 - smoothstep(0.06, 0.32, cover)) * (1.0 - smoothstep(0.25, 0.5, bare));
	vis *= (1.0 - smoothstep(0.35, 0.6, ao)) * (1.0 - smoothstep(fade_radius * 0.62, fade_radius, d));

	int zid = int(g.a * 255.0 / 20.0 + 0.5) - 1;
	float clean = zid >= 0 ? zone_clean[clamp(zid, 0, 11)] : 0.45;
	float n1 = textureLod(noise_tex, xz * 0.045, 0.0).r;
	float lush = smoothstep(n1 * 0.55 + 0.05, n1 * 0.55 + 0.4, clean);
	vec3 dry = mix(vec3(0.5, 0.46, 0.23), vec3(0.72, 0.62, 0.32), h2.x);
	vec3 green = mix(vec3(0.17, 0.4, 0.09), vec3(0.38, 0.57, 0.14), n1) * (0.85 + 0.3 * h2.x);
	vec3 c = mix(dry, green, lush) * (1.0 - 0.35 * ao);
	float tall = mix(0.45, 1.0, lush) * mix(0.7, 1.3, h2.y) * vis;

	// Flores: solo en matas del césped restaurado; si no, su geometría se colapsa en la punta.
	float fl = UV.x;
	vec2 fh = hash22(cell + 71.0);
	float flowering = step(0.86, fh.x) * step(0.55, lush);
	local = mix(local, flower_center, fl * (1.0 - flowering));

	float ang = h.x * 6.2832;
	float ca = cos(ang);
	float sa = sin(ang);
	local.xz = vec2(local.x * ca - local.z * sa, local.x * sa + local.z * ca);
	local *= vec3(vis, tall, vis);

	// Viento y apartarse al pasar (solo se mueve la parte alta de la hoja).
	float k = UV.y * UV.y;
	float w = sin(TIME * 1.7 + xz.x * 0.35 + xz.y * 0.22) * 0.6 + sin(TIME * 3.4 + xz.x * 1.1 - xz.y * 0.7 + h.y * 6.0) * 0.3;
	vec2 bend = (wind * 0.5 + normalize(wind + vec2(0.001)) * 0.25) * (0.5 + 0.5 * w) * 0.07 * k;
	vec2 pd = xz - cam_pos.xz;
	float pl = length(pd) + 0.001;
	bend += pd / pl * (1.0 - smoothstep(0.15, 0.75, pl)) * 0.13 * k;
	bend *= tall;
	float y = textureLod(height_tex, ((xz - height_map.xy) * height_map.z + 0.5) / height_size, 0.0).r;
	VERTEX = vec3(xz.x, y, xz.y) + local + vec3(bend.x, -dot(bend, bend) * 3.0, bend.y);
	// Normales casi verticales: la mata se ilumina como el suelo que la rodea.
	NORMAL = normalize(vec3(local.x * 4.0, 1.0, local.z * 4.0));

	vec3 fcol = fh.y > 0.66 ? vec3(0.98, 0.96, 0.9) : (fh.y > 0.33 ? vec3(1.0, 0.82, 0.22) : vec3(0.72, 0.5, 0.9));
	gcol = mix(c * mix(mix(0.66, 0.5, lush), 1.12, UV.y), fcol, fl);
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = gcol;
	BACKLIGHT = gcol * 0.4;
	ROUGHNESS = 0.9;
}
