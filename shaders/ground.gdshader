shader_type spatial;
// Suelo de la finca. Combina:
//  - césped que pasa de seco (paja con calvas) a verde intenso según el % limpio de cada zona;
//    el verde se extiende por manchas orgánicas y aparecen florecillas;
//  - losas de piedra en los caminos, surcos en la tierra del huerto y guijarros en la grava;
//  - hojarasca: hojas sueltas dibujadas (no manchas) cuya densidad sigue la cobertura de pile_tex;
//  - montones (desplazamiento de vértices) y oclusión suave al pie de montones, muros y troncos.
// El detalle procedural solo se calcula cerca de la cámara (detail_dist; 0 = calidad baja).
render_mode specular_disabled, diffuse_lambert_wrap;

uniform sampler2D pile_tex : filter_linear, repeat_disable;
uniform sampler2D ground_tex : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_tex : filter_linear, repeat_disable;
uniform vec4 grid_rect;
uniform vec2 grid_size;
uniform float pile_max = 1.25;
uniform float zone_clean[12];
uniform float detail_dist = 22.0;

varying vec3 wpos;
varying float occl;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Una hoja procedural por celda (q en unidades de celda). Devuelve color y máscara.
vec4 litter_leaf(vec2 q, float density, float tone) {
	vec2 id = floor(q);
	vec2 h = hash22(id);
	if (h.x > density) {
		return vec4(0.0);
	}
	vec2 r = hash22(id + 17.0);
	vec2 dir = normalize(r - 0.5 + vec2(0.001));
	vec2 f = fract(q) - 0.5 - (h - 0.5) * 0.2;
	vec2 lp = vec2(dot(f, vec2(dir.y, -dir.x)), dot(f, dir));
	float len = 0.22 + 0.16 * r.x;
	float y = lp.y / len;
	float w = len * (0.32 + 0.3 * r.y);
	// Óvalo apuntado, algo más ancho hacia la base; algunas con el borde lobulado (roble).
	float lobe = r.y > 0.72 ? 0.72 + 0.28 * abs(cos(y * 6.0)) : 1.0;
	float body = w * (1.0 - y * y) * (0.82 - 0.22 * y) * lobe - abs(lp.x);
	float m = smoothstep(0.0, 0.016, body);
	float k = fract(h.y * 5.0 + r.x * 0.3);
	vec3 c = k < 0.3 ? vec3(0.93, 0.5, 0.1) : (k < 0.5 ? vec3(0.84, 0.24, 0.07) : (k < 0.7 ? vec3(0.96, 0.72, 0.2) : (k < 0.88 ? vec3(0.64, 0.35, 0.13) : vec3(0.7, 0.14, 0.08))));
	c *= (0.8 + 0.28 * fract(h.y * 7.3)) * tone;
	// Nervio central y una mitad más oscura: cada hoja parece plegada. Borde algo más oscuro.
	c *= 1.0 - 0.3 * (1.0 - smoothstep(0.003, 0.013, abs(lp.x)));
	c *= lp.x > 0.0 ? 0.86 : 1.04;
	c *= 0.8 + 0.2 * smoothstep(0.0, 0.05, body);
	return vec4(c, m);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (wp.xz - grid_rect.xy) * grid_rect.zw;
	vec2 texel = vec2(1.5) / grid_size;
	float h = textureLod(pile_tex, uv, 0.0).g * pile_max;
	float hl = textureLod(pile_tex, uv - vec2(texel.x, 0.0), 0.0).g * pile_max;
	float hr = textureLod(pile_tex, uv + vec2(texel.x, 0.0), 0.0).g * pile_max;
	float hd = textureLod(pile_tex, uv - vec2(0.0, texel.y), 0.0).g * pile_max;
	float hu = textureLod(pile_tex, uv + vec2(0.0, texel.y), 0.0).g * pile_max;
	VERTEX.y += h;
	NORMAL = normalize(NORMAL + vec3(hl - hr, 0.0, hd - hu) * 1.1);
	wpos = wp + vec3(0.0, h, 0.0);
	// Oclusión: pie de los montones (entorno más alto que el punto) y cercanía a muros/troncos.
	float around = (hl + hr + hd + hu) * 0.25;
	float concave = clamp((around - h) * 2.2, 0.0, 0.55);
	float wall = textureLod(ao_tex, uv, 0.0).r;
	occl = (1.0 - concave) * (1.0 - 0.5 * wall);
}

