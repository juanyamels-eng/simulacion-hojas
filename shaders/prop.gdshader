shader_type spatial;
// Atrezo estilizado de la finca (lotes MultiMesh y mallas fusionadas con color por vértice).
//  - COLOR.rgb: color (vértice × instancia). COLOR.a: patrón procedural = (patrón + 16 · veta_vertical) / 32.
//  - INSTANCE_CUSTOM: x = altura del suelo bajo la instancia, y = radio de oclusión de contacto (0 = sin),
//    z = semilla de variación.
// Luz: difusa envolvente suave, borde cálido a contraluz, brillo especular solo en metal/cristal/agua,
// rebote cálido de la hojarasca en las caras que miran al suelo. Una o dos lecturas de textura por píxel.
render_mode cull_back;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float object_space = 0.0;      // 1: patrones en espacio de objeto (piezas que se mueven)
uniform float use_vertex_color = 1.0;  // 0: usa albedo y patron (mallas sin color por vértice)
uniform vec4 albedo : source_color = vec4(1.0);
uniform float pattern = 0.0;
uniform vec3 bounce_color : source_color = vec3(0.95, 0.52, 0.2);
uniform float bounce = 0.22;
uniform float rim_amount = 0.35;
uniform vec3 sky_tint : source_color = vec3(0.62, 0.72, 0.82);
uniform float window_glow = 1.0;       // luz cálida tras las ventanas (subir al anochecer)

varying vec3 pp;      // posición para patrones (m)
varying vec3 pn;      // normal para patrones
varying vec3 wpos;
varying vec3 orig;
varying float ao_h;
varying float seed;

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	orig = MODEL_MATRIX[3].xyz;
	if (object_space > 0.5) {
		pp = VERTEX;
		pn = NORMAL;
	} else {
		pp = wpos;
		pn = wn;
	}
	float r = INSTANCE_CUSTOM.y;
	ao_h = r > 0.0 ? (wpos.y - INSTANCE_CUSTOM.x) / r : 100.0;
	seed = INSTANCE_CUSTOM.z;
	if (use_vertex_color < 0.5) {
		COLOR = vec4(albedo.rgb, (pattern + 0.25) / 32.0);
	}
}

