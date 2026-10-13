shader_type spatial;
// Suelo de la finca. Combina:
//  - césped que pasa de seco a verde intenso según el % limpio de cada zona;
//  - caminos, tierra de huerto y grava pintados en ground_tex;
//  - hojarasca (cobertura) y montones (desplazamiento de vértices) desde pile_tex.
render_mode specular_disabled, diffuse_lambert_wrap;

uniform sampler2D pile_tex : filter_linear, repeat_disable;
uniform sampler2D ground_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 grid_rect;
uniform vec2 grid_size;
uniform float pile_max = 1.25;
uniform float zone_clean[12];

varying vec3 wpos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (wp.xz - grid_rect.xy) * grid_rect.zw;
	vec2 texel = vec2(1.0) / grid_size;
	float h = textureLod(pile_tex, uv, 0.0).g * pile_max;
	float hl = textureLod(pile_tex, uv - vec2(texel.x, 0.0), 0.0).g * pile_max;
	float hr = textureLod(pile_tex, uv + vec2(texel.x, 0.0), 0.0).g * pile_max;
	float hd = textureLod(pile_tex, uv - vec2(0.0, texel.y), 0.0).g * pile_max;
	float hu = textureLod(pile_tex, uv + vec2(0.0, texel.y), 0.0).g * pile_max;
	VERTEX.y += h;
	NORMAL = normalize(NORMAL + vec3(hl - hr, 0.0, hd - hu) * 1.6);
	wpos = wp + vec3(0.0, h, 0.0);
}

void fragment() {
	vec2 uv = (wpos.xz - grid_rect.xy) * grid_rect.zw;
	vec4 g = texture(ground_tex, uv);
	vec4 gz = texelFetch(ground_tex, ivec2(clamp(uv, 0.0, 0.9999) * grid_size), 0);
	int zid = int(gz.a * 255.0 / 20.0 + 0.5) - 1;
	float clean = zid >= 0 ? zone_clean[clamp(zid, 0, 11)] : 0.0;
	float n1 = texture(noise_tex, wpos.xz * 0.045).r;
	float n2 = texture(noise_tex, wpos.xz * 0.31).r;
	float n3 = texture(noise_tex, wpos.xz * 1.7).r;

	vec3 dry = vec3(0.52, 0.5, 0.26) * (0.85 + 0.3 * n1);
	vec3 lush = mix(vec3(0.27, 0.52, 0.17), vec3(0.36, 0.6, 0.2), n1) * (0.88 + 0.24 * n3);
	vec3 col = mix(dry, lush, smoothstep(0.0, 1.0, clean));
	// Caminos de piedra clara, tierra oscura y grava.
	vec3 path = vec3(0.74, 0.66, 0.53) * (0.86 + 0.22 * n3);
	vec3 soil = vec3(0.36, 0.25, 0.16) * (0.8 + 0.35 * n2);
	vec3 gravel = vec3(0.6, 0.58, 0.55) * (0.75 + 0.45 * n3);
	col = mix(col, path, smoothstep(0.35, 0.65, g.r + (n2 - 0.5) * 0.25));
	col = mix(col, soil, smoothstep(0.35, 0.65, g.g));
	col = mix(col, gravel, smoothstep(0.35, 0.65, g.b + (n3 - 0.5) * 0.3));
	// Hojarasca: alfombra de tonos otoñales donde hay hojas.
	vec4 pile = texture(pile_tex, uv);
	float cover = clamp(pile.r * 1.4 + pile.g * 2.0, 0.0, 1.0);
	vec3 litter = mix(vec3(0.62, 0.3, 0.1), vec3(0.88, 0.58, 0.16), n3);
	litter = mix(litter, vec3(0.7, 0.18, 0.08), smoothstep(0.62, 0.8, n2) * 0.7);
	litter *= 0.8 + 0.25 * n2;
	float lit = smoothstep(0.08, 0.55, cover + (n3 - 0.5) * 0.35);
	col = mix(col, litter, lit);
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
