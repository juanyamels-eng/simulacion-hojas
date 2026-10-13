shader_type spatial;
// Hojas instanciadas (MultiMesh). Opacas, sin transparencias: baratas en GPUs móviles.
// La malla (LeafMeshes) trae cuatro siluetas; el shader elige una por instancia, la curva
// (bordes levantados, punta arqueada, pliegue en el nervio), la agita y la colorea.
// INSTANCE_CUSTOM: x = escala, y = semilla aleatoria, z = factor de elevación sobre el montón,
//                  w = especie (parte entera de w*4) + variación de anchura (parte fraccionaria).
render_mode cull_disabled, specular_disabled, diffuse_lambert_wrap;

uniform sampler2D pile_tex : filter_linear, repeat_disable;
uniform sampler2D vein_tex : filter_linear_mipmap, repeat_disable;
uniform vec4 grid_rect;
uniform float pile_max = 1.25;
uniform float leaf_size = 0.27;

varying vec3 edge_col;
varying vec2 vein_uv;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	float sp = INSTANCE_CUSTOM.w * 4.0;
	float species = floor(sp);
	float vari = fract(sp);
	float seed = INSTANCE_CUSTOM.y;
	vec2 p = VERTEX.xz;
	if (species > 2.5) {
		p = CUSTOM0.xy;
	} else if (species > 1.5) {
		p = UV2;
	} else if (species > 0.5) {
		p = UV;
	}
	vec2 pc = clamp(p, vec2(-0.59), vec2(0.59));
	vein_uv = vec2(mod(species, 2.0), floor(species * 0.5)) * 0.5 + vec2(pc.x + 0.6, 0.6 - pc.y) * (0.5 / 1.2);
	p.x *= mix(0.86, 1.14, vari);

	float h1 = hash11(seed * 97.0 + 1.0);
	float h2 = hash11(seed * 57.0 + 7.0);
	float h3 = hash11(seed * 131.0 + 3.0);
	float h4 = hash11(seed * 211.0 + 5.0);
	// En el aire (inclinada por la física) aletea mucho más que en el suelo.
	float air = smoothstep(0.96, 0.8, MODEL_MATRIX[1].y);
	float cup = 0.35 + 0.9 * h1 + air * 0.6;
	float bow = (h2 - 0.25) * 0.5;
	float fold = 0.04 + 0.12 * h2;
	float wave = sin(TIME * (2.1 + 9.0 * air) + seed * 40.0 + p.y * (2.0 + 2.0 * air));
	float flap = wave * (0.025 + 0.2 * air);
	float tip = max(p.y, 0.0);
	float h = cup * p.x * p.x + bow * p.y * p.y + fold * abs(p.x) + flap * tip;
	float dhx = 2.0 * cup * p.x + fold * sign(p.x);
	float dhy = 2.0 * bow * p.y + flap * step(0.0, p.y);
	float s = INSTANCE_CUSTOM.x * leaf_size;
	VERTEX = vec3(p.x, h, -p.y) * s;
	NORMAL = normalize(vec3(-dhx, 1.0, dhy));

	// Montones: la hoja se apoya sobre la altura del montón en su posición.
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 uv = (origin.xz - grid_rect.xy) * grid_rect.zw;
	float ph = textureLod(pile_tex, uv, 0.0).g;
	float lift = ph * pile_max * INSTANCE_CUSTOM.z;
	VERTEX += transpose(mat3(MODEL_MATRIX)) * vec3(0.0, lift, 0.0);
	// Las hojas medio hundidas en un montón quedan en sombra.
	float embed = 1.0 - 0.32 * smoothstep(0.04, 0.35, ph) * clamp((1.03 - INSTANCE_CUSTOM.z) * 7.5, 0.0, 1.0);

	// Color: centro soleado (algunas recién caídas aún verdosas) y borde más oscuro y rojizo.
	vec3 base = COLOR.rgb * mix(vec3(1.06, 0.9, 0.86), vec3(0.96, 1.06, 1.02), h3);
	vec3 centre = base * mix(vec3(1.0), vec3(1.07, 1.13, 0.82), h4);
	float lum = dot(base, vec3(0.3, 0.55, 0.15));
	centre = mix(centre, vec3(0.5, 0.62, 0.16) * (0.5 + lum), step(0.88, h4) * 0.6);
	edge_col = base * mix(vec3(0.94, 0.72, 0.62), vec3(0.6, 0.36, 0.24), h3 * h4 + 0.15 * h1) * embed;
	COLOR.rgb = centre * embed;
}

void fragment() {
	vec2 vt = texture(vein_tex, vein_uv).rg;
	vec3 c = mix(COLOR.rgb, edge_col, smoothstep(0.3, 1.0, COLOR.a));
	c *= 0.86 + 0.28 * vt.g;
	// Nervios más claros y dorados.
	c = mix(c, c * vec3(1.2, 1.14, 0.78) + vec3(0.05, 0.035, 0.0), vt.r * 0.65);
	if (!FRONT_FACING) {
		// Envés: más pálido y mate (y con la misma iluminación que el haz).
		NORMAL = -NORMAL;
		c = mix(c, vec3(dot(c, vec3(0.3, 0.5, 0.2))), 0.3) * 0.84;
	}
	ALBEDO = c;
	// Translucidez: el sol a contraluz atraviesa la hoja.
	BACKLIGHT = c * 0.5;
	ROUGHNESS = 0.8;
}