void fragment() {
	vec3 col = COLOR.rgb;
	int code = int(COLOR.a * 32.0 + 0.5);
	int pat = code % 16;
	bool vgrain = ((code / 16) % 2) == 1;
	vec3 n = normalize(pn);
	vec3 an = abs(n);
	// Coordenadas de cara: v = altura en las caras verticales.
	vec2 pu = an.y > max(an.x, an.z) ? pp.xz : (an.x > an.z ? vec2(pp.z, pp.y) : vec2(pp.x, pp.y));
	float nlow = texture(noise_tex, pu * 0.31 + seed * 3.7).r;
	float fw = max(fwidth(pu.x), fwidth(pu.y));
	float rough = 0.9;
	float spec = 0.25;
	vec3 emit = vec3(0.0);
	// Variación suave de tono en todo el atrezo.
	col *= 0.9 + 0.2 * nlow;

	if (pat == 1) {
		// Madera con veta.
		vec2 g = vgrain ? vec2(pu.x * 7.0, pu.y * 0.35) : vec2(pu.x * 0.35, pu.y * 7.0);
		float v = texture(noise_tex, g + seed).r;
		col *= 0.8 + 0.34 * smoothstep(0.2, 0.8, v);
		rough = 0.85;
	} else if (pat == 2) {
		// Tablas horizontales solapadas (fachadas, cobertizos).
		float h = 0.21;
		float fy = fract(pu.y / h);
		float board = floor(pu.y / h);
		float fade = 1.0 - smoothstep(h * 0.2, h * 0.5, fw);
		float shade = mix(1.06, 0.86, fy);
		shade *= 1.0 - 0.3 * smoothstep(0.9, 0.985, fy);
		float tint = 0.94 + 0.12 * hash1(board + floor(pu.x / 3.1) * 7.0);
		col *= mix(1.0, shade * tint, fade);
	} else if (pat == 3) {
		// Tablas verticales (puertas, graneros).
		float w = 0.17;
		float fx = fract(pu.x / w);
		float board = floor(pu.x / w);
		float fade = 1.0 - smoothstep(w * 0.2, w * 0.5, fw);
		float groove = smoothstep(0.0, 0.07, fx) * smoothstep(1.0, 0.93, fx);
		float grain = texture(noise_tex, vec2(pu.x * 5.0, pu.y * 0.3) + seed).r;
		float tint = (0.9 + 0.18 * hash1(board)) * (0.88 + 0.22 * grain);
		col *= mix(1.0, tint * mix(0.62, 1.0, groove), fade);
	} else if (pat == 4 || pat == 5) {
		// Piedra irregular (4) o ladrillo (5).
		vec2 s = pat == 4 ? vec2(0.62, 0.3) : vec2(0.25, 0.085);
		float row = floor(pu.y / s.y);
		float x = pu.x / s.x + (pat == 4 ? hash1(row) * 0.8 : 0.0) + mod(row, 2.0) * 0.5;
		vec2 cell = vec2(floor(x), row);
		vec2 f = vec2(fract(x) * s.x, fract(pu.y / s.y) * s.y);
		float nh = texture(noise_tex, pu * 2.3 + seed).r;
		float edge = min(min(f.x, s.x - f.x), min(f.y, s.y - f.y)) + (nh - 0.5) * (pat == 4 ? 0.05 : 0.012);
		float mw = pat == 4 ? 0.022 : 0.009;
		float mortar = 1.0 - smoothstep(mw * 0.5, mw * 1.6, edge);
		float bevel = smoothstep(mw, mw * 4.0, edge);
		float fade = 1.0 - smoothstep(s.y * 0.15, s.y * 0.45, fw);
		vec3 stone = col * (0.82 + 0.32 * hash2(cell)) * (0.82 + 0.18 * bevel) * (0.9 + 0.2 * nh);
		vec3 mcol = col * vec3(0.62, 0.6, 0.57);
		col = mix(col * (0.95 + 0.1 * nh), mix(stone, mcol, mortar), fade);
	} else if (pat == 6) {
		// Tejas: filas horizontales (paralelas al alero) con bordes redondeados.
		float rh = 0.14;
		float u = an.x > an.z ? pp.z : pp.x;
		float r = pp.y / rh;
		float row = floor(r);
		float fy = fract(r);
		float x = u / 0.32 + mod(row, 2.0) * 0.5;
		float fx = fract(x);
		float scallop = 0.32 * (1.0 - pow(2.0 * fx - 1.0, 2.0));
		float lower = smoothstep(scallop - 0.06, scallop + 0.04, fy);
		float fade = 1.0 - smoothstep(rh * 0.25, rh * 0.6, fw);
		float tint = 0.85 + 0.28 * hash2(vec2(floor(x), row));
		float shade = mix(1.08, 0.8, fy) * mix(0.72, 1.0, lower) * (0.65 + 0.35 * smoothstep(0.0, 0.08, min(fx, 1.0 - fx)));
		col *= mix(0.95, tint * shade, fade);
	} else if (pat == 7 || pat == 8) {
		// Corteza (7) o abedul (8): coordenada alrededor del eje del tronco.
		vec3 d = wpos - orig;
		float ang = atan(d.z, d.x);
		vec2 bu = vec2(ang * 0.45, wpos.y);
		if (pat == 7) {
			float f = texture(noise_tex, vec2(bu.x * 2.2, bu.y * 0.22) + seed).r;
			float f2 = texture(noise_tex, vec2(bu.x * 5.0, bu.y * 0.6) + seed * 2.0).r;
			col *= 0.62 + 0.55 * smoothstep(0.32, 0.7, f * 0.7 + f2 * 0.4);
			float moss = (1.0 - smoothstep(0.0, 1.2, ao_h * 0.6)) * smoothstep(0.45, 0.7, nlow);
			col = mix(col, vec3(0.32, 0.4, 0.16), moss * 0.55);
		} else {
			float f = texture(noise_tex, vec2(bu.x * 1.3, bu.y * 5.0) + seed).r;
			float dash = smoothstep(0.66, 0.72, f);
			col = mix(col, vec3(0.16, 0.14, 0.13), dash * 0.85);
			col *= 0.94 + 0.08 * nlow;
		}
		rough = 0.9;
	} else if (pat == 9) {
		// Metal: brillo y cepillado sutil.
		float b = texture(noise_tex, vec2(pu.x * 0.4, pu.y * 9.0) + seed).r;
		col *= 0.88 + 0.22 * b;
		rough = 0.32;
		spec = 0.6;
	} else if (pat == 10) {
		// Cristal de ventana: reflejo del cielo, brillo diagonal y luz cálida interior.
		vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float fres = pow(1.0 - clamp(abs(dot(v, n)), 0.0, 1.0), 2.0);
		float streak = smoothstep(0.12, 0.0, abs(fract((pu.x + pu.y) * 0.55 + seed) - 0.5) - 0.06);
		col = mix(vec3(0.1, 0.13, 0.17), sky_tint, 0.18 + 0.5 * fres) + streak * 0.12;
		emit = vec3(1.0, 0.7, 0.36) * (0.12 + 0.12 * nlow) * window_glow;
		rough = 0.12;
		spec = 0.7;
	} else if (pat == 11) {
		// Baldosas cuadradas.
		vec2 f = fract(pu / 0.3);
		float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float fade = 1.0 - smoothstep(0.05, 0.14, fw);
		col *= mix(1.0, mix(0.7, 1.0, smoothstep(0.02, 0.06, e)) * (0.93 + 0.12 * hash2(floor(pu / 0.3))), fade);
		rough = 0.5;
		spec = 0.45;
	} else if (pat == 12) {
		// Toldo a rayas.
		float s = step(0.5, fract(pu.x / 0.42));
		col = mix(col, vec3(0.96, 0.92, 0.84) * (0.9 + 0.1 * nlow), s);
		rough = 0.95;
	} else if (pat == 13) {
		// Agua: ondas, reflejo del cielo.
		float w1 = texture(noise_tex, wpos.xz * 0.6 + vec2(TIME * 0.03, TIME * 0.02)).r;
		float w2 = texture(noise_tex, wpos.xz * 1.3 - vec2(TIME * 0.025, -TIME * 0.035)).r;
		vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float fres = pow(1.0 - clamp(v.y, 0.0, 1.0), 3.0);
		col = mix(col, sky_tint, 0.25 + 0.5 * fres) * (0.9 + 0.2 * w1);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4((w1 - 0.5) * 0.35, 0.0, (w2 - 0.5) * 0.35, 0.0)).xyz);
		rough = 0.08;
		spec = 0.8;
	} else if (pat == 14) {
		// Paja / heno.
		float s = texture(noise_tex, vec2(pu.x * 0.5, pu.y * 6.0) + seed).r;
		float s2 = texture(noise_tex, vec2(pu.y * 0.5, pu.x * 6.0) + seed).r;
		col *= 0.75 + 0.45 * max(s, s2 * 0.8);
	} else if (pat == 15) {
		// Luz (faroles, pantallas).
		emit = col * 1.4;
		rough = 0.4;
	} else {
		float nh = texture(noise_tex, pu * 2.7 + seed).r;
		col *= 0.95 + 0.1 * nh;
	}

	// Oclusión de contacto con el suelo y rebote cálido de la hojarasca.
	float ao = mix(0.5, 1.0, smoothstep(0.0, 1.0, ao_h));
	col *= ao;
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float down = clamp(-nw.y, 0.0, 1.0);
	ALBEDO = col;
	EMISSION = emit + col * bounce_color * bounce * (down * 0.8 + 0.2) * (1.0 - smoothstep(1.0, 5.0, ao_h * 0.7));
	ROUGHNESS = rough;
	SPECULAR = spec;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + 0.35) / 1.35, 0.0, 1.0);
	w = w * w * (3.0 - 2.0 * w);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * w * (0.92 / PI);
	// Borde cálido, más fuerte a contraluz.
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float back = clamp(dot(LIGHT, -VIEW) * 0.5 + 0.5, 0.0, 1.0);
	float rim = fres * fres * fres * (0.3 + 0.7 * back) * rim_amount;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * rim * clamp(ndl + 0.7, 0.0, 1.0) * (1.0 / PI);
	if (ROUGHNESS < 0.7) {
		vec3 h = normalize(LIGHT + VIEW);
		float sh = exp2(10.0 * (1.0 - ROUGHNESS) + 1.0);
		float s = pow(max(dot(NORMAL, h), 0.0), sh) * (sh + 8.0) / (8.0 * PI);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * s * (1.0 - ROUGHNESS) * 0.35 * clamp(ndl * 2.0, 0.0, 1.0);
	}
}