void fragment() {
	vec2 uv = (wpos.xz - grid_rect.xy) * grid_rect.zw;
	vec2 xz = wpos.xz;
	vec4 g = texture(ground_tex, uv);
	vec4 gz = texelFetch(ground_tex, ivec2(clamp(uv, 0.0, 0.9999) * grid_size), 0);
	int zid = int(gz.a * 255.0 / 20.0 + 0.5) - 1;
	float clean = zid >= 0 ? zone_clean[clamp(zid, 0, 11)] : 0.45;
	// Detalle procedural solo donde cada hoja/losa ocupa varios píxeles (evita parpadeo a lo lejos
	// y en ángulos rasantes) y dentro de la distancia que permite la calidad gráfica.
	vec2 fw = fwidth(wpos.xz);
	float px = sqrt(fw.x * fw.y);
	float near = (1.0 - smoothstep(detail_dist * 0.45, detail_dist, length(VERTEX))) * (1.0 - smoothstep(0.035, 0.09, px));
	float n1 = texture(noise_tex, xz * 0.045).r;
	float n2 = texture(noise_tex, xz * 0.31).r;
	float n3 = texture(noise_tex, xz * 1.7).r;
	vec2 bump = vec2(0.0);

	// --- Césped: el verde avanza por manchas a medida que la zona se limpia.
	float lush = smoothstep(n1 * 0.55 + 0.05, n1 * 0.55 + 0.4, clean);
	vec3 dry = mix(vec3(0.46, 0.43, 0.22), vec3(0.66, 0.56, 0.3), n2) * (0.84 + 0.3 * n3);
	dry = mix(dry, vec3(0.42, 0.32, 0.2) * (0.85 + 0.3 * n3), smoothstep(0.58, 0.72, n1 * 0.55 + n2 * 0.5) * 0.75);
	vec3 green = mix(vec3(0.16, 0.38, 0.09), vec3(0.35, 0.54, 0.13), n1);
	green = mix(green, vec3(0.13, 0.32, 0.09), smoothstep(0.55, 0.8, n2) * 0.55);
	green *= 0.8 + 0.38 * n3;
	vec3 col = mix(dry, green, lush);
	// Estrías de hierba (muestreo fuera de ramas: derivadas bien definidas para los mipmaps).
	float stria = texture(noise_tex, xz * vec2(7.0, 1.7)).r;
	col *= mix(1.0, 0.78 + 0.44 * stria, near * 0.7);
	if (near > 0.0) {
		// Florecillas en el césped restaurado.
		if (lush > 0.3) {
			vec2 fq = xz * 3.1;
			vec2 fid = floor(fq);
			vec2 fh = hash22(fid + 41.0);
			if (fh.x > 0.88) {
				vec2 fo = hash22(fid + 7.0) * 0.56 + 0.22;
				float d = length(fract(fq) - fo);
				float petal = (1.0 - smoothstep(0.075, 0.12, d)) * near * smoothstep(0.3, 0.8, lush);
				vec3 fcol = fh.y > 0.66 ? vec3(0.97, 0.95, 0.88) : (fh.y > 0.33 ? vec3(0.98, 0.8, 0.22) : vec3(0.7, 0.48, 0.88));
				fcol = mix(fcol, vec3(1.0, 0.72, 0.15), 1.0 - smoothstep(0.02, 0.045, d));
				col = mix(col, fcol, petal);
			}
		}
	}

	// --- Caminos: losas irregulares con juntas (musgo cuando la zona está restaurada).
	float pathm = smoothstep(0.35, 0.65, g.r + (n2 - 0.5) * 0.25);
	if (pathm > 0.002) {
		vec3 stone_flat = vec3(0.6, 0.54, 0.45) * (0.86 + 0.22 * n3);
		vec3 pcol = stone_flat;
		if (near > 0.0) {
			// Hiladas de 42 cm con losas de largo distinto en cada hilada.
			float row = floor(xz.y * 2.35);
			vec2 rh = hash22(vec2(row, 3.0));
			float sx = 1.5 + rh.x * 0.9;
			float qx = xz.x * sx + rh.y * 3.0;
			vec2 id = vec2(floor(qx), row);
			vec2 f = vec2(fract(qx), fract(xz.y * 2.35));
			vec2 hs = hash22(id);
			vec2 e = min(f, 1.0 - f) * vec2(1.0 / sx, 0.425);
			vec2 cc = max(vec2(0.06) - e, 0.0);
			float rd = 0.06 - length(cc) + (n3 - 0.5) * 0.02;
			float joint = 1.0 - smoothstep(0.006, 0.024, rd);
			vec3 st = vec3(0.63, 0.56, 0.47) * (0.8 + 0.32 * hs.x);
			st *= vec3(1.0 + (hs.y - 0.5) * 0.14, 1.0, 1.0 - (hs.y - 0.5) * 0.16);
			st *= (0.9 + 0.2 * n3) * (0.92 + 0.12 * smoothstep(0.0, 0.06, rd));
			vec3 jcol = mix(vec3(0.36, 0.3, 0.23), vec3(0.25, 0.37, 0.13), lush);
			pcol = mix(stone_flat, mix(st, jcol, joint), near);
		}
		col = mix(col, pcol, pathm);
	}

	// --- Tierra del huerto: surcos con caballones más claros.
	float soilm = smoothstep(0.35, 0.65, g.g);
	if (soilm > 0.002) {
		float fr = sin(xz.x * 12.566);
		vec3 soil = mix(vec3(0.27, 0.18, 0.11), vec3(0.42, 0.29, 0.18), fr * 0.5 + 0.5);
		soil *= 0.8 + 0.35 * n3;
		soil = mix(soil * vec3(1.06, 1.0, 0.94), soil * 0.82, lush);
		col = mix(col, soil, soilm);
		bump.x += cos(xz.x * 12.566) * 0.45 * soilm * near;
	}

	// --- Grava: guijarros redondeados con huecos oscuros.
	float gravm = smoothstep(0.35, 0.65, g.b + (n3 - 0.5) * 0.3);
	if (gravm > 0.002) {
		vec3 gflat = vec3(0.6, 0.57, 0.53) * (0.82 + 0.3 * n3);
		vec3 gcol = gflat;
		if (near > 0.0) {
			vec2 q = xz * 10.0;
			vec2 id = floor(q);
			vec2 hs = hash22(id + 3.0);
			float d = length(fract(q) - 0.5 - (hs - 0.5) * 0.3);
			float peb = 1.0 - smoothstep(0.3, 0.44, d + hs.x * 0.08);
			vec3 pc = vec3(0.64, 0.6, 0.55) * (0.72 + 0.45 * hs.y) * vec3(1.0 + (hs.x - 0.5) * 0.15, 1.0, 1.0);
			gcol = mix(gflat, mix(vec3(0.33, 0.3, 0.26), pc, peb), near);
		}
		col = mix(col, gcol, gravm);
	}

	// --- Hojarasca: capa de mantillo bajo la cobertura densa y hojas sueltas dibujadas encima.
	vec4 pile = texture(pile_tex, uv);
	float cover = clamp(pile.r * 1.4 + pile.g * 2.0, 0.0, 1.0);
	if (cover > 0.02) {
		vec3 mulch = mix(vec3(0.42, 0.21, 0.08), vec3(0.62, 0.36, 0.13), n3) * (0.85 + 0.3 * n2);
		float thick = smoothstep(0.2, 0.7, cover + (n2 - 0.5) * 0.35);
		col = mix(col, mulch, thick);
		float dens = smoothstep(0.02, 0.6, cover);
		if (near > 0.0) {
			// Tres capas: hojas viejas y oscuras abajo (solo en la hojarasca espesa) y dos capas encima.
			vec4 c0 = litter_leaf(mat2(vec2(0.6, -0.8), vec2(0.8, 0.6)) * xz * 3.4 + vec2(0.21, 0.63), thick, 0.74);
			col = mix(col, c0.rgb, c0.a * near);
			vec4 a = litter_leaf(xz * 6.2, dens, 1.0);
			col = mix(col, a.rgb, a.a * near);
			vec4 b = litter_leaf(mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * xz * 4.7 + vec2(0.37, 0.71), dens * 0.92, 1.0);
			col = mix(col, b.rgb, b.a * near);
		}
		vec3 avg = mix(mulch, vec3(0.84, 0.46, 0.13) * (0.86 + 0.28 * n3), 0.65);
		col = mix(col, avg, dens * (1.0 - near) * 0.85);
	}

	col *= occl;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	if (bump.x != 0.0) {
		NORMAL = normalize(NORMAL - mat3(VIEW_MATRIX) * vec3(bump.x, 0.0, bump.y));
	}
}
